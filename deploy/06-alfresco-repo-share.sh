#!/usr/bin/env bash
# =============================================================================
#  06 - Alfresco Community: Repositorio + Share + BPM (Activiti/Flowable)
#  MODELO CORRETO: a distribuicao do Alfresco NAO traz Tomcat. Instala-se um
#  Apache Tomcat 10.1 standalone (ACS 23.x EXIGE Tomcat 10) e sobrepoe-se o
#  conteudo de web-server/ (webapps, conf/Catalina, shared, lib) nesse Tomcat.
#
#  Estrutura real do zip (confirmada):
#    acs-dist/bin/alfresco-mmt.jar
#    acs-dist/amps/  acs-dist/keystore/metadata-keystore/  acs-dist/licenses/
#    acs-dist/web-server/{conf/Catalina, lib, shared/classes, webapps/*.war}
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root
confirm_secrets

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

# ---------------------------------------------------------------------------
# 1) Distribuicao Alfresco (download + extracao se ainda nao houver)
# ---------------------------------------------------------------------------
DISTROOT="${STAGE}/acs-dist"
if [ ! -d "${DISTROOT}/web-server" ]; then
  log "Baixando distribuicao Alfresco Content Services Community ${ACS_VERSION}..."
  cd "${STAGE}"
  wget -q --show-progress -O acs-dist.zip "${ACS_DIST_URL}" \
    || die "Falha no download da distribuicao. Confira ACS_DIST_URL."
  log "Extraindo distribuicao..."
  rm -rf "${DISTROOT}"; mkdir -p "${DISTROOT}"
  unzip -q acs-dist.zip -d "${DISTROOT}"
fi
WEBSRV="$(find "${DISTROOT}" -maxdepth 2 -type d -name web-server | head -n1)"
[ -n "${WEBSRV}" ] || die "Pasta web-server nao encontrada na distribuicao."
DISTROOT="$(dirname "${WEBSRV}")"
log "Distribuicao em: ${DISTROOT}"

# ---------------------------------------------------------------------------
# 2) Apache Tomcat 10.1 standalone
# ---------------------------------------------------------------------------
log "Baixando Apache Tomcat ${TOMCAT_VERSION}..."
cd "${STAGE}"
wget -q --show-progress -O tomcat.tar.gz "${TOMCAT_URL}" \
  || die "Falha no download do Tomcat. Confira TOMCAT_URL/TOMCAT_VERSION."

log "Instalando Tomcat em ${ALF_TOMCAT}..."
systemctl stop alfresco-tomcat 2>/dev/null || true
rm -rf "${ALF_TOMCAT:?}"
mkdir -p "${ALF_TOMCAT}"
tar -xzf tomcat.tar.gz -C "${ALF_TOMCAT}" --strip-components=1

# Remove webapps padrao do Tomcat (usaremos o ROOT.war do Alfresco)
rm -rf "${ALF_TOMCAT}/webapps/"*

# ---------------------------------------------------------------------------
# 3) Overlay do conteudo da distribuicao no Tomcat
# ---------------------------------------------------------------------------
log "Aplicando overlay (webapps, conf/Catalina, shared, lib)..."
# 3.1 WARs
cp -a "${WEBSRV}/webapps/." "${ALF_TOMCAT}/webapps/"
# 3.2 Contextos (alfresco.xml, share.xml em conf/Catalina/localhost)
mkdir -p "${ALF_TOMCAT}/conf/Catalina/localhost"
if [ -d "${WEBSRV}/conf/Catalina" ]; then
  cp -a "${WEBSRV}/conf/Catalina/." "${ALF_TOMCAT}/conf/Catalina/"
fi
# 3.3 shared (classes/ e libs especificas do Alfresco)
cp -a "${WEBSRV}/shared" "${ALF_TOMCAT}/shared"
# 3.4 libs do common classloader (driver JDBC, etc.)
cp -a "${WEBSRV}/lib/." "${ALF_TOMCAT}/lib/"

# 3.5 Habilita o shared classloader (shared.loader) no catalina.properties
CATPROP="${ALF_TOMCAT}/conf/catalina.properties"
sed -i 's#^shared.loader=.*#shared.loader=${catalina.base}/shared/classes,${catalina.base}/shared/lib/*.jar#' "${CATPROP}"
mkdir -p "${ALF_TOMCAT}/shared/lib"

# 3.5.1 RemoteIpValve: atras do Nginx (HTTPS), o Tomcat recebe HTTP na 8080. Sem
#       isto o Share monta o contexto como http e o filtro CSRF rejeita o login
#       (referer https vs contexto http). O Valve le o X-Forwarded-Proto do Nginx.
SX="${ALF_TOMCAT}/conf/server.xml"
grep -q "RemoteIpValve" "${SX}" || sed -i 's#</Host>#  <Valve className="org.apache.catalina.valves.RemoteIpValve" remoteIpHeader="X-Forwarded-For" protocolHeader="X-Forwarded-Proto" />\n</Host>#' "${SX}"

# 3.6 Diretorios de modulos: os contextos alfresco.xml/share.xml montam JARs de
#     tomcat/../modules/platform e tomcat/../modules/share. A distribuicao NAO os
#     cria; sem eles o Tomcat aborta o deploy ("directory ... does not exist").
mkdir -p "${ALF_HOME}/modules/platform" "${ALF_HOME}/modules/share"

# ---------------------------------------------------------------------------
# 4) Keystore de metadados (criptografia) - vem em keystore/metadata-keystore
# ---------------------------------------------------------------------------
log "Instalando metadata-keystore..."
if [ -d "${DISTROOT}/keystore/metadata-keystore" ]; then
  cp -a "${DISTROOT}/keystore/metadata-keystore/." "${ALF_KEYSTORE}/"
fi

# Utilitarios MMT/AMP para o script de assinatura (08)
mkdir -p "${ALF_HOME}/bin"
[ -d "${DISTROOT}/bin" ] && cp -a "${DISTROOT}/bin/." "${ALF_HOME}/bin/"
[ -d "${DISTROOT}/amps" ] && { mkdir -p "${ALF_HOME}/amps"; cp -a "${DISTROOT}/amps/." "${ALF_HOME}/amps/"; }
[ -d "${DISTROOT}/amps_share" ] && { mkdir -p "${ALF_HOME}/amps_share"; cp -a "${DISTROOT}/amps_share/." "${ALF_HOME}/amps_share/"; }

# ---------------------------------------------------------------------------
# 5) alfresco-global.properties
# ---------------------------------------------------------------------------
log "Gerando alfresco-global.properties..."
SHARED_CLASSES="${ALF_TOMCAT}/shared/classes"
mkdir -p "${SHARED_CLASSES}/alfresco/extension"
# URL externa: com Nginx/TLS o acesso e https/443; sem proxy, http/8080.
# (O RemoteIpValve + estes valores fazem o login do Share funcionar atras do proxy.)
if [ "${USE_NGINX_TLS}" = "true" ]; then EXT_PROTO="https"; EXT_PORT="443"; else EXT_PROTO="http"; EXT_PORT="8080"; fi
cat > "${SHARED_CLASSES}/alfresco-global.properties" <<EOF
# ============================================================
#  Alfresco Community - Cliente (gerado automaticamente)
# ============================================================
# --- Diretorios ---
dir.root=${ALF_DATA}
dir.keystore=${ALF_KEYSTORE}

# --- Admin (NT hash = MD4 do password em UTF-16LE; NAO e md5!) ---
alfresco_user_store.adminpassword=$(printf '%s' "${ALF_ADMIN_PASS}" | iconv -t utf-16le | openssl dgst -md4 -provider legacy -provider default | awk '{print \$NF}')

# --- Banco de dados (PostgreSQL) ---
db.driver=org.postgresql.Driver
db.url=jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
db.username=${DB_USER}
db.password=${DB_PASS}
db.pool.max=275

# --- URLs / Host (externos: com Nginx/TLS => https/443) ---
alfresco.host=${ALF_HOSTNAME}
alfresco.port=${EXT_PORT}
alfresco.protocol=${EXT_PROTO}
share.host=${ALF_HOSTNAME}
share.port=${EXT_PORT}
share.protocol=${EXT_PROTO}
aos.baseUrlOverwrite=${EXT_PROTO}://${ALF_HOSTNAME}/alfresco/aos

# --- Solr / Search Services (comunicacao por secret) ---
index.subsystem.name=solr6
solr.host=localhost
solr.port=8983
solr.secureComms=secret
solr.sharedSecret=${SOLR_SHARED_SECRET}

# --- Transform Service ---
localTransform.core-aio.url=http://localhost:8090/
transform.service.enabled=true

# --- ActiveMQ ---
messaging.broker.url=failover:(nio://localhost:61616)?timeout=3000&jms.useCompression=true

# --- Workflow / BPM (Activiti embarcado) ---
system.workflow.engine.activiti.enabled=true
system.workflow.engine.activiti.definitions.visible=true

# --- Criptografia de metadados (keystore padrao da distribuicao) ---
# As senhas abaixo sao os DEFAULTS publicos da Alfresco. Para PRODUCAO,
# regere o keystore (keytool) e troque estas senhas.
encryption.keystore.type=JCEKS
encryption.cipherAlgorithm=DESede/CBC/PKCS5Padding
encryption.keyAlgorithm=DESede
encryption.keystore.location=${ALF_KEYSTORE}/keystore
metadata-keystore.password=mp6yc0UD9e
metadata-keystore.aliases=metadata
metadata-keystore.metadata.password=oKIWzVdEdA
metadata-keystore.metadata.algorithm=DESede

# --- CSRF / cabecalhos atras de proxy ---
csrf.filter.referer=${EXT_PROTO}://${ALF_HOSTNAME}/.*
csrf.filter.origin=${EXT_PROTO}://${ALF_HOSTNAME}
EOF
warn "metadata-keystore usando senhas DEFAULT da Alfresco. Regere o keystore antes de producao."

# ---------------------------------------------------------------------------
# 6) JVM do Tomcat (setenv.sh) - Tomcat 10.1 possui bin/
# ---------------------------------------------------------------------------
log "Configurando JVM do Tomcat (setenv.sh)..."
cat > "${ALF_TOMCAT}/bin/setenv.sh" <<EOF
#!/bin/sh
export JAVA_HOME=${JAVA_HOME}
export CATALINA_PID="\${CATALINA_BASE}/temp/catalina.pid"
CATALINA_OPTS="-Xms2g -Xmx${TOMCAT_XMX}"
CATALINA_OPTS="\${CATALINA_OPTS} -XX:+UseG1GC -XX:+UseStringDeduplication"
CATALINA_OPTS="\${CATALINA_OPTS} -Dalfresco.home=${ALF_HOME}"
CATALINA_OPTS="\${CATALINA_OPTS} -Djava.awt.headless=true"
CATALINA_OPTS="\${CATALINA_OPTS} -Dsolr.secureComms=secret -Dsolr.sharedSecret=${SOLR_SHARED_SECRET}"
# Criptografia de metadados: o ACS 23 le estas configs SO de propriedades -D da
# JVM (NAO do alfresco-global.properties). Sem elas o repo nao sobe
# ("05220000 Unable to get secret key: no key information is provided").
CATALINA_OPTS="\${CATALINA_OPTS} -Dencryption.keystore.type=JCEKS"
CATALINA_OPTS="\${CATALINA_OPTS} -Dencryption.cipherAlgorithm=DESede/CBC/PKCS5Padding"
CATALINA_OPTS="\${CATALINA_OPTS} -Dencryption.keyAlgorithm=DESede"
CATALINA_OPTS="\${CATALINA_OPTS} -Dencryption.keystore.location=${ALF_KEYSTORE}/keystore"
CATALINA_OPTS="\${CATALINA_OPTS} -Dmetadata-keystore.password=mp6yc0UD9e"
CATALINA_OPTS="\${CATALINA_OPTS} -Dmetadata-keystore.aliases=metadata"
CATALINA_OPTS="\${CATALINA_OPTS} -Dmetadata-keystore.metadata.password=oKIWzVdEdA"
CATALINA_OPTS="\${CATALINA_OPTS} -Dmetadata-keystore.metadata.algorithm=DESede"
export CATALINA_OPTS
EOF
chmod +x "${ALF_TOMCAT}/bin/setenv.sh"

chown -R "${ALF_USER}:${ALF_GROUP}" "${ALF_HOME}"

# ---------------------------------------------------------------------------
# 7) Servico systemd
# ---------------------------------------------------------------------------
log "Criando servico systemd do Tomcat (Alfresco/Share)..."
cat > /etc/systemd/system/alfresco-tomcat.service <<EOF
[Unit]
Description=Alfresco Community (Tomcat 10.1: Repository + Share)
After=network.target postgresql.service alfresco-activemq.service alfresco-transform.service alfresco-search.service
Wants=alfresco-search.service

[Service]
Type=forking
User=${ALF_USER}
Group=${ALF_GROUP}
# Diretorio de trabalho gravavel: o log4j do Alfresco cria alfresco.log/share.log
# no CWD do processo. Sem isto (CWD=/) da "Permission denied" e o app nao loga.
WorkingDirectory=${ALF_TOMCAT}
Environment=JAVA_HOME=${JAVA_HOME}
Environment=CATALINA_PID=${ALF_TOMCAT}/temp/catalina.pid
ExecStart=${ALF_TOMCAT}/bin/startup.sh
ExecStop=${ALF_TOMCAT}/bin/shutdown.sh
PIDFile=${ALF_TOMCAT}/temp/catalina.pid
Restart=on-failure
TimeoutStartSec=600
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable alfresco-tomcat
log "Iniciando Alfresco (primeiro boot demora varios minutos - cria schema no DB)..."
systemctl start alfresco-tomcat

log "Acompanhe o boot com: tail -f ${ALF_TOMCAT}/logs/catalina.out"
log "06 - Alfresco Repositorio + Share instalados (Tomcat 10.1 + overlay)."
