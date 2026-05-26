# Runbook: Website Probe Alerts (Koha)

## Тригери
- `WebsiteDown` (critical): `probe_success < 1` для `koha-opac` або `koha-staff`
- `WebsiteHighLatency` (warning): `probe_duration_seconds > 2s`

## Що означає
Blackbox Exporter не отримує коректну HTTP-відповідь 2xx або отримує надто повільну відповідь. Поточні локальні probes перевіряють internal route `blackbox-exporter -> traefik -> service` з Host header відповідного public hostname, без виходу через Cloudflare edge.

## Дії
1. Перевірити internal probe з `blackbox-exporter` до `http://traefik...` з потрібним Host header.
2. Перевірити Traefik route/service labels і підключення `blackbox-exporter` до `proxy-net`.
3. Перевірити upstream (Koha/Apache/Plack, DSpace, Matomo) і логи реверс-проксі.
4. Якщо недоступний тільки один сайт, ізолювати проблему до конкретного endpoint.

## Перевірка відновлення
- `probe_success=1` стабільно 5+ хв
- `probe_duration_seconds` повернувся до baseline
- Алерт автоматично перейшов у resolved
