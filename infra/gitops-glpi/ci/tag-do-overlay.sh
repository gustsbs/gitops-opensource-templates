#!/bin/sh
# Imprime o newTag de uma imagem no kustomization.yaml de um overlay.
# Uso: tag-do-overlay.sh <diretorio-do-overlay> <imagem-sem-tag>
set -eu
T=$(IMG="$2" yq '.images[] | select(.name == strenv(IMG)) | .newTag' "$1/kustomization.yaml")
[ -n "$T" ] && [ "$T" != "null" ] || { echo "ERRO: $2 sem newTag em $1/kustomization.yaml" >&2; exit 1; }
printf '%s\n' "$T"
