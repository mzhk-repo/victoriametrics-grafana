#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

read_env_or_default() {
  local key="$1"
  local default_value="$2"
  local env_value="${!key:-}"

  if [[ -n "$env_value" ]]; then
    printf '%s\n' "$env_value"
    return 0
  fi

  if [[ -f "$ENV_FILE" ]]; then
    local line
    line="$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 || true)"
    if [[ -n "$line" ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  fi

  printf '%s\n' "$default_value"
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "./.data/node-exporter-textfile")"
MATOMO_CRON_CONTAINER_NAME="$(read_env_or_default MATOMO_CRON_CONTAINER_NAME "matomo-cron")"
TEXTFILE_DIR_ABS="$(abs_path "$NODE_EXPORTER_TEXTFILE_DIR")"
collect_timestamp="$(date +%s)"
success_timestamp="0"
metric_status="0"

mkdir -p "$TEXTFILE_DIR_ABS"

emit_metrics() {
  local metrics_payload
  metrics_payload="$(cat <<EOF
# HELP matomo_archiving_last_success_timestamp Unix timestamp of the last successful Matomo archiving run.
# TYPE matomo_archiving_last_success_timestamp gauge
matomo_archiving_last_success_timestamp{env="prod",service="matomo"} $success_timestamp
# HELP matomo_archiving_last_collect_timestamp Unix timestamp of the last Matomo archiving metric collection attempt.
# TYPE matomo_archiving_last_collect_timestamp gauge
matomo_archiving_last_collect_timestamp{env="prod",service="matomo"} $collect_timestamp
# HELP matomo_archiving_last_status Last Matomo archiving metric collection status (1=success, 0=failure).
# TYPE matomo_archiving_last_status gauge
matomo_archiving_last_status{env="prod",service="matomo"} $metric_status
EOF
)"

  printf '%s\n' "$metrics_payload" | docker run --rm -i \
    -v "$TEXTFILE_DIR_ABS:/metrics" \
    alpine:3.20 \
    sh -c 'cat > /metrics/matomo_archiving.prom'
}

trap 'emit_metrics' EXIT

if ! docker ps --format '{{.Names}}' | grep -qx "$MATOMO_CRON_CONTAINER_NAME"; then
  echo "ERROR: Matomo cron container is not running: $MATOMO_CRON_CONTAINER_NAME"
  exit 1
fi

last_success_line="$(docker logs --timestamps "$MATOMO_CRON_CONTAINER_NAME" 2>&1 | grep 'Done archiving!' | tail -n1 || true)"

if [[ -z "$last_success_line" ]]; then
  echo "ERROR: Could not find successful 'Done archiving!' marker in $MATOMO_CRON_CONTAINER_NAME logs"
  exit 1
fi

last_success_iso="$(printf '%s\n' "$last_success_line" | awk '{print $1}')"
success_timestamp="$(date -d "$last_success_iso" +%s)"

if [[ ! "$success_timestamp" =~ ^[0-9]+$ ]] || [[ "$success_timestamp" -le 0 ]]; then
  echo "ERROR: Failed to parse success timestamp from log line: $last_success_line"
  exit 1
fi

metric_status="1"
emit_metrics
trap - EXIT

echo "Matomo archiving success timestamp collected: $success_timestamp"
