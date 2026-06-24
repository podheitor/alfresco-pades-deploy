#!/usr/bin/env bash
# =============================================================================
#  Instalador do microsservico de assinatura PAdES (ICP-Brasil A1) - Cliente
#  - Instala Maven (se preciso), compila o fat-jar, instala em /opt/alfresco/signer
#    e cria o servico systemd 'alfresco-signer' (porta 8092, localhost).
#  Uso: sudo ./install-signer.sh
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
SIGNER_HOME="/opt/alfresco/signer"
SVC_USER="alfresco"

log(){ echo -e "\n\033[1;34m[SIGNER]\033[0m $*"; }
die(){ echo -e "\033[1;31m[ERRO]\033[0m $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "Execute como root (sudo)."

log "Instalando Maven (se necessario)..."
if ! command -v mvn >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || true
  apt-get install -y --no-install-recommends maven
fi

log "Compilando o microsservico (mvn package - baixa dependencias na 1a vez)..."
cd "${DIR}"
JAVA_HOME="${JAVA_HOME}" mvn -q -DskipTests clean package

JAR="${DIR}/target/alfresco-signer-service.jar"
[ -f "${JAR}" ] || die "Fat-jar nao gerado em ${JAR}."

log "Instalando em ${SIGNER_HOME}..."
mkdir -p "${SIGNER_HOME}"
cp -f "${JAR}" "${SIGNER_HOME}/alfresco-signer-service.jar"
if id "${SVC_USER}" >/dev/null 2>&1; then
  chown -R "${SVC_USER}:${SVC_USER}" "${SIGNER_HOME}"
else
  SVC_USER="root"
fi

log "Criando servico systemd 'alfresco-signer'..."
cat > /etc/systemd/system/alfresco-signer.service <<EOF
[Unit]
Description=Alfresco PAdES Signer (ICP-Brasil A1)
After=network.target alfresco-tomcat.service

[Service]
User=${SVC_USER}
Group=${SVC_USER}
ExecStart=${JAVA_HOME}/bin/java -jar ${SIGNER_HOME}/alfresco-signer-service.jar
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now alfresco-signer

log "Aguardando o servico (porta 8092)..."
for i in $(seq 1 30); do
  curl -fs http://localhost:8092/health >/dev/null 2>&1 && break
  sleep 2
done
if curl -fs http://localhost:8092/health >/dev/null 2>&1; then
  log "Signer NO AR: http://localhost:8092/health -> OK"
else
  die "Servico nao respondeu. Veja: journalctl -u alfresco-signer -n 50"
fi

log "Instalacao concluida. Endpoint de assinatura: POST http://localhost:8092/sign"
