# OpenCloud monitoring

## Configure before deployment

Set `OPENCLOUD_ENV=dev` or `prod` and `OPENCLOUD_STORAGE_MOUNTPOINT` in the monitoring environment file. The mountpoint must be the exact `mountpoint` label exported by the Node Exporter that runs on the OpenCloud storage node; for example, `/srv/opencloud/data` may reside on `/`. Determine it on that host with `findmnt -T /srv/opencloud/data -no TARGET` and verify it against the exported metric. The renderer requires an absolute path containing only letters, digits, `_`, `-`, `.`, and `/`; `SERVER_ENV` can supply the environment if `OPENCLOUD_ENV` is absent. Provision the same values for Grafana and the scrape renderer. The settings are required for deployment; missing or invalid values stop scrape rendering.

The `opencloud` target is `opencloud_opencloud:9205` on the existing `proxy-net` overlay. This requires both stacks in the same Swarm and the actual proxy network to be the same. The OpenCloud debug listener also exposes `/config`, `/healthz`, and `/readyz` to network peers; review peer trust and the OpenCloud provisioning security notes before enabling the listener. Do not publish port 9205 on the host or through Traefik. If the endpoint uses an authentication token, configure an appropriate secret-backed scrape mechanism before deploying; this configuration does not supply one.

Node Exporter must run on the storage host and read the same textfile directory used by OpenCloud backup and restore smoke scripts. The producer's `env` and `service` labels become `exported_env` and `exported_service` because the scrape job assigns those labels. Relabeling marks only the selected environment's OpenCloud textfile series and the configured mountpoint. Recheck both if tasks move or storage changes.

## Alerts and checks

- `OpenCloudDown`: check the OpenCloud task, its internal debug listener, shared overlay and target DNS. A successful scrape does not prove external ingress, identity or storage operations work. A planned backup may stop the service long enough to trigger this alert.
- `OpenCloudHigh5xxErrors` and `OpenCloudSlowUI`: inspect OpenCloud logs, filesystem and upstream identity dependencies. Latency excludes PUT and PATCH. At low traffic, the ratio and percentile can fluctuate.
- `OpenCloudDiskSpaceLow`: inspect the selected filesystem and free inodes; the threshold is 50 GiB. `OpenCloudHostOOMRisk` checks host memory, not the container limit. Missing filesystem or memory metrics cause Grafana No Data alerting.
- `OpenCloudBackupMissing`: inspect the last backup attempt and remote copy; a missing metric or no success for 26 hours triggers the alert.
- `OpenCloudRestoreTestFailed`: inspect the restore smoke result; a missing, failed or older-than-eight-days result triggers the alert. Run the OpenCloud restore smoke procedure under its own runbook and schedule. A successful smoke test checks an isolated extraction and at least one `user.oc.id`, not every file or service startup.

After deployment, confirm the target is up and inspect the actual label sets in VictoriaMetrics. Confirm the configured mountpoint yields exactly the expected filesystem series, check both textfile metrics after the respective jobs run, and exercise alert and notification delivery. Until jobs have produced their metrics, backup and restore alerts will fire. Dashboard and alert provisioning require Grafana to load the new files; the deployed monitoring service checksums trigger updates when configuration changes.
