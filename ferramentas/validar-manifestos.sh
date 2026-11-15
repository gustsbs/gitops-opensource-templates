#!/usr/bin/env bash
# Renderiza todos os overlays com kustomize e valida o resultado com
# kubeconform (CRDs como SealedSecret sao ignorados por falta de schema).
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for k in $(find infra -name kustomization.yaml -path '*/overlays/*' | sort); do
  dir=$(dirname "$k")
  if kustomize build "$dir" | kubeconform -strict -summary -ignore-missing-schemas \
       -output text - > /tmp/kubeconform.out 2>&1; then
    echo "OK   $dir  $(tail -1 /tmp/kubeconform.out)"
  else
    echo "ERRO $dir"; cat /tmp/kubeconform.out; status=1
  fi
done
exit $status
