#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
  printf '[deploy-orchestrator] %s\n' "$*"
}

require_script() {
  local script_path="$1"
  if [[ ! -f "${script_path}" ]]; then
    log "ERROR: required script is missing: ${script_path}"
    exit 1
  fi
}

cd "${PROJECT_ROOT}"

require_script "./scripts/check-internal-ports-policy.sh"
require_script "./scripts/init-volumes.sh"

log "Running mandatory check-internal-ports-policy.sh"
bash ./scripts/check-internal-ports-policy.sh

log "Running mandatory init-volumes.sh"
bash ./scripts/init-volumes.sh

log "Orchestration script completed"
