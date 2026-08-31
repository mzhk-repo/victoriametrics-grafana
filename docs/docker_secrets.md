# **План переведення деплою на автономну матеріалізацію Docker Secrets без Ansible**

## **Мета**

1. Повністю прибрати залежність від Ansible для секретів Docker Swarm у `victoriametrics-grafana`.
2. Забезпечити безпечне створення версіонованих Docker Secrets з розшифровуванням секретів виключно в ОЗП (`/dev/shm`) із гарантованим `cleanup trap` (`shred -u` або `rm -f`).
3. Додати надійний `cleanup trap` у `scripts/deploy-orchestrator-swarm.sh` для видалення тимчасових маніфестів (`.monitoring.stack.*`) і артефактів у разі падіння деплою (сигнали `EXIT`, `ERR`, `INT`, `TERM`).
4. Оновити GitHub Actions workflow (`.github/workflows/main.yml`), вимкнувши `use_ansible: false` (або вилучивши непотрібний крок `secrets`).

---

## **1. Запропоновані зміни**

### **1.1. GitHub Actions Pipeline (`.github/workflows/main.yml`)**

- Змінити `use_ansible: true` на `use_ansible: false` у джобах `deploy-dev` та `deploy-prod`.
- Тепер деплой виконуватиметься суто через `scripts/deploy-orchestrator-swarm.sh` із розшифрованим `ORCHESTRATOR_ENV_FILE`.

### **1.2. Оркестратор Swarm (`scripts/deploy-orchestrator-swarm.sh`)**

- **Вилучити/задизейблити `run_ansible_secrets_if_configured`**: Ansible більше не викликається для створення секретів.
- **Посилити `cleanup trap`**:
    - Зараз `trap 'rm -f "${raw_manifest:-}" "${deploy_manifest:-}"' RETURN` спрацьовує тільки при нормальному виході з функції.
    - Додати глобальний або функціональний trap на `EXIT ERR INT TERM`, який гарантовано видаляє тимчасові файли маніфестів (`.${STACK_NAME}.stack.raw.*`, `.${STACK_NAME}.stack.deploy.*`) та будь-які тимчасові файли навіть при падінні чи аварійному завершенні (`set -e`).

### **1.3. Створення версіонованих секретів (`scripts/render-versioned-env-secret.sh`)**

- Переконатися, що всі тимчасові файли секретів створюються виключно в `/dev/shm` (якщо каталог доступний) з правами `0600`.
- Удосконалити `cleanup trap`: використовувати `shred -u` (якщо встановлено) з fallback на `rm -f` при `EXIT ERR INT TERM`.
- Передача секретів у `docker secret create` відбувається через stdin або тимчасовий файл у `/dev/shm`, після чого файл негайно видаляється.
- Контейнери монтують секрети у `/run/secrets/`, а зміна значення веде до нового hash-суфікса та безшовного оновлення сервісів Swarm.

### **1.4. Документація та Changelog**

- Зафіксувати зміни у .
    
    **`docs/changelogs/CHANGELOG_2026_VOL_05.md`**
    
- Оновити  та архітектурні примітки за потреби.
    
    **`docs/scripts_runbook.md`**
    

---

## **2. План верифікації**

1. **Синтаксис shell**: `bash -n scripts/deploy-orchestrator-swarm.sh scripts/render-versioned-env-secret.sh`.
2. **Observability config test**: `bash tests/test-observability-config.sh`.
3. **Dry-run / Trap test**:
    - Перевірка генерації та очищення тимчасових файлів при емуляції збою.
    - Перевірка очищення файлів у `/dev/shm`.
4. **Валідація робочого процесу**: `git diff --check`.