#!/usr/bin/env bash
# =============================================================================
#  01 - Preparacao e hardening do sistema operacional (Ubuntu 22.04 LTS)
#  Escopo da proposta: "Survey e validacao do ambiente" + "hardening".
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

log "Validando recursos minimos (proposta: 8vCPU/16GB; recomendado: 10/24/2TB)..."
CPUS=$(nproc)
MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
log "vCPU detectados: ${CPUS} | RAM detectada: ${MEM_GB} GB"
[ "${CPUS}" -ge 8 ]  || warn "CPU abaixo do minimo da proposta (8 vCPU)."
[ "${MEM_GB}" -ge 16 ] || warn "RAM abaixo do minimo da proposta (16 GB)."

log "Atualizando indices e pacotes do sistema..."
export DEBIAN_FRONTEND=noninteractive
# Tolera repositorios de TERCEIROS quebrados (ex.: PPA/Zabbix sem Release file).
# O update nao deve abortar todo o deploy por causa de uma fonte externa.
if ! apt-get update -y; then
  warn "apt-get update reportou erro(s) - provavelmente um repositorio de terceiros quebrado."
  warn "Verifique com: grep -rn '404\\|does not have a Release' (ou revise /etc/apt/sources.list.d/)."
  warn "Prosseguindo com os indices disponiveis dos repositorios oficiais Ubuntu."
fi
# NAO fazemos 'apt-get upgrade' em massa: dispara needrestart/atualizacao de
# kernel e prende o deploy. Atualizacoes de SO devem ser feitas em janela propria.

log "Instalando utilitarios de base..."
# LibreOffice/ImageMagick/Ghostscript: exigidos pelo Transform Service (conversoes).
# --no-install-recommends evita arrastar GUI (gtk/tilix) junto do libreoffice.
# OBS: A3 (token) e CLIENT-SIDE, entao o servidor NAO precisa de pcscd/opensc.
apt-get install -y --no-install-recommends \
  wget curl unzip zip tar ca-certificates gnupg lsb-release \
  ufw fail2ban chrony rsync htop net-tools jq \
  fontconfig fonts-dejavu \
  libreoffice-core libreoffice-writer libreoffice-calc libreoffice-impress \
  imagemagick ghostscript

log "Sincronizando relogio (chrony) - critico para validade de assinaturas/certificados..."
systemctl enable --now chrony

log "Criando usuario de servico '${ALF_USER}'..."
if ! id "${ALF_USER}" >/dev/null 2>&1; then
  groupadd --system "${ALF_GROUP}"
  useradd --system --gid "${ALF_GROUP}" --home-dir "${ALF_HOME}" \
          --shell /usr/sbin/nologin "${ALF_USER}"
fi

log "Criando estrutura de diretorios..."
mkdir -p "${ALF_HOME}" "${ALF_DATA}" "${ALF_SOLR}" "${ALF_AMQ}" \
         "${ALF_TRANSFORM}" "${ALF_KEYSTORE}" "${ALF_CERTS}" \
         "${ALF_LOGS}" "${ALF_BACKUP}" "${STAGE}"
chown -R "${ALF_USER}:${ALF_GROUP}" "${ALF_HOME}" "${ALF_BACKUP}"
# Cofre de certificados A1: acesso restrito.
chmod 700 "${ALF_CERTS}"

log "Ajustando limites de arquivos abertos (Alfresco/Solr exigem >= 65535)..."
cat > /etc/security/limits.d/99-alfresco.conf <<EOF
${ALF_USER}   soft   nofile   65535
${ALF_USER}   hard   nofile   65535
${ALF_USER}   soft   nproc    32768
${ALF_USER}   hard   nproc    32768
EOF

log "Ajustando parametros de kernel (vm/limites)..."
cat > /etc/sysctl.d/99-alfresco.conf <<EOF
vm.swappiness=10
vm.max_map_count=262144
fs.file-max=2097152
EOF
sysctl --system >/dev/null

# Swap de seguranca (2 GB) caso a VM nao possua swap.
if ! swapon --show | grep -q .; then
  log "Criando swapfile de 2GB..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

log "Configurando firewall (UFW)..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
if [ "${USE_NGINX_TLS}" = "true" ]; then
  ufw allow 443/tcp comment 'HTTPS Alfresco (Nginx)'
  ufw allow 80/tcp  comment 'HTTP redirect'
else
  ufw allow 8080/tcp comment 'Alfresco Tomcat (sem proxy)'
fi
# Portas internas (8983 Solr, 5432 PostgreSQL, 8090 Transform, 61616 AMQ)
# permanecem fechadas ao exterior - comunicacao apenas em localhost.
ufw --force enable
ufw status verbose

log "Habilitando fail2ban (protecao SSH)..."
systemctl enable --now fail2ban

log "01 - Preparacao do sistema concluida."
