#!/usr/bin/env bash
#--------------------------------------------------------------------------
# Pre-flight check: verify every image in the compose files is reachable
# on at least one configured registry mirror.
#--------------------------------------------------------------------------
# Catches 404 (typo'd tag, e.g. `kafka-ui:0.7.2` instead of `v0.7.2`),
# 403 (mirror doesn't carry this image), and 429 (rate-limited) errors
# BEFORE `docker compose up -d` fails partway through the long pull chain.
#
# Usage:
#   ./scripts/check-versions.sh              # check all images, verbose
#   ./scripts/check-versions.sh --quiet      # only show failures
#   SKIP_VERSION_CHECK=1 make go-env         # bypass the check
#
# Configuration:
#   - Registry mirrors are read from ~/.orbstack/config/docker.json
#     (falls back to ~/.docker/daemon.json, then to a hardcoded list).
#   - Locally-cached images are skipped automatically (no need to verify
#     reachability for images already on disk).
#--------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

QUIET=0
for arg in "$@"; do
  case "$arg" in
    --quiet|-q) QUIET=1 ;;
    --help|-h)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { [ $QUIET -eq 0 ] && echo "$@" || true; }
fail() { echo "$@" >&2; }

# --- Mirror discovery ----------------------------------------------------

load_mirrors() {
  local config=""
  for f in "$HOME/.orbstack/config/docker.json" "$HOME/.docker/daemon.json"; do
    if [ -f "$f" ]; then config="$f"; break; fi
  done
  if [ -z "$config" ]; then
    echo "https://docker.1ms.run"
    echo "https://docker.m.daocloud.io"
    return
  fi
  # Prefer jq if available; fall back to a naive awk + grep extraction.
  if command -v jq >/dev/null 2>&1; then
    jq -r '."registry-mirrors"[]?' "$config" 2>/dev/null
  else
    awk '/registry-mirrors/,/\]/' "$config" | grep -oE '"https?://[^"]+"' | tr -d '"'
  fi
}

MIRRORS=()
while IFS= read -r line; do
  line="${line// /}"
  [ -n "$line" ] && MIRRORS+=("$line")
done < <(load_mirrors)

if [ ${#MIRRORS[@]} -eq 0 ] || [ -z "${MIRRORS[0]:-}" ]; then
  fail "✗ no registry mirrors configured (set registry-mirrors in OrbStack/Docker daemon.json)"
  exit 2
fi

# --- Image discovery -----------------------------------------------------

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

log "→ resolving images from compose files..."
# Enable every profile defined anywhere in compose/*.yml so `config --images`
# returns the full set of images, not just the non-profiled ones.
ALL_PROFILES=$(grep -hoE 'profiles:[[:space:]]*\[[^]]+\]' compose/*.yml 2>/dev/null | \
  grep -oE '"[^"]+"' | tr -d '"' | sort -u | paste -sd, -)
if ! IMAGES=$(COMPOSE_PROFILES="$ALL_PROFILES" docker compose "${COMPOSE_FILES[@]}" config --images 2>&1); then
  fail "✗ failed to resolve compose images:"
  echo "$IMAGES" >&2
  exit 2
fi

IMG_COUNT=$(echo "$IMAGES" | wc -l | tr -d ' ')
log "→ checking $IMG_COUNT images against ${#MIRRORS[@]} mirror(s)..."
log ""

# --- Local image integrity check -----------------------------------------
# Project-built images (development-docker-*) reference blobs that can be
# GC'd from the local content-addressable store. The image manifest
# survives, but `docker compose up` then 404s at container creation with:
#   "apply layer error ... NotFound: failed to get reader from content
#    store: content digest sha256:...: not found"
# That's exactly the failure mode this check is meant to catch.
#
# Heuristic: if a project-built image is OLD (>1y) AND TINY (<50MB on
# disk — the manifest + labels alone are a few kB; a real image with all
# its layers is at least tens of MB), it's almost certainly an empty
# shell. Flag it so the user knows to rmi + rebuild before `up`.
#
# Recent small images (e.g. a freshly built distroless service) are
# still flagged as warnings — the threshold is intentionally generous so
# a real but small image gets a "suspicious, double-check" note rather
# than a silent skip.

# Convert "11.5kB" / "926MB" / "2.1GB" to bytes. Bash 3.2 safe (no bc).
size_to_bytes() {
  local s=$1 n u
  n=$(echo "$s" | sed -E 's/^([0-9.]+).*/\1/')
  u=$(echo "$s" | sed -E 's/^[0-9.]+//')
  case "$u" in
    *kB|*KB) awk "BEGIN {printf \"%d\", $n * 1024}" ;;
    *MB)     awk "BEGIN {printf \"%d\", $n * 1024 * 1024}" ;;
    *GB)     awk "BEGIN {printf \"%d\", $n * 1024 * 1024 * 1024}" ;;
    *B)      awk "BEGIN {printf \"%d\", $n}" ;;
    *)       echo 0 ;;
  esac
}

# Convert "2 years ago" / "3 months ago" / "5 days ago" to days. Anything
# shorter than a day returns 0 (recent).
age_to_days() {
  local s=$1 n u
  n=$(echo "$s" | sed -E 's/^([0-9]+).*/\1/')
  u=$(echo "$s" | sed -E 's/^[0-9]+[[:space:]]+//')
  case "$u" in
    year*)   echo $((n * 365)) ;;
    month*)  echo $((n * 30))  ;;
    week*)   echo $((n * 7))   ;;
    day*)    echo "$n"         ;;
    *)       echo 0            ;;
  esac
}

# Pull (image, size_str, age_str) for every development-docker-* image
# currently in the local store. Skip $1 (already under test) so the
# caller can de-dup with the registry-check loop below.
local_integrity_issues=0
local_integrity_warnings=0
for project_image in $(docker images --format "{{.Repository}}:{{.Tag}}|{{{.Size}}}|{{{.CreatedSince}}}" 2>/dev/null \
                       | grep "^development-docker"); do
  IFS='|' read -r img size_str age_str <<< "$project_image"
  bytes=$(size_to_bytes "$size_str")
  days=$(age_to_days "$age_str")
  if [ "$bytes" -lt 52428800 ] && [ "$days" -gt 365 ]; then
    echo "  ✗ $img  (LOCAL EMPTY SHELL: size=$size_str, age=$age_str — run: docker rmi -f $img && docker compose ... build $img)"
    local_integrity_issues=$((local_integrity_issues + 1))
  elif [ "$bytes" -lt 52428800 ]; then
    log "  ⚠ $img  (suspiciously small: size=$size_str, age=$age_str — verify it actually has layers, not just labels)"
    local_integrity_warnings=$((local_integrity_warnings + 1))
  fi
done

if [ "$local_integrity_issues" -gt 0 ]; then
  fail ""
  fail "✗ local image integrity check failed: $local_integrity_issues project image(s) look like empty shells"
  fail "  These have a manifest in the local image store but their layer blobs"
  fail "  are missing from the content store. docker compose up will fail with"
  fail "  'apply layer error ... NotFound ... content store' at container creation."
  fail "  → docker rmi -f <image>  then  docker compose ... build <image>"
  exit 1
fi

# --- Auth (no cache — bash 3.2 compat; ~100ms per request is fine) -------

get_realm() {
  curl -sS -I --max-time 5 "${1}/v2/" 2>/dev/null | \
    grep -i 'www-authenticate' | \
    sed -n 's/.*realm="\([^"]*\)".*/\1/p' | head -1
}

get_token() {
  local mirror=$1 repo=$2 realm service
  realm=$(get_realm "$mirror")
  [ -z "$realm" ] && return 1
  service="${mirror#https://}"; service="${service%%/*}"
  curl -sS --max-time 8 \
    "${realm}?service=${service}&scope=repository:${repo}:pull" 2>/dev/null | \
    sed -n 's/.*"token":"\([^"]*\)".*/\1/p' | head -1
}

# --- Image check ---------------------------------------------------------

check_image() {
  local mirror=$1 image=$2 repo="${image%:*}" tag="${image##*:}"
  [ "$repo" = "$image" ] && { echo "SKIP (no tag)"; return 2; }

  local headers=(
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json"
    -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json"
    -H "Accept: application/vnd.oci.image.manifest.v1+json"
    -H "Accept: application/vnd.oci.image.index.v1+json"
  )
  local token
  if token=$(get_token "$mirror" "$repo") && [ -n "$token" ]; then
    headers+=(-H "Authorization: Bearer $token")
  fi

  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 15 \
    "${headers[@]}" "${mirror}/v2/${repo}/manifests/${tag}")

  case "$code" in
    200|301|302) echo "OK ($code)"; return 0 ;;
    401) echo "FAIL (401 auth)"; return 1 ;;
    403) echo "FAIL (403 forbid)"; return 1 ;;
    404) echo "FAIL (404 missing)"; return 1 ;;
    429) echo "FAIL (429 rate-limited)"; return 1 ;;
    000) echo "FAIL (timeout)"; return 1 ;;
    *)   echo "FAIL ($code)"; return 1 ;;
  esac
}

# --- Main ----------------------------------------------------------------

ok_count=0
skip_count=0
failed_count=0
for image in $IMAGES; do
  # Skip images built locally by this project's compose files
  # (e.g. development-docker-workspace, development-docker-mysql).
  # These are never on a registry; the check would falsely 404.
  case "$image" in
    development-docker-*)
      log "  ⊘ $image  (project build, skip)"
      skip_count=$((skip_count + 1))
      continue
      ;;
  esac

  # Skip images already in local cache
  if docker image inspect "$image" >/dev/null 2>&1; then
    log "  ⊘ $image  (local, skip)"
    skip_count=$((skip_count + 1))
    continue
  fi

  ok=0
  detail=""
  for mirror in "${MIRRORS[@]}"; do
    if result=$(check_image "$mirror" "$image" 2>/dev/null); then
      log "  ✓ $image  ←  $result via $mirror"
      ok=1
      break
    else
      detail+="$mirror → $result; "
    fi
  done

  if [ $ok -eq 0 ]; then
    echo "  ✗ $image  ←  $detail"
    failed_count=$((failed_count + 1))
  else
    ok_count=$((ok_count + 1))
  fi
done

echo ""
echo "→ $ok_count reachable, $skip_count local (skipped), $failed_count unreachable"

if [ $failed_count -gt 0 ]; then
  fail ""
  fail "✗ pre-flight failed: $failed_count image(s) unreachable on any configured mirror"
  fail "  → check version pins in .env / .env.example (e.g. is the v-prefix present?)"
  fail "  → or update registry-mirrors in ~/.orbstack/config/docker.json"
  exit 1
fi
