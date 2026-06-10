#!/bin/sh
#--------------------------------------------------------------------------
# Entrypoint for the self-built etcd image.
# Translates the ETCD_* env vars the compose file passes into the
# corresponding --flags etcd expects, then execs etcd in the foreground.
#
# IMPORTANT: etcd refuses to start if BOTH an env var and its corresponding
# --flag are set (its verifyEnv check fatal-errors with "conflicting
# environment variable is shadowed by corresponding command-line flag").
# So this script reads the env vars into local shell variables, UNSETS the
# env vars, then execs etcd with --flags as the single source of truth.
# Mirrors bitnami/etcd defaults: data dir /bitnami/etcd, listen on
# 0.0.0.0:2379 (client) and 0.0.0.0:2380 (peer).
#--------------------------------------------------------------------------
set -eu

DATA_DIR="${ETCD_DATA_DIR:-/bitnami/etcd}"
LISTEN_CLIENT="${ETCD_LISTEN_CLIENT_URLS:-http://0.0.0.0:2379}"
LISTEN_PEER="${ETCD_LISTEN_PEER_URLS:-http://0.0.0.0:2380}"
ADVERTISE_CLIENT="${ETCD_ADVERTISE_CLIENT_URLS:-http://0.0.0.0:2379}"
NAME="${ETCD_NAME:-etcd}"
INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER:-${NAME}=http://0.0.0.0:2380}"
INITIAL_ADVERTISE_PEER="${ETCD_INITIAL_ADVERTISE_PEER_URLS:-http://0.0.0.0:2380}"

# bitnami/etcd accepted ALLOW_NONE_AUTHENTICATION=yes as a no-auth toggle;
# etcd itself uses --client-cert-auth for the same effect. We just leave
# auth off by default (--client-cert-auth unset) for a local dev cluster.
AUTH_FLAG=""
if [ "${ALLOW_NONE_AUTHENTICATION:-yes}" != "yes" ]; then
  AUTH_FLAG="--client-cert-auth"
fi

# Unset the ETCD_* env vars so etcd's verifyEnv check doesn't see them as
# conflicts against the --flags we pass below. ALLOW_NONE_AUTHENTICATION is
# not an etcd env var (it's bitnami-style), so we leave it.
unset ETCD_DATA_DIR \
      ETCD_LISTEN_CLIENT_URLS \
      ETCD_LISTEN_PEER_URLS \
      ETCD_ADVERTISE_CLIENT_URLS \
      ETCD_NAME \
      ETCD_INITIAL_CLUSTER \
      ETCD_INITIAL_ADVERTISE_PEER_URLS

mkdir -p "$DATA_DIR"

exec /opt/bitnami/etcd/bin/etcd \
  --name "$NAME" \
  --data-dir "$DATA_DIR" \
  --listen-client-urls        "$LISTEN_CLIENT" \
  --listen-peer-urls          "$LISTEN_PEER" \
  --advertise-client-urls     "$ADVERTISE_CLIENT" \
  --initial-advertise-peer-urls "$INITIAL_ADVERTISE_PEER" \
  --initial-cluster           "$INITIAL_CLUSTER" \
  --initial-cluster-state     "new" \
  $AUTH_FLAG
