#!/bin/sh
# Da o nome de versao a uma imagem ja construida, sem rebuild: copia a tag no
# registry preservando o digest. Tag de versao existente nunca e sobrescrita.
# Com origem = versao, apenas confere a imagem e registra o digest.
#
# Uso: publicar-versao.sh <imagem-sem-tag> <tag-origem> <tag-versao>
# Saida: .promocao/<imagem>.digest e .promocao/<imagem>.revisao
set -eu
IMG=$1; ORIG=$2; VER=$3; NOME=${IMG##*/}
AUTH="--authfile ${REGISTRY_AUTH_FILE:-/docker/config.json}"
mkdir -p .promocao

D_ORIG=$(skopeo inspect $AUTH --format '{{.Digest}}' "docker://$IMG:$ORIG")
REV=$(skopeo inspect $AUTH --format '{{index .Labels "org.opencontainers.image.revision"}}' "docker://$IMG:$ORIG" 2>/dev/null || true)

if D_VER=$(skopeo inspect $AUTH --format '{{.Digest}}' "docker://$IMG:$VER" 2>/dev/null); then
  if [ "$D_VER" != "$D_ORIG" ]; then
    echo "ERRO: $IMG:$VER ja existe com outro conteudo ($D_VER)."
    echo "      Tags de versao nao sao sobrescritas: use uma revisao nova (ex.: -v1.2)."
    exit 1
  fi
  echo "$IMG:$VER ja existe com o mesmo digest: nada a copiar."
else
  skopeo copy $AUTH --preserve-digests "docker://$IMG:$ORIG" "docker://$IMG:$VER"
  D_VER=$(skopeo inspect $AUTH --format '{{.Digest}}' "docker://$IMG:$VER")
  [ "$D_VER" = "$D_ORIG" ] || { echo "ERRO: o digest mudou na copia ($D_ORIG -> $D_VER)"; exit 1; }
fi

printf '%s' "$D_ORIG" > ".promocao/$NOME.digest"
printf '%s' "$REV" > ".promocao/$NOME.revisao"
echo "OK: $IMG:$ORIG -> $IMG:$VER  digest=$D_ORIG  commit=${REV:-desconhecido}"
