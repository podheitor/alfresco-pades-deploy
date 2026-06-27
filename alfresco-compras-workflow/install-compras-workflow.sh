#!/usr/bin/env bash
# =============================================================================
#  Instala o módulo "Fluxo de Compras" (workflow Activiti) no Alfresco nativo.
#  Roda NO SERVIDOR, como root, a partir do diretório do módulo.
#    sudo ./install-compras-workflow.sh
#  Variáveis (env, com defaults):
#    ALF_HOME=/opt/alfresco  SERVICE=alfresco-tomcat
#    ADMIN_USER=admin  ADMIN_PASS=alfresco01  BASE=http://localhost:8080
# =============================================================================
set -euo pipefail
ALF_HOME="${ALF_HOME:-/opt/alfresco}"
TOMCAT="${TOMCAT:-$ALF_HOME/tomcat}"
EXT="$TOMCAT/shared/classes/alfresco/extension"
WEBEXT="$TOMCAT/shared/classes/alfresco/web-extension"
SERVICE="${SERVICE:-alfresco-tomcat}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-alfresco01}"
BASE="${BASE:-http://localhost:8080}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log(){ echo -e "\n\033[1;34m[COMPRAS-WF]\033[0m $*"; }
[ "$(id -u)" -eq 0 ] || { echo "rode como root (sudo)"; exit 1; }

log "1/5 Copiando arquivos de plataforma -> $EXT"
mkdir -p "$EXT"
cp "$DIR/platform/compras-fluxo.bpmn20.xml"       "$EXT/"
cp "$DIR/platform/compras-workflow-model.xml"     "$EXT/"
cp "$DIR/platform/compras-workflow.properties"    "$EXT/"
cp "$DIR/platform/compras-workflow-context.xml"   "$EXT/"

log "2/5 Configurando formulários do Share -> $WEBEXT/share-config-custom.xml"
mkdir -p "$WEBEXT"
SRC="$DIR/share/share-config-custom.xml"
DST="$WEBEXT/share-config-custom.xml"
if [ ! -f "$DST" ]; then
  cp "$SRC" "$DST"
  echo "   (criado novo share-config-custom.xml)"
elif grep -q "cpr:triagemTask" "$DST"; then
  echo "   (já contém os forms de Compras — nada a fazer)"
else
  cp "$DST" "$DST.bak.$(date +%s 2>/dev/null || echo bak)"
  # insere os blocos <config> do nosso arquivo antes do </alfresco-config> do destino
  awk 'NR==FNR{ if($0 ~ /<alfresco-config>/){f=1;next} if($0 ~ /<\/alfresco-config>/){f=0} if(f)buf=buf $0 ORS; next }
       /<\/alfresco-config>/{ printf "%s", buf } { print }' "$SRC" "$DST.bak."* > "$DST" 2>/dev/null \
       || { echo "   !! merge automático falhou — mescle $SRC manualmente em $DST"; }
  echo "   (blocos de Compras mesclados; backup em $DST.bak.*)"
fi

log "3/5 Grupos = grupos-líder do AD (sincronizam no restart abaixo)"
echo "   Compras=GROUP_COMPRAS · Financeiro=GROUP_FINANCEIRO"
echo "   Gestor Imediato=dinâmico (grupo-líder do setor escolhido na abertura)."
echo "   >>> Setores cujo grupo-líder está VAZIO no AD não terão aprovador até"
echo "       que um líder seja adicionado ao grupo no Active Directory."

log "4/5 Reiniciando o Alfresco ($SERVICE) para registrar o modelo e o processo..."
systemctl restart "$SERVICE"
echo "   aguardando subir (até ~3 min)..."
for i in $(seq 1 36); do
  sleep 5
  ready=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-" || echo 000)
  [ "$ready" = "200" ] && break
done

log "5/5 Validando o registro do fluxo 'comprasFluxo'..."
sleep 5
out=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/alfresco/s/api/workflow-definitions" || true)
if echo "$out" | grep -q "comprasFluxo"; then
  echo "   OK — fluxo registrado:"; echo "$out" | grep -o '"title":"[^"]*"' | grep -i compra || true
  echo "   --- grupos-líder chave sincronizados? ---"
  for g in COMPRAS FINANCEIRO; do
    n=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/alfresco/s/api/groups?shortNameFilter=$g" | grep -c "GROUP_$g")
    echo "   GROUP_$g: $([ "$n" -gt 0 ] && echo presente || echo AUSENTE-rode-novo-sync)"
  done
  echo
  echo "   Pronto! Em Share: Tarefas > Iniciar fluxo de trabalho > 'Fluxo de Compras'."
else
  echo "   !! 'comprasFluxo' NÃO apareceu. Verifique os logs:"
  echo "      journalctl -u $SERVICE --since '-3min' | grep -aiE 'compras|workflow|bpmn|error'"
  echo "      grep -a -iE 'compras|bpmn|cpr:' $TOMCAT/logs/catalina.out | tail -40"
fi
