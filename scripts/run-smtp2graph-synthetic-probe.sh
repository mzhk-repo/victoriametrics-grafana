#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --env)
      ENVIRONMENT_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "ERROR: Unsupported argument: $1" >&2
      exit 1
      ;;
  esac
done

# shellcheck source=scripts/lib/autonomous-env.sh
. "$ROOT_DIR/scripts/lib/autonomous-env.sh"
load_autonomous_env "$ROOT_DIR" "$ENVIRONMENT_ARG"

python3 "$ROOT_DIR/scripts/smtp2graph-synthetic-probe.py"
