#!/usr/bin/env bash
# =============================================================================
#  Projeto: Deploy Alfresco Community + Assinatura Digital ICP-Brasil (Cliente)
#  Proposta Comercial - OpenTechs LTDA
#  Arquivo: 00-variaveis.sh  -> Variaveis compartilhadas por todos os scripts
#  Alvo...: Ubuntu Server 22.04 LTS (instalacao NATIVA)
# =============================================================================
# Este arquivo NAO deve ser executado isoladamente. Ele e carregado (source)
# pelos demais scripts. Ajuste os valores conforme o ambiente da Cliente ANTES
# de iniciar o deploy.
# -----------------------------------------------------------------------------

set -euo pipefail

# ----------------------------- VERSOES (CONFIRMAR) ---------------------------
# IMPORTANTE: confirme as versoes/URLs vigentes no portal Hyland/Alfresco no
# momento do deploy. Artefatos Community ficam no Nexus publico da Alfresco.
export ACS_VERSION="23.2.1"            # Alfresco Content Services Community
export SEARCH_VERSION="2.0.13"         # Alfresco Search Services (Solr 6)
export TRANSFORM_VERSION="5.1.7"       # Alfresco Transform Core (All-In-One)
export ACTIVEMQ_VERSION="5.18.3"       # Apache ActiveMQ (broker de mensagens)
export TOMCAT_VERSION="10.1.48"        # Apache Tomcat 10.1 (ACS 23.x EXIGE Tomcat 10)
export DIGITAL_SIGNING_VERSION="2.0.0" # AMP de assinatura (Atol CD digital-signing)

# URLs de download (Nexus publico Alfresco / Apache). Confirmar antes de usar.
export ACS_DIST_URL="https://nexus.alfresco.com/nexus/repository/public/org/alfresco/alfresco-content-services-community-distribution/${ACS_VERSION}/alfresco-content-services-community-distribution-${ACS_VERSION}.zip"
export SEARCH_URL="https://nexus.alfresco.com/nexus/repository/public/org/alfresco/alfresco-search-services/${SEARCH_VERSION}/alfresco-search-services-${SEARCH_VERSION}.zip"
export TRANSFORM_URL="https://nexus.alfresco.com/nexus/repository/public/org/alfresco/alfresco-transform-core-aio/${TRANSFORM_VERSION}/alfresco-transform-core-aio-${TRANSFORM_VERSION}.jar"
export ACTIVEMQ_URL="https://archive.apache.org/dist/activemq/${ACTIVEMQ_VERSION}/apache-activemq-${ACTIVEMQ_VERSION}-bin.tar.gz"
export TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
# AMP de assinatura digital (server-side PAdES, certificados A1/PKCS12).
# VAZIO por padrao: NAO ha AMP community de assinatura ICP-Brasil garantido para
# o ACS 23 (o da Atol so tem releases p/ versoes antigas). O modulo de assinatura
# e decisao de survey (microsservico PAdES ou AMP validado). Quando houver, ponha
# a URL aqui OU copie o .amp direto em ${ALF_HOME}/amps/. Ex. (NAO compativel c/ 23):
# https://github.com/atolcd/alfresco-digital-signing/releases/download/${DIGITAL_SIGNING_VERSION}/digital-signing-repo-${DIGITAL_SIGNING_VERSION}.amp
export DIGITAL_SIGNING_AMP_URL=""

# ----------------------------- DIRETORIOS ------------------------------------
export ALF_HOME="/opt/alfresco"               # base da instalacao
export ALF_TOMCAT="${ALF_HOME}/tomcat"        # Tomcat (web-server da distribuicao)
export ALF_DATA="${ALF_HOME}/alf_data"        # content store (documentos)
export ALF_SOLR="${ALF_HOME}/search-services" # Alfresco Search Services
export ALF_AMQ="${ALF_HOME}/activemq"         # ActiveMQ
export ALF_TRANSFORM="${ALF_HOME}/transform"  # Transform Core (jar)
export ALF_KEYSTORE="${ALF_HOME}/keystore"    # metadata keystore Alfresco
export ALF_CERTS="${ALF_HOME}/certificados"   # cofre de certificados ICP-Brasil (A1)
export ALF_LOGS="${ALF_HOME}/logs"
export ALF_BACKUP="/opt/backup-alfresco"      # destino dos backups (ajustar p/ 2TB SSD)
export STAGE="/opt/stage-alfresco"            # area temporaria de download/unzip

# ----------------------------- USUARIO DE SERVICO ----------------------------
export ALF_USER="alfresco"
export ALF_GROUP="alfresco"

# ----------------------------- BANCO DE DADOS --------------------------------
export DB_HOST="localhost"
export DB_PORT="5432"
export DB_NAME="alfresco"
export DB_USER="alfresco"
# TROCAR a senha abaixo por um valor forte (use: openssl rand -base64 24)
export DB_PASS="ALTERE_ESTA_SENHA_DB"

# ----------------------------- ALFRESCO --------------------------------------
# Senha do usuario admin do Alfresco. TROCAR antes do deploy.
export ALF_ADMIN_PASS="ALTERE_ESTA_SENHA_ADMIN"
# Hostname/IP pelo qual o Alfresco sera acessado (usado no proxy e nas URLs)
export ALF_HOSTNAME="alfresco.nbs.local"
# Segredo compartilhado entre repo e Solr (mTLS desligado, usar secret).
export SOLR_SHARED_SECRET="ALTERE_ESTE_SECRET_SOLR"

# ----------------------------- JVM / RECURSOS --------------------------------
# VM dimensionada: 10 vCPU / 24 GB RAM / 2 TB SSD (environment.txt).
# Distribuicao de memoria sugerida (deixa folga p/ SO, PostgreSQL e Solr):
export TOMCAT_XMX="10g"     # repositorio Alfresco + Share
export SOLR_XMX="6g"        # indexacao/busca
export TRANSFORM_XMX="2g"   # transformacoes
export AMQ_XMX="1g"         # ActiveMQ

# ----------------------------- TLS / PROXY -----------------------------------
export USE_NGINX_TLS="true"            # publicar via Nginx + HTTPS
export TLS_CERT="/etc/ssl/nbs/alfresco.crt"
export TLS_KEY="/etc/ssl/nbs/alfresco.key"

# =============================================================================
# Funcoes utilitarias compartilhadas
# =============================================================================
log()  { echo -e "\n\033[1;34m[Cliente-DEPLOY]\033[0m $*"; }
warn() { echo -e "\033[1;33m[ATENCAO]\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m[ERRO]\033[0m $*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Execute como root (sudo)."
}

confirm_secrets() {
  for v in DB_PASS ALF_ADMIN_PASS SOLR_SHARED_SECRET; do
    case "${!v}" in
      ALTERE_*) die "A variavel $v ainda esta com o valor padrao. Defina um segredo forte em 00-variaveis.sh." ;;
    esac
  done
}
