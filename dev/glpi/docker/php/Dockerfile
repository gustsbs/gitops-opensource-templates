# Imagem php-glpi: PHP-FPM exclusivo do GLPI (runtime + codigo + plugins).
#
# Build a partir da RAIZ deste repositorio (o contexto precisa do downloads.sh):
#   docker build --pull --platform linux/amd64 -f docker/php/Dockerfile \
#     -t registry.exemplo.edu.br/dev/glpi/php-glpi:11.0.11-v1.0 .
#
# Uma imagem so para teste, homologacao e producao (mesma lista de plugins):
# a promocao entre ambientes reaproveita a imagem, sem novo build.
FROM php:8.5.12-fpm-alpine

ARG GLPI_VERSION=11.0.11
# Versao fixa da extensao redis (PECL), para builds reprodutiveis.
ARG PHPREDIS_VERSION=6.3.0

# Bibliotecas de runtime FORA do grupo virtual: o "apk del .build-deps" nao
# enxerga a dependencia via dlopen das extensoes e removeria as libs junto.
RUN apk add --no-cache \
        freetype libjpeg-turbo libpng libwebp libzip icu-libs oniguruma \
        openldap libbz2 msmtp \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS freetype-dev libjpeg-turbo-dev libpng-dev libwebp-dev \
        libzip-dev icu-dev oniguruma-dev openldap-dev bzip2-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" \
        mysqli pdo_mysql gd intl mbstring bcmath zip bz2 exif ldap \
    && pecl install "redis-${PHPREDIS_VERSION}" \
    && docker-php-ext-enable redis \
    && apk del --no-cache .build-deps \
    && rm -rf /tmp/pear \
    && for ext in mysqli gd intl mbstring bcmath zip bz2 exif ldap redis curl sodium; do \
           php -m | grep -qix "$ext" || { echo "extensao ausente: $ext"; exit 1; }; \
       done \
    && php -m | grep -q 'Zend OPcache'

COPY docker/php/conf.d/opcache.ini     /usr/local/etc/php/conf.d/zz-opcache.ini
COPY docker/php/conf.d/glpi.ini        /usr/local/etc/php/conf.d/zz-glpi.ini
COPY docker/php/conf.d/fpm-health.conf /usr/local/etc/php-fpm.d/zz-health.conf

# Codigo do GLPI e plugins homologados. "sh -e" e a verificacao final fazem
# o build falhar se o download ou a extracao vierem incompletos.
COPY downloads.sh /tmp/downloads.sh
RUN apk add --no-cache --virtual .fetch-deps wget bzip2 ca-certificates \
    && cd /var/www \
    && sh -e /tmp/downloads.sh "${GLPI_VERSION}" \
    && rm -f /tmp/downloads.sh \
    && apk del --no-cache .fetch-deps \
    && for f in bin/console public/index.php vendor/autoload.php; do \
           test -f "/var/www/html/$f" || { echo "GLPI incompleto: falta $f"; exit 1; }; \
       done

# Plugins proprios da instituicao (opcional):
# COPY meuplugin/ /var/www/html/plugins/meuplugin/

# Codigo imutavel: dono root, apenas leitura para o processo. O GLPI grava so
# em files/ (volume persistente) e le config/ montado de Secrets/ConfigMaps.
# O Pod roda com runAsUser/runAsGroup 33, dono dos dados no volume.
RUN chown -R root:root /var/www/html \
    && chmod -R u=rwX,go=rX /var/www/html

WORKDIR /var/www/html

USER www-data

EXPOSE 9000
