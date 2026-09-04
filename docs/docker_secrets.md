# Автономна матеріалізація Docker Secrets у стеку VictoriaMetrics + Grafana

Цей документ описує архітектуру, перелік змінних та механізм автономної матеріалізації версіонованих Docker Secrets у стеку `victoriametrics-grafana` без використання Ansible.

---

## 1. Концепція та архітектурні принципи

1. **Zero-Disk для секретів**:
   - Розшифрування SOPS (`env.dev.enc` / `env.prod.enc`) виконується виключно в ОЗП (`/dev/shm`).
   - Тимчасові файли секретів створюються з правами `0600` у `/dev/shm` і гарантовано знищуються через `shred -u` (і fallback `rm -f`) по сигналах `EXIT ERR INT TERM`.
2. **Immutable Versioned Docker Secrets**:
   - Секрети генеруються з детермінованим суфіксом хешу значення (SHA-256, перші 12 символів): `<BASE_NAME>_<HASH>`.
   - Зміна секрету створює новий Docker Secret і викликає безшовний rolling update сервісів Swarm без потреби видаляти чи переписувати старі секрети.
3. **Пряме монтування через `/run/secrets/`**:
   - Сервіси не отримують паролі через `environment:` або змінні процесу на хості.
   - Паролі монтуються Docker Swarm як файли у `/run/secrets/<secret_name>` і зчитуються entrypoint-скриптами контейнерів.

---

## 2. Матриця змінних та Docker Secrets

| Ключ у SOPS Dotenv | Змінна імені секрету | Базова назва секрету | Контейнер/Сервіс | Цільовий шлях у контейнері |
|---|---|---|---|---|
| `GRAFANA_ADMIN_PASSWORD` | `GRAFANA_ADMIN_PASSWORD_SECRET_NAME` | `grafana_admin_password` | `grafana` | `/run/secrets/grafana_admin_password` |
| `GOOGLE_SMTP_PASSWORD` | `GOOGLE_SMTP_PASSWORD_SECRET_NAME` | `grafana_smtp_password` | `grafana` | `/run/secrets/grafana_smtp_password` |
| `MARIADB_EXPORTER_PASSWORD` | `MARIADB_EXPORTER_PASSWORD_SECRET_NAME` | `mariadb_exporter_password` | `mariadb-exporter` | `/run/secrets/mariadb_exporter_password` |
| `MATOMO_MARIADB_EXPORTER_PASSWORD` | `MATOMO_MARIADB_EXPORTER_PASSWORD_SECRET_NAME` | `matomo_mariadb_exporter_password` | `matomo-mariadb-exporter` | `/run/secrets/matomo_mariadb_exporter_password` |
| `SMTP2GRAPH_SYNTHETIC_PASSWORD` | `SMTP2GRAPH_SYNTHETIC_PASSWORD_SECRET_NAME` | `smtp2graph_synthetic_password` | `smtp2graph-synthetic-runner` | `/run/secrets/smtp2graph_synthetic_password` |

---

## 3. Компоненти оркестрації

### 3.1. GitHub Actions Workflow (`.github/workflows/main.yml`)
- У `deploy-dev` та `deploy-prod` встановлено `use_ansible: true`, що у shared workflow обирає Swarm+SOPS deploy path (назва input є історичною).
- Пайплайн передає керування безпосередньо у `scripts/deploy-orchestrator-swarm.sh` і не виконує legacy `docker compose up` після Swarm deploy.

### 3.2. Оркестратор Swarm (`scripts/deploy-orchestrator-swarm.sh`)
- **CLI прапорці**:
  - `--env-file FILE`: передача явного розшифрованого env-файлу.
  - `--deploy` / `--apply`: запуск деплою у Swarm (за замовчуванням `MODE="swarm"`).
  - `--check` / `--dry-run`: перевірка без внесення змін (`MODE="noop"`).
- **Auto-Decryption**:
  - Якщо `ENV_FILE` не передано або відсутній, скрипт визначає середовище через `SERVER_ENV` (`dev` або `prod`), розшифровує `env.${SERVER_ENV}.enc` у `/dev/shm` за допомогою `scripts/lib/autonomous-env.sh` або використовує `.env` для локальної розробки.
- **Cleanup Trap**:
  - Маніфести `.${STACK_NAME}.stack.raw.*.yml` та `.${STACK_NAME}.stack.deploy.*.yml` автоматично видаляються за сигналом `EXIT ERR INT TERM RETURN`, запобігаючи накопиченню сміття при падіннях деплою.

### 3.3. Рендерер секретів (`scripts/render-versioned-env-secret.sh`)
- Читає значення змінних з `ENV_FILE`.
- Для кожного секрету формує тимчасовий файл у `/dev/shm`, обчислює хеш, створює Docker Secret (`docker secret create`) за відсутності, та записує згенеровані назви `*_SECRET_NAME` назад у розшифрований `ENV_FILE`.
- Очищає пам'ять через `shred -u` на `EXIT ERR INT TERM`.

### 3.4. Ініціалізація томів (`scripts/init-volumes.sh`)
- Враховує `PRIV_MODE`:
  - `root`: прямі `chown`/`chmod`.
  - `sudo`: виклик через `sudo -n`.
  - `docker` (дефолт для CI/non-root оператора): використання ephemeral helper контейнера (`alpine:3.20`), що запобігає помилкам `Operation not permitted`.

---

## 4. Інструкція з ручного запуску та перевірки

### Деплой вручну на сервері (із зашифрованого SOPS файлу):

```bash
# 1. Запуск з автоматичним розшифруванням за SERVER_ENV:
SERVER_ENV=dev bash scripts/deploy-orchestrator-swarm.sh

# 2. Або з явним розшифруванням у /dev/shm:
ENV_TMP="$(mktemp /dev/shm/env-XXXXXX)"
chmod 600 "${ENV_TMP}"
sops --decrypt --input-type dotenv --output-type dotenv env.dev.enc > "${ENV_TMP}"

bash scripts/deploy-orchestrator-swarm.sh --env-file "${ENV_TMP}" --deploy --apply

shred -u "${ENV_TMP}" 2>/dev/null || rm -f "${ENV_TMP}"
```

### Перевірка створених секретів у Docker Swarm:

```bash
docker secret ls | grep -E 'grafana|mariadb|matomo|smtp2graph'
```

### Перевірка здоров'я сервісів стеку:

```bash
docker stack services monitoring
docker service ps monitoring_grafana --no-trunc
docker service ps monitoring_victoriametrics --no-trunc
docker service ps monitoring_smtp2graph-synthetic-runner --no-trunc
```
