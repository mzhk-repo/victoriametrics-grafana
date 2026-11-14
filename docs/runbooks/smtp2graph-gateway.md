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

## Перегляд і обробка `failed` черги

Алерт означає, що в каталозі `failed` є принаймні одне повідомлення. Панель показує кількість і розмір, але не вміст. Переглядайте лише метадані; `.eml` може містити лист, адреси та вкладення. Не використовуйте `cat`, `less`, `head` чи копіювання файлів у логи/тікет.

Команди нижче виконуйте на авторизованому Swarm manager. Спершу отримайте назву активного task і container ID:

```bash
docker service ps smtp2graph_gateway --filter desired-state=running --no-trunc
TASK_ID=<ID_активного_task>
CID=$(docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' "$TASK_ID")
```

Перевірте, що `CID` не порожній, а контейнер належить активному task `smtp2graph_gateway`. Перегляньте тільки імена та розміри файлів:

```bash
test -n "$CID" && docker exec "$CID" sh -c 'find /data/failed -maxdepth 1 -type f -printf "%f %s bytes\\n"'
```

Для повторної спроби спершу усуньте причину постійної помилки доставки (наприклад, Graph-доступ або політику одержувача). Повторне подання може доставити лист адресату; погодьте це з власником повідомлення. Gateway не має штатної команди retry для `failed`, тому операція потребує короткого вікна обслуговування: зупиніть gateway, перемістіть лише погоджений файл назад у `queue`, потім відновіть сервіс. Перевірте точне ім'я через метадані вище; не застосовуйте wildcard.

```bash
docker service scale smtp2graph_gateway=0
```

На хості зупиненого task, використовуючи фактичний `SMTP2GRAPH_STORAGE_HOST_PATH` з конфігурації розгортання:

```bash
STORAGE_ROOT='/фактичний/SMTP2GRAPH_STORAGE_HOST_PATH'
FILE='точне-імя-файлу.eml'
test -f "$STORAGE_ROOT/failed/$FILE" && test ! -e "$STORAGE_ROOT/queue/$FILE"
mv -- "$STORAGE_ROOT/failed/$FILE" "$STORAGE_ROOT/queue/$FILE"
docker service scale smtp2graph_gateway=1
```

Переконайтеся, що розгортання справді має одну репліку перед масштабуванням; ця процедура тимчасово зупиняє приймання пошти. Після команди перевірте `docker service ps smtp2graph_gateway` і дочекайтеся `1/1`; якщо перевірка файлу чи переміщення завершилися помилкою, окремо виконайте `docker service scale smtp2graph_gateway=1`, не видаляючи оригінал, і ескалуйте власнику SMTP2Graph. Після повторного запуску перевірте, що лічильник `state="failed"` став нульовим після наступного scrape.

Видаляйте повідомлення лише після підтвердження власника, що воно не потрібне для повторної доставки чи розслідування. Видалення незворотне і саме по собі не виправляє причину збою. Після зупинки gateway та перевірки точного файлу:

```bash
STORAGE_ROOT='/фактичний/SMTP2GRAPH_STORAGE_HOST_PATH'
FILE='точне-імя-файлу.eml'
test -f "$STORAGE_ROOT/failed/$FILE" && rm -- "$STORAGE_ROOT/failed/$FILE"
docker service scale smtp2graph_gateway=1
```

Якщо перевірка або видалення завершилися помилкою, окремо відновіть сервіс командою `docker service scale smtp2graph_gateway=1`.

Після відновлення сервісу дочекайтеся scrape і перевірте метрику `smtp2graph_queue_messages{state="failed"}`. Не видаляйте файли з `queue` або весь каталог `failed`. Планове очищення прострочених payloads виконується окремою процедурою SMTP2Graph із dry-run за замовчуванням; вона не призначена для негайного скидання цього алерту.

## Synthetic runner

`monitoring_smtp2graph-synthetic-runner` is a single Swarm service on `monitoring_net` and `smtp2graph_internal_enc`. It runs immediately after start and then every `SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS` seconds (default `900`, minimum `60`), reaches VictoriaMetrics as `http://victoriametrics:8428` without a host-published port, and writes only aggregate status/timestamp textfile metrics. It uses the image default user (root) because the shared textfile directory is owned by the host deploy user; the service can write only to its `/metrics` bind mount. It also writes `smtp2graph_synthetic_freshness_threshold_seconds`, calculated as interval plus `SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS` (default `300`), which is consumed by the freshness alert. The atomic `.prom` file is mode `0644`, so the Node Exporter textfile collector can read it.

Required encrypted env keys: `SMTP2GRAPH_SYNTHETIC_HOST`, `SMTP2GRAPH_SYNTHETIC_PORT`, `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME`, `SMTP2GRAPH_SYNTHETIC_USER`, `SMTP2GRAPH_SYNTHETIC_PASSWORD`, `SMTP2GRAPH_SYNTHETIC_SENDER`, `SMTP2GRAPH_SYNTHETIC_RECIPIENT`, `SMTP2GRAPH_SYNTHETIC_DELIVERY_TIMEOUT_SECONDS`, `SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS` and `SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS`. The password is rendered as a versioned Docker Secret; never place it in a service environment variable or shell arguments.

`SMTP2GRAPH_SYNTHETIC_HOST` is the SMTP2Graph Swarm DNS alias on `smtp2graph_internal_enc` (currently `gateway`), while `SMTP2GRAPH_SYNTHETIC_TLS_SERVER_NAME` remains the gateway certificate name (currently `smtp-int.pinokew.buzz`). Never use `127.0.0.1` for the host: inside the runner it refers to the runner itself, not the gateway.

Synthetic textfile metrics are scraped through Node Exporter, whose target labels set `service="host"`; the metric's original `service="smtp2graph"` is preserved as `exported_service="smtp2graph"`. Queries for synthetic status must use both labels.

The queue-capacity expressions derive maximum capacity from the exported rejection threshold and the reviewed gateway setting `QUEUE_REJECT_THRESHOLD_PERCENT=80`. Update both alert and dashboard expressions with the gateway change if that setting is changed.
