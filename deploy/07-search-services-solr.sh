#!/usr/bin/env bash
# =============================================================================
#  07 - Alfresco Search Services (Solr 6) - indexacao e busca textual
#  Observacao: rode ANTES de subir o Tomcat em producao, ou reinicie o Tomcat
#  apos o Solr estar ativo. O orquestrador (install-all.sh) trata a ordem.
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root
confirm_secrets

# IMPORTANTE: Search Services 2.0.13 (com ACS 23.2) tem classes compiladas para
# JAVA 17 (Spring 6). Roda em Java 17, NAO em Java 11 (java 11 da
# UnsupportedClassVersionError 61.0 > 55.0). Mas o solr.in.sh padrao do Solr 6
# usa flags de GC antigas (CMS) que o Java 17 rejeita -> forcamos G1GC.
SOLR_JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
log "Java do Solr: ${SOLR_JAVA_HOME}"

log "Baixando Alfresco Search Services ${SEARCH_VERSION}..."
cd "${STAGE}"
wget -q --show-progress -O search-services.zip "${SEARCH_URL}" \
  || die "Falha no download do Search Services. Confira SEARCH_URL."

log "Extraindo em ${ALF_SOLR}..."
rm -rf "${STAGE}/search-dist"
unzip -q search-services.zip -d "${STAGE}/search-dist"
SS_DIR="$(find "${STAGE}/search-dist" -maxdepth 2 -type d -name 'alfresco-search-services' | head -n1)"
[ -n "${SS_DIR}" ] || die "Diretorio alfresco-search-services nao encontrado."
rm -rf "${ALF_SOLR:?}"/*
cp -a "${SS_DIR}/." "${ALF_SOLR}/"

log "Configurando comunicacao por secret (repo <-> solr)..."
SOLR_IN_SH="${ALF_SOLR}/solr/bin/solr.in.sh"
{
  echo ""
  echo "# --- Ajustes Cliente ---"
  echo "SOLR_SOLR_HOST=localhost"
  echo "SOLR_SOLR_PORT=8983"
  echo "SOLR_ALFRESCO_HOST=localhost"
  echo "SOLR_ALFRESCO_PORT=8080"
  echo "SOLR_HEAP=\"${SOLR_XMX}\""
  echo "ALFRESCO_SECURE_COMMS=secret"
  echo "JAVA_TOOL_OPTIONS=\"-Dalfresco.secureComms.secret=${SOLR_SHARED_SECRET}\""
  echo "SOLR_OPTS=\"\$SOLR_OPTS -Dsolr.sharedSecret=${SOLR_SHARED_SECRET}\""
  # GC compativel com Java 17 (o default do Solr 6 usa CMS, removido no Java 14+)
  echo "GC_TUNE=\"-XX:+UseG1GC\""
} >> "${SOLR_IN_SH}"

chown -R "${ALF_USER}:${ALF_GROUP}" "${ALF_SOLR}"

log "Criando servico systemd do Search Services..."
cat > /etc/systemd/system/alfresco-search.service <<EOF
[Unit]
Description=Alfresco Search Services (Solr 6)
After=network.target
Before=alfresco-tomcat.service

[Service]
Type=simple
User=${ALF_USER}
Group=${ALF_GROUP}
Environment=JAVA_HOME=${SOLR_JAVA_HOME}
Environment=SOLR_JAVA_HOME=${SOLR_JAVA_HOME}
Environment=SOLR_INCLUDE=${ALF_SOLR}/solr/bin/solr.in.sh
ExecStart=${ALF_SOLR}/solr/bin/solr start -f -a "-Dcreate.alfresco.defaults=alfresco,archive"
ExecStop=${ALF_SOLR}/solr/bin/solr stop
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now alfresco-search

log "Aguardando Solr (porta 8983)..."
for i in $(seq 1 30); do
  ss -ltn | grep -q ':8983' && break
  sleep 2
done
ss -ltn | grep -q ':8983' && log "Solr ativo." || warn "Solr nao subiu na 8983 - verifique ${ALF_SOLR}/logs/solr.log."

log "07 - Search Services (Solr) instalado."
