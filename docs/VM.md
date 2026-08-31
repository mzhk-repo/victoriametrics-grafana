# Оновлений Backlog: (VictoriaMetrics, Grafana & Independent Synthetic Probe)

## Мета

Забезпечити повноцінний моніторинг шлюзу Smtp2Graph у VictoriaMetrics/Grafana та реалізувати легкий синтетичний тестувальник (Synthetic Probe) з можливістю надсилання алертів про аварії.

## 1. Підключення VictoriaMetrics до мережі шлюзу

- **Мережа:** Оновити `docker-compose.yml` / `docker-compose.swarm.yml` в `/opt/victoriametrics-grafana`, додавши мережу `smtp2graph_internal_enc` до сервісу `victoriametrics`.
- **Конфігурація:** Переконатися, що мережа є `external` та `encrypted`, і порт `9464` не публікується у зовнішній світ.
- **Scrape Target:** Додати `SMTP2GRAPH_METRICS_TARGET=smtp2graph_gateway:9464` до env-контракту та забезпечити його рендеринг у `scripts/render-scrape-config.sh`.

## 2. Налаштування Scrape Job

- Розширити `victoria-metrics/scrape-config.tmpl.yml` новим job `smtp2graph-gateway`.
- **Мітки (Labels):** `env`, `service: smtp2graph`, `component: gateway`.
- **Scrape endpoint:** `/metrics` з `SMTP2GRAPH_METRICS_TARGET`.
- Перезапускати тільки VictoriaMetrics при зміні згенерованого scrape-конфігу.

## 3. Створення Grafana Dashboard (`SMTP2Graph Gateway`)

Створити один дашборд з наступними основними панелями:

1. `up`, readiness/liveness та час безперервної роботи (uptime).
2. Активні SMTP-сесії.
3. Лічильники авторизацій SMTP (упішні / відхилені).
4. Лічильники прийнятих та відхилених листів.
5. Метрики Graph API delivery (success / retry / failed) та латентність (latency).
6. Використання черги (повідомлення/байти) та наявність помилкових листів (failed queue).
7. Використання диска під чергу та поріг відхилення (у MB та %).
8. Залишок днів дії TLS-сертифіката (days-to-expiry).

## 4. Конфігурація алертів метрик (`alerting/rules/smtp2graph.yml`)

Створити **8 основних алертів** на основі метрик (без централізованого логування):

- `SMTP2GraphMetricsDown` — critical (`up == 0`).
- `SMTP2GraphAuthFailuresHigh` — warning/critical при сплеску відмов авторизації.
- `SMTP2GraphDeliveryFailuresHigh` — critical при сплеску помилок Graph API.
- `SMTP2GraphDeliveryRetriesHigh` — warning при накопиченні повторних спроб відправки.
- `SMTP2GraphQueueUsageWarning` — warning при заповненні черги на 60%.
- `SMTP2GraphQueueUsageCritical` — critical при заповненні черги на 80%.
- `SMTP2GraphFailedQueueNotEmpty` — warning, якщо у `/data/failed` з'явилися листи.
- `SMTP2GraphTLSCertificateExpiring` — warning за 30 днів / critical за 7 днів.

## 5. Легкий Synthetic Runner

Створити автономний легкий протекційний скрипт (Cron job / Swarm timer):

### Контракт роботи:

1. **Тестова відправка:** Раз на 15 хвилин надсилає тестовий лист через шлюз Smtp2Graph (порт 2525, STARTTLS) на дозволену поштову скриньку з `NONPRODUCTION_RECIPIENT_ALLOWLIST`. У Swarm `SMTP2GRAPH_SYNTHETIC_HOST` має бути DNS alias шлюзу в encrypted overlay (поточний: `gateway`), а не `127.0.0.1`: loopback у runner вказує на сам runner.
2. **Перевірка:** Перевіряє успішне завершення SMTP-сесії (код `250 OK`) або зміну лічильника `smtp2graph_graph_delivery_success_total`.

## 6. Зведені автотести (2 скрипти)


| **Файл** | **Що перевіряє** |
| --- | --- |
| `tests/test-observability-config.sh` | Валідність YAML алертів `smtp2graph.yml`, валідність JSON дашборду Grafana, наявність target у scrape-конфігу VictoriaMetrics. |
| `tests/integration/test-synthetic-and-metrics.sh` | Виконує тестовий прогін Synthetic Probe, перевіряє факт зчитування `up == 1` у VictoriaMetrics та коректність генерації alert payload для зовнішнього SMTP. |

## 7. Порядок виконання та імплементації

1. **Network & Scrape:** Приєднати VictoriaMetrics до overlay-мережі та запустити збір метрик.
2. **Dashboard & Rules:** Імпортувати JSON дашборд та файл алертів.
3. **Synthetic Probe:** Налаштувати cron-скрипт з реквізитами резервного external SMTP-сервера.
4. **Validation:** Виконати 2 тестові скрипти для підтвердження проходження Task 7.2.
