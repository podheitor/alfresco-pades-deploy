#!/usr/bin/env bash
# =============================================================================
#  install-all.sh - Orquestrador do deploy Alfresco + Assinatura Digital (Cliente)
#  Executa os modulos na ordem correta de dependencia.
#  Uso:  sudo ./install-all.sh
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root
confirm_secrets

STEPS=(
  "01-preparacao-sistema.sh"
  "02-java17.sh"
  "03-postgresql.sh"
  "04-activemq.sh"
  "05-transform-service.sh"
  "07-search-services-solr.sh"   # Solr antes do Tomcat
  "06-alfresco-repo-share.sh"
  "08-assinatura-digital-pades.sh"
  "09-nginx-tls.sh"
  "10-backup-logrotate-monitor.sh"
  "11-validacao.sh"
)

log "Iniciando deploy completo da plataforma Cliente (Proposta )."
for step in "${STEPS[@]}"; do
  log ">>> Executando ${step}"
  bash "${DIR}/${step}" || die "Falha em ${step}. Corrija e reexecute a partir deste passo."
done

log "============================================================"
log " DEPLOY CONCLUIDO."
log " Acesso Share : https://${ALF_HOSTNAME}/share/  (ou http://IP:8080/share/)"
log " Usuario      : admin"
log " Proximos     : survey de assinatura (08) + modelagem dos 3 workflows BPMN."
log "============================================================"
