#!/usr/bin/env bash
# =============================================================================
#  05 - Alfresco Transform Core (All-In-One) - renderizacao/conversao de docs
#  Necessario para previews, PDF, OCR e transformacoes usadas no fluxo PAdES.
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

log "Baixando Transform Core AIO ${TRANSFORM_VERSION}..."
cd "${STAGE}"
wget -q --show-progress -O transform-core-aio.jar "${TRANSFORM_URL}" \
  || die "Falha no download do Transform Core. Confira TRANSFORM_URL."

install -o "${ALF_USER}" -g "${ALF_GROUP}" -m 0644 \
  transform-core-aio.jar "${ALF_TRANSFORM}/transform-core-aio.jar"

log "Criando servico systemd do Transform..."
cat > /etc/systemd/system/alfresco-transform.service <<EOF
[Unit]
Description=Alfresco Transform Core (AIO)
After=network.target alfresco-activemq.service
Before=alfresco-tomcat.service

[Service]
Type=simple
User=${ALF_USER}
Group=${ALF_GROUP}
Environment=JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
Environment=ACTIVEMQ_URL=tcp://localhost:61616
# LibreOffice/ImageMagick/Ghostscript ja instalados no script 01.
ExecStart=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}/bin/java -Xmx${TRANSFORM_XMX} \\
  -jar ${ALF_TRANSFORM}/transform-core-aio.jar --server.port=8090
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now alfresco-transform

log "Aguardando Transform (porta 8090)..."
for i in $(seq 1 30); do
  curl -fs "http://localhost:8090/ready" >/dev/null 2>&1 && break
  sleep 2
done
curl -fs "http://localhost:8090/ready" >/dev/null 2>&1 \
  && log "Transform Core pronto." || warn "Transform nao respondeu em /ready - verifique logs."

log "05 - Transform Service instalado."
