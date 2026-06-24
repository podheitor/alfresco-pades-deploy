#!/usr/bin/env bash
# =============================================================================
#  04 - Apache ActiveMQ (broker de mensagens exigido pelo Alfresco 23.x)
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

log "Baixando ActiveMQ ${ACTIVEMQ_VERSION}..."
cd "${STAGE}"
wget -q --show-progress -O activemq.tar.gz "${ACTIVEMQ_URL}" \
  || die "Falha no download do ActiveMQ. Confira ACTIVEMQ_URL em 00-variaveis.sh."

log "Instalando em ${ALF_AMQ}..."
rm -rf "${ALF_AMQ:?}"/*
tar -xzf activemq.tar.gz -C "${ALF_AMQ}" --strip-components=1

# Limitar memoria da JVM do broker.
sed -i "s/^ACTIVEMQ_OPTS_MEMORY=.*/ACTIVEMQ_OPTS_MEMORY=\"-Xms256m -Xmx${AMQ_XMX}\"/" \
  "${ALF_AMQ}/bin/env" || true

chown -R "${ALF_USER}:${ALF_GROUP}" "${ALF_AMQ}"

log "Criando servico systemd do ActiveMQ..."
cat > /etc/systemd/system/alfresco-activemq.service <<EOF
[Unit]
Description=Alfresco ActiveMQ Broker
After=network.target
Before=alfresco-tomcat.service

[Service]
Type=forking
User=${ALF_USER}
Group=${ALF_GROUP}
Environment=JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
ExecStart=${ALF_AMQ}/bin/activemq start
ExecStop=${ALF_AMQ}/bin/activemq stop
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now alfresco-activemq

log "Aguardando broker subir..."
for i in $(seq 1 20); do
  ss -ltn | grep -q ':61616' && break
  sleep 2
done
ss -ltn | grep -q ':61616' && log "ActiveMQ ativo (porta 61616)." || warn "Broker nao respondeu na 61616 - verifique logs."

log "04 - ActiveMQ instalado."
