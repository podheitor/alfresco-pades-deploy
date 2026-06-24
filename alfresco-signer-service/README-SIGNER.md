# Microsserviço de Assinatura Digital PAdES (ICP-Brasil) — Cliente

Serviço dedicado, 100% software livre (Apache PDFBox + BouncyCastle), que assina
PDFs no padrão **PAdES** (PAdES-BES, SubFilter `ETSI.CAdES.detached`) usando
certificados **A1 (.p12/.pfx)** do cofre `/opt/alfresco/certificados`, com a
cadeia ICP-Brasil completa embarcada. Roda na mesma VM, só em `localhost:8092`.

> Assinatura **A1 server-side**. A3 (token) é client-side (decisão de survey) —
> ver o roteiro principal em `deploy/`.

## 1. Instalar

```bash
cd alfresco-signer-service
sudo ./install-signer.sh
```

Isso instala o Maven (se preciso), compila o fat-jar, instala em
`/opt/alfresco/signer/` e sobe o serviço systemd `alfresco-signer` (porta 8092).

```bash
systemctl status alfresco-signer
curl http://localhost:8092/health      # -> OK
```

## 2. Testar (com um certificado de TESTE, sem precisar de ICP real)

Gere um A1 autoassinado só para validar o fluxo:

```bash
cd /tmp
openssl req -x509 -newkey rsa:2048 -keyout t.key -out t.crt -days 365 -nodes \
  -subj "/CN=Teste Cliente/C=BR"
openssl pkcs12 -export -out /opt/alfresco/certificados/teste.p12 \
  -inkey t.key -in t.crt -passout pass:teste123
chown alfresco:alfresco /opt/alfresco/certificados/teste.p12

# Um PDF qualquer para assinar:
echo "Documento de teste Cliente" | ps2pdf - /tmp/doc.pdf 2>/dev/null || \
  libreoffice --headless --convert-to pdf --outdir /tmp <(echo teste) 2>/dev/null || true

# Assinar:
curl -s -F "file=@/tmp/doc.pdf" -F "cert=teste.p12" -F "password=teste123" \
  -F "reason=Teste PAdES" http://localhost:8092/sign -o /tmp/assinado.pdf

# Conferir que a assinatura existe (instale poppler-utils p/ pdfsig):
pdfsig /tmp/assinado.pdf 2>/dev/null || echo "abra /tmp/assinado.pdf num leitor (Adobe/ITI)"
```

Esperado: `pdfsig` lista 1 assinatura; em produção, com um **A1 ICP-Brasil real**,
ela é validada pelo Verificador do ITI (https://verificador.iti.gov.br) e pelo Adobe.

## 3. Uso em produção

1. A Cliente deposita os `.p12`/`.pfx` reais em `/opt/alfresco/certificados/`
   (dono `alfresco`, permissão `600`).
2. Para validar a cadeia, importe a cadeia ICP-Brasil no truststore (ver
   `deploy/08-assinatura-digital-pades.sh`).
3. Chame `POST /sign` com `cert=<arquivo.p12>` e `password=<senha>`.

### API

`POST http://localhost:8092/sign` (multipart/form-data)

| Campo | Obrigatório | Descrição |
|---|---|---|
| `file` | sim | o PDF a assinar |
| `cert` | sim | nome do `.p12`/`.pfx` no cofre (ex.: `fulano.p12`) |
| `password` | sim | senha do certificado A1 |
| `reason` | não | motivo da assinatura |
| `location` | não | local |

Retorna o **PDF assinado** (`application/pdf`).

## 4. Integração com o Alfresco (workflow)

O serviço é o "motor" de assinatura. A amarração como **etapa de workflow** se faz
no Alfresco apontando para este endpoint. Opções (a decidir no survey):
- **Regra de pasta / ação** que envia o PDF a `POST /sign` e grava a versão assinada.
- **Tarefa de workflow** (Activiti) que, ao aprovar, chama o serviço.
- Script de ponte (CMIS/REST) para automações em lote.

> Próximo incremento sugerido: PAdES-BR completo (OID de política de assinatura +
> carimbo do tempo de uma ACT), se a Cliente exigir conformidade DOC-ICP-15 plena.

## 5. Segurança

- O serviço escuta **apenas em 127.0.0.1** (não exposto na rede).
- Proteção contra path traversal no parâmetro `cert`.
- As senhas dos A1 não ficam no serviço; são passadas na chamada (sobre localhost).
  Para produção, considere um cofre de segredos (ex.: variável por usuário) e
  hardening adicional conforme política da Cliente.
