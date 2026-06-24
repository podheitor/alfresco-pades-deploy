# Integração de Assinatura no Alfresco (fluxo "A Assinar" → "Assinados")

Transforma o microsserviço PAdES num **fluxo operacional** dentro do Alfresco,
sem precisar de AMP/rebuild: o usuário sobe o PDF na pasta **"A Assinar"** (no
Share), e o sistema assina e move para **"Assinados"** automaticamente.

Usa a API REST v1 do Alfresco (download do conteúdo → `:8092/sign` → grava versão
assinada → move). Depende de `jq` e `curl` (já instalados no deploy).

## Pré-requisitos
- Alfresco no ar (`:8080`) e microsserviço de assinatura no ar (`:8092`).
- Um certificado A1 no cofre `/opt/alfresco/certificados` (para teste: `teste.p12`).

## Passos

```bash
cd /root/alfresco-signer-integration

# 1. Configurar: edite SO a senha do admin (e, em producao, o certificado real)
nano assinar-config.sh        # ALF_ADMIN_PASS=... (e SIGN_CERT/SIGN_PASS se for o A1 real)
chmod +x assinar-alfresco.sh

# 2. Criar as pastas no Alfresco (grava os IDs no config automaticamente)
./assinar-alfresco.sh setup

# 3. Ligar o fluxo automatico (verifica a pasta a cada 1 min)
sudo ./assinar-alfresco.sh enable-timer
```

Pronto. Agora, no **Share** (Repositório → Company Home), aparecem as pastas
**"A Assinar"** e **"Assinados"**. Suba um PDF em "A Assinar" → em até 1 min ele
é assinado (PAdES) e movido para "Assinados".

## Testar na hora (sem esperar o timer)

```bash
./assinar-alfresco.sh scan          # assina agora tudo que estiver em "A Assinar"
```

Ou assinar um documento específico (gera nova versão assinada no próprio nó):

```bash
./assinar-alfresco.sh node <nodeId> # o nodeId aparece na URL de detalhes do doc no Share
```

## Operação
- Logs do fluxo: `journalctl -u alfresco-assinar -f`
- Desligar o automático: `sudo ./assinar-alfresco.sh disable-timer`
- Trocar para o certificado real da Cliente: depositar o `.p12` em
  `/opt/alfresco/certificados`, ajustar `SIGN_CERT`/`SIGN_PASS` no config.

## Observações
- Comunicação toda em **localhost** (Alfresco e signer).
- Senhas (admin e do A1) ficam no `assinar-config.sh` — proteja o arquivo
  (`chmod 600`) e, em produção, considere um cofre de segredos.
- Este fluxo por pasta é o caminho mais direto e robusto. Se a Cliente exigir a
  assinatura como **tarefa dentro de um processo Activiti** (aprovação → assina),
  dá para chamar o mesmo `:8092/sign` a partir de um service task — incremento
  futuro, sem mudar o motor de assinatura.
```
