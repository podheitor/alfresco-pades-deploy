#!/usr/bin/env bash
# =============================================================================
#  10 - Politica de backup, rotacao de logs e monitoramento basico
#  Atende ao item "Politica de backup, rotacao de logs e monitoramento basico".
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

# ---------------------------------------------------------------------------
# 1) Script de backup (banco + content store + configs)
# ---------------------------------------------------------------------------
log "Instalando script de backup em /usr/local/bin/alfresco-backup.sh..."
cat > /usr/local/bin/alfresco-backup.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "${DIR}/00-variaveis.sh"
STAMP=\$(date +%Y%m%d-%H%M%S)
DEST="${ALF_BACKUP}/\${STAMP}"
mkdir -p "\${DEST}"

# 1. Dump do PostgreSQL
PGPASSWORD="${DB_PASS}" pg_dump -h 127.0.0.1 -U "${DB_USER}" -Fc "${DB_NAME}" \
  > "\${DEST}/${DB_NAME}.dump"

# 2. Content store (alf_data) - rsync incremental
rsync -a --delete "${ALF_DATA}/" "\${DEST}/alf_data/"

# 3. Configuracoes criticas e keystore
cp -a "${ALF_TOMCAT}/shared/classes/alfresco-global.properties" "\${DEST}/" 2>/dev/null || true
cp -a "${ALF_KEYSTORE}" "\${DEST}/keystore" 2>/dev/null || true

# 4. Retencao: manter ultimos 7 backups
ls -1dt ${ALF_BACKUP}/*/ 2>/dev/null | tail -n +8 | xargs -r rm -rf

echo "Backup concluido em \${DEST}"
EOF
chmod +x /usr/local/bin/alfresco-backup.sh

log "Agendando backup diario as 02:00 (cron)..."
cat > /etc/cron.d/alfresco-backup <<EOF
0 2 * * * root /usr/local/bin/alfresco-backup.sh >> ${ALF_LOGS}/backup.log 2>&1
EOF

# ---------------------------------------------------------------------------
# 2) Rotacao de logs
# ---------------------------------------------------------------------------
log "Configurando logrotate..."
cat > /etc/logrotate.d/alfresco <<EOF
${ALF_TOMCAT}/logs/catalina.out
${ALF_TOMCAT}/logs/alfresco.log
${ALF_TOMCAT}/logs/share.log
${ALF_SOLR}/logs/solr.log
${ALF_LOGS}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su ${ALF_USER} ${ALF_GROUP}
}
EOF

# ---------------------------------------------------------------------------
# 3) Monitoramento basico (health check + alerta por log)
# ---------------------------------------------------------------------------
log "Instalando health check basico..."
cat > /usr/local/bin/alfresco-healthcheck.sh <<EOF
#!/usr/bin/env bash
# Verifica servicos essenciais e registra em ${ALF_LOGS}/health.log
LOG="${ALF_LOGS}/health.log"
ts() { date '+%Y-%m-%d %H:%M:%S'; }
check() {
  if systemctl is-active --quiet "\$1"; then
    echo "\$(ts) OK    \$1" >> "\$LOG"
  else
    echo "\$(ts) FALHA \$1 - tentando reiniciar" >> "\$LOG"
    systemctl restart "\$1"
  fi
}
for svc in postgresql alfresco-activemq alfresco-transform alfresco-search alfresco-tomcat; do
  check "\$svc"
done
# Endpoint de aplicacao
curl -fsk "http://localhost:8080/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-" \
  >/dev/null 2>&1 \
  && echo "\$(ts) OK    repo-readiness-probe" >> "\$LOG" \
  || echo "\$(ts) FALHA repo-readiness-probe" >> "\$LOG"
EOF
chmod +x /usr/local/bin/alfresco-healthcheck.sh

cat > /etc/cron.d/alfresco-healthcheck <<EOF
*/5 * * * * root /usr/local/bin/alfresco-healthcheck.sh
EOF

log "10 - Backup, logrotate e monitoramento configurados."
log "    Backup manual:    /usr/local/bin/alfresco-backup.sh"
log "    Health check:     /usr/local/bin/alfresco-healthcheck.sh"
