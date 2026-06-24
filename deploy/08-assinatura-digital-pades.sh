#!/usr/bin/env bash
# =============================================================================
#  08 - Assinatura Digital PAdES (ICP-Brasil)
#
#  ARQUITETURA (definida no survey):
#   - A1 (arquivo .p12/.pfx): SERVER-SIDE. A chave fica no cofre do servidor e
#     a assinatura PAdES roda no proprio Alfresco como etapa de workflow.
#   - A3 (token/smartcard): CLIENT-SIDE. A chave NUNCA sai do token, que esta
#     no DESKTOP do usuario. A assinatura e feita por componente cliente
#     (navegador/applet) que devolve o PDF ja assinado ao Alfresco.
#     => O SERVIDOR NAO escaneia leitora. Por isso NAO instalamos/usamos
#        pcscd/opensc aqui. O mecanismo cliente do A3 e item de survey.
#
#  Base juridica: MP 2.200-2/2001 (equivalencia a assinatura de proprio punho).
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
MMT_JAR="$(find "${ALF_HOME}/bin" -name 'alfresco-mmt*.jar' | head -n1)"
[ -n "${MMT_JAR}" ] || die "alfresco-mmt.jar nao encontrado em ${ALF_HOME}/bin (rode o script 06 antes)."

# ---------------------------------------------------------------------------
# 1) Cadeia ICP-Brasil no truststore da JVM (validacao de assinaturas A1 e A3)
#    Util independentemente de onde a assinatura e gerada: o Alfresco precisa
#    confiar na cadeia ICP-Brasil para validar os certificados.
# ---------------------------------------------------------------------------
log "Preparando importacao da cadeia ICP-Brasil no truststore da JVM..."
CACERTS="${JAVA_HOME}/lib/security/cacerts"
CHAIN_DIR="${ALF_CERTS}/cadeia-icpbrasil"
mkdir -p "${CHAIN_DIR}"
chown -R "${ALF_USER}:${ALF_GROUP}" "${ALF_CERTS}"
chmod 700 "${ALF_CERTS}"

if compgen -G "${CHAIN_DIR}/*.crt" > /dev/null; then
  log "Importando certificados de ${CHAIN_DIR} no cacerts..."
  for crt in "${CHAIN_DIR}"/*.crt; do
    alias="icpbrasil-$(basename "${crt}" .crt)"
    keytool -importcert -trustcacerts -noprompt \
      -alias "${alias}" -file "${crt}" \
      -keystore "${CACERTS}" -storepass changeit 2>/dev/null \
      && log "  importado: ${alias}" || warn "  ja existe/erro: ${alias}"
  done
else
  warn "Nenhum .crt em ${CHAIN_DIR}. A Cliente deve depositar a cadeia oficial"
  warn "ICP-Brasil (AC Raiz + intermediarias) ali e reexecutar este script,"
  warn "ou importar manualmente com keytool -importcert ... -keystore ${CACERTS}"
fi

# ---------------------------------------------------------------------------
# 2) Cofre de certificados A1 (server-side)
# ---------------------------------------------------------------------------
log "Cofre de certificados A1 em ${ALF_CERTS} (700, dono ${ALF_USER})."
warn "Os arquivos .p12/.pfx dos signatarios (A1) devem ser depositados em"
warn "${ALF_CERTS} pela Cliente - nunca versionados, nunca em repositorio."

# ---------------------------------------------------------------------------
# 3) AMP de assinatura digital (server-side PAdES, certificados A1)
# ---------------------------------------------------------------------------
cd "${STAGE}"
if [ -z "${DIGITAL_SIGNING_AMP_URL:-}" ]; then
  warn "DIGITAL_SIGNING_AMP_URL vazio: nenhum AMP de assinatura sera baixado."
  warn "NAO ha AMP community de assinatura ICP-Brasil garantido para o ACS 23."
  warn "Definir no survey (microsservico PAdES com BouncyCastle/Demoiselle ou"
  warn "AMP validado p/ ACS 23) e colocar o .amp em ${ALF_HOME}/amps/ depois."
elif wget -q --show-progress -O digital-signing-repo.amp "${DIGITAL_SIGNING_AMP_URL}"; then
  cp -f digital-signing-repo.amp "${ALF_HOME}/amps/"
  warn "AMP baixado: CONFIRME a compatibilidade com ACS ${ACS_VERSION}/Tomcat 10 antes de confiar nele."
else
  warn "Download do AMP falhou (URL invalida/incompativel com ACS 23)."
  warn "Coloque um .amp compativel em ${ALF_HOME}/amps/ e reexecute, se aplicavel."
fi

ALF_WAR="$(find "${ALF_TOMCAT}/webapps" -maxdepth 1 -name 'alfresco*.war' | head -n1)"
[ -n "${ALF_WAR}" ] || die "alfresco.war nao encontrado em ${ALF_TOMCAT}/webapps (rode o 06 antes)."

log "Parando Tomcat para aplicar AMPs..."
systemctl stop alfresco-tomcat || true

if compgen -G "${ALF_HOME}/amps/*.amp" > /dev/null; then
  log "Aplicando AMPs de ${ALF_HOME}/amps no alfresco.war..."
  "${JAVA_HOME}/bin/java" -jar "${MMT_JAR}" install \
    "${ALF_HOME}/amps" "${ALF_WAR}" -directory -nobackup -force \
    || warn "Falha ao aplicar AMP - verifique compatibilidade/versao."
  # Forca re-deploy do war atualizado
  rm -rf "${ALF_TOMCAT}/webapps/alfresco" "${ALF_TOMCAT}/work/"* 2>/dev/null || true
  chown -R "${ALF_USER}:${ALF_GROUP}" "${ALF_TOMCAT}"
  log "Modulos aplicados no war:"
  "${JAVA_HOME}/bin/java" -jar "${MMT_JAR}" list "${ALF_WAR}" || true
else
  warn "Nenhum .amp em ${ALF_HOME}/amps - pulando aplicacao. Coloque o AMP e reexecute."
fi

log "Subindo Tomcat novamente..."
systemctl start alfresco-tomcat

cat <<NOTA

------------------------------------------------------------------------
ASSINATURA DIGITAL - PROXIMOS PASSOS (configuracao funcional / survey):

  A1 (server-side, ja provisionado aqui):
    1. Depositar os .p12/.pfx dos signatarios em ${ALF_CERTS}.
    2. Configurar a ACTION/REGRA de assinatura como etapa de workflow:
       - PAdES, assinatura simples e multipla;
       - carimbo visual no PDF;
       - verificacao automatica de validade do certificado.
    3. Importar a cadeia ICP-Brasil em ${CHAIN_DIR} e reexecutar (passo 1).

  A3 (token/smartcard) - CLIENT-SIDE (definir no survey):
    - A chave fica no token, no DESKTOP do usuario; o servidor nao assina.
    - Escolher o componente cliente: extensao/applet de navegador, Web PKI,
      ou assinador local que envie o PDF assinado (PAdES) de volta ao Alfresco.
    - Definir o fluxo: tarefa de workflow atribuida ao usuario -> assinatura
      no desktop -> upload do documento assinado -> verificacao no servidor.
------------------------------------------------------------------------
NOTA

log "08 - Assinatura PAdES: A1 server-side provisionado; A3 client-side (survey)."
