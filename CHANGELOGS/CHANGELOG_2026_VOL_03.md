# CHANGELOG 2026 VOL 03

## [2026-03-10] — Rotation: старт нового тому changelog

- **Context:** `CHANGELOG_2026_VOL_02.md` досяг soft limit `300` рядків згідно політики ротації.
- **Change:** Створено новий активний том `CHANGELOGS/CHANGELOG_2026_VOL_03.md`.
- **Verification:** Перевірено наявність нового файлу в `CHANGELOGS/`.
- **Risks:** Відсутні (організаційна зміна, без впливу на runtime).
- **Rollback:** Видалити новий том і повернути `VOL_02` як active в `CHANGELOG.md`.

## [2026-03-10] — Phase 5 (інкремент 3): Grafana RBAC baseline (Admin/Viewer)

- **Context:** Наступний крок Phase 5: `Grafana RBAC` з розподілом ролей `Admin` для `ops-team` і `Viewer` для stakeholders.
- **Change:**
	- Оновлено `docker-compose.yml` (сервіс `grafana`):
		- `GF_USERS_ALLOW_SIGN_UP=false`
		- `GF_USERS_AUTO_ASSIGN_ORG=true`
		- `GF_USERS_AUTO_ASSIGN_ORG_ROLE=${GRAFANA_AUTO_ASSIGN_ORG_ROLE:-Viewer}`
	- Оновлено `.env.example`:
		- додано `GRAFANA_AUTO_ASSIGN_ORG_ROLE=Viewer`.
	- Додано новий обов'язковий security-документ:
		- `docs/security/monitoring-security-notes.md` (RBAC policy, validation, risks, rollback).
	- У `docs/ROADMAP.md` відмічено виконання пункту `Grafana RBAC: admin для ops-team, viewer для stakeholders`.
- **Verification:**
	- `docker compose -f docker-compose.yml config -q` проходить без помилок.
	- Очікуваний runtime результат: нові користувачі отримують роль `Viewer` за замовчуванням, self-signup вимкнений.
- **Risks:** Призначення `ops-team` у роль `Admin` лишається операційним кроком в Grafana org (після входу адміністратора).
- **Rollback:** Повернути попередні `GF_USERS_*` параметри у `docker-compose.yml`/`.env`, перезапустити Grafana.

## [2026-03-10] — Phase 5 (інкремент 4): backup VictoriaMetrics volume + restore test

- **Context:** Наступний P0-крок роадмапи: налаштувати backup VictoriaMetrics volume і підтвердити відновлення.
- **Change:**
	- Додано скрипт `scripts/backup-victoriametrics-volume.sh`:
		- консистентний backup через короткий stop/start `victoriametrics`;
		- архівація у `VM_BACKUP_DIR` (`vmdata-YYYYMMDD-HHMMSS.tar.gz`);
		- генерація checksum `.sha256`;
		- ротація архівів за `VM_BACKUP_RETENTION_COUNT`.
	- Додано скрипт `scripts/test-victoriametrics-restore.sh`:
		- валідація checksum;
		- підняття тимчасового VM контейнера з backup-даних;
		- health smoke test через `http://127.0.0.1:${VM_RESTORE_TEST_PORT}/health`.
	- Оновлено `.env.example`:
		- `VM_BACKUP_DIR`, `VM_BACKUP_RETENTION_COUNT`, `VM_RESTORE_TEST_PORT`.
	- Додано документацію `docs/configuration/retention-policy.md` (policy + cron приклади).
	- Оновлено `docs/deployment/monitoring-stack-deploy.md` секцією backup/restore.
	- В `docs/ROADMAP.md` відмічено виконання backup-пункту Phase 5 та чекпойнту `VM volume backup налаштований та протестований`.
- **Verification:**
	- `./scripts/backup-victoriametrics-volume.sh` -> backup архів і `.sha256` створені.
	- `./scripts/test-victoriametrics-restore.sh` -> `Restore smoke test passed`.
	- Перевірено checksum: `vmdata-...tar.gz: OK`.
- **Risks:** Backup-скрипт робить короткий stop/start `victoriametrics`, що дає невелике вікно недоступності.
- **Rollback:** Видалити/відкотити нові backup-скрипти та змінні `.env.example`, повернути попередню документацію.

## [2026-03-10] — Phase 5 (інкремент 4.1): init volumes + повний restore backup

- **Context:** Додаткові операційні вимоги до backup-напрямку: ініціалізація директорій томів із `.env` та окремий бойовий restore-скрипт.
- **Change:**
	- Додано `scripts/init-monitoring-volumes.sh`:
		- читає шляхи томів із `.env` (`VM_DATA_DIR`, `VM_BACKUP_DIR`, `GRAFANA_DATA_DIR`, `GRAFANA_LOGS_DIR`);
		- створює директорії;
		- виставляє owner/mode (VM: `root:root`, Grafana: з `GRAFANA_CONTAINER_USER`);
		- підтримує `--dry-run`.
	- Додано `scripts/restore-victoriametrics-backup.sh` (destructive restore):
		- валідує checksum архіву (якщо є `.sha256`);
		- зупиняє `victoriametrics`, очищає `VM_DATA_DIR`, розпаковує backup;
		- піднімає `victoriametrics` і перевіряє `/health`;
		- підтримує `--yes` (підтвердження) і `--dry-run`.
	- Оновлено документацію:
		- `docs/configuration/retention-policy.md`
		- `docs/deployment/monitoring-stack-deploy.md`.
- **Verification:**
	- `bash -n scripts/init-monitoring-volumes.sh`
	- `bash -n scripts/restore-victoriametrics-backup.sh`
	- `./scripts/init-monitoring-volumes.sh --dry-run`
	- `./scripts/restore-victoriametrics-backup.sh --dry-run`
- **Risks:** Неправильні права/власник на `/srv/...` можуть вимагати запуск через `sudo`.
- **Rollback:** Видалити нові скрипти й повернути попередню версію docs.

## [2026-03-10] — Phase 5 (інкремент 4.2): alerts для backup creation і smoke restore success

- **Context:** Потрібно алертити на відсутність успішного backup і відсутність успішного smoke restore test.
- **Change:**
	- `node-exporter` переведено на textfile collector для backup-метрик:
		- `--collector.textfile.directory=/vm-backup-metrics`
		- mount `${VM_BACKUP_DIR}:/vm-backup-metrics:ro`
	- `scripts/backup-victoriametrics-volume.sh` записує `vm_backup.prom` з метриками `kdi_vm_backup_*`.
	- `scripts/test-victoriametrics-restore.sh` записує `vm_restore_smoke.prom` з метриками `kdi_vm_restore_smoke_*`.
	- Додано Grafana provisioning rules: `grafana/provisioning/alerting/backup-alerts.yml`:
		- `VictoriaMetricsBackupStale` (critical)
		- `VictoriaMetricsRestoreSmokeStale` (warning)
	- Оновлено Prometheus-style catalog rules: `alerting/rules/monitoring.yml`.
	- Додано runbook: `docs/runbooks/vm-backup-restore.md`.
	- Оновлено `docs/alerting/alert-rules-catalog.md` і `docs/configuration/retention-policy.md`.
- **Verification:**
	- Після запуску backup/smoke скриптів з'являються файли `vm_backup.prom` і `vm_restore_smoke.prom` у `VM_BACKUP_DIR`.
	- Метрики доступні через node-exporter (`/metrics`) і у VictoriaMetrics query.
	- Після рестарту Grafana provisioning завантажує `backup-alerts.yml`.
- **Risks:** Якщо backup/smoke скрипти не виконуються регулярно (cron/systemd timer), alerts будуть спрацьовувати як stale.
- **Rollback:** Видалити `backup-alerts.yml`, прибрати textfile collector mount/flag, повернути попередні версії скриптів.

## [2026-03-10] — Phase 5 (інкремент 5): верифікація `VictoriaMetricsDown` (observability of observability)

- **Context:** У Phase 5 залишався production-блокер: підтвердити, що алерт `VictoriaMetricsDown` справді critical і коректно працює при падінні VictoriaMetrics.
- **Change:**
	- Оновлено `grafana/provisioning/alerting/alert-rules.yml` для правила `victoriametrics-down`:
		- `noDataState: NoData` (щоб уникнути false-positive у healthy стані);
		- `execErrState: Alerting` (щоб алерт спрацьовував при повній недоступності datasource).
	- Оновлено `docs/ROADMAP.md`: пункт Phase 5 про `VictoriaMetricsDown` позначено як виконаний.
- **Verification:**
	- Перевірено runtime API правила:
		- `title=VictoriaMetricsDown`, `severity=critical`, `for=2m`, `noDataState=NoData`, `execErrState=Alerting`.
	- Проведено контрольований outage test:
		- `docker compose stop victoriametrics` -> після вікна оцінки алерт `VictoriaMetricsDown` переходить в `active`.
		- `docker compose start victoriametrics` -> після recovery/evaluation алерт очищається (active count -> `0`).
- **Risks:** Під час ручного outage test зупинка `victoriametrics` може тимчасово згенерувати `DatasourceError` для інших правил (очікувана поведінка під час тесту).
- **Rollback:** Повернути попередні `noDataState/execErrState` у `grafana/provisioning/alerting/alert-rules.yml` і виконати `docker compose restart grafana`.