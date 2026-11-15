# redis-wordpress: object cache dos sites WordPress, sem persistencia.
ARG BASE_IMAGE=registry.exemplo.edu.br/dev/docker-base-images/redis:8.8.3-alpine-v1.0
FROM ${BASE_IMAGE}

COPY confs/redis.conf /usr/local/etc/redis/redis.conf

CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]
