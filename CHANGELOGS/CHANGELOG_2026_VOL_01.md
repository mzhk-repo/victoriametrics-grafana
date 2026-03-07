# CHANGELOG 2026 VOL 01

## [2026-03-07] — Phase 0 старт: структура та ADR база

- **Context:** Старт `Phase 0 — Pre-Flight`, підготовка репозиторію до подальшого deployment етапу.
- **Change:** Створено каркас monitoring stack у корені репо (`docker-compose.monitoring.yml`, `victoria-metrics/`, `grafana/`, `alerting/`, `exporters/`), додано `ADR-001..003`, створено `docs/architecture/monitoring-architecture.md` та `docs/architecture/ports-map.md`, ініціалізовано changelog-том.
- **Verification:** Перевірено наявність структури директорій та файлів; перевірено disk space (`df -h .`) — доступно 27G.
- **Risks:** Конфігураційні файли поки placeholder; фактичний deploy не виконано (очікується у Phase 1).
- **Rollback:** `git revert <commit>` після коміту змін.
