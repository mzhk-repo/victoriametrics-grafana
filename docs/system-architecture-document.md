# System Architecture Document (SAD)

## 1. Мета документа
Цей документ описує цільову архітектуру production-ready observability stack для KDI (Koha + DSpace + KDV Integrator) на базі VictoriaMetrics + Grafana.

Документ узагальнює поточну реалізацію в репозиторії та правила експлуатації у production.

## 2. Scope і межі
### In scope
- Збір метрик з host, контейнерів, БД, reverse-proxy та synthetic probes.
- Зберігання метрик у VictoriaMetrics single-node.
- Візуалізація та alerting у Grafana через provisioning (config-as-code).
- Security baseline: localhost-only binding, Cloudflare Access для Grafana, secrets only via `.env`.
- Backup/restore для VictoriaMetrics data volume.

### Out of scope (на поточний етап)
- Логи (Loki/ELK), distributed tracing.
- Перехід на VictoriaMetrics cluster.
- Повний incident-response workflow поза monitoring stack.

## 3. Контекст системи
### Бізнес-контекст
Стек забезпечує спостережуваність критичних компонентів KDI і мінімізує MTTR через:
- централізований збір метрик;
- стандартизовані dashboards;
- критичні алерти з routing на email/notification channels;
- runbooks для швидкої діагностики.

### Основні цілі якості
- Security first: без публічних monitoring endpoint.
- Надійність: retention 90 днів, backup + restore smoke tests.
- Керованість: повний config-as-code в Git.
- Операційна прозорість: alerting включно з `observability of observability`.

## 4. Архітектурні рішення
### ADR-орієнтири
- Використання VictoriaMetrics як TSDB (див. `docs/adr/ADR-001-victoriametrics-choice.md`).
- Single-node топологія як production baseline (див. `docs/adr/ADR-002-vm-topology.md`).
- Єдина label schema для jobs/rules/dashboards (див. `docs/adr/ADR-003-label-schema.md`).

### Ключові принципи
- Всі monitoring сервіси слухають тільки `127.0.0.1` на хості.
- Доступ зовні дозволений лише до Grafana через Cloudflare Tunnel + Access.
- Конфігурації dashboards/datasources/alerts керуються тільки файлами у Git.
- Секрети не зберігаються в репозиторії.

## 5. Логічна архітектура
### Компоненти
- VictoriaMetrics: TSDB, scrape engine, query API.
- Grafana: dashboards + unified alerting.
- Exporters:
  - Node Exporter
  - cAdvisor
  - MariaDB Exporter
  - PostgreSQL Exporter
  - Traefik metrics endpoint
  - Blackbox Exporter (synthetic probes)
- Cloudflared: edge bridge для безпечного доступу до Grafana.

### Потоки даних
1. Exporters/targets віддають `/metrics`.
2. VictoriaMetrics scrape-ить targets за `victoria-metrics/scrape-config.yml`.
3. Grafana читає метрики через datasource `victoriametrics`.
4. Alert rules виконуються Grafana Alerting і маршрутизуються за severity.
5. Backup/restore скрипти оновлюють textfile metrics для додаткового моніторингу backup health.

## 6. Фізична/мережева архітектура
### Розміщення
Всі компоненти працюють у Docker Compose на одному host VM.

### Мережі Docker
- `monitoring_net` (internal stack network)
- `kohanet` (external network для Koha/MariaDB інтеграції)
- `dspacenet` (external network для DSpace/PostgreSQL інтеграції)

### Host port policy
Порти публікуються тільки на loopback interface (`127.0.0.1`).
Детальна карта портів: `docs/architecture/ports-map.md`.

## 7. Security Architecture
### Security invariants
- Заборонено bind на `0.0.0.0` для monitoring сервісів.
- `GF_AUTH_ANONYMOUS_ENABLED=false`.
- Grafana sign-up вимкнений; default role для нових користувачів `Viewer`.
- DB exporters працюють з read-only обліковками.
- VictoriaMetrics API не публікується через edge.

### Identity and access
- Зовнішній доступ до Grafana: Cloudflare Access + MS Entra ID.
- RBAC у Grafana:
  - `ops-team`: Admin
  - stakeholders: Viewer

## 8. Observability Design
### Scrape and labels
- Базові обов'язкові labels: `env`, `service` (+ `component` за потреби).
- Продукційне середовище: `env=prod`.

### Dashboards
- P0 каталог дашбордів provisioned з JSON у `grafana/dashboards/`.
- Опис дашбордів: `docs/dashboards/dashboard-catalog.md`.

### Alerting
- Основні P0/P1 правила і routing задокументовані в `docs/alerting/alert-rules-catalog.md`.
- `VictoriaMetricsDown` налаштований як critical і перевірений outage/recovery тестом.

## 9. Надійність і DR
### Retention
- VictoriaMetrics retention: `90d`.

### Backup/Restore
- Backup через snapshot-архів volume з checksum.
- Smoke restore test на тимчасовому контейнері.
- Destructive restore сценарій задокументований окремо.
- Деталі: `docs/configuration/retention-policy.md`.

## 10. Deployment and Operations
### Стандартний запуск
- Ініціалізація volume директорій: `scripts/init-monitoring-volumes.sh`.
- Рендер scrape-config з template: `scripts/render-scrape-config.sh`.
- Підняття стеку: `docker compose up -d`.

### Операційні перевірки
- `docker compose ps`
- `curl http://127.0.0.1:8428/health`
- `curl http://127.0.0.1:3000/api/health`
- `ss -tlnp` для перевірки localhost-only bindings

### CI/CD
- Деплой та базові security/runtime checks реалізовано в GitHub Actions workflow.

## 11. Ризики і обмеження
- Single-node VM є точкою відмови до можливої міграції в cluster.
- Backup snapshot strategy включає коротке вікно недоступності VictoriaMetrics.
- Частина edge-security перевірок залежить від зовнішніх систем (Cloudflare/MS Entra), які не повністю валідуються локально.

## 12. Посилання на артефакти
- `docker-compose.yml`
- `victoria-metrics/scrape-config.tmpl.yml`
- `victoria-metrics/scrape-config.yml`
- `grafana/provisioning/`
- `alerting/rules/`
- `docs/architecture/monitoring-architecture.md`
- `docs/architecture/ports-map.md`
- `docs/deployment/monitoring-stack-deploy.md`
- `docs/security/monitoring-security-notes.md`
- `docs/configuration/retention-policy.md`
- `docs/alerting/alert-rules-catalog.md`
- `docs/ROADMAP.md`
