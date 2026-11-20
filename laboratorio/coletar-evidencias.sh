#!/usr/bin/env bash
# Coleta evidencias da validacao do modelo GitOps no laboratorio: estado das
# Applications do Argo CD, recursos implantados, segredos selados, resposta
# HTTP e testes de drift cronometrados (alteracao manual -> correcao pelo
# Argo CD). Gera um relatorio em Markdown e os arquivos brutos (YAML).
#
# Pre-requisito: laboratorio aplicado pela etapa "argocd" do laboratorio.sh
# (Applications lab-glpi e lab-wordpress com sync automatico e self-heal).
#
# Uso: laboratorio/coletar-evidencias.sh [--sem-drift] [diretorio-de-saida]
#   padrao: ~/evidencias-gitops-lab/<data-hora>
set -euo pipefail

K="microk8s kubectl"
DRIFT=1
if [ "${1:-}" = "--sem-drift" ]; then DRIFT=0; shift; fi
DEST=${1:-$HOME/evidencias-gitops-lab/$(date +%Y-%m-%d_%H%M%S)}
TIMEOUT=${TIMEOUT:-300}
APPS=(lab-glpi lab-wordpress)

mkdir -p "$DEST"/{argocd,recursos,drift}
REL=$DEST/relatorio.md
log() { printf '%s\n' "$*" | tee -a "$REL" >/dev/null; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

agora() { date +%s.%N; }
dif() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

for app in "${APPS[@]}"; do
  $K -n argocd get application "$app" >/dev/null 2>&1 \
    || { echo "Application $app nao encontrada: rode 'laboratorio/laboratorio.sh argocd' antes." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
info "Ambiente"
k8s=$($K version -o json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])' 2>/dev/null || echo "?")
argo=$($K -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}')
ss=$($K -n kube-system get deploy -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null || echo "?")
cat > "$REL" <<EOF
# Evidências da validação do modelo GitOps (laboratório)

- Data da coleta: $(date '+%d/%m/%Y %H:%M:%S %Z')
- Kubernetes: MicroK8s $(microk8s version 2>/dev/null | awk '{print $2}') (API $k8s)
- Argo CD: \`$argo\`
- Sealed Secrets: \`$ss\`
- Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "?")
- Commit local do repositório: \`$(git -C "$(dirname "$0")/.." rev-parse --short HEAD 2>/dev/null || echo "?")\`

## 1. Applications do Argo CD

| Application | Repositório / caminho | Revisão sincronizada | Sync | Saúde | Política |
|---|---|---|---|---|---|
EOF
for app in "${APPS[@]}"; do
  $K -n argocd get application "$app" -o yaml > "$DEST/argocd/$app.yaml"
  $K -n argocd get application "$app" -o jsonpath='{range .status.resources[*]}{.kind}{"\t"}{.namespace}{"\t"}{.name}{"\t"}{.status}{"\t"}{.health.status}{"\n"}{end}' \
    > "$DEST/argocd/$app-recursos.tsv"
  $K -n argocd get application "$app" -o jsonpath='{range .status.history[*]}{.id}{"\t"}{.revision}{"\t"}{.deployedAt}{"\n"}{end}' \
    > "$DEST/argocd/$app-historico.tsv"
  linha=$($K -n argocd get application "$app" -o jsonpath='{.spec.source.repoURL} `{.spec.source.path}`|`{.status.sync.revision}`|{.status.sync.status}|{.status.health.status}|automated: prune={.spec.syncPolicy.automated.prune}, selfHeal={.spec.syncPolicy.automated.selfHeal}')
  log "| $app | $linha |"
done

log ""
log "### Recursos gerenciados"
for app in "${APPS[@]}"; do
  log ""
  log "**$app**"
  log ""
  log "| Tipo | Namespace | Nome | Sync | Saúde |"
  log "|---|---|---|---|---|"
  while IFS=$'\t' read -r kind ns name st he; do
    log "| $kind | ${ns:--} | $name | $st | ${he:--} |"
  done < "$DEST/argocd/$app-recursos.tsv"
done

# ---------------------------------------------------------------------------
info "Recursos, imagens e segredos"
log ""
log "## 2. Recursos em execução"
for ns in glpi-lab wp-lab; do
  $K -n "$ns" get all,pvc,ingress,networkpolicy,configmap -o wide > "$DEST/recursos/$ns.txt" 2>&1 || true
  $K -n "$ns" get sealedsecrets -o yaml > "$DEST/recursos/$ns-sealedsecrets.yaml" 2>&1 || true
  log ""
  log "**Pods em $ns** (imagem e digest em execução)"
  log ""
  log "| Contêiner | Imagem | Digest |"
  log "|---|---|---|"
  $K -n "$ns" get pods --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.name}{"|"}{.image}{"|"}{.imageID}{"\n"}{end}{end}' 2>/dev/null \
    | while IFS='|' read -r cont img id; do
        log "| $cont | \`$img\` | \`${id##*@}\` |"
      done
done
# lista de pods com reinicios, para os arquivos brutos
for ns in glpi-lab wp-lab; do
  $K -n "$ns" get pods -o custom-columns='POD:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount,NO:.spec.nodeName' \
    >> "$DEST/recursos/pods.txt" 2>&1 || true
done

log ""
log "## 3. Segredos selados"
log ""
log "Os segredos estão no cluster apenas como \`SealedSecret\` (cifrados com a chave pública do controller); o controller os abriu como \`Secret\`:"
log ""
log "| Namespace | SealedSecret | Condição | Secret criado |"
log "|---|---|---|---|"
for ns in glpi-lab wp-lab; do
  $K -n "$ns" get sealedsecrets -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[0].type}={.status.conditions[0].status}{"\n"}{end}' 2>/dev/null \
    | while IFS=$'\t' read -r nome cond; do
        if $K -n "$ns" get secret "$nome" >/dev/null 2>&1; then s=sim; else s=não; fi
        log "| $ns | $nome | $cond | $s |"
      done
done

log ""
log "## 4. Resposta HTTP pelo ingress"
log ""
log "| Endereço | HTTP | Tempo (s) |"
log "|---|---|---|"
ip=$(hostname -I | awk '{print $1}')
for u in "http://glpi.lab.localhost/" "https://glpi.lab.localhost/" "http://site.lab.localhost/"; do
  h=${u#*://}; h=${h%%/*}; porta=80; [[ $u == https* ]] && porta=443
  r=$(curl -sk -o /dev/null -w '%{http_code} %{time_total}' --max-time 15 --resolve "$h:$porta:$ip" "$u" || echo "000 -")
  log "| $u | ${r% *} | ${r#* } |"
done

# ---------------------------------------------------------------------------
# Teste de drift: faz uma alteracao manual (fora do Git) e cronometra ate o
# Argo CD devolver o recurso ao estado declarado.
esperar() {  # esperar <condicao-shell>: retorna 0 quando a condicao vale
  local fim=$((SECONDS + TIMEOUT))
  while [ $SECONDS -lt $fim ]; do
    if eval "$1" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

drift() {  # drift <id> <descricao> <comando-de-alteracao> <condicao-de-restauracao> [condicao-de-servico]
  local id=$1 desc=$2 acao=$3 restaurado=$4 servico=${5:-}
  info "Drift: $desc"
  $K -n argocd get application lab-glpi lab-wordpress -o wide > "$DEST/drift/$id-antes.txt" 2>&1 || true
  local t0 t1 t2 r1="não restaurado em ${TIMEOUT}s" r2="-"
  t0=$(agora)
  eval "$acao" > "$DEST/drift/$id-acao.txt" 2>&1
  if esperar "$restaurado"; then t1=$(agora); r1="$(dif "$t0" "$t1") s"; fi
  if [ -n "$servico" ]; then
    if esperar "$servico"; then t2=$(agora); r2="$(dif "$t0" "$t2") s"; else r2="não pronto em ${TIMEOUT}s"; fi
  fi
  $K -n argocd get application lab-glpi lab-wordpress -o wide > "$DEST/drift/$id-depois.txt" 2>&1 || true
  log "| $id | $desc | $r1 | $r2 |"
  echo "    restaurado: $r1   servico pronto: $r2"
}

if [ "$DRIFT" -eq 1 ]; then
  log ""
  log "## 5. Testes de drift (alteração manual fora do Git)"
  log ""
  log "Cada teste altera o cluster diretamente com \`kubectl\`, sem passar pelo Git, e mede o tempo até o Argo CD (sync automático com *self-heal* e *prune*) devolver o recurso ao estado declarado no repositório."
  log ""
  log "| Teste | Alteração manual | Estado declarado restaurado | Serviço pronto |"
  log "|---|---|---|---|"

  drift D1 "Deployment glpi escalado para 0 réplicas" \
    "$K -n glpi-lab scale deploy glpi --replicas=0" \
    "[ \"\$($K -n glpi-lab get deploy glpi -o jsonpath='{.spec.replicas}')\" = 1 ]" \
    "[ \"\$($K -n glpi-lab get deploy glpi -o jsonpath='{.status.readyReplicas}')\" = 1 ]"

  drift D2 "ConfigMap glpi-php-config alterado (php-custom.ini trocado)" \
    "$K -n glpi-lab patch configmap glpi-php-config --type merge -p '{\"data\":{\"php-custom.ini\":\"memory_limit = 64M\"}}'" \
    "$K -n glpi-lab get configmap glpi-php-config -o jsonpath='{.data.php-custom\\.ini}' | grep -q 'memory_limit = 4G'"

  drift D3 "Service glpi apagado" \
    "$K -n glpi-lab delete service glpi" \
    "$K -n glpi-lab get service glpi" \
    "curl -sk -o /dev/null -w '%{http_code}' --max-time 5 --resolve glpi.lab.localhost:443:$ip https://glpi.lab.localhost/ | grep -qE '^(200|302)$'"

  drift D4 "Ingress do WordPress apagado" \
    "$K -n wp-lab delete ingress wordpress" \
    "$K -n wp-lab get ingress wordpress" \
    "curl -s -o /dev/null -w '%{http_code}' --max-time 5 --resolve site.lab.localhost:80:$ip http://site.lab.localhost/ | grep -qE '^(200|302)$'"

  drift D5 "NetworkPolicy do Redis do WordPress apagada" \
    "$K -n wp-lab delete networkpolicy redis" \
    "$K -n wp-lab get networkpolicy redis"

  for app in "${APPS[@]}"; do
    $K -n argocd get application "$app" -o yaml > "$DEST/argocd/$app-pos-drift.yaml"
  done
fi

log ""
log "## Arquivos brutos"
log ""
log "- \`argocd/\`: Applications (YAML), recursos gerenciados e histórico de sincronização"
log "- \`recursos/\`: recursos em execução, pods e SealedSecrets por namespace"
[ "$DRIFT" -eq 1 ] && log "- \`drift/\`: estado das Applications antes/depois de cada teste e saída da alteração manual"

info "Relatorio: $REL"
echo "    Para o Windows: explorer.exe \"\$(wslpath -w '$DEST')\""
