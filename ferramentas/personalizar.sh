#!/usr/bin/env bash
# Substitui os valores de exemplo dos templates (dominios dos Ingress,
# registry, servidor Git, NFS, SMTP...) pelos valores da sua instituicao.
#
# Uso:
#   cp ferramentas/personalizar.env.exemplo personalizar.env   # edite os valores
#   ferramentas/personalizar.sh personalizar.env               # mostra o que mudaria
#   ferramentas/personalizar.sh personalizar.env --aplicar     # grava as mudancas
#
# Altera apenas os arquivos de dev/ e infra/. Rode em um clone limpo (ou
# confira com "git diff" depois): os valores de exemplo deixam de existir e
# uma segunda execucao nao encontra mais o que trocar.
set -euo pipefail

ARQ_ENV=${1:?uso: $0 <arquivo.env> [--aplicar]}
MODO=${2:-}
[ -f "$ARQ_ENV" ] || { echo "Arquivo nao encontrado: $ARQ_ENV" >&2; exit 1; }
[ -z "$MODO" ] || [ "$MODO" = "--aplicar" ] || { echo "Opcao invalida: $MODO" >&2; exit 1; }

# shellcheck disable=SC1090
source "$ARQ_ENV"

DOMINIO=${DOMINIO:?defina DOMINIO no $ARQ_ENV}
REGISTRY=${REGISTRY:-registry.$DOMINIO}
GIT_HOST=${GIT_HOST:-git.$DOMINIO}
GRUPO_DEV=${GRUPO_DEV:-dev}
GRUPO_INFRA=${GRUPO_INFRA:-infra}
GRUPO_TEMAS=${GRUPO_TEMAS:-temas}
GLPI_HOST_PROD=${GLPI_HOST_PROD:-glpi.$DOMINIO}
GLPI_HOST_HML=${GLPI_HOST_HML:-glpi.homologa.$DOMINIO}
GLPI_HOST_TESTE=${GLPI_HOST_TESTE:-glpi.teste.$DOMINIO}
NFS_SERVER=${NFS_SERVER:-192.0.2.10}
NFS_EXPORT=${NFS_EXPORT:-/exports}
POD_CIDR=${POD_CIDR:-10.244.0.0/16}
SMTP_HOST=${SMTP_HOST:-smtp.$DOMINIO}
EMAIL_REMETENTE=${EMAIL_REMETENTE:-naoresponda@$DOMINIO}
EMAIL_CI=${EMAIL_CI:-ci@$DOMINIO}

# Pares "valor de exemplo" -> "valor real". A ordem importa: os nomes mais
# especificos vem antes do dominio generico (exemplo.edu.br), senao
# registry.exemplo.edu.br viraria registry.<seu-dominio> antes da troca certa.
PARES=(
  "registry.exemplo.edu.br/dev/"   "$REGISTRY/$GRUPO_DEV/"
  "registry.exemplo.edu.br/temas/" "$REGISTRY/$GRUPO_TEMAS/"
  "registry.exemplo.edu.br"        "$REGISTRY"
  "git.exemplo.edu.br/infra/"      "$GIT_HOST/$GRUPO_INFRA/"
  "git.exemplo.edu.br"             "$GIT_HOST"
  "@infra"                         "@$GRUPO_INFRA"
  "glpi.teste.exemplo.edu.br"      "$GLPI_HOST_TESTE"
  "glpi.homologa.exemplo.edu.br"   "$GLPI_HOST_HML"
  "glpi.exemplo.edu.br"            "$GLPI_HOST_PROD"
  "smtp.exemplo.edu.br"            "$SMTP_HOST"
  "naoresponda@exemplo.edu.br"     "$EMAIL_REMETENTE"
  "ci@exemplo.edu.br"              "$EMAIL_CI"
  "exemplo.edu.br"                 "$DOMINIO"
  "192.0.2.10"                     "$NFS_SERVER"
  "/exports/"                      "${NFS_EXPORT%/}/"
  "10.244.0.0/16"                  "$POD_CIDR"
)

cd "$(dirname "$0")/.."

# Escapa um texto para uso literal no sed (padrao e substituicao).
esc_padrao() { printf '%s' "$1" | sed 's/[][\.*^$|/]/\\&/g'; }
esc_subst()  { printf '%s' "$1" | sed 's/[\&|/]/\\&/g'; }

SCRIPT_SED=""
for ((i = 0; i < ${#PARES[@]}; i += 2)); do
  de=${PARES[i]}; para=${PARES[i+1]}
  [ "$de" = "$para" ] && continue
  SCRIPT_SED+="s|$(esc_padrao "$de")|$(esc_subst "$para")|g;"
done

if [ -z "$SCRIPT_SED" ]; then
  echo "Nada a trocar: os valores do $ARQ_ENV sao iguais aos de exemplo."
  exit 0
fi

mapfile -t ARQUIVOS < <(grep -rlI -F -e exemplo.edu.br -e 192.0.2.10 -e /exports/ -e 10.244.0.0/16 -e @infra dev infra 2>/dev/null | sort)
if [ ${#ARQUIVOS[@]} -eq 0 ]; then
  echo "Nenhum valor de exemplo encontrado em dev/ e infra/ (ja personalizado?)."
  exit 0
fi

alterados=0
for f in "${ARQUIVOS[@]}"; do
  novo=$(sed "$SCRIPT_SED" "$f")
  if [ "$novo" != "$(cat "$f")" ]; then
    alterados=$((alterados + 1))
    if [ "$MODO" = "--aplicar" ]; then
      printf '%s\n' "$novo" > "$f"
      echo "alterado: $f"
    else
      diff -u --label "$f" --label "$f (personalizado)" "$f" <(printf '%s\n' "$novo") || true
    fi
  fi
done

echo
if [ "$MODO" = "--aplicar" ]; then
  echo "$alterados arquivo(s) alterado(s). Confira com: git diff"
  echo "Depois gere os SealedSecrets no seu cluster (veja infra/gitops-glpi/README.md)."
else
  echo "$alterados arquivo(s) seriam alterados. Para gravar: $0 $ARQ_ENV --aplicar"
fi
