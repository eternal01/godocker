ARG ETCD_VERSION
ARG SYSTEM_VERSION=bookworm

#--------------------------------------------------------------------------
# Self-built etcd image.
# Reason: bitnami/etcd (and every other published etcd image) is no longer
# carried by CN registry mirrors — 1ms.run returns empty tags and daocloud
# returns 403 for every probe. etcd is a single static Go binary, so we
# download it directly from GitHub releases via a CN-friendly mirror
# (ghfast.top) and ship a minimal Debian-slim image.
#--------------------------------------------------------------------------
# Layout intentionally matches the bitnami/etcd paths the existing compose
# service relies on, so no compose changes are required:
#   - binaries in /opt/bitnami/etcd/bin/  (etcd, etcdctl)
#   - data dir  /bitnami/etcd
#   - listener  0.0.0.0:2379 / 0.0.0.0:2380
#--------------------------------------------------------------------------

FROM debian:${SYSTEM_VERSION}-slim

ARG ETCD_VERSION
# CN-friendly GitHub release mirror. ghfast.top is a public reverse proxy
# that fronts github.com/.../releases/download/* — the original URL is the
# path component, so it works for any release tarball. Falls back to the
# canonical GitHub URL if the mirror is down.
ARG GITHUB_MIRROR=https://ghfast.top/https://github.com

ENV ETCD_DATA_DIR=/bitnami/etcd \
    ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379 \
    ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380 \
    ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379 \
    ETCDCTL_API=3 \
    PATH=/opt/bitnami/etcd/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tar; \
    rm -rf /var/lib/apt/lists/*; \
    \
    download_tarball() { \
      url="$1"; \
      curl -fsSL --retry 5 --retry-delay 5 -o /tmp/etcd.tgz "$url"; \
    }; \
    \
    TARBALL_URL="${GITHUB_MIRROR}/etcd-io/etcd/releases/download/v${ETCD_VERSION#v}/etcd-v${ETCD_VERSION#v}-linux-amd64.tar.gz"; \
    if ! download_tarball "$TARBALL_URL"; then \
      echo "⚠ mirror failed, falling back to github.com"; \
      TARBALL_URL="https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION#v}/etcd-v${ETCD_VERSION#v}-linux-amd64.tar.gz"; \
      download_tarball "$TARBALL_URL"; \
    fi; \
    \
    EXTRACT_DIR="/tmp/etcd-v${ETCD_VERSION#v}-linux-amd64"; \
    mkdir -p /opt/bitnami/etcd/bin; \
    tar -xzf /tmp/etcd.tgz -C /tmp; \
    install -m 0755 "$EXTRACT_DIR/etcd"    /opt/bitnami/etcd/bin/etcd; \
    install -m 0755 "$EXTRACT_DIR/etcdctl" /opt/bitnami/etcd/bin/etcdctl; \
    rm -rf /tmp/etcd.tgz "$EXTRACT_DIR"; \
    \
    /opt/bitnami/etcd/bin/etcd --version; \
    /opt/bitnami/etcd/bin/etcdctl version; \
    \
    mkdir -p /bitnami/etcd; \
    useradd -r -u 999 -g root -d /bitnami/etcd -s /sbin/nologin etcd; \
    chown -R etcd:root /bitnami/etcd /opt/bitnami/etcd; \
    chmod 0755 /opt/bitnami/etcd/bin/*; \
    \
    # Note: don't purge `tar` — dpkg depends on it and the resolver refuses.
    # The extra ~2MB on disk isn't worth the fragility.
    apt-get purge -y --auto-remove curl; \
    rm -rf /var/lib/apt/lists/*

COPY --chown=etcd:root entrypoint.sh /opt/bitnami/etcd/bin/entrypoint.sh
RUN chmod 0755 /opt/bitnami/etcd/bin/entrypoint.sh

USER etcd
WORKDIR /bitnami/etcd
VOLUME /bitnami/etcd
EXPOSE 2379 2380

ENTRYPOINT ["/opt/bitnami/etcd/bin/entrypoint.sh"]
