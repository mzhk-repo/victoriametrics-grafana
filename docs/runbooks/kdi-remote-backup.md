# KDI remote backup stale

`KDIRemoteBackupStale` fires when the last successful rsync is more than 26 hours old. Grafana also alerts when the metric is missing. The scheduled backup chain starts daily; delays in earlier jobs can delay the remote copy.

1. Inspect `/data/node-exporter-textfile/kdi_prod_remote_backup.prom`: compare the last attempt, last success timestamp, and last completed attempt status.
2. Inspect `scheduled-kdi-prod-push-backup.service` and `/var/log/kdi-prod-push-backup.log`, including rotated logs. Check the preceding scheduled backup services if the remote job did not start.
3. Investigate rsync, SSH connectivity, remote storage, and permissions using the service logs. A successful rsync confirms the transfer completed; it does not verify a restore.
4. Confirm a subsequent successful run updates the last success timestamp and that the alert returns to normal. Check Node Exporter and VictoriaMetrics ingestion if the metric is absent.
