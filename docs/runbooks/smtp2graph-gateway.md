# Runbook: SMTP2Graph Gateway

## Scope

VictoriaMetrics scrapes `smtp2graph_gateway:9464/metrics` only through the external encrypted Swarm overlay `smtp2graph_internal_enc`. Grafana alerts are delivered through the independent MS365 SMTP relay; do not route them through SMTP2Graph.

## First checks

1. Confirm the Swarm overlay is encrypted and both `monitoring_victoriametrics` and `smtp2graph_gateway` are attached. The gateway metrics port must not be host-published.
2. Query `up{job="smtp2graph-gateway",env="prod",service="smtp2graph"}`. If it is `0`, inspect gateway readiness and the VictoriaMetrics task network attachment before checking application metrics.
3. Check delivery outcomes, queue size and failed queue count in the `SMTP2Graph Gateway` dashboard. Do not inspect queued or failed message payloads during routine monitoring.

## Alert response

- AUTH spikes: verify client source policy and rate limits; do not log or copy credentials.
- Delivery failures/retries: validate Graph service health and gateway logs without exposing mail content, recipient addresses or tokens.
- Queue threshold or failed queue: stop new client onboarding if capacity is critical; follow the SMTP2Graph failed-payload retention procedure separately and never delete queue payloads as an alert reaction.
- TLS expiry: renew and reconcile the TLS Secret through SMTP2Graph IaC, then verify the exported `not_after` timestamp after rollout.
- Synthetic failure: run `SERVER_ENV=prod bash scripts/run-smtp2graph-synthetic-probe.sh` only when the recipient allowlist and source CIDR are confirmed. It emits no message content or credentials.

## Synthetic timer

Install the reviewed units only on the production manager after the SOPS env keys are populated:

```bash
install -m 0644 systemd/smtp2graph-synthetic-probe.service /etc/systemd/system/
install -m 0644 systemd/smtp2graph-synthetic-probe.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now smtp2graph-synthetic-probe.timer
```

Required encrypted env keys: `SMTP2GRAPH_METRICS_TARGET`, `VM_SYNTHETIC_QUERY_URL`, `SMTP2GRAPH_SYNTHETIC_HOST`, `SMTP2GRAPH_SYNTHETIC_PORT`, `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME`, `SMTP2GRAPH_SYNTHETIC_USER`, `SMTP2GRAPH_SYNTHETIC_PASSWORD`, `SMTP2GRAPH_SYNTHETIC_SENDER`, `SMTP2GRAPH_SYNTHETIC_RECIPIENT`, `SMTP2GRAPH_SYNTHETIC_DELIVERY_TIMEOUT_SECONDS` and `NODE_EXPORTER_TEXTFILE_DIR`. The password remains only in SOPS; never place it in a unit file or shell arguments.

The queue-capacity expressions derive maximum capacity from the exported rejection threshold and the reviewed gateway setting `QUEUE_REJECT_THRESHOLD_PERCENT=80`. Update both alert and dashboard expressions with the gateway change if that setting is changed.
