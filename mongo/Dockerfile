ARG MONGO_VERSION
FROM mongo:${MONGO_VERSION}

LABEL maintainer="muxk <361087696@qq.com>"

#COPY mongo.conf /usr/local/etc/mongo/mongo.conf

VOLUME /data/db /data/configdb

CMD ["mongod"]

EXPOSE 27017
