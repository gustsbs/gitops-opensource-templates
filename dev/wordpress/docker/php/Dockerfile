# php-wordpress: PHP-FPM para os sites WordPress - sem codigo.
# Core, plugins, temas e uploads ficam no volume de cada site e sao
# atualizados pelo wp-admin; esta imagem traz so runtime e configuracao.
#   docker build --label org.opencontainers.image.revision=$(git rev-parse HEAD) \
#     -t registry.exemplo.edu.br/dev/wordpress/php-wordpress:8.5.12-v1.0 docker/php
ARG BASE_IMAGE=registry.exemplo.edu.br/dev/docker-base-images/php:8.5.12-fpm-alpine-v1.0
FROM ${BASE_IMAGE}

USER root

# msmtp: envio de e-mail (wp_mail) pelo relay SMTP da instituicao.
# php.ini-production: sem ele o PHP usa os padroes de desenvolvimento
# (display_errors ligado, expondo erros e caminhos ao visitante).
RUN apk add --no-cache msmtp \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# zzz-*: carregados depois dos zz-* da base e sobrescrevem o necessario.
COPY conf.d/wordpress.ini /usr/local/etc/php/conf.d/zzz-wordpress.ini
COPY fpm/zzz-pool.conf    /usr/local/etc/php-fpm.d/zzz-pool.conf

USER www-data
