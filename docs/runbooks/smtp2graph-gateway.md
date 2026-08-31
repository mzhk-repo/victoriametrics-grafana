# Runbook: SMTP2Graph Gateway

## Scope

VictoriaMetrics scrapes `smtp2graph_gateway:9464/metrics` only through the external encrypted Swarm overlay `smtp2graph_internal_enc`. Grafana alerts are delivered through independent Google SMTP; do not route them through SMTP2Graph.

## First checks

1. Confirm the Swarm overlay is encrypted and both `monitoring_victoriametrics` and `smtp2graph_gateway` are attached. The gateway metrics port must not be host-published.
2. Query `up{job="smtp2graph-gateway",env="prod",service="smtp2graph"}`. If it is `0`, inspect gateway readiness and the VictoriaMetrics task network attachment before checking application metrics.
3. Check delivery outcomes, queue size and failed queue count in the `SMTP2Graph Gateway` dashboard. Do not inspect queued or failed message payloads during routine monitoring.

## Alert response

- AUTH spikes: verify client source policy and rate limits; do not log or copy credentials.
- Delivery failures/retries: validate Graph service health and gateway logs without exposing mail content, recipient addresses or tokens.
- Queue threshold or failed queue: stop new client onboarding if capacity is critical; follow the SMTP2Graph failed-payload retention procedure separately and never delete queue payloads as an alert reaction.
- TLS expiry: renew and reconcile the TLS Secret through SMTP2Graph IaC, then verify the exported `not_after` timestamp after rollout.
- Synthetic failure: inspect `monitoring_smtp2graph-synthetic-runner` logs and its textfile metric. The runner emits no message content or credentials.

## Synthetic runner

`monitoring_smtp2graph-synthetic-runner` is a single Swarm service on `monitoring_net` and `smtp2graph_internal_enc`. It runs immediately after start and then every 15 minutes, reaches VictoriaMetrics as `http://victoriametrics:8428` without a host-published port, and writes only aggregate status/timestamp textfile metrics as UID/GID `1000:1000`. The atomic `.prom` file is mode `0644`, so the Node Exporter textfile collector can read it.

Required encrypted env keys: `SMTP2GRAPH_SYNTHETIC_HOST`, `SMTP2GRAPH_SYNTHETIC_PORT`, `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME`, `SMTP2GRAPH_SYNTHETIC_USER`, `SMTP2GRAPH_SYNTHETIC_PASSWORD`, `SMTP2GRAPH_SYNTHETIC_SENDER`, `SMTP2GRAPH_SYNTHETIC_RECIPIENT` and `SMTP2GRAPH_SYNTHETIC_DELIVERY_TIMEOUT_SECONDS`. The password is rendered as a versioned Docker Secret; never place it in a service environment variable or shell arguments.

`SMTP2GRAPH_SYNTHETIC_HOST` is the SMTP2Graph Swarm DNS alias on `smtp2graph_internal_enc` (currently `gateway`), while `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME` remains the gateway certificate name (currently `smtp-int.pinokew.buzz`). Never use `127.0.0.1` for the host: inside the runner it refers to the runner itself, not the gateway.

The queue-capacity expressions derive maximum capacity from the exported rejection threshold and the reviewed gateway setting `QUEUE_REJECT_THRESHOLD_PERCENT=80`. Update both alert and dashboard expressions with the gateway change if that setting is changed.
