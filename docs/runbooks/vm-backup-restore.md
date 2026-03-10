# Runbook: VictoriaMetrics Backup / Restore Alerts

## Тригери
- `VictoriaMetricsBackupStale`
- `VictoriaMetricsRestoreSmokeStale`

## Що означає
- Backup не був успішним протягом очікуваного вікна.
- Smoke restore test не проходив успішно в очікуваному вікні.

## Дії
1. Перевірити наявність backup-файлів у `VM_BACKUP_DIR`:
   - `ls -lah ${VM_BACKUP_DIR}`
2. Запустити ручний backup:
   - `./scripts/backup-victoriametrics-volume.sh`
3. Запустити smoke restore test:
   - `./scripts/test-victoriametrics-restore.sh`
4. Перевірити, що в `NODE_EXPORTER_TEXTFILE_DIR` з'явилися/оновилися `vm_backup.prom` і `vm_restore_smoke.prom`.
5. Перевірити node-exporter метрики:
   - `curl -s http://127.0.0.1:9100/metrics | grep -E 'kdi_vm_backup|kdi_vm_restore_smoke'`
6. Перевірити в VictoriaMetrics:
   - `curl -s "http://127.0.0.1:8428/api/v1/query?query=kdi_vm_backup_last_status"`
   - `curl -s "http://127.0.0.1:8428/api/v1/query?query=kdi_vm_restore_smoke_last_status"`

## Критерій відновлення
- `kdi_vm_backup_last_status=1` і `kdi_vm_backup_last_success_timestamp_seconds` оновився.
- `kdi_vm_restore_smoke_last_status=1` і `kdi_vm_restore_smoke_last_success_timestamp_seconds` оновився.
- Alert переходить у `Normal` після evaluation window.
