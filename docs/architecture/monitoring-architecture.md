# Monitoring Architecture (KDI)

## Мета
Описати цільову архітектуру observability stack для KDI.

## Компоненти
- VictoriaMetrics (`127.0.0.1:8428`) — зберігання метрик
- Grafana (`127.0.0.1:3000`) — візуалізація та alerting
- Exporters (host/db/container/proxy/app) — джерела метрик

## Мережева модель
- Всі monitoring-порти доступні тільки на `127.0.0.1`
- Публічний доступ дозволено тільки до Grafana через Cloudflare Tunnel + Access
- VictoriaMetrics API не публікується назовні

## Дані та потік
1. Exporters віддають `/metrics`
2. VictoriaMetrics scrape-ить targets за `scrape-config.yml`
3. Grafana читає дані з VictoriaMetrics datasource
4. Alerting працює через Grafana provisioning

## Security інваріанти
- Заборонено `0.0.0.0:PORT` для monitoring сервісів
- Секрети лише в `.env`, не в Git
- Для DB exporters використовуються тільки read-only користувачі
