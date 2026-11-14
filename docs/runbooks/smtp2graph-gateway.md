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

## Remove queued or failed messages without retrying

The `queue` directory contains messages awaiting delivery; `failed` contains messages that could not be delivered. Removing a message is irreversible and does not fix the delivery failure. Obtain the message owner's approval before deleting it. Inspect only file metadata: `.eml` files can contain message bodies, addresses and attachments.

On an authorized Swarm manager, identify the running task and its node. Verify that the service has exactly one replica before scaling it:

```bash
docker service ps smtp2graph_gateway --filter desired-state=running --no-trunc
docker service ls --filter name=smtp2graph_gateway
```

Stop the gateway and wait until its task has stopped before touching its storage. This interrupts mail acceptance. Run this command on the manager:

```bash
docker service scale smtp2graph_gateway=0
docker service ps smtp2graph_gateway --no-trunc
```

On the node that hosted the task, set the actual `SMTP2GRAPH_STORAGE_HOST_PATH` from the deployment configuration and list file names and sizes:

```bash
STORAGE_ROOT='/actual/SMTP2GRAPH_STORAGE_HOST_PATH'
find "$STORAGE_ROOT/queue" "$STORAGE_ROOT/failed" -maxdepth 1 -type f -printf '%p %s bytes\n'
```

For each approved message, choose its directory and exact file name from the listing. Do not use a wildcard or a path as the file name:

```bash
STATE='failed' # Use 'queue' for a message awaiting delivery.
FILE='exact-file-name.eml'
case "$STATE:$FILE" in
  queue:*.eml|failed:*.eml) ;;
  *) echo 'Invalid state or file name' >&2; false ;;
esac && case "$FILE" in
  */*|.*) echo 'File name must be a direct, non-hidden child' >&2; false ;;
  *) test -f "$STORAGE_ROOT/$STATE/$FILE" && test ! -L "$STORAGE_ROOT/$STATE/$FILE" && rm -- "$STORAGE_ROOT/$STATE/$FILE" ;;
esac
```

Check the command's exit status and repeat the metadata listing to confirm removal. Even if a check or deletion fails, restore the service on the manager:

```bash
docker service scale smtp2graph_gateway=1
docker service ls --filter name=smtp2graph_gateway
```

Wait for `1/1` replicas and the next scrape, then check `smtp2graph_queue_messages` for the relevant state. Other queued messages can still be delivered after restart. Scheduled retention of expired failed payloads is a separate SMTP2Graph procedure with a dry run by default.

## Synthetic runner

`monitoring_smtp2graph-synthetic-runner` is a single Swarm service on `monitoring_net` and `smtp2graph_internal_enc`. It runs immediately after start and then every `SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS` seconds (default `900`, minimum `60`), reaches VictoriaMetrics as `http://victoriametrics:8428` without a host-published port, and writes only aggregate status/timestamp textfile metrics. It uses the image default user (root) because the shared textfile directory is owned by the host deploy user; the service can write only to its `/metrics` bind mount. It also writes `smtp2graph_synthetic_freshness_threshold_seconds`, calculated as interval plus `SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS` (default `300`), which is consumed by the freshness alert. The atomic `.prom` file is mode `0644`, so the Node Exporter textfile collector can read it.

Required encrypted env keys: `SMTP2GRAPH_SYNTHETIC_HOST`, `SMTP2GRAPH_SYNTHETIC_PORT`, `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME`, `SMTP2GRAPH_SYNTHETIC_USER`, `SMTP2GRAPH_SYNTHETIC_PASSWORD`, `SMTP2GRAPH_SYNTHETIC_SENDER`, `SMTP2GRAPH_SYNTHETIC_RECIPIENT`, `SMTP2GRAPH_SYNTHETIC_DELIVERY_TIMEOUT_SECONDS`, `SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS` and `SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS`. The password is rendered as a versioned Docker Secret; never place it in a service environment variable or shell arguments.

`SMTP2GRAPH_SYNTHETIC_HOST` is the SMTP2Graph Swarm DNS alias on `smtp2graph_internal_enc` (currently `gateway`), while `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME` remains the gateway certificate name (currently `smtp-int.pinokew.buzz`). Never use `127.0.0.1` for the host: inside the runner it refers to the runner itself, not the gateway.

Synthetic textfile metrics are scraped through Node Exporter, whose target labels set `service="host"`; the metric's original `service="smtp2graph"` is preserved as `exported_service="smtp2graph"`. Queries for synthetic status must use both labels.

The queue-capacity expressions derive maximum capacity from the exported rejection threshold and the reviewed gateway setting `QUEUE_REJECT_THRESHOLD_PERCENT=80`. Update both alert and dashboard expressions with the gateway change if that setting is changed.
