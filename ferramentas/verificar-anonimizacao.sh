#!/usr/bin/env bash
# Procura dados institucionais que nao deveriam estar num template publico.
#
# Verificacoes padrao:
#   - dominios .br que nao sejam exemplo.edu.br (ou o oficial br.wordpress.org);
#   - e-mails fora de @exemplo.edu.br;
#   - enderecos IPv4 privados especificos (os de documentacao e as faixas
#     genericas de exemplo sao permitidos).
# Termos proprios da sua instituicao (nomes, siglas) entram por variavel,
# para nao precisarem ficar escritos no repositorio:
#   ANON_PATTERNS='sigla1|sigla2|dominio-interno' ferramentas/verificar-anonimizacao.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ARQS=$(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
ARQS=$(printf '%s\n' "$ARQS" | grep -v -E '^(\./)?(LICENSE|ferramentas/verificar-anonimizacao\.sh)$')
falhas=0

checa() {  # checa <descricao> <regex-PCRE> [regex-de-excecao]
  local desc=$1 re=$2 exc=${3:-}
  local out
  out=$(printf '%s\n' "$ARQS" | xargs -d '\n' grep -n -o -i -P "$re" 2>/dev/null || true)
  [ -n "$exc" ] && out=$(printf '%s\n' "$out" | grep -v -i -P "$exc" || true)
  out=$(printf '%s\n' "$out" | sed '/^$/d')
  if [ -n "$out" ]; then
    echo "!! $desc:"; printf '%s\n' "$out" | sed 's/^/   /'; falhas=1
  fi
}

checa "dominio .br fora do exemplo" '\b[a-z0-9-]+(\.[a-z0-9-]+)*\.br\b' ':(exemplo\.edu\.br|[a-z0-9.-]*\.exemplo\.edu\.br|br\.wordpress\.org)$'
checa "e-mail fora do exemplo" '\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b' '@exemplo\.edu\.br$'
checa "IPv4 privado especifico" '\b(10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+)\b' ':(10\.0\.0\.0|10\.244\.0\.0|172\.16\.0\.0|192\.168\.0\.0)$'
if [ -n "${ANON_PATTERNS:-}" ]; then
  checa "termo institucional (ANON_PATTERNS)" "$ANON_PATTERNS"
fi

if [ "$falhas" -eq 0 ]; then echo "OK: nenhum dado institucional encontrado."; fi
exit "$falhas"
