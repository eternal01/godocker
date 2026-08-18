#!/usr/bin/env bash
set -euo pipefail

# Build the workspace image for one or more target platforms. Multi-platform
# images must be pushed to a registry; Docker's local image store cannot load a
# manifest list with `--load` in the usual Docker Desktop configuration.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "${ROOT_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${ROOT_DIR}/.env"
    set +a
fi

PLATFORMS="${PLATFORMS:-${WORKSPACE_PLATFORMS:-linux/amd64,linux/arm64}}"
IMAGE="${IMAGE:-${WORKSPACE_IMAGE:-development-docker/workspace:multiarch}}"
PUSH="${PUSH:-0}"

usage() {
    cat <<'EOF'
Usage: scripts/build-workspace.sh

Environment:
  WORKSPACE_PLATFORMS  Target platforms, default: linux/amd64,linux/arm64
  WORKSPACE_IMAGE      Image tag, default: development-docker/workspace:multiarch
  PUSH=1               Push the multi-platform manifest to the image registry

Examples:
  PUSH=1 scripts/build-workspace.sh
  PLATFORMS=linux/arm64 scripts/build-workspace.sh
  PLATFORMS=linux/amd64 IMAGE=registry.example.com/team/workspace:dev PUSH=1 scripts/build-workspace.sh
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

case ",${PLATFORMS}," in
    *,linux/amd64,*|*,linux/arm64,*) ;;
    *) echo "Unsupported workspace platform list: ${PLATFORMS}" >&2; exit 1 ;;
esac

if [[ "${PLATFORMS}" == *,* ]] && [ "${PUSH}" != "1" ]; then
    echo "Multi-platform builds require PUSH=1 and a registry image tag." >&2
    echo "Example: PUSH=1 scripts/build-workspace.sh" >&2
    exit 1
fi

build_args=(
    --build-arg "SYSTEM_NAME=${SYSTEM_NAME:-debian}"
    --build-arg "SYSTEM_VERSION=${SYSTEM_VERSION:-bookworm}"
    --build-arg "WORKSPACE_USER=${WORKSPACE_USER:-developer}"
    --build-arg "WORKSPACE_HOME=${WORKSPACE_HOME:-/home/developer}"
    --build-arg "WORKSPACE_PATH=${APP_CODE_PATH_CONTAINER:-/workspace}"
    --build-arg "WORKSPACE_INSTALL_BREW=${WORKSPACE_INSTALL_BREW:-true}"
    --build-arg "WORKSPACE_PREINSTALL_LANGUAGES=${WORKSPACE_PREINSTALL_LANGUAGES:-}"
    --build-arg "WORKSPACE_INSTALL_DNSUTILS=${WORKSPACE_INSTALL_DNSUTILS:-true}"
    --build-arg "WORKSPACE_INSTALL_WORKSPACE_SSH=${WORKSPACE_INSTALL_WORKSPACE_SSH:-true}"
    --build-arg "WORKSPACE_BREW_PACKAGES=${WORKSPACE_BREW_PACKAGES:-}"
    --build-arg "MISE_VERSION=${MISE_VERSION:-v2026.6.1}"
    --build-arg "MISE_RELEASE_BASE_URL=${MISE_RELEASE_BASE_URL:-https://github.com/jdx/mise/releases/download}"
    --build-arg "PUID=${WORKSPACE_PUID:-1000}"
    --build-arg "PGID=${WORKSPACE_PGID:-1000}"
    --build-arg "TZ=${TZ:-UTC}"
    --build-arg "HTTP_PROXY=${HTTP_PROXY:-}"
    --build-arg "HTTPS_PROXY=${HTTPS_PROXY:-}"
    --build-arg "NO_PROXY=${NO_PROXY:-localhost,127.0.0.1,::1,.local}"
    --build-arg "DEBIAN_MIRROR=${DEBIAN_MIRROR:-deb.debian.org}"
    --build-arg "DEBIAN_SECURITY_MIRROR=${DEBIAN_SECURITY_MIRROR:-security.debian.org}"
)

cmd=(
    docker buildx build
    --platform "${PLATFORMS}"
    --file "${ROOT_DIR}/workspaces/workspace.Dockerfile"
    --tag "${IMAGE}"
    --network "${WORKSPACE_BUILD_NETWORK:-default}"
    --add-host host.docker.internal:host-gateway
    "${build_args[@]}"
)

if [ "${PUSH}" = "1" ]; then
    cmd+=(--push)
elif [[ "${PLATFORMS}" != *,* ]]; then
    cmd+=(--load)
fi

cmd+=("${ROOT_DIR}")
printf 'Building %s for %s\n' "${IMAGE}" "${PLATFORMS}"
exec "${cmd[@]}"
