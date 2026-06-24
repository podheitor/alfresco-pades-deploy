#!/usr/bin/env bash
# =============================================================================
#  11 - Validacao pos-deploy (testes de aceitacao tecnica)
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"

PASS=0; FAIL=0
ok()   { echo -e "  \033[1;32m[OK]\033[0m   $*"; PASS=$((PASS+1)); }
nok()  { echo -e "  \033[1;31m[FALHA]\033[0m $*"; FAIL=$((FAIL+1)); }

log "== Servicos systemd =="
for svc in postgresql alfresco-activemq alfresco-transform alfresco-search alfresco-tomcat; do
  systemctl is-active --quiet "$svc" && ok "servico $svc ativo" || nok "servico $svc inativo"
done
[ "${USE_NGINX_TLS}" = "true" ] && { systemctl is-active --quiet nginx && ok "nginx ativo" || nok "nginx inativo"; }

log "== Portas em escuta =="
for p in 5432 61616 8090 8983 8080; do
  ss -ltn | grep -q ":$p" && ok "porta $p escutando" || nok "porta $p sem escuta"
done

log "== Banco de dados =="
PGPASSWORD="${DB_PASS}" psql -h 127.0.0.1 -U "${DB_USER}" -d "${DB_NAME}" -tAc \
  "SELECT count(*) FROM information_schema.tables;" >/dev/null 2>&1 \
  && ok "conexao/schema PostgreSQL" || nok "conexao PostgreSQL"

log "== Transform Service =="
curl -fs "http://localhost:8090/ready" >/dev/null 2>&1 && ok "transform /ready" || nok "transform /ready"

log "== Repositorio Alfresco (readiness probe) =="
curl -fs "http://localhost:8080/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-" \
  >/dev/null 2>&1 && ok "repo readiness probe" || nok "repo readiness probe (pode ainda estar iniciando)"

log "== Share (interface web) =="
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/share/" || echo 000)
[ "$code" = "200" ] || [ "$code" = "302" ] && ok "Share responde (HTTP $code)" || nok "Share HTTP $code"

log "== Solr (indexacao) =="
# Comunicacao por secret: o endpoint exige o cabecalho X-Alfresco-Search-Secret.
SOLR_SECRET="${SOLR_SHARED_SECRET:-}"
if curl -fs -H "X-Alfresco-Search-Secret: ${SOLR_SECRET}" \
     "http://localhost:8983/solr/admin/cores?action=STATUS" >/dev/null 2>&1; then
  ok "Solr admin acessivel (cores)"
else
  nok "Solr admin"
fi

log "== Assinatura PAdES (microsservico) =="
# A assinatura e feita por um microsservico externo (porta 8092), NAO por AMP no war.
if curl -fs http://localhost:8092/health >/dev/null 2>&1; then
  ok "microsservico de assinatura ativo (porta 8092)"
else
  nok "microsservico de assinatura (8092) inativo - veja alfresco-signer-service/"
fi

echo ""
log "Resultado: ${PASS} OK / ${FAIL} FALHA(S)."
[ "${FAIL}" -eq 0 ] && log "Ambiente validado. Pronto para os testes de aceitacao com usuarios-chave." \
  || warn "Existem itens com falha - revise os logs antes do go-live."
