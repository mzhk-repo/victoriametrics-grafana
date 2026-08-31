## [2026-08-31] — SMTP2Graph synthetic alert: derive freshness from runner schedule

- **Context:** A fixed 1,200-second freshness threshold caused false alerts when an environment used a longer synthetic-delivery interval.
- **Change:** The runner now exports `smtp2graph_synthetic_freshness_threshold_seconds`, calculated as `SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS + SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS`; the grace default is `300` seconds. Both VictoriaMetrics and Grafana alert rules consume the exported threshold.
- **Verification:** Unit and configuration tests cover threshold emission, input validation, and both alert definitions.
- **Risks:** A grace period that is too small can alert during normal delivery or scrape delay; an excessive one delays detection.
- **Rollback:** Remove the threshold metric use and restore a fixed alert threshold only if all environments return to a common interval.

## [2026-08-31] — SMTP2Graph synthetic runner: configurable delivery interval

- **Context:** The runner had a hardcoded 15-minute interval, preventing per-environment tuning of synthetic email frequency.
- **Change:** Added `SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS` to the Swarm runtime contract and `.env.example`; default is `900` seconds. Runner startup validates a positive integer interval of at least `60` seconds before entering the loop.
- **Verification:** Configuration test asserts the env contract and variable-based `sleep`; static Compose rendering validates the default.
- **Risks:** Lower intervals generate more synthetic email and Graph API traffic; use a non-production recipient and keep the configured timeout below the interval.
- **Rollback:** Remove the environment setting and restore the fixed `900` second sleep.

## [2026-08-31] — SMTP2Graph synthetic alert: align Node Exporter labels

- **Context:** Synthetic textfile metrics were ingested successfully, but Node Exporter's static target labels overrode `service="smtp2graph"` with `service="host"`, preserving the original as `exported_service="smtp2graph"`; the alert and dashboard query returned no data.
- **Change:** Updated synthetic alert rules and the SMTP2Graph dashboard to match `service="host", exported_service="smtp2graph"`. Added regression checks and documented the label transformation.
- **Verification:** Live VictoriaMetrics query returned `smtp2graph_synthetic_last_status=1` with the new matcher labels.
- **Risks:** Any future change to Node Exporter target labels must update the synthetic alert/dashboard matchers together.
- **Rollback:** Restore the prior label matchers only if the Node Exporter scrape target stops defining `service="host"`.

## [2026-08-31] — SMTP2Graph synthetic runner: expose textfile metrics to Node Exporter

- **Context:** Synthetic delivery succeeded, but Node Exporter logged `permission denied` for `smtp2graph_synthetic.prom`, so VictoriaMetrics and Grafana could not observe the result.
- **Change:** The runner now sets mode `0644` on its temporary Prometheus textfile before the atomic rename. Added a unit assertion for the final file mode and documented the collector-read requirement.
- **Verification:** Unit test validates the metric content remains secret-free and the published textfile is world-readable; runtime validation requires redeploying the runner and checking Node Exporter no longer logs textfile permission errors.
- **Risks:** The textfile contains only aggregate status and timestamps; mode `0644` does not expose credentials or message content.
- **Rollback:** Revert the mode change; Node Exporter ingestion of this textfile will fail again for non-owner users.

## [2026-08-28] — SMTP2Graph synthetic runner: use gateway overlay alias

- **Context:** Swarm synthetic runner received `SMTP2GRAPH_SYNTHETIC_HOST=127.0.0.1` and failed with `ConnectionRefusedError`; loopback resolves to the runner itself, not SMTP2Graph.
- **Change:** Set the example contract to the encrypted-overlay gateway DNS alias `gateway` and document the required separation between SMTP TCP host (`gateway`) and TLS server name (`smtp-int.pinokew.buzz`).
- **Verification:** From `monitoring_smtp2graph-synthetic-runner`, `gateway` resolved to `10.0.8.2` and a TCP connection to `gateway:2525` succeeded.
- **Risks:** The encrypted runtime env must be updated and the Swarm stack redeployed; the result still depends on valid STARTTLS, authentication and recipient policy at the gateway.
- **Rollback:** Restore the prior runtime host only if an alternate reachable SMTP endpoint is intentionally configured.

## [2026-08-28] — Grafana alert delivery: migrate from MS365 SMTP to Google SMTP

- **Context:** Alert delivery must use Google Workspace/Gmail SMTP instead of the MS365 relay.
- **Change:** Replaced the `MS365_*` alert-delivery contract with `GOOGLE_*` in Compose, Swarm, Grafana contact points and versioned Docker-secret rendering. Default endpoint is `smtp.gmail.com:587`; Grafana enforces `MandatoryStartTLS`. Updated operational and product documentation.
- **Verification:** Static Compose rendering and configuration checks are required before deployment; the Google App Password remains in the encrypted runtime env and is never committed.
- **Risks:** Google SMTP submission requires a permitted account and App Password (or an approved Workspace SMTP relay). Existing encrypted env files must be migrated from `MS365_*` to `GOOGLE_*` before deployment.
- **Rollback:** Restore the previous `MS365_*` contract and redeploy Grafana.

## [2026-05-08] — VictoriaMetrics backup: fix autonomous env loading, rclone upload, and alert age logic
- **Context:** `SERVER_ENV=prod bash scripts/backup-victoriametrics-volume.sh` падав під час завантаження decrypted `env.prod.enc` з `/dev/shm`: Bash `source` ламався на dotenv-значенні `MARIADB_EXPORTER_DSN` з `tcp(...)`.
- **Change:**
- Оновлено `scripts/lib/autonomous-env.sh`: dotenv тепер читається без `source`/`eval`, з явним парсингом `KEY=VALUE`, щоб значення з дужками або пробілами не виконувалися як shell-код.
- Оновлено `scripts/backup-victoriametrics-volume.sh`:
	- rclone upload переведено на streaming через Docker mount + `rclone rcat`, бо host user не має прямого доступу до `/data/backup/victoriametrics-grafana`;
	- локальну ротацію backup-ів переведено на Docker container, щоб вона також не залежала від host permissions.
- Оновлено `grafana/provisioning/alerting/backup-alerts.yml`: Grafana alert queries для backup/restore тепер повертають age metric, а пороги `93600` і `691200` застосовуються в evaluator; це не перетворює нормальний стан на empty vector при `noDataState=Alerting`.
- **Verification:**
- `SERVER_ENV=prod bash scripts/backup-victoriametrics-volume.sh` успішно створив backup `vmdata-20260508-133241.tar.gz` і завантажив його в `gdrive-backup:victoriametrics`.
- `SERVER_ENV=prod bash scripts/test-victoriametrics-restore.sh` успішно перевірив checksum і restore smoke test пройшов на 2-й спробі.
- Node exporter показує `kdi_vm_backup_*` і `kdi_vm_restore_smoke_*` зі status `1`.
- VictoriaMetrics API повертає backup/restore series з labels `job="node-exporter"`, `service="host"`, `exported_service="monitoring"`.
- Age queries для Grafana alert-ів повернули свіжі значення нижче порогів.
- `bash -n` для env loader, backup і restore scripts успішний; `grafana/provisioning/alerting/backup-alerts.yml` валідний YAML; `git diff --check` успішний.
- **Risks:** Якщо rclone remote або шлях у SOPS env зміняться, backup завершиться помилкою після старту VictoriaMetrics назад і запише failure metric.
- **Rollback:** Повернути `source`-loader тільки після обов'язкового quoting усіх shell-sensitive dotenv values; повернути rclone `copyto` тільки якщо host user має read/execute доступ до backup directory.

## [2026-05-08] — DSpace backup/restore freshness alerts
- **Context:** DSpace repo додав textfile metrics для backup і restore smoke; monitoring stack має підняти alerts за тим самим freshness-патерном, що VictoriaMetrics/Matomo.
- **Change:**
- Додано Prometheus-style catalog rules у `alerting/rules/monitoring.yml`:
	- `DSpaceBackupStale` — critical, якщо немає успішного backup понад 26 годин;
	- `DSpaceRestoreSmokeStale` — warning, якщо немає успішного restore smoke понад 8 діб.
- Додано Grafana provisioning rules у `grafana/provisioning/alerting/backup-alerts.yml`.
- Оновлено `docs/alerting/alert-rules-catalog.md`.
- **Verification:** YAML parse для `backup-alerts.yml` і `monitoring.yml` успішний; VictoriaMetrics API повертає `dspace_backup_last_success_timestamp_seconds` і `dspace_restore_smoke_last_success_timestamp_seconds` з labels `job="node-exporter"`, `service="host"`, `exported_service="dspace"`; age queries повернули свіжі значення нижче порогів.
- **Risks:** Якщо DSpace backup/test-restore cron не запускаються регулярно або textfile path розійдеться з mount-ом node-exporter, alerts перейдуть у stale/no-data.
- **Rollback:** Видалити DSpace alert rules з `backup-alerts.yml`, `monitoring.yml` і catalog docs.

## [2026-05-10] — Koha backup/restore freshness alerts
- **Context:** Koha backup і restore smoke scripts додають textfile collector metrics; monitoring stack має alert-и за тим самим freshness-патерном, що DSpace/VictoriaMetrics.
- **Change:**
- Додано Prometheus-style catalog rules у `alerting/rules/monitoring.yml`:
	- `KohaBackupStale` — critical, якщо немає успішного backup понад 26 годин;
	- `KohaRestoreSmokeStale` — warning, якщо немає успішного restore smoke понад 8 діб.
- Додано Grafana provisioning rules у `grafana/provisioning/alerting/backup-alerts.yml`; query повертає age, thresholds `93600` і `691200` задані через evaluator.
- Оновлено `docs/alerting/alert-rules-catalog.md`.
- **Verification:** YAML parse для `backup-alerts.yml` і `monitoring.yml` успішний; node-exporter читає `koha_backup_*` і `koha_restore_smoke_*` з `node_textfile_scrape_error=0`; VictoriaMetrics API повертає `koha_backup_last_success_timestamp_seconds` і `koha_restore_smoke_last_success_timestamp_seconds` з labels `job="node-exporter"`, `service="host"`, `exported_service="koha"`; age expressions для Koha backup/restore нижче порогів і alert threshold queries повертають empty vector; `docker service update --force monitoring_grafana` завершився converged, Grafana logs показали `finished to provision alerting`.
- **Risks:** Якщо Koha cron не запускає backup/test-restore регулярно або textfile path не змонтовано в node-exporter, alerts перейдуть у stale/no-data.
- **Rollback:** Видалити Koha alert rules з `backup-alerts.yml`, `monitoring.yml` і catalog docs.

## [2026-05-11] — Data volume alerts for `/data` and `/data2`
- **Context:** Oracle Linux KVM node має два критичні XFS data volume-и: `/data` на `vdb` і `/data2` на `vdc`; потрібні окремі Grafana alert-и без додаткового dashboard JSON.
- **Change:**
- Додано Grafana Unified Alerting provisioning rules у `grafana/provisioning/alerting/data-volumes.yml`:
	- `DataVolumesFreeSpaceWarning` — warning, якщо вільне місце на `/data` або `/data2` нижче 15%;
	- `DataVolumesFreeSpaceCritical` — critical, якщо вільне місце на `/data` або `/data2` нижче 5%;
	- `DataVolumesRunoutPredictedWarning` — warning, якщо `predict_linear` за 24 години прогнозує вичерпання місця протягом 4 днів;
	- `DataVolumesReadLatencyWarning` і `DataVolumesWriteLatencyWarning` — warning, якщо середня latency на `vdb` або `vdc` понад 100ms.
- Додано Prometheus-style catalog rules у `alerting/rules/data-volumes.yml`.
- Оновлено `docs/alerting/alert-rules-catalog.md`.
- **Verification:** YAML parse для `grafana/provisioning/alerting/data-volumes.yml` і `alerting/rules/data-volumes.yml` успішний; VictoriaMetrics API повертає series для `/data`, `/data2`, `vdb` і `vdc`; free-space expressions показали `/data` ~98.03% і `/data2` ~97.61% вільного місця, threshold queries повернули empty vector у healthy стані; `predict_linear` повернув позитивний прогноз вільних байтів для обох volume-ів; read/write latency expressions повернули значення значно нижче 100ms, threshold queries повернули empty vector; `docker service update --force monitoring_grafana` завершився `converged`, Grafana logs показали `finished to provision alerting`, а Grafana DB містить UID/title нових `DataVolumes*` правил.
- **Risks:** Якщо labels node-exporter відрізняються від `job="node-exporter", env="prod", service="host"` або device names зміняться після перезавантаження VM, алерти перейдуть у no-data.
- **Rollback:** Видалити `grafana/provisioning/alerting/data-volumes.yml`, `alerting/rules/data-volumes.yml` і записи з catalog/changelog.

## [2026-05-12] — Traefik dashboard: support Swarm service labels
- **Context:** Після переведення Traefik на Docker Swarm network частина панелей Grafana dashboard не показувала service-level метрики, хоча VictoriaMetrics scrape target `job="traefik"` був `UP`.
- **Change:** Оновлено `grafana/dashboards/traefik-v3-official-17346.json`: змінна `service` тепер приймає labels `.*@(docker|swarm)` замість тільки `.*@docker`.
- **Verification:** VictoriaMetrics повертає актуальні Traefik services з labels `dspace-api@swarm`, `dspace-ui@swarm`, `grafana@swarm`, `koha-opac@swarm`, `koha-staff@swarm`, `matomo@swarm`, `portainer@swarm`; старий фільтр `.*@docker` повертав empty vector.
- **Risks:** Якщо у майбутньому Traefik provider label зміниться на інший suffix, змінну dashboard потрібно буде розширити.
- **Rollback:** Повернути фільтр змінної `service` у dashboard до `.*@docker`.

## [2026-05-12] — VictoriaMetrics scrape config: refresh Swarm service on config changes
- **Context:** Dashboard `KDI Cloudflare Tunnel Overview` не показував Cloudflare metrics після додання scrape job, хоча endpoint `http://cf_tunnel_tunnel:2000/metrics` був доступний з контейнера VictoriaMetrics і віддавав `cloudflared_tunnel_*`/`quic_client_*`.
- **Root cause:** `scripts/render-scrape-config.sh` оновлює `victoria-metrics/scrape-config.yml` через атомарний `mv`; Swarm service мав file-level bind mount на старий inode, тому runtime `/etc/vm/scrape-config.yml` і `/config` у VictoriaMetrics не містили job `cloudflare-tunnel`.
- **Change:** Оновлено `scripts/deploy-orchestrator-swarm.sh`: deploy тепер рахує checksum scrape config до/після render і, якщо файл змінився, після `docker stack deploy` виконує `docker service update --force ${STACK_NAME}_victoriametrics`; якщо service ще не існує, deploy лишає старт нового task зі свіжим bind mount.
- **Verification:** Ручний `docker service update --force monitoring_victoriametrics` відновив Cloudflare metrics у Grafana; `bash -n scripts/deploy-orchestrator-swarm.sh` і `git diff --check` успішні.
- **Risks:** Зміна restart-ить тільки VictoriaMetrics і тільки при зміні scrape config; під час rolling update можливий короткий розрив scrape/query availability.
- **Rollback:** Видалити checksum-gate і `docker service update --force` блок із `scripts/deploy-orchestrator-swarm.sh`; після ручних змін scrape config знову потрібен явний restart VictoriaMetrics service.

## [2026-05-13] — Alert noise hardening for Grafana NoData and Swarm container names
- **Context:** Періодично надходили `DatasourceNoData`/container alerts, хоча scrape targets і контейнери були `UP`; live VictoriaMetrics queries показали empty vector для healthy `absent_over_time` rules, старий Compose-only cAdvisor regex і невдалий Matomo archiving collector через Swarm task names.
- **Change:**
- Оновлено Grafana provisioning і Prometheus-style rules:
	- DB/VictoriaMetrics down rules переведено на `present_over_time(...) or vector(0)` з threshold `< 1`;
	- `TraefikHighErrorRate` отримав fallback `or vector(0)` і `clamp_min`, щоб відсутність 5xx series не ставала NoData;
	- `MatomoDatabaseSizeHigh` і `MatomoArchivingStale` отримали numeric fallback замість empty vector;
	- `ContainerDown` тепер рахує очікувані monitoring containers і підтримує Swarm names `monitoring_<service>.1.*`;
	- `ContainerHighRestarts` підтримує Compose і Swarm container names.
- Оновлено `scripts/collect-matomo-archiving-metric.sh` і `scripts/collect-matomo-db-size.sh`: якщо exact container name з env не знайдено, скрипти шукають Swarm task name із суфіксом `.1.*`.
- `scripts/collect-matomo-db-size.sh` тепер використовує `MATOMO_DB_NAME` з env-file або дефолт `matomo`, якщо `DB_NAME` у Matomo DB контейнері порожній.
- Оновлено `docs/alerting/alert-rules-catalog.md`, `docs/configuration/exporters-config.md` і `docs/scripts_runbook.md`.
- **Verification:** `bash -n` для Matomo collector scripts успішний; YAML parse для змінених alert/provisioning files успішний; `git diff --check` успішний; live VictoriaMetrics queries повертають numeric healthy values для DB/VictoriaMetrics/Traefik/container/Matomo DB size rules; `collect-matomo-archiving-metric.sh` оновив `matomo_archiving_last_success_timestamp` і status `1`; `collect-matomo-db-size.sh` з `MATOMO_DB_NAME=matomo` записав `kdi_matomo_database_size_bytes=31031296` і status `1`.
- **Risks:** `ContainerDown` очікує 7 monitoring containers; якщо склад monitoring stack зміниться, поріг треба оновити разом із regex.
- **Rollback:** Повернути попередні PromQL expressions і видалити fallback resolution для Swarm task names у Matomo collector scripts.

## [2026-05-16] — Grafana mute timing for daily backup window
- **Context:** Під час консистентного VictoriaMetrics backup сервіс коротко зупиняється, що може створювати шторм alert notifications у Grafana.
- **Change:** Оновлено `grafana/provisioning/alerting/notification-policies.yml`: додано provisioned mute timing `daily-backup-window` з вікном `00:55`–`01:45` у timezone `Europe/Kyiv`; critical і warning routes тепер посилаються на нього через `mute_time_intervals`. Оператори `object_matchers` взято в лапки як рядки для валідного YAML parse.
- **Verification:** `grafana/provisioning/alerting/notification-policies.yml` успішно проходить YAML parse через PyYAML. Runtime reload/deploy Grafana не виконувався в межах цієї ітерації.
- **Risks:** У backup-вікно notifications для `severity=critical` і `severity=warning` не надсилатимуться, але alert evaluation і стан alert instances продовжать працювати.
- **Rollback:** Видалити `muteTimes.daily-backup-window` і `mute_time_intervals` з routes у `notification-policies.yml`, після чого повторно застосувати Grafana provisioning.

## [2026-05-26] — Internal website probes and Traefik latency NoData fallback
- **Context:** Локальні blackbox probes перевіряли public URL через Cloudflare edge і tunnel назад у той самий origin stack. Під час timeout до Cloudflare edge IP `188.114.96.11/188.114.97.11` сервіси лишалися доступними всередині Swarm, але Grafana отримувала `WebsiteDown`/`MatomoDown`/`DSpaceWebsiteDown` і latency alerts. Окремо `TraefikHighLatency` міг давати `DatasourceNoData`, коли histogram bucket series відсутні у вікні.
- **Change:**
- `blackbox-exporter` підключено до `proxy-net`, щоб він міг ходити до internal Traefik service.
- Додано blackbox modules `http_2xx_internal_*` з Host header для Koha, Matomo і DSpace.
- Website scrape jobs у `victoria-metrics/scrape-config.tmpl.yml` переведено на targets `http://traefik/` або `http://traefik/server/`; public URL з env лишається у labels `public_instance`/`instance` для читабельних alert-ів.
- `TraefikHighLatency` у Grafana provisioning і Prometheus-style rule отримав fallback `or vector(0)`, щоб відсутність request duration buckets не ставала `DatasourceNoData`.
- Оновлено документацію для blackbox probes, render script і website probe runbook.
- **Verification:** YAML parse для `blackbox/blackbox.yml`, `victoria-metrics/scrape-config.tmpl.yml`, `docker-compose.yml`, `grafana/provisioning/alerting/alert-rules.yml` і `alerting/rules/traefik.yml` успішний; `blackbox_exporter --config.check` успішний; internal Traefik smoke checks для Koha OPAC/staff, Matomo, DSpace UI і DSpace API повернули `200 OK`; `git diff --check` успішний. Runtime deploy/reload ще не виконувався в межах цієї ітерації.
- **Risks:** Internal probes більше не перевіряють Cloudflare edge availability; для public uptime потрібен окремий зовнішній моніторинг з незалежної мережі. Host headers у `blackbox/blackbox.yml` мають відповідати Traefik router hostnames.
- **Rollback:** Повернути blackbox jobs на public URL targets, прибрати `proxy-net` з `blackbox-exporter`, видалити `http_2xx_internal_*` modules і повернути попередній Traefik latency expression.

## [2026-08-28] — SMTP2Graph metrics, Grafana alerts, and synthetic delivery probe
- **Context:** SMTP2Graph gateway exposes private Prometheus metrics on encrypted overlay port `9464`; monitoring stack needed scrape, dashboard, independent email alerting and controlled delivery verification.
- **Change:** VictoriaMetrics joins the external SMTP2Graph overlay and scrapes `smtp2graph-gateway` with canonical labels. Added SMTP2Graph Grafana dashboard, provisioning alert rules, Prometheus-style catalog rules, runbook, and a Swarm-scheduled STARTTLS/AUTH synthetic runner that verifies Graph delivery counter growth through internal `victoriametrics:8428` service DNS and publishes node-exporter textfile status metrics. Grafana alert delivery remains on independent MS365 SMTP. Counter-based alert expressions use `or vector(0)` to avoid startup `DatasourceNoData` notifications.
- **Verification:** Static YAML/JSON, renderer contract and synthetic probe unit tests are included in the repository. Production overlay inspection, SOPS secret population and live alert delivery remain separate authorised operations.
- **Risks:** Synthetic probe requires an allowlisted host source CIDR and non-production recipient; missing initial probe metrics intentionally trigger the synthetic-delivery alert.
- **Rollback:** Remove SMTP2Graph scrape/dashboard/alert assets and systemd units, detach VictoriaMetrics from the SMTP2Graph overlay, then redeploy the monitoring stack.
