#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
ENV_EXAMPLE_FILE=".env.example"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: $COMPOSE_FILE not found"
  exit 1
fi

if [[ ! -f "$ENV_EXAMPLE_FILE" ]]; then
  echo "ERROR: $ENV_EXAMPLE_FILE not found"
  exit 1
fi

bind_ip_line="$(grep -E '^MONITORING_BIND_IP=' "$ENV_EXAMPLE_FILE" || true)"
if [[ -z "$bind_ip_line" ]]; then
  echo "ERROR: MONITORING_BIND_IP is missing in $ENV_EXAMPLE_FILE"
  exit 1
fi

bind_ip_value="${bind_ip_line#MONITORING_BIND_IP=}"
if [[ "$bind_ip_value" != "127.0.0.1" ]]; then
  echo "ERROR: MONITORING_BIND_IP must be 127.0.0.1 in $ENV_EXAMPLE_FILE, got: $bind_ip_value"
  exit 1
fi

echo "Checking published port mappings in $COMPOSE_FILE"

violations=0

while IFS='|' read -r service raw_mapping; do
  mapping="${raw_mapping%\"}"
  mapping="${mapping#\"}"

  if [[ "$mapping" == 0.0.0.0:* ]]; then
    echo "ERROR: Service '$service' publishes a port on 0.0.0.0: $mapping"
    violations=$((violations + 1))
  fi

  if [[ "$mapping" != *'${MONITORING_BIND_IP}'* ]]; then
    echo "ERROR: Service '$service' must use MONITORING_BIND_IP in ports mapping: $mapping"
    violations=$((violations + 1))
  fi

  colon_count="$(awk -F':' '{ print NF-1 }' <<< "$mapping")"
  if [[ "$colon_count" -lt 2 ]]; then
    echo "ERROR: Service '$service' has non-internal ports mapping (expected host_ip:host_port:container_port): $mapping"
    violations=$((violations + 1))
  fi

done < <(
  awk '
    BEGIN {
      in_services = 0
      in_ports = 0
      service = ""
    }

    /^services:[[:space:]]*$/ {
      in_services = 1
      next
    }

    /^[a-zA-Z0-9_.-]+:[[:space:]]*$/ {
      if ($0 != "services:" && $0 != "networks:" && $0 != "volumes:") {
        in_services = 0
      }
    }

    !in_services {
      next
    }

    /^  [a-zA-Z0-9_.-]+:[[:space:]]*$/ {
      service = $0
      sub(/^  /, "", service)
      sub(/:[[:space:]]*$/, "", service)
      in_ports = 0
      next
    }

    /^    ports:[[:space:]]*$/ {
      in_ports = 1
      next
    }

    in_ports && /^    [a-zA-Z0-9_.-]+:[[:space:]]*$/ {
      in_ports = 0
    }

    in_ports && /^      - / {
      mapping = $0
      sub(/^      - /, "", mapping)
      gsub(/[[:space:]]+$/, "", mapping)
      print service "|" mapping
    }
  ' "$COMPOSE_FILE"
)

if [[ "$violations" -gt 0 ]]; then
  echo "Port policy check failed with $violations violation(s)."
  exit 1
fi

echo "Port policy check passed: all published ports are internal-only via MONITORING_BIND_IP=127.0.0.1"
