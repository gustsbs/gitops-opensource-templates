#!/bin/sh
# Executado no Job wp-lab-instalar (imagem php-wordpress, uid 33).
# DB_HOST, DB_NAME, DB_USER, DB_PASSWORD vem do Secret wp-lab-db.
set -eu
cd /var/www/html

if [ -f wp-load.php ] && [ -f wp-config.php ]; then
  echo "WordPress ja presente no volume: nada a fazer."
  exit 0
fi

echo "Baixando o WordPress (pt_BR)..."
curl -fsSL https://br.wordpress.org/latest-pt_BR.tar.gz -o /tmp/wordpress.tar.gz
tar xzf /tmp/wordpress.tar.gz --strip-components=1 -C /var/www/html
rm -f /tmp/wordpress.tar.gz

php /scripts/gerar-wp-config.php > wp-config.php
chmod 640 wp-config.php
echo "WordPress pronto. Conclua a instalacao em http://site.lab.localhost"
