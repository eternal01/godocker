FROM minio/minio:${MINIO_VERSION}

LABEL maintainer="muxk <361087696@qq.com>"

ENTRYPOINT ["minio", "server", "--console-address", ":9001", "/export"]
