#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

contains_fixed() {
  grep -Fq -- "$1" "$2"
}

python3 - <<'PY'
import json
from pathlib import Path
import yaml

for path in [
    Path("alerting/rules/smtp2graph.yml"),
    Path("grafana/provisioning/alerting/smtp2graph-alerts.yml"),
]:
    yaml.safe_load(path.read_text(encoding="utf-8"))

dashboard = json.loads(Path("grafana/dashboards/smtp2graph-gateway.json").read_text(encoding="utf-8"))
assert dashboard["title"] == "SMTP2Graph Gateway"
assert len(dashboard["panels"]) >= 8
PY

fixture="$(mktemp)"
output_file="$(mktemp)"
trap 'rm -f "$fixture" "$output_file" "${fixture}.invalid"' EXIT
cat >"$fixture" <<'EOF'
KOHA_OPAC_URL=https://opac.example.test
KOHA_STAFF_URL=https://staff.example.test
MATOMO_URL=https://matomo.example.test
DSPACE_UI_URL=https://dspace.example.test
DSPACE_API_URL=https://dspace.example.test/server
CLOUDFLARE_TUNNEL_METRICS_TARGET=cloudflared:2000
CLOUDFLARE_TUNNEL_NAME=grafana
SMTP2GRAPH_METRICS_TARGET=smtp2graph_gateway:9464
OPENCLOUD_ENV=dev
OPENCLOUD_STORAGE_MOUNTPOINT=/srv/opencloud.data
EOF

ORCHESTRATOR_ENV_FILE="$fixture" bash scripts/render-scrape-config.sh --output-file "$output_file" >/dev/null
contains_fixed 'job_name: smtp2graph-gateway' "$output_file"
contains_fixed 'smtp2graph_gateway:9464' "$output_file"
contains_fixed 'service: smtp2graph' "$output_file"
contains_fixed 'job_name: opencloud' "$output_file"
contains_fixed 'opencloud_opencloud:9205' "$output_file"
contains_fixed 'node_filesystem_.*;/srv/opencloud\.data' "$output_file"
contains_fixed 'env: dev' "$output_file"
python3 - "$output_file" <<'PYTEST'
import json
import re
import sys
from pathlib import Path
import yaml

scrape = yaml.safe_load(Path(sys.argv[1]).read_text())
node = next(job for job in scrape['scrape_configs'] if job['job_name'] == 'node-exporter')
mount, environment = node['metric_relabel_configs']
assert re.fullmatch(mount['regex'], 'node_filesystem_avail_bytes;/srv/opencloud.data')
assert not re.fullmatch(mount['regex'], 'node_filesystem_avail_bytes;/srv/opencloudXdata')
assert re.fullmatch(environment['regex'], 'opencloud_backup_last_status;dev')
assert not re.fullmatch(environment['regex'], 'opencloud_backup_last_status;prod')
grafana = yaml.safe_load(Path('grafana/provisioning/alerting/opencloud-alerts.yml').read_text())['groups'][0]['rules']
prom = yaml.safe_load(Path('alerting/rules/opencloud.yml').read_text())['groups'][0]['rules']
assert len(grafana) == len(prom) == 7
assert {r['title'] for r in grafana} == {r['alert'] for r in prom}
assert all(r['labels']['env'] == '$OPENCLOUD_ENV' for r in grafana)
assert all('opencloud_environment="true"' in r['data'][0]['model']['expr'] for r in grafana if r['title'] in ('OpenCloudBackupMissing', 'OpenCloudRestoreTestFailed'))
dashboard = json.loads(Path('grafana/provisioning/opencloud-dashboards/opencloud.json').read_text())
assert dashboard['title'] == 'OpenCloud' and len(dashboard['panels']) == 5
assert len({p['id'] for p in dashboard['panels']}) == 5
provider = yaml.safe_load(Path('grafana/provisioning/dashboards/dashboards.yml').read_text())['providers']
opencloud = next(p for p in provider if p['name'] == 'opencloud-dashboards')
assert opencloud['folder'] == 'OpenCloud'
assert opencloud['options']['path'] == '/etc/grafana/provisioning/opencloud-dashboards'
host = json.loads(Path('grafana/provisioning/opencloud-dashboards/host.json').read_text())
assert host['title'] == 'OpenCloud Host' and host['uid'] != dashboard['uid']
assert any('opencloud_storage="true"' in t['expr'] for p in host['panels'] for t in p['targets'])

PYTEST

contains_fixed 'networks: !override' docker-compose.swarm.yml
contains_fixed 'smtp2graph-synthetic-runner:' docker-compose.swarm.yml
if sed -n '/  smtp2graph-synthetic-runner:/,/    deploy:/p' docker-compose.swarm.yml | grep -Fq 'user: "1000:1000"'; then
  echo 'SMTP2Graph synthetic runner must use its image default user to write textfile metrics' >&2
  exit 1
fi
contains_fixed 'VM_SYNTHETIC_QUERY_URL: http://victoriametrics:8428' docker-compose.swarm.yml
contains_fixed 'smtp2graph_synthetic_password' docker-compose.swarm.yml
contains_fixed 'SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS: ${SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS:-900}' docker-compose.swarm.yml
contains_fixed 'SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS: ${SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS:-300}' docker-compose.swarm.yml
contains_fixed 'sleep "$${SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS}"' docker-compose.swarm.yml
contains_fixed 'SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS=900' .env.example
contains_fixed 'SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS=300' .env.example
contains_fixed 'service="host",exported_service="smtp2graph"' alerting/rules/smtp2graph.yml
contains_fixed 'service="host",exported_service="smtp2graph"' grafana/provisioning/alerting/smtp2graph-alerts.yml
contains_fixed 'smtp2graph_synthetic_freshness_threshold_seconds' alerting/rules/smtp2graph.yml
contains_fixed 'smtp2graph_synthetic_freshness_threshold_seconds' grafana/provisioning/alerting/smtp2graph-alerts.yml
if sed -n '/  grafana:/,/    secrets:/p' docker-compose.swarm.yml | grep -Fq 'smtp2graph_internal_enc'; then
  echo 'Grafana must not join the SMTP2Graph overlay' >&2
  exit 1
fi

for setting in 'OPENCLOUD_ENV=invalid' 'OPENCLOUD_STORAGE_MOUNTPOINT=relative/path' 'OPENCLOUD_STORAGE_MOUNTPOINT=/bad path'; do
  key=${setting%%=*}
  sed "s|^${key}=.*|${setting}|" "$fixture" >"${fixture}.invalid"
  if ORCHESTRATOR_ENV_FILE="${fixture}.invalid" bash scripts/render-scrape-config.sh --output-file "$output_file" >/dev/null 2>&1; then
    echo "renderer accepted invalid $key" >&2
    exit 1
  fi
done

for invalid in 'http://smtp2graph_gateway:9464' 'smtp2graph_gateway:not-a-port' 'smtp2 graph:9464'; do
  sed "s|^SMTP2GRAPH_METRICS_TARGET=.*|SMTP2GRAPH_METRICS_TARGET=$invalid|" "$fixture" >"${fixture}.invalid"
  if ORCHESTRATOR_ENV_FILE="${fixture}.invalid" bash scripts/render-scrape-config.sh --output-file "$output_file" >/dev/null 2>&1; then
    echo "renderer accepted invalid SMTP2GRAPH_METRICS_TARGET" >&2
    exit 1
  fi
  rm -f "${fixture}.invalid"
done

echo 'PASS: SMTP2Graph and OpenCloud observability configuration is valid.'
