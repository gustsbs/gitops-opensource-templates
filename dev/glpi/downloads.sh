#!/bin/sh
# Baixa o GLPI e os plugins homologados. A lista de plugins e a mesma em todos
# os ambientes: a imagem validada no teste e na homologacao e a mesma que vai
# para a producao. O que fica ativo em cada ambiente e decidido no proprio
# GLPI (Configurar > Plugins); plugin presente mas nao ativado nao carrega.
#
# Uso: downloads.sh <versao-do-glpi>   (executado em /var/www pelo Dockerfile)
set -eu

GLPI_VERSION=${1:?informe a versao do GLPI (ex.: 11.0.11)}

rm -rf html
wget -q "https://github.com/glpi-project/glpi/releases/download/$GLPI_VERSION/glpi-$GLPI_VERSION.tgz"
tar xzf "glpi-$GLPI_VERSION.tgz"
rm "glpi-$GLPI_VERSION.tgz"
mv glpi html
mkdir -p html/plugins
cd html/plugins

# Use o ramo de cada plugin compativel com a versao do GLPI.
wget -q https://github.com/pluginsGLPI/pdf/releases/download/4.1.6/glpi-pdf-4.1.6.tar.bz2
wget -q https://github.com/pluginsGLPI/addressing/releases/download/3.2.15/glpi-addressing-3.2.15.tar.bz2
wget -q https://github.com/glpi-project/glpi-inventory-plugin/releases/download/1.6.10/glpi-glpiinventory-1.6.10.tar.bz2
wget -q https://github.com/pluginsGLPI/news/releases/download/1.14.2/glpi-news-1.14.2.tar.bz2
wget -q https://github.com/pluginsGLPI/datainjection/releases/download/2.15.12/glpi-datainjection-2.15.12.tar.bz2
wget -q https://github.com/pluginsGLPI/escalade/releases/download/2.10.7/glpi-escalade-2.10.7.tar.bz2
wget -q https://github.com/pluginsGLPI/tag/releases/download/2.14.8/glpi-tag-2.14.8.tar.bz2
wget -q https://github.com/pluginsGLPI/satisfaction/releases/download/1.7.8/glpi-satisfaction-1.7.8.tar.bz2
wget -q https://github.com/pluginsGLPI/mreporting/releases/download/1.10.3/glpi-mreporting-1.10.3.tar.bz2
wget -q https://github.com/edgardmessias/glpi-singlesignon/releases/download/v2.0.3/singlesignon.tar.bz2

for i in *.bz2; do tar xjf "$i" && rm "$i"; done
