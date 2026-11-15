#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Gera o SealedSecret "glpi-oauth" (oauth.pem + oauth.pub) de um overlay.
#
# O GLPI 11 grava o par de chaves RSA do servidor OAuth2 (API v2) em
# /var/www/html/config/oauth.{pem,pub}. Esse diretório vem da imagem e não é
# persistido, então as chaves somem a cada novo pod. Este script sela as chaves
# para serem montadas a partir de um Secret (ver glpi-deployment.yaml).
#
# Uso:
#   ./scripts/seal-oauth-keys.sh <producao|homologa|teste> [--from-pod|--generate] [--force]
#
#   --from-pod  (padrão) copia as chaves que existem hoje no pod em execução,
#               preservando os tokens já emitidos (validade de 1h).
#   --generate  gera um par novo (RSA 2048, mesmo formato do GLPI). Os tokens
#               de acesso emitidos invalidam; os clientes OAuth cadastrados no
#               GLPI (client_id/secret) continuam valendo, pois ficam no banco.
#               Por segurança, o --generate se recusa a continuar se:
#                 - o pod já tiver oauth.pem/oauth.pub (use --from-pod para aproveitá-las);
#                 - o SealedSecret do overlay já existir no repositório.
#               Para uma rotação intencional de chaves, acrescente --force.
#
# Controller do Sealed Secrets no cluster: svc "sealed-secrets" em kube-system
# (instalação via Helm; o padrão do kubeseal seria "sealed-secrets-controller").
# Para sobrescrever: KUBESEAL_ARGS="--controller-name X --controller-namespace Y" ./scripts/...
# -----------------------------------------------------------------------------
set -euo pipefail

OVERLAY="${1:-}"; shift || true
MODE="--from-pod"; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --from-pod|--generate) MODE="$arg" ;;
    --force) FORCE=1 ;;
    *) echo "Opção inválida: $arg" >&2; exit 1 ;;
  esac
done
case "$OVERLAY" in
  producao) NS=glpi-prod;  OUT=sealed-oauth.yaml ;;
  homologa) NS=glpi-hml;   OUT=sealed-oauth.yaml ;;
  teste)    NS=glpi-teste; OUT=sealed-oauth.yaml ;;
  *) echo "Uso: $0 <producao|homologa|teste> [--from-pod|--generate] [--force]" >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBESEAL_ARGS="${KUBESEAL_ARGS:---controller-name sealed-secrets --controller-namespace kube-system}"
DEST="$REPO_ROOT/gitops/overlays/$OVERLAY/$OUT"

for bin in kubectl kubeseal openssl; do
  command -v "$bin" >/dev/null || { echo "Falta o binário: $bin" >&2; exit 1; }
done

# --- Proteções do --generate (evitam trocar as chaves sem querer) ------------
if [ "$MODE" = "--generate" ] && [ "$FORCE" -eq 0 ]; then
  if [ -s "$DEST" ]; then
    echo "!! Já existe ${DEST#$REPO_ROOT/}." >&2
    echo "   Gerar um par novo troca as chaves e invalida os tokens em uso." >&2
    echo "   Para uma rotação intencional: $0 $OVERLAY --generate --force" >&2
    exit 1
  fi
  if kubectl -n "$NS" get deploy glpi >/dev/null 2>&1; then
    if kubectl -n "$NS" exec deploy/glpi -c php -- \
         sh -c 'test -s /var/www/html/config/oauth.pem && test -s /var/www/html/config/oauth.pub' 2>/dev/null; then
      echo "!! O pod em $NS já tem oauth.pem/oauth.pub." >&2
      echo "   Para reaproveitá-las (recomendado): $0 $OVERLAY --from-pod" >&2
      echo "   Para descartá-las e gerar novas:    $0 $OVERLAY --generate --force" >&2
      exit 1
    fi
  else
    echo ">> Aviso: não encontrei deploy/glpi em $NS (sem acesso ao cluster?)." >&2
    echo "   Não foi possível verificar se o pod já tem chaves; seguindo com a geração." >&2
  fi
fi

# Chaves em texto puro só em diretório temporário fora do repositório.
TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

case "$MODE" in
  --from-pod)
    echo ">> Copiando chaves do pod em execução (ns $NS)..."
    for f in oauth.pem oauth.pub; do
      if ! kubectl -n "$NS" exec deploy/glpi -c php -- \
           cat "/var/www/html/config/$f" > "$TMP/$f" 2>/dev/null || [ ! -s "$TMP/$f" ]; then
        echo "!! $f não existe no pod. Use --generate para criar um par novo." >&2
        exit 1
      fi
    done
    ;;
  --generate)
    echo ">> Gerando novo par RSA 2048..."
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TMP/oauth.pem" 2>/dev/null
    openssl pkey -in "$TMP/oauth.pem" -pubout -out "$TMP/oauth.pub"
    ;;
  *) echo "Modo inválido: $MODE" >&2; exit 1 ;;
esac

# Confere se a chave pública corresponde à privada.
if ! diff -q <(openssl pkey -in "$TMP/oauth.pem" -pubout) "$TMP/oauth.pub" >/dev/null; then
  echo "!! oauth.pub não corresponde a oauth.pem — abortando." >&2; exit 1
fi

echo ">> Selando para o namespace $NS..."
# shellcheck disable=SC2086
kubectl create secret generic glpi-oauth -n "$NS" \
    --from-file=oauth.pem="$TMP/oauth.pem" \
    --from-file=oauth.pub="$TMP/oauth.pub" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml ${KUBESEAL_ARGS:-} \
  | awk '
      # sync-wave -1: o Secret precisa existir antes do Deployment (mesmo padrão do overlay teste)
      !done && /^  namespace:/ { print; print "  annotations:"; print "    argocd.argoproj.io/sync-wave: \"-1\""; done=1; next }
      { print }' > "$TMP/sealed.yaml"

# Só substitui o arquivo do repositório se o selo deu certo (evita arquivo vazio).
grep -q '^kind: SealedSecret' "$TMP/sealed.yaml" || { echo "!! Saída do kubeseal inválida — nada foi gravado." >&2; exit 1; }
mv "$TMP/sealed.yaml" "$DEST"
echo ">> Gerado: ${DEST#$REPO_ROOT/}"
