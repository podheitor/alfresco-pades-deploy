#!/usr/bin/env bash
# =============================================================================
#  09 - Nginx reverse proxy + TLS (publicacao segura do Alfresco/Share)
#  Atende ao requisito de "certificados TLS" do survey da proposta.
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-variaveis.sh
source "${DIR}/00-variaveis.sh"
require_root

if [ "${USE_NGINX_TLS}" != "true" ]; then
  log "USE_NGINX_TLS=false -> pulando proxy. Alfresco respondera em :8080."
  exit 0
fi

log "Instalando Nginx..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y nginx

mkdir -p "$(dirname "${TLS_CERT}")"
if [ ! -f "${TLS_CERT}" ] || [ ! -f "${TLS_KEY}" ]; then
  warn "Certificado TLS nao encontrado em ${TLS_CERT}. Gerando AUTOASSINADO (substituir pelo oficial da Cliente)."
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout "${TLS_KEY}" -out "${TLS_CERT}" \
    -subj "/C=BR/O=Cliente/CN=${ALF_HOSTNAME}"
fi

log "Configurando virtual host..."
cat > /etc/nginx/sites-available/alfresco.conf <<EOF
server {
    listen 80;
    server_name ${ALF_HOSTNAME};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${ALF_HOSTNAME};

    ssl_certificate     ${TLS_CERT};
    ssl_certificate_key ${TLS_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    client_max_body_size 2g;   # uploads grandes de documentos
    proxy_read_timeout 300s;

    location / { return 302 /share/; }

    location /share/ {
        proxy_pass http://127.0.0.1:8080/share/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    location /alfresco/ {
        proxy_pass http://127.0.0.1:8080/alfresco/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    location /api-explorer/ {
        proxy_pass http://127.0.0.1:8080/api-explorer/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

ln -sf /etc/nginx/sites-available/alfresco.conf /etc/nginx/sites-enabled/alfresco.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl enable --now nginx && systemctl reload nginx

log "09 - Nginx + TLS configurado. Acesso: https://${ALF_HOSTNAME}/share/"
