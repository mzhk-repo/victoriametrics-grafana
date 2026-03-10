# Monitoring Security Notes

## Мета
Зафіксувати security-базу для production-ready monitoring stack (VictoriaMetrics + Grafana) та правила доступу.

## Security інваріанти
- Всі monitoring порти публікуються тільки на `127.0.0.1`.
- Grafana доступна зовні лише через Cloudflare Tunnel + Access policy.
- `GF_AUTH_ANONYMOUS_ENABLED=false` (анонімний доступ заборонено).
- Секрети зберігаються тільки в `.env` (не в Git).
- DB exporters використовують тільки read-only користувачів.

## Grafana RBAC policy (Phase 5)
- `ops-team` -> роль `Admin` в Grafana org.
- `stakeholders` -> роль `Viewer`.
- Роль за замовчуванням для нових користувачів: `Viewer`.

### Поточна реалізація в цьому репозиторії
- У `docker-compose.yml` увімкнено:
  - `GF_USERS_ALLOW_SIGN_UP=false`
  - `GF_USERS_AUTO_ASSIGN_ORG=true`
  - `GF_USERS_AUTO_ASSIGN_ORG_ROLE=${GRAFANA_AUTO_ASSIGN_ORG_ROLE:-Viewer}`
- У `.env.example` зафіксовано default:
  - `GRAFANA_AUTO_ASSIGN_ORG_ROLE=Viewer`

## Операційні кроки для ролей
1. Увійти під Grafana admin.
2. Додати користувачів/групи `ops-team` як `Admin`.
3. Переконатися, що всі користувачі `stakeholders` мають `Viewer`.
4. Перевірити, що новий тестовий користувач автоматично отримує `Viewer`.

## Перевірка (Validation)
- `curl -s http://127.0.0.1:3000/api/health` -> `{"database":"ok"...}`
- У Grafana: `Administration -> Users and access`:
  - self-sign-up вимкнений;
  - default role = `Viewer`;
  - `ops-team` має `Admin`.

## Ризики
- Якщо default role помилково змінити на `Editor` або `Admin`, stakeholders отримають зайві права.
- Якщо повторно увімкнути sign-up, можливе неконтрольоване створення акаунтів.

## Rollback
- Повернути попередні значення `GF_USERS_*` у `docker-compose.yml` / `.env`.
- Перезапустити Grafana: `docker compose restart grafana`.
