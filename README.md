# Observability Structure

Це базова структура для observability stack (Phase 0).
На цьому етапі створюємо каркас директорій і документацію, без фактичного production deploy.

## Директорії

- `victoria-metrics/` — scrape-конфіг для VictoriaMetrics
- `grafana/provisioning/` — provisioning datasource/dashboards/alerting
- `grafana/dashboards/` — JSON дашборди
- `alerting/rules/` — YAML правила алертів
- `exporters/` — compose-фрагменти exporter-ів
