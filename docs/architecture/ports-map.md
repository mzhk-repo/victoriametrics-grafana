# Ports Map (Monitoring)

| Компонент | Порт | Bind | Примітка |
|-----------|------|------|----------|
| VictoriaMetrics | 8428 | `127.0.0.1` | TSDB API + /targets |
| Grafana | 3000 | `127.0.0.1` | Доступ через Cloudflare Tunnel |
| Node Exporter | 9100 | `127.0.0.1` | Host metrics |
| cAdvisor | 8081 | `127.0.0.1` | Container metrics |
| MariaDB Exporter | 9104 | `127.0.0.1` | Koha DB metrics |
| PostgreSQL Exporter | 9187 | `127.0.0.1` | DSpace DB metrics |
| Elasticsearch Exporter | 9114 | `127.0.0.1` | ES metrics (P1) |
| RabbitMQ Prometheus | 15692 | `127.0.0.1` | RabbitMQ metrics (P1) |
| KDV Integrator `/metrics` | 5001 | `127.0.0.1` | App metrics (P1) |
