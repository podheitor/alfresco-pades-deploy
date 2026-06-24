#!/usr/bin/env bash
# =============================================================================
#  03 - PostgreSQL 14+ (banco de metadados e estado dos processos BPM)
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root
confirm_secrets

log "Instalando PostgreSQL (versao do repositorio jammy = 14)..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y postgresql postgresql-contrib

systemctl enable --now postgresql

log "Criando role e database do Alfresco..."
sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  ELSE
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
SQL

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" -E UTF8 "${DB_NAME}"
fi

log "Aplicando tunings de performance no PostgreSQL (perfil 24GB RAM)..."
PG_CONF="$(sudo -u postgres psql -tAc 'SHOW config_file')"
PG_DIR="$(dirname "${PG_CONF}")"
cat > "${PG_DIR}/conf.d-alfresco.conf" <<EOF
# Tunings Alfresco (incluido via include_dir)
max_connections = 300
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 24MB
maintenance_work_mem = 1GB
wal_buffers = 16MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
EOF
# Garante o include do diretorio conf.d
grep -q "include_dir = 'conf.d'" "${PG_CONF}" || echo "include_dir = 'conf.d'" >> "${PG_CONF}"
mkdir -p "${PG_DIR}/conf.d"
mv -f "${PG_DIR}/conf.d-alfresco.conf" "${PG_DIR}/conf.d/alfresco.conf"

# Restringir conexao do Alfresco apenas a localhost com senha (scram).
PG_HBA="${PG_DIR}/pg_hba.conf"
grep -q "host    ${DB_NAME}    ${DB_USER}    127.0.0.1/32    scram-sha-256" "${PG_HBA}" || \
  echo "host    ${DB_NAME}    ${DB_USER}    127.0.0.1/32    scram-sha-256" >> "${PG_HBA}"

systemctl restart postgresql

log "Testando conexao do usuario alfresco..."
PGPASSWORD="${DB_PASS}" psql -h 127.0.0.1 -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT version();" >/dev/null \
  && log "Conexao OK." || die "Falha ao conectar no banco ${DB_NAME}."

log "03 - PostgreSQL configurado."
