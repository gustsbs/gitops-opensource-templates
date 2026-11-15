# Imagem nginx-glpi: nginx unprivileged (uid 101, porta 8080) com a
# configuracao do GLPI. Nao contem codigo: os arquivos de public/ chegam por
# um emptyDir semeado por initContainer a partir da imagem php-glpi.
#   docker build -f docker/nginx/Dockerfile \
#     -t registry.exemplo.edu.br/dev/glpi/nginx-glpi:1.30.6-v1.0 docker/nginx
ARG BASE_IMAGE=registry.exemplo.edu.br/dev/docker-base-images/nginx:1.30.6-alpine-v1.0
FROM ${BASE_IMAGE}

COPY nginx.conf /etc/nginx/nginx.conf
COPY site_glpi.conf /etc/nginx/conf.d/default.conf
COPY glpi.d/ /etc/nginx/glpi.d/

EXPOSE 8080
