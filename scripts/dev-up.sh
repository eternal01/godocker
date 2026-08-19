#!/usr/bin/env bash
#--------------------------------------------------------------------------
# Start a preset dev environment with optional service override
#--------------------------------------------------------------------------
# Usage:
#   dev-up.sh <preset>                 # use preset's default service list
#   dev-up.sh <preset> <svc1> <svc2>   # start exactly the listed services
#
# Preset defaults (override by passing service names after the preset):
#   rust-env   workspace mysql postgres redis
#   go-env     workspace mysql mongo redis etcd etcd-manager dtm kafka \
#              kafka-ui elasticsearch grafana prometheus jaeger
#   php-env    workspace mysql redis rabbitmq
#   full-env   all services except the mutually-exclusive PostGIS variant
#   custom     <no defaults, services required>
#
# Mechanics:
#   - The active service list is exported as a comma-separated
#     COMPOSE_PROFILES so the services' own profile tags in compose/*.yml
#     are activated. workspace has no profile; it starts because it is
#     named explicitly in `up -d`.
#   - full-env uses an explicit service list so mutually-exclusive database
#     variants do not start together.
#--------------------------------------------------------------------------

set -euo pipefail

# Pull explicitly only when requested. Normal startup uses Docker's local
# cache and Compose's default pull behavior.
pull_with_retry() {
  local attempt=0 max=5
  while [ $attempt -lt "$max" ]; do
    attempt=$((attempt + 1))
    if "$@"; then
      return 0
    fi
    if [ $attempt -eq "$max" ]; then
      echo "✗ pull failed after $max attempts; check registry-mirrors config" >&2
      return 1
    fi
    local delay=$((attempt * 10))
    echo "⚠ pull attempt $attempt/$max failed, retrying in ${delay}s..." >&2
    sleep "$delay"
  done
}

PRESET="${1:-}"
shift || true

case "$PRESET" in
  rust-env) DEFAULTS="workspace mysql postgres redis" ;;
  go-env)   DEFAULTS="workspace mysql mongo redis etcd etcd-manager dtm kafka kafka-ui elasticsearch grafana prometheus jaeger" ;;
  php-env)  DEFAULTS="workspace mysql redis rabbitmq" ;;
  full-env) DEFAULTS="workspace mysql postgres mongo redis rabbitmq kafka kafka-ui etcd etcd-manager dtm elasticsearch logstash kibana minio grafana prometheus jaeger gitlab gitlab-runner portainer traefik swagger-editor swagger-ui" ;;
  custom)   DEFAULTS="" ;;
  *)        echo "Unknown preset: $PRESET" >&2
            echo "Valid presets: rust-env | go-env | php-env | full-env | custom" >&2
            exit 1
            ;;
esac

if [ "$PRESET" = "custom" ] && [ $# -eq 0 ]; then
  echo "Error: 'custom' preset requires at least one service name" >&2
  echo "Usage: dev-up.sh custom <service1> [service2] ..." >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  SERVICES="$*"
else
  SERVICES="$DEFAULTS"
fi

cd "$(dirname "$0")/.."

if [ "${CHECK_VERSIONS:-0}" = "1" ]; then
  if ! ./scripts/check-versions.sh > /dev/null 2>&1; then
    echo ""
    echo "✗ pre-flight check failed (set CHECK_VERSIONS=0 to bypass):"
    ./scripts/check-versions.sh
    exit 1
  fi
fi

if [ -n "$SERVICES" ]; then
  PROFILES=$(echo "$SERVICES" | tr ' ' ',')
  echo "→ [$PRESET] starting: $SERVICES"
  if [ "${PULL_IMAGES:-0}" = "1" ]; then
    COMPOSE_PROFILES="$PROFILES" pull_with_retry docker compose pull
  fi
  COMPOSE_PROFILES="$PROFILES" docker compose up -d $SERVICES
else
  echo "→ [$PRESET] no services selected"
  exit 1
fi
