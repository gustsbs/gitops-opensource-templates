#!/bin/sh
# Executado no Job glpi-lab-instalar (imagem php-glpi, uid 33).
# DB_HOST, DB_NAME, DB_USER, DB_PASSWORD vem do Secret glpi-lab-db.
set -eu
cd /var/www/html

if php -r '
  try {
    $p = new PDO("mysql:host=".getenv("DB_HOST").";dbname=".getenv("DB_NAME"), getenv("DB_USER"), getenv("DB_PASSWORD"));
    exit($p->query("SHOW TABLES LIKE \"glpi_configs\"")->rowCount() > 0 ? 0 : 1);
  } catch (Exception $e) { fwrite(STDERR, $e->getMessage()."\n"); exit(2); }'; then
  echo "GLPI ja instalado no banco ${DB_NAME}: nada a fazer."
  exit 0
fi

# A mesma glpicrypt.key do Secret glpi-key, para o banco e os pods usarem
# a mesma chave. O config/ aqui e um emptyDir: o config_db.php gerado pelo
# instalador e descartado (os pods recebem o do Secret glpi-config).
cp /secrets/glpicrypt.key config/glpicrypt.key

php bin/console db:install \
  --db-host="$DB_HOST" \
  --db-name="$DB_NAME" \
  --db-user="$DB_USER" \
  --db-password="$DB_PASSWORD" \
  --default-language=pt_BR \
  --no-interaction

echo "GLPI instalado. Usuario inicial: glpi / glpi (troque no primeiro acesso)."
