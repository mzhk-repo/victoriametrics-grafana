#!/usr/bin/env bash
# Live smoke check for the SMTP2Graph synthetic runner and VictoriaMetrics scrape.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

VM_QUERY_URL="${VM_QUERY_URL:-http://victoriametrics:8428}"
SWARM_SYNTHETIC_SERVICE="${SWARM_SYNTHETIC_SERVICE:-monitoring_smtp2graph-synthetic-runner}"
SWARM_GRAFANA_SERVICE="${SWARM_GRAFANA_SERVICE:-monitoring_grafana}"
VM_QUERY_TIMEOUT_SECONDS="${VM_QUERY_TIMEOUT_SECONDS:-60}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

assert_alert_email_payload_contract() {
  python3 - <<'PY'
from pathlib import Path
import yaml

contact_points = yaml.safe_load(
    Path("grafana/provisioning/alerting/contact-points.yml").read_text(encoding="utf-8")
)
policies = yaml.safe_load(
    Path("grafana/provisioning/alerting/notification-policies.yml").read_text(encoding="utf-8")
)

receivers = {
    receiver["uid"]: receiver
    for point in contact_points["contactPoints"]
    for receiver in point["receivers"]
}
for uid in ("critical-email", "warning-email"):
    receiver = receivers.get(uid)
    assert receiver and receiver["type"] == "email", f"missing external SMTP receiver: {uid}"
    assert receiver["settings"] == {
        "addresses": "${GOOGLE_ALERT_EMAIL_TO}",
        "singleEmail": True,
    }, f"unexpected email payload settings for {uid}"

routes = policies["policies"][0]["routes"]
assert any(route["receiver"] == "critical-email-telegram" for route in routes)
assert any(route["receiver"] == "warning-email" for route in routes)
PY
}

query_vm_from_runner() {
  local query="$1"
  docker exec "$runner_container_id" python3 -c '
import json
import sys
import urllib.parse
import urllib.request

url = sys.argv[1].rstrip("/") + "/api/v1/query?" + urllib.parse.urlencode({"query": sys.argv[2]})
with urllib.request.urlopen(url, timeout=10) as response:  # nosec B310: operator-controlled URL
    print(response.read().decode("utf-8"))
' "$VM_QUERY_URL" "$query"
}

assert_single_value_is_one() {
  python3 -c '
import json
import sys

payload = json.load(sys.stdin)
result = payload.get("data", {}).get("result", [])
if payload.get("status") != "success" or len(result) != 1 or result[0].get("value", [None, None])[1] != "1":
    raise SystemExit("VictoriaMetrics query did not return exactly one value of 1")
'
}

require_command docker
require_command python3

assert_alert_email_payload_contract

docker service inspect "$SWARM_SYNTHETIC_SERVICE" >/dev/null \
  || die "Swarm service not found: $SWARM_SYNTHETIC_SERVICE"
docker service inspect "$SWARM_GRAFANA_SERVICE" >/dev/null \
  || die "Swarm service not found: $SWARM_GRAFANA_SERVICE"

runner_container_id="$(docker ps --filter "label=com.docker.swarm.service.name=${SWARM_SYNTHETIC_SERVICE}" --format '{{.ID}}' | head -n 1)"
[[ -n "$runner_container_id" ]] || die "no running task found for: $SWARM_SYNTHETIC_SERVICE"

printf 'Running synthetic probe in %s...\n' "$SWARM_SYNTHETIC_SERVICE"
docker exec "$runner_container_id" /bin/sh -ec '
  export SMTP2GRAPH_SYNTHETIC_PASSWORD="$(cat /run/secrets/smtp2graph_synthetic_password)"
  exec python3 /app/smtp2graph-synthetic-probe.py
'

printf 'Waiting for VictoriaMetrics scrape result...\n'
deadline=$((SECONDS + VM_QUERY_TIMEOUT_SECONDS))
up_query='up{job="smtp2graph-gateway",env="prod",service="smtp2graph",component="gateway"}'
until query_vm_from_runner "$up_query" | assert_single_value_is_one; do
  (( SECONDS < deadline )) || die "SMTP2Graph target did not report up == 1 within ${VM_QUERY_TIMEOUT_SECONDS}s"
  sleep 5
done

printf 'PASS: synthetic delivery, VictoriaMetrics scrape, and external SMTP alert payload contract are valid.\n'
