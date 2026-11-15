# Imagem base nginx - ramo stable, variante unprivileged: roda como uid 101,
# escuta na 8080 e grava pid/temporarios em /tmp. Compativel com
# runAsNonRoot e readOnlyRootFilesystem (montar /tmp e /var/cache/nginx em emptyDir).
FROM nginxinc/nginx-unprivileged:1.30.6-alpine

COPY confs/ /opt/nginx-confs/

EXPOSE 8080
