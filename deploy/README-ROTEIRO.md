# Roteiro de Instalação — Alfresco Community + Assinatura Digital ICP-Brasil (Cliente)

> **Referência:** Proposta Comercial — OpenTechs LTDA
> **Cliente:** Cliente — CNPJ  ()
> **Analista responsável:** Heitor Medrado de Faria
> **Alvo:** VM única — Ubuntu Server 22.04 LTS · 10 vCPU · 24 GB RAM · 2 TB SSD (`environment.txt`)
> **Método:** Instalação **nativa** (pacotes/distribuição), não-Docker

Este roteiro automatiza, em scripts modulares, **todos os itens previstos na proposta**:
implantação do Alfresco Community, deploy do motor de workflow (BPMN 2.0),
habilitação de assinatura digital PAdES (ICP-Brasil A1/A3), backup, monitoramento e validação.

---

## 1. Mapeamento Proposta → Scripts

| Item da proposta | Script |
|---|---|
| Survey/validação do ambiente + hardening | `01-preparacao-sistema.sh` |
| Java 17 (pré-requisito) | `02-java17.sh` |
| PostgreSQL 14+ (metadados/estado BPM) | `03-postgresql.sh` |
| ActiveMQ (broker exigido pelo Alfresco) | `04-activemq.sh` |
| Transform Service (conversões/preview/PDF) | `05-transform-service.sh` |
| Solr / Search Services (indexação e busca) | `07-search-services-solr.sh` |
| Alfresco Repository + Share + **Activiti/Flowable BPM** | `06-alfresco-repo-share.sh` |
| **Assinatura Digital PAdES (ICP-Brasil A1/A3)** | `08-assinatura-digital-pades.sh` |
| Publicação segura (TLS) | `09-nginx-tls.sh` |
| Backup, rotação de logs, monitoramento básico | `10-backup-logrotate-monitor.sh` |
| Testes de aceitação técnica | `11-validacao.sh` |
| Orquestrador (executa tudo na ordem) | `install-all.sh` |

> O **motor de workflow (Activiti/Flowable)** já vem embarcado no repositório Alfresco
> e é habilitado via `alfresco-global.properties` no script `06`. A *modelagem* dos
> até 3 processos BPMN 2.0 e a integração funcional da assinatura são atividades de
> consultoria (survey/modelagem), executadas após este deploy de infraestrutura.

---

## 2. Pré-requisitos (responsabilidade da Cliente — conforme proposta)

- Servidor Linux Ubuntu 22.04 (ou RHEL/Rocky 9) com acesso `sudo`/root.
- Conectividade à internet (download dos artefatos) **ou** artefatos pré-baixados.
- Certificados digitais ICP-Brasil A1 (.p12/.pfx) e/ou A3 (token/smartcard + leitora).
- Cadeia oficial ICP-Brasil (AC Raiz/intermediárias) para validação.
- Certificado TLS do domínio (ou usar o autoassinado gerado para homologação).
- Diretório de identidade LDAP/Active Directory (se a integração for desejada).

---

## 3. Como executar

```bash
# 1. Copie a pasta deploy/ para o servidor da Cliente
scp -r deploy/ usuario@servidor-nbs:/tmp/

# 2. No servidor, ENTRE no diretório e edite os segredos
cd /tmp/deploy
nano 00-variaveis.sh      # <-- OBRIGATÓRIO: trocar senhas/segredos e hostname

# 3a. Execução completa (recomendado)
sudo bash install-all.sh

# 3b. OU execução passo a passo (útil para acompanhar/depurar)
sudo bash 01-preparacao-sistema.sh
sudo bash 02-java17.sh
# ... e assim por diante (ordem do install-all.sh)
```

### Variáveis que **devem** ser ajustadas em `00-variaveis.sh`
- `DB_PASS` — senha do banco (`openssl rand -base64 24`)
- `ALF_ADMIN_PASS` — senha do `admin` do Alfresco
- `SOLR_SHARED_SECRET` — segredo de comunicação repo↔Solr
- `ALF_HOSTNAME` — host/domínio de acesso
- `*_VERSION` e `*_URL` — **confirmar versões/URLs vigentes** no Nexus público da Alfresco

> Os scripts **abortam** se as senhas continuarem com o valor padrão `ALTERE_...`.

---

## 4. Distribuição de recursos (perfil 24 GB RAM / 10 vCPU)

| Serviço | Heap (Xmx) |
|---|---|
| Alfresco Repository + Share (Tomcat) | 10 GB |
| Solr / Search Services | 6 GB |
| Transform Core | 2 GB |
| ActiveMQ | 1 GB |
| PostgreSQL (shared_buffers/cache) | ~4 GB / 12 GB cache |
| Reserva SO / LibreOffice / picos | ~3 GB |

Ajuste em `00-variaveis.sh` (`TOMCAT_XMX`, `SOLR_XMX`, etc.).

---

## 5. Pós-deploy (atividades de consultoria da proposta)

1. **Workflows (BPM):** levantar e modelar até **3 processos críticos** (BPMN 2.0) no
   Activiti/Flowable — papéis, prazos, escalonamentos, notificações — e publicar.
2. **Assinatura digital:** concluir a configuração funcional (vide nota ao final do
   script `08`): cadastro de certificados, action/regra de assinatura como etapa de
   workflow (simples e múltipla), carimbo visual PAdES e verificação de validade.
3. **Autenticação:** integrar LDAP/Active Directory, se aplicável.
4. **Modelo de conteúdo:** sites, tipos de conteúdo, metadados e regras de classificação.
5. **Testes de aceitação** com usuários-chave e **knowledge transfer** ao time de TI.
6. **Suporte pós go-live:** 30 dias (abertura de chamados via GLPI + VPN).

---

## 6. Portas e segurança

| Porta | Serviço | Exposição |
|---|---|---|
| 443 / 80 | Nginx (HTTPS / redirect) | Externa |
| 8080 | Tomcat (Alfresco/Share) | **Localhost** (atrás do Nginx) |
| 8983 | Solr | Localhost |
| 8090 | Transform | Localhost |
| 61616 / 8161 | ActiveMQ | Localhost |
| 5432 | PostgreSQL | Localhost |

UFW libera apenas SSH + 80/443. Fail2ban protege o SSH. Comunicação repo↔Solr por *secret*.

---

## 7. Operação

```bash
# Status dos serviços
systemctl status alfresco-tomcat alfresco-search alfresco-transform alfresco-activemq postgresql

# Logs principais
tail -f /opt/alfresco/tomcat/logs/catalina.out
tail -f /opt/alfresco/search-services/logs/solr.log

# Backup manual / health check
sudo /usr/local/bin/alfresco-backup.sh
sudo /usr/local/bin/alfresco-healthcheck.sh

# Revalidar o ambiente
sudo bash 11-validacao.sh
```

---

## 8. Observações importantes (honestidade técnica)

- **Versões/URLs:** os artefatos Community ficam no **Nexus público da Alfresco** e podem
  exigir confirmação de caminho/versão exata no momento do deploy. As URLs em
  `00-variaveis.sh` são o ponto único de ajuste.
- **Assinatura A3 (token/smartcard):** a assinatura com token costuma ser **client-side**
  (a chave privada não sai do hardware). O servidor é preparado (`pcscd`/`opensc`/PKCS#11),
  mas a estratégia A3 (cliente vs. servidor com HSM) deve ser **fechada no survey** com a Cliente.
- **Assinatura A1 (arquivo):** suportada server-side via cofre `/opt/alfresco/certificados`.
- **Keystore de metadados:** troque as senhas padrão e **regere o keystore** antes da produção.
- Este roteiro entrega a **infraestrutura**; a **modelagem dos workflows** e a **configuração
  funcional da assinatura** são as etapas de consultoria descritas na proposta.
```
