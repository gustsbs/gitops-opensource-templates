#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Gera os SealedSecrets "glpi-config" (config_db.php) e "glpi-key"
# (glpicrypt.key) de um overlay, selados para o cluster do contexto atual do
# kubectl.
#
# Quando usar: sempre que o overlay mudar de cluster (cada cluster tem o seu par
# de chaves do Sealed Secrets, então um SealedSecret selado para um cluster não
# abre em outro) ou quando o config_db.php/glpicrypt.key mudarem.
#
# Uso:
#   kubectl config use-context <cluster-de-destino>
#   ./scripts/seal-config-secrets.sh <producao|homologa|teste>
#
# Arquivos de origem (texto puro, ignorados pelo .gitignore — apague depois):
#   gitops/overlays/<overlay>/config_db.php
#   gitops/overlays/<overlay>/glpicrypt.key
#
# ATENÇÃO: o glpicrypt.key tem que ser o MESMO que gerou os dados cifrados no
# banco usado pelo overlay. Uma chave diferente não quebra o login, mas deixa
# ilegíveis as senhas de integração (LDAP, e-mail, coletores etc.).
#
# Controller do Sealed Secrets: svc "sealed-secrets" em kube-system (igual ao
# seal-oauth-keys.sh). Para sobrescrever:
#   KUBESEAL_ARGS="--controller-name X --controller-namespace Y" ./scripts/...
# -----------------------------------------------------------------------------
set -euo pipefail

OVERLAY="${1:-}"
case "$OVERLAY" in
  producao) NS=glpi-prod;  PREFIX=sealed ;;
  homologa) NS=glpi-hml;   PREFIX=sealed ;;
  teste)    NS=glpi-teste; PREFIX=sealed ;;
  *) echo "Uso: $0 <producao|homologa|teste>" >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$REPO_ROOT/gitops/overlays/$OVERLAY"
KUBESEAL_ARGS="${KUBESEAL_ARGS:---controller-name sealed-secrets --controller-namespace kube-system}"

for bin in kubectl kubeseal; do
  command -v "$bin" >/dev/null || { echo "Falta o binário: $bin" >&2; exit 1; }
done
for f in config_db.php glpicrypt.key; do
  [ -s "$DIR/$f" ] || { echo "!! Não encontrei ${DIR#$REPO_ROOT/}/$f (texto puro de origem)." >&2; exit 1; }
done

# Mostra para qual cluster vai selar: selar no contexto errado é o erro mais comum.
CTX="$(kubectl config current-context)"
SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
echo ">> Selando para o namespace $NS no contexto '$CTX' ($SERVER)"
read -r -p "   Confirma? [s/N] " ok
[ "$ok" = "s" ] || [ "$ok" = "S" ] || { echo "Cancelado."; exit 1; }

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

seal() {  # seal <nome-do-secret> <chave-no-secret> <arquivo-de-saída>
  local name="$1" key="$2" out="$3"
  # shellcheck disable=SC2086
  kubectl create secret generic "$name" -n "$NS" \
      --from-file="$key"="$DIR/$key" \
      --dry-run=client -o yaml \
    | kubeseal --format yaml ${KUBESEAL_ARGS:-} \
    | awk '
        # sync-wave -1: o Secret precisa existir antes do Deployment/CronJob
        !done && /^  namespace:/ { print; print "  annotations:"; print "    argocd.argoproj.io/sync-wave: \"-1\""; done=1; next }
        { print }' > "$TMP/$out"
  grep -q '^kind: SealedSecret' "$TMP/$out" || { echo "!! Saída do kubeseal inválida para $name — nada foi gravado." >&2; exit 1; }
}

seal glpi-config config_db.php "$PREFIX-config_db.yaml"
seal glpi-key    glpicrypt.key "$PREFIX-glpicrypt.yaml"

# Só grava no repositório depois que os dois selos deram certo.
mv "$TMP/$PREFIX-config_db.yaml" "$DIR/"
mv "$TMP/$PREFIX-glpicrypt.yaml" "$DIR/"
echo ">> Gerados:"
echo "   ${DIR#$REPO_ROOT/}/$PREFIX-config_db.yaml"
echo "   ${DIR#$REPO_ROOT/}/$PREFIX-glpicrypt.yaml"
echo ">> Agora apague os arquivos em texto puro: rm $DIR/config_db.php $DIR/glpicrypt.key"
