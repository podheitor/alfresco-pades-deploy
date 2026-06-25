#!/usr/bin/env bash
# =============================================================================
#  Gera os prints do Alfresco automaticamente (roda NO SERVIDOR Alfresco).
#  Instala Node + Playwright + Chromium, executa o robo e zipa os PNGs.
#  Uso:  sudo ./gerar-prints.sh
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

log(){ echo -e "\n\033[1;34m[PRINTS]\033[0m $*"; }
[ "$(id -u)" -eq 0 ] || { echo "rode como root (sudo)"; exit 1; }

log "1/4 Node.js 20 (se necessario)..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node --version

log "2/4 Playwright + Chromium + dependencias..."
npm init -y >/dev/null 2>&1 || true
npm install playwright@latest
npx --yes playwright install --with-deps chromium

log "3/4 Capturando as telas (login admin/alfresco01 em http://localhost:8080/share)..."
BASE_URL="${BASE_URL:-http://localhost:8080/share}" \
ALF_USER="${ALF_USER:-admin}" \
ALF_PASS="${ALF_PASS:-alfresco01}" \
node capturar-prints.js

log "4/4 Compactando os PNGs..."
command -v zip >/dev/null 2>&1 || apt-get install -y zip
rm -f prints-alfresco.zip
zip -rj prints-alfresco.zip prints/
echo
log "Pronto! Prints em: ${DIR}/prints/   e zip: ${DIR}/prints-alfresco.zip"
ls -la prints/
