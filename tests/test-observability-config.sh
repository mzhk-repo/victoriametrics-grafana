#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
EOF

ORCHESTRATOR_ENV_FILE="$fixture" bash scripts/render-scrape-config.sh --output-file "$output_file" >/dev/null
rg -Fq 'job_name: smtp2graph-gateway' "$output_file"
rg -Fq 'smtp2graph_gateway:9464' "$output_file"
rg -Fq 'service: smtp2graph' "$output_file"
rg -Fq 'networks: !override' docker-compose.swarm.yml
rg -Fq 'smtp2graph-synthetic-runner:' docker-compose.swarm.yml
rg -Fq 'VM_SYNTHETIC_QUERY_URL: http://victoriametrics:8428' docker-compose.swarm.yml
rg -Fq 'smtp2graph_synthetic_password' docker-compose.swarm.yml
rg -Fq 'SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS: ${SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS:-900}' docker-compose.swarm.yml
rg -Fq 'SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS: ${SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS:-300}' docker-compose.swarm.yml
rg -Fq 'sleep "$${SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS}"' docker-compose.swarm.yml
rg -Fq 'SMTP2GRAPH_SYNTHETIC_INTERVAL_SECONDS=900' .env.example
rg -Fq 'SMTP2GRAPH_SYNTHETIC_FRESHNESS_GRACE_SECONDS=300' .env.example
rg -Fq 'service="host",exported_service="smtp2graph"' alerting/rules/smtp2graph.yml
rg -Fq 'service="host",exported_service="smtp2graph"' grafana/provisioning/alerting/smtp2graph-alerts.yml
rg -Fq 'smtp2graph_synthetic_freshness_threshold_seconds' alerting/rules/smtp2graph.yml
rg -Fq 'smtp2graph_synthetic_freshness_threshold_seconds' grafana/provisioning/alerting/smtp2graph-alerts.yml
if sed -n '/  grafana:/,/    secrets:/p' docker-compose.swarm.yml | rg -Fq 'smtp2graph_internal_enc'; then
  echo 'Grafana must not join the SMTP2Graph overlay' >&2
  exit 1
fi

for invalid in 'http://smtp2graph_gateway:9464' 'smtp2graph_gateway:not-a-port' 'smtp2 graph:9464'; do
  sed "s|^SMTP2GRAPH_METRICS_TARGET=.*|SMTP2GRAPH_METRICS_TARGET=$invalid|" "$fixture" >"${fixture}.invalid"
  if ORCHESTRATOR_ENV_FILE="${fixture}.invalid" bash scripts/render-scrape-config.sh --output-file "$output_file" >/dev/null 2>&1; then
    echo "renderer accepted invalid SMTP2GRAPH_METRICS_TARGET" >&2
    exit 1
  fi
  rm -f "${fixture}.invalid"
done

echo 'PASS: SMTP2Graph observability configuration is valid.'
