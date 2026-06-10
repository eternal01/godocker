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
#   full-env   <all services in the loaded compose files>
#   custom     <no defaults, services required>
#
# Mechanics:
#   - The active service list is exported as a comma-separated
#     COMPOSE_PROFILES so the services' own profile tags in compose/*.yml
#     are activated. workspace has no profile; it starts because it is
#     named explicitly in `up -d`.
#   - full-env and custom-with-no-services both omit the profile filter
#     so every service in the loaded compose files comes up.
#--------------------------------------------------------------------------

set -euo pipefail

# Pre-pull with exponential backoff. Chinese public registry mirrors
# frequently return 429 under load, and Docker does NOT fall back to the
# next mirror when manifest resolution returns 429. Retrying with
# backoff lets the rate-limit clear without bouncing the whole dev env.
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
  full-env) DEFAULTS="" ;;
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

# Pre-flight: verify every image is reachable on at least one configured
# mirror. Saves time on misconfigured versions (e.g. wrong tag prefix)
# by failing fast instead of mid-pull. Set SKIP_VERSION_CHECK=1 to bypass.
if [ "${SKIP_VERSION_CHECK:-0}" != "1" ]; then
  if ! ./scripts/check-versions.sh > /dev/null 2>&1; then
    echo ""
    echo "✗ pre-flight check failed (set SKIP_VERSION_CHECK=1 to bypass):"
    ./scripts/check-versions.sh
    exit 1
  fi
fi

COMPOSE_FILES=(
  -f docker-compose.yml
  -f compose/db.yml
  -f compose/cache.yml
  -f compose/registry.yml
  -f compose/mq.yml
  -f compose/observability.yml
  -f compose/storage.yml
  -f compose/ci.yml
  -f compose/gateway.yml
  -f compose/docs.yml
)

if [ -n "$SERVICES" ]; then
  PROFILES=$(echo "$SERVICES" | tr ' ' ',')
  echo "→ [$PRESET] starting: $SERVICES"
  # --policy always re-fetches blobs even when the manifest digest already
  # matches the local copy. The default ("missing") skips blob download in
  # that case, which can leave a half-pulled image whose layer blobs were
  # GC'd from the local content store — the manifest is fine but layer
  # extraction then 404s with "NotFound ... content store". "always" makes
  # that class of failure impossible at the cost of a few extra MB on a
  # warm cache.
  COMPOSE_PROFILES="$PROFILES" pull_with_retry docker compose "${COMPOSE_FILES[@]}" pull --policy always
  COMPOSE_PROFILES="$PROFILES" docker compose "${COMPOSE_FILES[@]}" up -d $SERVICES
else
  echo "→ [$PRESET] starting everything"
  pull_with_retry docker compose "${COMPOSE_FILES[@]}" pull --policy always
  docker compose "${COMPOSE_FILES[@]}" up -d
fi
