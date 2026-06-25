# Alfresco Community + Assinatura Digital PAdES (ICP-Brasil)

Automação de implantação **nativa** (não-Docker) do **Alfresco Community 23.2**
em Ubuntu Server 22.04, com **assinatura digital PAdES** (ICP-Brasil, certificados
A1) via microsserviço dedicado e fluxo de assinatura por pastas integrado ao
Alfresco — tudo software livre, numa única VM.

> Conjunto de scripts e serviços extraído de um projeto real e **generalizado**
> (sem dados de cliente). Ajuste as variáveis ao seu ambiente antes de usar.

## Componentes

| Pasta | O que é |
|---|---|
| [`deploy/`](deploy/) | Scripts modulares (01–11 + `install-all.sh`) que instalam Java 17, PostgreSQL, ActiveMQ, Transform Service, Solr (Search Services), Tomcat 10.1 + Alfresco/Share, Nginx/TLS, backup e monitoramento. |
| [`alfresco-signer-service/`](alfresco-signer-service/) | Microsserviço Spring Boot (PDFBox + BouncyCastle) que assina PDFs em PAdES com A1 do cofre, via REST (`:8092/sign`). |
| [`alfresco-signer-integration/`](alfresco-signer-integration/) | Fluxo "A Assinar → Assinados": PDF colocado numa pasta do Alfresco é assinado e movido automaticamente (timer systemd, API REST v1). |
| [`DEPLOY.md`](DEPLOY.md) | Runbook de implantação ponta a ponta. |
| [`GUIA-TESTE.md`](GUIA-TESTE.md) | Guia de testes de aceitação (orientado ao usuário final). |
| [`MANUAL-WORKFLOWS-ALFRESCO.md`](MANUAL-WORKFLOWS-ALFRESCO.md) | Manual ilustrado de **fluxos de trabalho (workflows)**: iniciar/acompanhar/concluir tarefas, tarefas de grupo (pooled), **regras de pasta** e customização **Activiti/BPMN**. Também em `.html`/`.pdf`/`.docx`. |
| [`screenshots-alfresco/`](screenshots-alfresco/) | Robôs **Playwright** que capturam automaticamente os prints das telas do Share (usados para ilustrar os manuais). |

## Início rápido

```bash
# 1. Plataforma Alfresco
cd deploy
nano 00-variaveis.sh        # definir senhas, hostname/IP de acesso
sudo bash install-all.sh

# 2. Microsserviço de assinatura PAdES
cd ../alfresco-signer-service
sudo ./install-signer.sh

# 3. Fluxo de assinatura no Alfresco
cd ../alfresco-signer-integration
nano assinar-config.sh      # senha admin + certificado A1
./assinar-alfresco.sh setup
sudo ./assinar-alfresco.sh enable-timer
```

Detalhes completos em [`DEPLOY.md`](DEPLOY.md).

## Decisões técnicas e armadilhas resolvidas

- **Tomcat 10.1 standalone + overlay** da distribuição (a distribuição do ACS não traz Tomcat).
- Criação dos diretórios `modules/platform` e `modules/share` (senão o deploy do war aborta).
- **Keystore de metadados via propriedades `-D`** da JVM (o ACS 23 não lê do `alfresco-global.properties`).
- **Solr (Search Services 2.0.x) em Java 17 + G1GC** (o GC padrão do Solr 6 não roda em Java 17).
- **Senha do admin = NT hash** (MD4 do password em UTF-16LE), não MD5.
- **`RemoteIpValve`** no Tomcat + host/protocolo externos (login do Share atrás do Nginx/HTTPS).
- Assinatura **A1 server-side**; **A3 (token) é client-side** por design.

## Requisitos

- Ubuntu Server 22.04 LTS, acesso root/sudo, internet.
- Recomendado: 8+ vCPU, 16+ GB RAM, disco conforme volume de documentos.
- Certificados ICP-Brasil A1 (`.p12`) para assinatura em produção.

## Licença

Scripts sob licença MIT (ver `LICENSE`). Alfresco Community, PDFBox, BouncyCastle
e demais componentes mantêm suas respectivas licenças.

---

Mantido por **OpenTechs**.
