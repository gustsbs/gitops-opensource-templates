#!/bin/sh
# Troca tags de imagem num overlay e abre um MR no gitops-glpi.
# O MR e criado por push options do GitLab: o token precisa so de
# write_repository. Nunca grava na main.
#
# Uso: abrir-mr.sh <overlay> <ambiente> <imagem:tag> [<imagem:tag> ...]
# Ambiente: GIT_USER, GIT_PASS, GITOPS_REPO (host/caminho.git), DESCRICAO (uma linha)
set -eu
OVERLAY=$1; AMB=$2; shift 2
DIR=$(mktemp -d)
git clone -q "https://$GIT_USER:$GIT_PASS@$GITOPS_REPO" "$DIR"
cd "$DIR"
git config user.name "CI"
git config user.email "ci@exemplo.edu.br"

sh ci/trocar-tag.sh "$OVERLAY" "$@"

RESUMO=""; SUFIXO=""
for ref in "$@"; do
  NOME_TAG=${ref##*/}
  RESUMO="$RESUMO $NOME_TAG"
  SUFIXO="$SUFIXO-$(printf '%s' "$NOME_TAG" | tr ':' '-')"
done

RENDER=$(kustomize build "$OVERLAY")
for ref in "$@"; do
  printf '%s\n' "$RENDER" | grep -qF "image: $ref" || { echo "ERRO: $ref nao aparece no render de $OVERLAY"; exit 1; }
done

if git diff --quiet; then
  echo "Nada a promover: $AMB ja usa$RESUMO"
  exit 0
fi

BRANCH="promover/$AMB$SUFIXO"
TITULO="chore($AMB): promover$RESUMO"
git checkout -q -b "$BRANCH"
git commit -q -a -m "$TITULO" -m "$DESCRICAO" -m "Build: ${BUILD_URL:-}"
git --no-pager show --stat --format='%s' HEAD
git --no-pager diff HEAD~1
git push -f origin "$BRANCH" \
  -o merge_request.create \
  -o merge_request.target=main \
  -o "merge_request.title=$TITULO" \
  -o "merge_request.description=$DESCRICAO" \
  -o merge_request.remove_source_branch \
  -o merge_request.label=promocao
