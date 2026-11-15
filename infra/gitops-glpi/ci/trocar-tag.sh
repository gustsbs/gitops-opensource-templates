#!/bin/sh
# Troca o newTag de imagens no kustomization.yaml de um overlay, mexendo so na
# linha do newTag (preserva formato, ordem, comentarios e linhas em branco).
# Falha se a imagem nao tiver entrada com newTag no images:.
#
# Uso: trocar-tag.sh <overlay> <imagem:tag> [<imagem:tag> ...]
set -eu
K="$1/kustomization.yaml"; shift
for ref in "$@"; do
  IMG=${ref%:*}; TAG=${ref##*:}
  if ! awk -v img="$IMG" -v tag="$TAG" '
      /^[ \t]*-[ \t]*name:/ { v = $0; sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", v); alvo = (v == img) }
      alvo && /^[ \t]*newTag:/ { sub(/newTag:.*/, "newTag: " tag); alvo = 0; n++ }
      { print }
      END { exit (n ? 0 : 3) }' "$K" > "$K.tmp"; then
    rm -f "$K.tmp"
    echo "ERRO: $IMG nao tem newTag em $K" >&2
    exit 1
  fi
  mv "$K.tmp" "$K"
done
