# Imagem base PHP-FPM - generica, sem codigo de aplicacao.
# Fixe o digest do indice multi-arquitetura para builds reprodutiveis:
#   docker buildx imagetools inspect php:<tag> | grep -m1 Digest
FROM php:8.5.12-fpm-alpine

# Versao fixa da extensao redis (PECL): sem versao, cada build pode trazer
# uma release diferente.
ARG PHPREDIS_VERSION=6.3.0

RUN apk add --no-cache \
        freetype libjpeg-turbo libpng libzip icu-libs oniguruma libwebp openldap \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS freetype-dev libjpeg-turbo-dev libpng-dev libzip-dev \
        icu-dev oniguruma-dev libwebp-dev openldap-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        mysqli pdo_mysql gd zip exif intl mbstring bcmath ldap \
    && pecl install "redis-${PHPREDIS_VERSION}" \
    && docker-php-ext-enable redis \
    && apk del --no-cache .build-deps \
    && rm -rf /tmp/pear \
    && for ext in mysqli pdo_mysql gd zip exif intl mbstring bcmath ldap redis; do \
           php -m | grep -qix "$ext" || { echo "extensao ausente: $ext"; exit 1; }; \
       done \
    && php -m | grep -q 'Zend OPcache'

COPY conf.d/opcache.ini     /usr/local/etc/php/conf.d/zz-opcache.ini
COPY conf.d/uploads.ini     /usr/local/etc/php/conf.d/zz-uploads.ini
# Endpoint /fpm-ping para as probes (respondido pelo proprio php-fpm)
COPY conf.d/fpm-health.conf /usr/local/etc/php-fpm.d/zz-health.conf

WORKDIR /var/www/html

# Usuario nao root (www-data, uid 82 no Alpine)
USER www-data

EXPOSE 9000
