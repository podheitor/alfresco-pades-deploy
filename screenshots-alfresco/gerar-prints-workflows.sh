#!/usr/bin/env bash
# =============================================================================
#  Gera os prints de WORKFLOWS do Alfresco (roda NO SERVIDOR Alfresco).
#  Companion do gerar-prints.sh. Reaproveita Node/Playwright/Chromium ja
#  instalados pelo 1o robo; instala se faltar. Executa e zipa os PNGs.
#  Uso:  sudo ./gerar-prints-workflows.sh
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

log(){ echo -e "\n\033[1;34m[PRINTS-WF]\033[0m $*"; }
[ "$(id -u)" -eq 0 ] || { echo "rode como root (sudo)"; exit 1; }

log "1/4 Node.js 20 (se necessario)..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
node --version

log "2/4 Playwright + Chromium (se necessario)..."
npm init -y >/dev/null 2>&1 || true
npm ls playwright >/dev/null 2>&1 || npm install playwright@latest
npx --yes playwright install --with-deps chromium

log "3/4 Capturando as telas de workflow (admin/alfresco01)..."
BASE_URL="${BASE_URL:-http://localhost:8080/share}" \
REPO_URL="${REPO_URL:-http://localhost:8080/alfresco}" \
ALF_USER="${ALF_USER:-admin}" \
ALF_PASS="${ALF_PASS:-alfresco01}" \
node capturar-prints-workflows.js

log "4/4 Compactando os PNGs..."
command -v zip >/dev/null 2>&1 || apt-get install -y zip
rm -f prints-workflows.zip
# inclui apenas os prints novos de workflow (20*..27*)
zip -rj prints-workflows.zip prints/2*.png 2>/dev/null || zip -rj prints-workflows.zip prints/
echo
log "Pronto! Prints em: ${DIR}/prints/   e zip: ${DIR}/prints-workflows.zip"
log "Depois copie 20*/21*/22*/23*/24*/26*/27* para ../images/ e gere o .docx/.html/.pdf."
ls -la prints/2*.png 2>/dev/null || ls -la prints/
