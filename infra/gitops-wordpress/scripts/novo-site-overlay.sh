#!/usr/bin/env bash
# Gera overlays/<slug>-prod no repositorio gitops-wordpress (rodar na raiz do repositorio).
#
# Uso: novo-site-overlay.sh <slug> <dominio> <servidor-nfs> [caminho-nfs] [--sem-www]
#   ex.: novo-site-overlay.sh site-exemplo site-exemplo.exemplo.edu.br 192.0.2.10
#        (caminho padrao: /exports/wordpress/<slug>)
set -euo pipefail
 
SLUG=${1:?uso: $0 <slug> <dominio> <servidor-nfs> [caminho-nfs] [--sem-www]}
DOMINIO=${2:?uso: $0 <slug> <dominio> <servidor-nfs> [caminho-nfs] [--sem-www]}
NFS_SERVER=${3:?uso: $0 <slug> <dominio> <servidor-nfs> [caminho-nfs] [--sem-www]}
NFS_PATH=/exports/wordpress/$SLUG
WWW=1
for a in "${@:4}"; do
  case "$a" in
    --sem-www) WWW=0 ;;
    /*) NFS_PATH=$a ;;
    *) echo "argumento desconhecido: $a"; exit 1 ;;
  esac
done
NS=$SLUG-prod
DIR=overlays/$NS
TAMANHO=${TAMANHO:-20Gi}
 
[ -d base ] || { echo "rode na raiz do gitops-wordpress (pasta base/ nao encontrada)"; exit 1; }
[ ! -e "$DIR" ] || { echo "$DIR ja existe - nada foi alterado"; exit 1; }
mkdir -p "$DIR"
 
cat > "$DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
 
# $DOMINIO - codigo, wp-config.php e uploads no NFS do site, atualizados pelo
# wp-admin; imagens e tags vem da base.
namespace: $NS
 
resources:
  - ../../base
  - pv-html.yaml
  - pvc-html.yaml
  - ingress.yaml
 
patches:
  - path: patch-deployment.yaml
EOF
 
cat > "$DIR/pv-html.yaml" <<EOF
# Arquivos com dono 33:33 e ACL de leitura para o nginx (uid 101).
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $NS-html-pv
  labels:
    app.kubernetes.io/name: wordpress
    app.kubernetes.io/part-of: wordpress
spec:
  capacity:
    storage: $TAMANHO
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  nfs:
    server: $NFS_SERVER
    path: $NFS_PATH
  claimRef:
    namespace: $NS
    name: $SLUG-html
EOF
 
cat > "$DIR/pvc-html.yaml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $SLUG-html
  labels:
    app.kubernetes.io/name: wordpress
    app.kubernetes.io/part-of: wordpress
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  volumeName: $NS-html-pv
  resources:
    requests:
      storage: $TAMANHO
EOF
 
cat > "$DIR/patch-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  replicas: 1
  template:
    spec:
      volumes:
        - name: wp-html
          persistentVolumeClaim:
            claimName: $SLUG-html
EOF
 
regra() {
cat <<EOF
    - host: $1
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: wordpress
                port:
                  name: http
EOF
}
{
cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wordpress
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: 250m
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/send-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
EOF
regra "$DOMINIO"
[ "$WWW" -eq 1 ] && regra "www.$DOMINIO"
} > "$DIR/ingress.yaml"
 
echo ">> $DIR criado"
if command -v kubectl >/dev/null; then
  kubectl kustomize "$DIR" | grep -E '^kind:|image:|server:|path: /exports|host:' || true
fi
echo
echo "Proximo passo:"
echo "  git add $DIR && git commit -m \"feat($NS): adicionar o site $DOMINIO no modelo GitOps\""
