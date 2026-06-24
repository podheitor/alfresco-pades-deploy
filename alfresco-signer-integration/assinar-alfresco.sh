#!/usr/bin/env bash
# =============================================================================
#  Integracao Alfresco <-> microsservico PAdES (Cliente)
#  Fluxo: PDF dropado na pasta "A Assinar" -> assinado -> movido p/ "Assinados".
#
#  Comandos:
#    setup          cria/descobre as pastas no Alfresco e grava os IDs no config
#    scan           assina todos os PDFs da pasta "A Assinar" e move p/ "Assinados"
#    node <id>      assina um documento especifico (nova versao no proprio node)
#    enable-timer   instala timer systemd que roda 'scan' a cada 1 min
#    disable-timer  remove o timer
# =============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assinar-config.sh
source "${DIR}/assinar-config.sh"

API="${ALF_BASE}/alfresco/api/-default-/public/alfresco/versions/1"
AUTH=(-u "${ALF_ADMIN_USER}:${ALF_ADMIN_PASS}")
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

log(){ echo -e "\033[1;34m[ASSINAR]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[ATENCAO]\033[0m $*" >&2; }
die(){ echo -e "\033[1;31m[ERRO]\033[0m $*" >&2; exit 1; }

check_secrets() {
  case "${ALF_ADMIN_PASS}" in ALTERE_*) die "Defina ALF_ADMIN_PASS em assinar-config.sh." ;; esac
}

# ---------------------------------------------------------------------------
get_or_create_folder() {
  local name="$1" existing
  existing=$(curl -s "${AUTH[@]}" "${API}/nodes/-root-/children?where=(isFolder=true)&maxItems=1000" \
    | jq -r --arg n "$name" '.list.entries[]? | select(.entry.name==$n) | .entry.id' | head -n1)
  if [ -n "${existing}" ]; then echo "${existing}"; return; fi
  curl -s "${AUTH[@]}" -X POST "${API}/nodes/-root-/children" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"nodeType\":\"cm:folder\"}" | jq -r '.entry.id'
}

cmd_setup() {
  check_secrets
  log "Verificando conexao com o Alfresco..."
  curl -fs "${AUTH[@]}" "${API}/nodes/-root-" >/dev/null || die "Falha ao autenticar no Alfresco (cheque URL/senha)."
  log "Criando/descobrindo pastas em Company Home..."
  local a s
  a=$(get_or_create_folder "A Assinar")
  s=$(get_or_create_folder "Assinados")
  [ -n "${a}" ] && [ -n "${s}" ] || die "Nao consegui obter os IDs das pastas."
  sed -i "s#^export A_ASSINAR_FOLDER=.*#export A_ASSINAR_FOLDER=\"${a}\"#" "${DIR}/assinar-config.sh"
  sed -i "s#^export ASSINADOS_FOLDER=.*#export ASSINADOS_FOLDER=\"${s}\"#" "${DIR}/assinar-config.sh"
  log "Pasta 'A Assinar' : ${a}"
  log "Pasta 'Assinados' : ${s}"
  log "Setup concluido. No Share/Repositorio aparecem as pastas 'A Assinar' e 'Assinados'."
}

# ---------------------------------------------------------------------------
sign_node() {
  local node="$1" name code
  name=$(curl -s "${AUTH[@]}" "${API}/nodes/${node}?fields=name" | jq -r '.entry.name // empty')
  [ -n "${name}" ] || die "Node ${node} nao encontrado."
  log "Assinando: ${name} (${node})"
  # baixa conteudo
  curl -fs "${AUTH[@]}" "${API}/nodes/${node}/content" -o "${TMP}/in.pdf" || die "Falha ao baixar o conteudo."
  # assina no microsservico
  code=$(curl -s -F "file=@${TMP}/in.pdf" -F "cert=${SIGN_CERT}" -F "password=${SIGN_PASS}" \
      -F "reason=${SIGN_REASON}" "${SIGNER_URL}/sign" -o "${TMP}/out.pdf" -w "%{http_code}")
  [ "${code}" = "200" ] || die "Signer retornou HTTP ${code} (cheque o certificado/senha)."
  # grava nova versao assinada
  curl -fs "${AUTH[@]}" -X PUT \
      "${API}/nodes/${node}/content?majorVersion=true&comment=Assinado%20digitalmente%20(PAdES)" \
      -H "Content-Type: application/pdf" --data-binary "@${TMP}/out.pdf" >/dev/null \
      || die "Falha ao gravar a versao assinada."
  log "  -> versao assinada gravada."
}

# ---------------------------------------------------------------------------
cmd_scan() {
  check_secrets
  [ -n "${A_ASSINAR_FOLDER}" ] && [ -n "${ASSINADOS_FOLDER}" ] || die "Pastas nao configuradas. Rode 'setup' primeiro."
  local ids id
  ids=$(curl -s "${AUTH[@]}" "${API}/nodes/${A_ASSINAR_FOLDER}/children?maxItems=500&where=(isFile=true)" \
    | jq -r '.list.entries[]? | select(.entry.content.mimeType=="application/pdf") | .entry.id')
  if [ -z "${ids}" ]; then log "Nada a assinar em 'A Assinar'."; return; fi
  for id in ${ids}; do
    sign_node "${id}" || { warn "Falhou no node ${id}, seguindo."; continue; }
    # move para 'Assinados' (evita reprocessar e organiza)
    curl -fs "${AUTH[@]}" -X POST "${API}/nodes/${id}/move" \
        -H "Content-Type: application/json" \
        -d "{\"targetParentId\":\"${ASSINADOS_FOLDER}\"}" >/dev/null \
        && log "  -> movido para 'Assinados'." || warn "  assinou mas falhou ao mover ${id}."
  done
  log "Scan concluido."
}

# ---------------------------------------------------------------------------
cmd_enable_timer() {
  cat > /etc/systemd/system/alfresco-assinar.service <<EOF
[Unit]
Description=Assina PDFs da pasta 'A Assinar' (Alfresco -> PAdES)
After=alfresco-tomcat.service alfresco-signer.service

[Service]
Type=oneshot
ExecStart=${DIR}/assinar-alfresco.sh scan
EOF
  cat > /etc/systemd/system/alfresco-assinar.timer <<EOF
[Unit]
Description=Verifica a pasta 'A Assinar' periodicamente

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
Unit=alfresco-assinar.service

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now alfresco-assinar.timer
  log "Timer ativo: a pasta 'A Assinar' sera verificada a cada 1 min."
  log "Acompanhe: journalctl -u alfresco-assinar -f"
}

cmd_disable_timer() {
  systemctl disable --now alfresco-assinar.timer 2>/dev/null || true
  rm -f /etc/systemd/system/alfresco-assinar.timer /etc/systemd/system/alfresco-assinar.service
  systemctl daemon-reload
  log "Timer removido."
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  setup)         cmd_setup ;;
  scan)          cmd_scan ;;
  node)          check_secrets; sign_node "${2:?uso: node <id>}" ;;
  enable-timer)  cmd_enable_timer ;;
  disable-timer) cmd_disable_timer ;;
  *) echo "uso: $0 {setup|scan|node <id>|enable-timer|disable-timer}"; exit 1 ;;
esac
