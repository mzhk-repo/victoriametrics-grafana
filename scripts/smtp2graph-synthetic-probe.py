#!/usr/bin/env python3
"""Submit a bounded synthetic SMTP message and verify Graph delivery metrics."""

from __future__ import annotations

import json
import os
import smtplib
import ssl
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path

DELIVERY_QUERY = (
    'sum(smtp2graph_delivery_attempts_total{job="smtp2graph-gateway",'
    'env="prod",service="smtp2graph",component="gateway",result="succeeded"})'
)
REQUIRED_KEYS = (
    "SMTP2GRAPH_SYNTHETIC_HOST",
    "SMTP2GRAPH_SYNTHETIC_PORT",
    "SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME",
    "SMTP2GRAPH_SYNTHETIC_USER",
    "SMTP2GRAPH_SYNTHETIC_PASSWORD",
    "SMTP2GRAPH_SYNTHETIC_SENDER",
    "SMTP2GRAPH_SYNTHETIC_RECIPIENT",
    "VM_SYNTHETIC_QUERY_URL",
    "NODE_EXPORTER_TEXTFILE_DIR",
)


@dataclass(frozen=True)
class Config:
    host: str
    port: int
    tls_server_name: str
    username: str
    password: str
    sender: str
    recipient: str
    query_url: str
    textfile_dir: Path
    delivery_timeout_seconds: int


def config_from_env(env: dict[str, str]) -> Config:
    missing = [key for key in REQUIRED_KEYS if not env.get(key)]
    if missing:
        raise ValueError("missing required synthetic probe configuration")
    try:
        port = int(env["SMTP2GRAPH_SYNTHETIC_PORT"])
        timeout = int(env.get("SMTP2GRAPH_SYNTHETIC_DELIVERY_TIMEOUT_SECONDS", "120"))
    except ValueError as exc:
        raise ValueError("synthetic probe port and timeout must be integers") from exc
    if not 1 <= port <= 65535 or timeout < 1:
        raise ValueError("synthetic probe port or timeout is out of range")
    query_url = env["VM_SYNTHETIC_QUERY_URL"].rstrip("/")
    if not query_url.startswith(("http://", "https://")):
        raise ValueError("VM_SYNTHETIC_QUERY_URL must use http:// or https://")
    return Config(
        host=env["SMTP2GRAPH_SYNTHETIC_HOST"],
        port=port,
        tls_server_name=env["SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME"],
        username=env["SMTP2GRAPH_SYNTHETIC_USER"],
        password=env["SMTP2GRAPH_SYNTHETIC_PASSWORD"],
        sender=env["SMTP2GRAPH_SYNTHETIC_SENDER"],
        recipient=env["SMTP2GRAPH_SYNTHETIC_RECIPIENT"],
        query_url=query_url,
        textfile_dir=Path(env["NODE_EXPORTER_TEXTFILE_DIR"]),
        delivery_timeout_seconds=timeout,
    )


def query_delivery_count(config: Config) -> float:
    url = f"{config.query_url}/api/v1/query?{urllib.parse.urlencode({'query': DELIVERY_QUERY})}"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=10) as response:  # nosec B310: URL is operator-controlled
        payload = json.loads(response.read().decode("utf-8"))
    if payload.get("status") != "success" or payload.get("data", {}).get("resultType") != "vector":
        raise RuntimeError("VictoriaMetrics returned an invalid delivery query response")
    result = payload["data"].get("result", [])
    if len(result) != 1:
        raise RuntimeError("SMTP2Graph delivery counter is unavailable")
    return float(result[0]["value"][1])


def submit_message(config: Config) -> None:
    marker = uuid.uuid4().hex
    message = (
        f"From: {config.sender}\r\n"
        f"To: {config.recipient}\r\n"
        "Subject: SMTP2Graph synthetic probe\r\n"
        f"X-SMTP2Graph-Synthetic-ID: {marker}\r\n"
        "\r\n"
        "Synthetic monitoring message.\r\n"
    )
    context = ssl.create_default_context()
    with smtplib.SMTP(config.host, config.port, timeout=15) as smtp:
        smtp.ehlo()
        # smtplib uses _host as TLS server_hostname. Keep the TCP endpoint
        # configurable independently from the certificate hostname.
        smtp._host = config.tls_server_name  # noqa: SLF001
        smtp.starttls(context=context)
        smtp.ehlo()
        smtp.login(config.username, config.password)
        refused = smtp.sendmail(config.sender, [config.recipient], message)
    if refused:
        raise RuntimeError("SMTP server refused the synthetic recipient")


def wait_for_delivery(config: Config, baseline: float) -> bool:
    deadline = time.monotonic() + config.delivery_timeout_seconds
    while time.monotonic() < deadline:
        if query_delivery_count(config) > baseline:
            return True
        time.sleep(5)
    return False


def write_metrics(config: Config, status: int, success_timestamp: int, collect_timestamp: int) -> None:
    config.textfile_dir.mkdir(parents=True, exist_ok=True)
    payload = f'''# HELP smtp2graph_synthetic_last_success_timestamp Unix timestamp of the last successful SMTP2Graph synthetic delivery.
# TYPE smtp2graph_synthetic_last_success_timestamp gauge
smtp2graph_synthetic_last_success_timestamp{{env="prod",service="smtp2graph"}} {success_timestamp}
# HELP smtp2graph_synthetic_last_collect_timestamp Unix timestamp of the last SMTP2Graph synthetic delivery attempt.
# TYPE smtp2graph_synthetic_last_collect_timestamp gauge
smtp2graph_synthetic_last_collect_timestamp{{env="prod",service="smtp2graph"}} {collect_timestamp}
# HELP smtp2graph_synthetic_last_status Last SMTP2Graph synthetic delivery status (1=success, 0=failure).
# TYPE smtp2graph_synthetic_last_status gauge
smtp2graph_synthetic_last_status{{env="prod",service="smtp2graph"}} {status}
'''
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=config.textfile_dir, delete=False) as handle:
        handle.write(payload)
        temp_name = handle.name
    os.chmod(temp_name, 0o644)
    os.replace(temp_name, config.textfile_dir / "smtp2graph_synthetic.prom")


def run(config: Config) -> bool:
    baseline = query_delivery_count(config)
    submit_message(config)
    return wait_for_delivery(config, baseline)


def main() -> int:
    collect_timestamp = int(time.time())
    config: Config | None = None
    success = False
    try:
        config = config_from_env(dict(os.environ))
        success = run(config)
        if not success:
            raise RuntimeError("Graph delivery counter did not increase before timeout")
    except Exception as exc:  # Deliberately avoid printing configuration or SMTP replies.
        print(f"ERROR: SMTP2Graph synthetic probe failed: {type(exc).__name__}", file=sys.stderr)
    if config is None:
        return 1
    write_metrics(config, int(success), collect_timestamp if success else 0, collect_timestamp)
    if success:
        print("SMTP2Graph synthetic delivery verified")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
