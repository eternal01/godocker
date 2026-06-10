ARG PROMETHEUS_VERSION

# Switched from bitnami/prometheus to the official prom/prometheus image.
# Bitnami deprecated its public image catalog in 2024, so the CN registry
# mirrors (1ms.run, daocloud) no longer carry bitnami/* — see etcd/Dockerfile
# for the same pattern. prom/prometheus is the upstream image Prometheus
# itself publishes to Docker Hub, which the mirrors still proxy.
#
# Directory conventions differ from bitnami, so compose/observability.yml
# mounts the config at /etc/prometheus/prometheus.yml (the official path)
# instead of /opt/bitnami/prometheus/conf/prometheus.yml.
FROM prom/prometheus:${PROMETHEUS_VERSION}

LABEL maintainer="muxk <361087696@qq.com>"
