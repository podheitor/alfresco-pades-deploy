#!/usr/bin/env bash
# =============================================================================
#  02 - Java 17 (OpenJDK) - pre-requisito da proposta
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

log "Instalando OpenJDK 17..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y openjdk-17-jdk-headless

JAVA_PATH="$(readlink -f "$(command -v java)")"
JAVA_HOME_DIR="$(dirname "$(dirname "${JAVA_PATH}")")"
log "JAVA_HOME detectado: ${JAVA_HOME_DIR}"

cat > /etc/profile.d/java.sh <<EOF
export JAVA_HOME=${JAVA_HOME_DIR}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF

# Persistir para os scripts subsequentes
grep -q "JAVA_HOME=" "${DIR}/00-variaveis.sh" || \
  echo "export JAVA_HOME=${JAVA_HOME_DIR}" >> "${DIR}/00-variaveis.sh"

java -version
log "02 - Java 17 instalado."
