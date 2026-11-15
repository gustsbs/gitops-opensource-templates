#!/usr/bin/env bash
# Laboratorio local dos templates no MicroK8s: build das imagens, banco,
# segredos selados e Argo CD sincronizando os overlays de laboratorio
# (laboratorio/glpi e laboratorio/wordpress) a partir do repositorio Git.
#
# Uso: laboratorio/laboratorio.sh <etapa>
#   pre-requisitos  addons do MicroK8s, kubeseal, Sealed Secrets e Argo CD
#   imagens         build das imagens de dev/ e push para localhost:32000
#                   (ou importacao direta no MicroK8s, se o registry nao responder)
#   banco           MariaDB do laboratorio (simula o banco externo)
#   segredos        gera, sela (kubeseal) e aplica os segredos do GLPI e do WordPress
#   aplicar         aplica laboratorio/glpi e laboratorio/wordpress da pasta local
#                   (kubectl apply -k, sem Argo CD): para testar antes do push
#   argocd          cria as Applications que leem laboratorio/ no Git
#   testar          estado das Applications e resposta HTTP dos sites
#   tunel           abre as portas 80/443 do ingress para o navegador do Windows
#                   (deixe rodando; Ctrl+C para fechar)
#   tudo            pre-requisitos, imagens, banco, segredos, argocd, testar
#   tudo-local      igual, mas com "aplicar" no lugar de "argocd"
#   remover         apaga as Applications e os namespaces do laboratorio
#
# Variaveis opcionais: REPO_URL (padrao: remote origin), REVISAO (padrao: main),
# KUBESEAL_VERSION, ARGOCD_MANIFEST.
set -euo pipefail

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
cd "$RAIZ"

K="microk8s kubectl"
REG=localhost:32000
ENTREGA=registry   # registry | importacao (definido na etapa imagens)
DADOS=${XDG_CONFIG_HOME:-$HOME/.config}/gitops-lab   # senhas e chaves do laboratorio (fora do Git)
KCFG=$DADOS/kubeconfig
REVISAO=${REVISAO:-main}
KUBESEAL_VERSION=${KUBESEAL_VERSION:-0.27.3}
ARGOCD_MANIFEST=${ARGOCD_MANIFEST:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}

passo() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()    { printf '    \033[32mOK\033[0m %s\n' "$*"; }
aviso() { printf '    \033[33m!!\033[0m %s\n' "$*"; }
falha() { printf '\033[31mERRO:\033[0m %s\n' "$*" >&2; exit 1; }

repo_url() {
  local u=${REPO_URL:-$(git remote get-url origin 2>/dev/null || true)}
  [ -n "$u" ] || falha "defina REPO_URL ou configure o remote origin"
  # git@github.com:dono/repo.git -> https://github.com/dono/repo.git
  if [[ $u == git@*:* ]]; then u="https://${u#git@}"; u="${u/://}"; fi
  printf '%s' "$u"
}

kubeconfig() {
  mkdir -p "$DADOS"; chmod 700 "$DADOS"
  microk8s config > "$KCFG"; chmod 600 "$KCFG"
}

controller_sealed() {
  $K get svc -n kube-system -l app.kubernetes.io/name=sealed-secrets \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

addon() {  # addon <nome>: habilita se estiver desligado
  if microk8s status -a "$1" 2>/dev/null | grep -q enabled; then
    ok "addon $1"
  else
    microk8s enable "$1"; ok "addon $1 habilitado"
  fi
}

# ---------------------------------------------------------------------------
pre_requisitos() {
  passo "Pre-requisitos"
  for b in microk8s docker git openssl curl; do
    command -v "$b" >/dev/null || falha "comando nao encontrado: $b"
  done
  microk8s status --wait-ready >/dev/null
  for a in dns hostpath-storage ingress registry helm3; do addon "$a"; done
  # Addon recem-habilitado: o pod do registry leva alguns segundos para subir
  $K -n container-registry rollout status deploy/registry --timeout=180s >/dev/null
  ok "registry respondendo em $REG"
  kubeconfig

  if ! command -v kubeseal >/dev/null; then
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
      | tar xz -C "$HOME/.local/bin" kubeseal
    export PATH="$HOME/.local/bin:$PATH"
    ok "kubeseal ${KUBESEAL_VERSION} instalado em ~/.local/bin"
  else
    ok "kubeseal $(kubeseal --version 2>&1 | head -1)"
  fi

  if [ -z "$(controller_sealed)" ]; then
    microk8s helm3 repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null
    microk8s helm3 repo update >/dev/null
    microk8s helm3 install sealed-secrets sealed-secrets/sealed-secrets -n kube-system --wait
    ok "Sealed Secrets instalado"
  else
    ok "Sealed Secrets (servico $(controller_sealed))"
  fi

  if ! $K get ns argocd >/dev/null 2>&1; then
    $K create namespace argocd
    $K apply -n argocd --server-side -f "$ARGOCD_MANIFEST"
    $K -n argocd rollout status deploy/argocd-server --timeout=300s
    ok "Argo CD instalado"
  else
    ok "Argo CD (namespace argocd)"
  fi
}

# ---------------------------------------------------------------------------
build() {  # build <imagem> <contexto> [args do docker build...]
  local img=$REG/$1:lab ctx=$2; shift 2
  echo "    build $img"
  docker build -q --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" -t "$img" "$@" "$ctx" >/dev/null
  if [ "$ENTREGA" = registry ]; then
    docker push -q "$img" >/dev/null
  else
    # Sem registry acessivel: importa direto no containerd do MicroK8s. Com a
    # tag "lab" (nao "latest") o Kubernetes usa IfNotPresent e nao tenta baixar.
    docker save "$img" | microk8s ctr image import - >/dev/null
  fi
  ok "$img ($ENTREGA)"
}

imagens() {
  passo "Imagens (build local)"
  ENTREGA=importacao
  local _
  for _ in $(seq 1 10); do
    if curl -fsS "http://$REG/v2/" >/dev/null 2>&1; then ENTREGA=registry; break; fi
    sleep 2
  done
  if [ "$ENTREGA" = registry ]; then
    ok "push para o registry $REG"
  else
    aviso "registry $REG nao responde em localhost (comum no WSL em modo mirrored):"
    aviso "as imagens serao importadas direto no containerd do MicroK8s"
  fi
  local base=$REG/docker-base-images
  build docker-base-images/php   dev/docker-base-images/php
  build docker-base-images/nginx dev/docker-base-images/nginx
  build docker-base-images/redis dev/docker-base-images/redis
  build glpi/php-glpi    dev/glpi -f dev/glpi/docker/php/Dockerfile
  build glpi/nginx-glpi  dev/glpi/docker/nginx --build-arg "BASE_IMAGE=$base/nginx:lab"
  build wordpress/php-wordpress   dev/wordpress/docker/php   --build-arg "BASE_IMAGE=$base/php:lab"
  build wordpress/nginx-wordpress dev/wordpress/docker/nginx --build-arg "BASE_IMAGE=$base/nginx:lab"
  build wordpress/redis-wordpress dev/wordpress/docker/redis --build-arg "BASE_IMAGE=$base/redis:lab"
  # Mesma tag ":lab": pods que ja existem so pegam a imagem nova com restart
  for ns in glpi-lab wp-lab; do
    if $K get ns "$ns" >/dev/null 2>&1; then
      $K -n "$ns" rollout restart deploy >/dev/null 2>&1 || true
      ok "pods de $ns reiniciados com as imagens novas"
    fi
  done
}

# ---------------------------------------------------------------------------
senha() {  # senha <nome>: gera uma vez e reaproveita nas proximas execucoes
  local f=$DADOS/$1
  [ -s "$f" ] || { openssl rand -hex 16 > "$f"; chmod 600 "$f"; }
  cat "$f"
}

banco() {
  passo "Banco do laboratorio (MariaDB em lab-db)"
  mkdir -p "$DADOS"; chmod 700 "$DADOS"
  local root; root=$(senha mariadb-root)
  $K create namespace lab-db --dry-run=client -o yaml | $K apply -f - >/dev/null
  $K -n lab-db create secret generic mariadb-root --from-literal=senha="$root" \
    --dry-run=client -o yaml | $K apply -f - >/dev/null
  $K apply -k laboratorio/mariadb >/dev/null
  $K -n lab-db rollout status deploy/mariadb --timeout=300s
  local sql=""
  for app in glpi wordpress; do
    local s; s=$(senha "db-$app")
    sql+="CREATE DATABASE IF NOT EXISTS \`$app\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sql+="CREATE USER IF NOT EXISTS '$app'@'%' IDENTIFIED BY '$s';"
    sql+="ALTER USER '$app'@'%' IDENTIFIED BY '$s';"
    sql+="GRANT ALL PRIVILEGES ON \`$app\`.* TO '$app'@'%';"
  done
  # GLPI recomenda acesso as timezones
  sql+="GRANT SELECT ON mysql.time_zone_name TO 'glpi'@'%'; FLUSH PRIVILEGES;"
  $K -n lab-db exec deploy/mariadb -- mariadb -uroot -p"$root" -e "$sql"
  ok "bancos glpi e wordpress, usuarios com acesso so ao proprio banco"
}

# ---------------------------------------------------------------------------
selar() {  # selar <namespace> <nome> <args do kubectl create secret generic...>
  local ns=$1 nome=$2; shift 2
  local ctrl; ctrl=$(controller_sealed)
  [ -n "$ctrl" ] || falha "controller do Sealed Secrets nao encontrado (rode pre-requisitos)"
  $K -n "$ns" create secret generic "$nome" "$@" --dry-run=client -o yaml \
    | kubeseal --kubeconfig "$KCFG" --controller-name "$ctrl" --controller-namespace kube-system --format yaml \
    | $K apply -f - >/dev/null
  ok "SealedSecret $ns/$nome"
}

segredos() {
  passo "Segredos (selados com a chave do Sealed Secrets deste cluster)"
  command -v kubeseal >/dev/null || export PATH="$HOME/.local/bin:$PATH"
  kubeconfig
  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  local db_host=mariadb.lab-db.svc.cluster.local
  for ns in glpi-lab wp-lab; do
    $K create namespace "$ns" --dry-run=client -o yaml | $K apply -f - >/dev/null
  done

  # GLPI: a glpicrypt.key e as chaves OAuth sao geradas uma vez e reaproveitadas
  [ -s "$DADOS/glpicrypt.key" ] || { openssl rand 32 > "$DADOS/glpicrypt.key"; chmod 600 "$DADOS/glpicrypt.key"; }
  if [ ! -s "$DADOS/oauth.pem" ]; then
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$DADOS/oauth.pem" 2>/dev/null
    openssl pkey -in "$DADOS/oauth.pem" -pubout -out "$DADOS/oauth.pub"
    chmod 600 "$DADOS/oauth.pem"
  fi
  local s_glpi; s_glpi=$(senha db-glpi)
  cat > "$tmp/config_db.php" <<EOF
<?php
class DB extends DBmysql {
   public \$dbhost     = '$db_host';
   public \$dbuser     = 'glpi';
   public \$dbpassword = '$s_glpi';
   public \$dbdefault  = 'glpi';
   public \$use_utf8mb4 = true;
   public \$allow_myisam = false;
   public \$allow_datetime = false;
   public \$allow_signed_keys = false;
}
EOF
  selar glpi-lab glpi-config --from-file=config_db.php="$tmp/config_db.php"
  selar glpi-lab glpi-key    --from-file=glpicrypt.key="$DADOS/glpicrypt.key"
  selar glpi-lab glpi-oauth  --from-file=oauth.pem="$DADOS/oauth.pem" --from-file=oauth.pub="$DADOS/oauth.pub"
  selar glpi-lab glpi-lab-db --from-literal=DB_HOST="$db_host" --from-literal=DB_NAME=glpi \
    --from-literal=DB_USER=glpi --from-literal=DB_PASSWORD="$s_glpi"
  selar wp-lab wp-lab-db --from-literal=DB_HOST="$db_host" --from-literal=DB_NAME=wordpress \
    --from-literal=DB_USER=wordpress --from-literal=DB_PASSWORD="$(senha db-wordpress)"

  # Confere se o controller abriu os selos (Secrets criados)
  sleep 3
  for s in glpi-lab/glpi-config glpi-lab/glpi-key glpi-lab/glpi-oauth glpi-lab/glpi-lab-db wp-lab/wp-lab-db; do
    $K -n "${s%/*}" get secret "${s#*/}" >/dev/null 2>&1 && ok "Secret $s aberto pelo controller" \
      || aviso "Secret $s ainda nao existe (veja: $K -n ${s%/*} describe sealedsecret ${s#*/})"
  done
}

# ---------------------------------------------------------------------------
aguardar() {  # aguardar <namespace> <job>: espera o Job de instalacao terminar
  if $K -n "$1" wait --for=condition=complete "job/$2" --timeout=600s >/dev/null 2>&1; then
    ok "job $1/$2 concluido"
  else
    aviso "job $1/$2 nao concluiu; ultimas linhas do log:"
    $K -n "$1" logs "job/$2" --all-containers --tail=30 2>&1 | sed 's/^/      /' || true
  fi
}

aplicar() {
  passo "Aplicando os overlays da pasta local (sem Argo CD)"
  if $K -n argocd get application lab-glpi lab-wordpress >/dev/null 2>&1; then
    aviso "existem Applications lab-* no Argo CD: elas vao desfazer esta aplicacao local (rode 'remover' antes)"
  fi
  for app in glpi wordpress; do
    local ns job
    if [ $app = glpi ]; then ns=glpi-lab; job=glpi-lab-instalar; else ns=wp-lab; job=wp-lab-instalar; fi
    # Job e imutavel: recria a cada aplicacao (os scripts de instalacao sao idempotentes)
    $K -n "$ns" delete job "$job" --ignore-not-found >/dev/null
    $K apply -k "laboratorio/$app" >/dev/null
    ok "laboratorio/$app aplicado em $ns"
  done
  # Sem Argo CD nao ha sync-wave: os Deployments sobem junto com os Jobs e
  # ficam "nao prontos" ate a instalacao terminar.
  aguardar glpi-lab glpi-lab-instalar
  aguardar wp-lab wp-lab-instalar
  for ns in glpi-lab wp-lab; do
    $K -n "$ns" rollout status deploy --timeout=300s >/dev/null 2>&1 \
      && ok "deployments de $ns prontos" || aviso "deployments de $ns ainda nao prontos (veja: $K -n $ns get pods)"
  done
}

# ---------------------------------------------------------------------------
argocd() {
  passo "Argo CD lendo laboratorio/ de $(repo_url) ($REVISAO)"
  if git fetch -q origin "$REVISAO" 2>/dev/null; then
    git diff --quiet "origin/$REVISAO" -- laboratorio infra \
      || aviso "laboratorio/ ou infra/ tem mudancas locais que nao estao no origin/$REVISAO: o Argo CD le o que esta no Git (faca commit e push)"
  fi
  local url; url=$(repo_url)
  for app in glpi wordpress; do
    local ns; ns=$([ $app = glpi ] && echo glpi-lab || echo wp-lab)
    $K apply -f - >/dev/null <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: lab-$app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $url
    targetRevision: $REVISAO
    path: laboratorio/$app
  destination:
    server: https://kubernetes.default.svc
    namespace: $ns
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    ok "Application lab-$app"
  done
  echo "    aguardando a sincronizacao (ate 10 min; o primeiro pull das imagens demora)..."
  local fim=$((SECONDS + 600))
  while [ $SECONDS -lt $fim ]; do
    local g w
    g=$($K -n argocd get application lab-glpi -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    w=$($K -n argocd get application lab-wordpress -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    printf '\r    lab-glpi: %-22s lab-wordpress: %-22s' "$g" "$w"
    [ "$g" = "Synced/Healthy" ] && [ "$w" = "Synced/Healthy" ] && { echo; ok "as duas Applications estao Synced/Healthy"; return 0; }
    sleep 10
  done
  echo; aviso "tempo esgotado: confira na interface do Argo CD ou com a etapa testar"
}

# ---------------------------------------------------------------------------
testar() {
  passo "Teste"
  $K -n argocd get applications lab-glpi lab-wordpress 2>/dev/null \
    || echo "    (sem Applications lab-* no Argo CD: normal se o laboratorio foi aplicado com a etapa aplicar)"
  for ns in glpi-lab wp-lab; do echo; $K -n "$ns" get pods 2>/dev/null || true; done
  echo
  local ip; ip=$(hostname -I | awk '{print $1}')
  for h in glpi.lab.localhost site.lab.localhost; do
    local c; c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$h:80:$ip" "http://$h/" || true)
    case "$c" in
      200|301|302) ok "http://$h -> HTTP $c" ;;
      *) aviso "http://$h -> HTTP ${c:-sem resposta}" ;;
    esac
  done
  cat <<EOF

    Navegador (com a etapa "tunel" rodando em outro terminal):
               https://glpi.lab.localhost (aceite o certificado; usuario glpi / senha glpi)
               http://site.lab.localhost  (conclui a instalacao do WordPress)
    Argo CD:   $K -n argocd port-forward svc/argocd-server 8443:443
               https://localhost:8443  usuario admin, senha:
               $K -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
EOF
}

tunel() {
  passo "Tunel do ingress para o navegador do Windows"
  # O ingress do MicroK8s recebe nas portas 80/443 por hostPort (iptables).
  # No WSL em modo mirrored, so portas com um processo escutando chegam ao
  # localhost do Windows; o port-forward cria esse processo. Portas abaixo de
  # 1024 exigem sudo.
  local ds
  ds=$($K -n ingress get daemonset -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  [ -n "$ds" ] || falha "ingress controller nao encontrado no namespace ingress (addon ingress habilitado?)"
  echo "    Abra no navegador do Windows:"
  echo "      https://glpi.lab.localhost   (certificado autoassinado do ingress: aceite o aviso)"
  echo "      http://site.lab.localhost"
  echo "    Ctrl+C fecha o tunel."
  echo
  sudo microk8s kubectl -n ingress port-forward --address 127.0.0.1 "daemonset/$ds" 80:80 443:443
}

remover() {
  passo "Removendo o laboratorio"
  $K -n argocd delete application lab-glpi lab-wordpress --ignore-not-found
  $K delete namespace glpi-lab wp-lab lab-db --ignore-not-found
  ok "removido (Argo CD, Sealed Secrets e as chaves em $DADOS foram mantidos)"
}

case "${1:-}" in
  pre-requisitos) pre_requisitos ;;
  imagens)        imagens ;;
  banco)          banco ;;
  segredos)       segredos ;;
  argocd)         argocd ;;
  testar)         testar ;;
  tunel)          tunel ;;
  aplicar)        aplicar ;;
  tudo)           pre_requisitos; imagens; banco; segredos; argocd; testar ;;
  tudo-local)     pre_requisitos; imagens; banco; segredos; aplicar; testar ;;
  remover)        remover ;;
  *) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 1 ;;
esac
