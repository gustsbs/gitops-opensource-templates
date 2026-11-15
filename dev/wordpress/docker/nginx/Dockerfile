# nginx-wordpress: nginx dos sites WordPress. Escuta na 8080 (uid 101).
#   docker build --label org.opencontainers.image.revision=$(git rev-parse HEAD) \
#     -t registry.exemplo.edu.br/dev/wordpress/nginx-wordpress:1.30.6-v1.0 docker/nginx
ARG BASE_IMAGE=registry.exemplo.edu.br/dev/docker-base-images/nginx:1.30.6-alpine-v1.0
FROM ${BASE_IMAGE}

USER root
COPY confs/wordpress_nginx.conf /etc/nginx/nginx.conf
COPY confs/site_wordpress.conf  /etc/nginx/conf.d/default.conf
COPY confs/realip.conf          /etc/nginx/wordpress.d/realip.conf
# nginx -t roda como root e deixa arquivos em /tmp com dono root: limpar.
RUN nginx -t && rm -rf /tmp/*
USER 101

EXPOSE 8080
