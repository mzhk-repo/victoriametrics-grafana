#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
DRY_RUN="false"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
fi

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

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

run_chown() {
  local owner="$1"
  local target="$2"

  if run_cmd chown "$owner" "$target"; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    run_cmd sudo chown "$owner" "$target"
    return 0
  fi

  echo "ERROR: Cannot change owner for $target to $owner (need root/sudo)"
  return 1
}

VM_DATA_DIR="$(read_env_or_default VM_DATA_DIR "./.data/victoriametrics")"
VM_BACKUP_DIR="$(read_env_or_default VM_BACKUP_DIR "./.backups/victoriametrics")"
GRAFANA_DATA_DIR="$(read_env_or_default GRAFANA_DATA_DIR "./.data/grafana")"
GRAFANA_LOGS_DIR="$(read_env_or_default GRAFANA_LOGS_DIR "./.data/grafana-logs")"
NODE_EXPORTER_TEXTFILE_DIR="$(read_env_or_default NODE_EXPORTER_TEXTFILE_DIR "./.data/node-exporter-textfile")"
GRAFANA_CONTAINER_USER="$(read_env_or_default GRAFANA_CONTAINER_USER "0")"

if [[ "$GRAFANA_CONTAINER_USER" == *:* ]]; then
  GRAFANA_OWNER="$GRAFANA_CONTAINER_USER"
else
  GRAFANA_OWNER="${GRAFANA_CONTAINER_USER}:${GRAFANA_CONTAINER_USER}"
fi

VM_OWNER="0:0"

if [[ -n "${SUDO_UID:-}" ]] && [[ -n "${SUDO_GID:-}" ]]; then
  TEXTFILE_OWNER="${SUDO_UID}:${SUDO_GID}"
else
  TEXTFILE_OWNER="$(id -u):$(id -g)"
fi

declare -a DIRS
DIRS=(
  "$(abs_path "$VM_DATA_DIR")|$VM_OWNER|0750"
  "$(abs_path "$VM_BACKUP_DIR")|$VM_OWNER|0750"
  "$(abs_path "$NODE_EXPORTER_TEXTFILE_DIR")|$TEXTFILE_OWNER|0775"
  "$(abs_path "$GRAFANA_DATA_DIR")|$GRAFANA_OWNER|0750"
  "$(abs_path "$GRAFANA_LOGS_DIR")|$GRAFANA_OWNER|0750"
)

echo "Initializing monitoring volume directories"
for entry in "${DIRS[@]}"; do
  IFS='|' read -r dir owner mode <<< "$entry"

  echo "- ensure dir: $dir"
  run_cmd mkdir -p "$dir"

  echo "  owner: $owner"
  run_chown "$owner" "$dir"

  echo "  mode: $mode"
  run_cmd chmod "$mode" "$dir"
done

echo "Volume initialization completed."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry-run mode: no filesystem changes were applied."
fi
