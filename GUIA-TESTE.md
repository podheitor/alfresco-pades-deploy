# Guia de Testes de Aceitação — Plataforma Alfresco + Assinatura Digital

**Cliente:** Cliente  ·  **Fornecedor:** OpenTechs  ·  **Proposta:** 

Este guia orienta a equipe da Cliente a validar o ambiente entregue: acesso, funções
de gestão de documentos (ECM), busca, e assinatura digital PAdES (ICP-Brasil).

---

## 1. Como acessar

| O quê | Endereço |
|---|---|
| Interface principal (Alfresco Share) | **https://SEU_SERVIDOR_IP/share/** |
| (alternativo, sem HTTPS) | http://SEU_SERVIDOR_IP:8080/share/ |
| Usuário administrador | **admin** |
| Senha | **SUA_SENHA_ADMIN** |

> Recomendado trocar a senha do `admin` após os testes de aceitação.

> No primeiro acesso o navegador pode alertar sobre o certificado TLS
> (autoassinado de homologação). É esperado — substituível pelo certificado
> oficial da Cliente quando disponível.

---

## 2. Portas e serviços (para a equipe de TI)

| Porta | Serviço | Exposição |
|---|---|---|
| **443 / 80** | Acesso web (HTTPS / redireciona) | Externa (rede da Cliente) |
| 8080 | Alfresco/Share (Tomcat) | Interna (atrás do proxy) |
| 8983 | Solr (busca/indexação) | Interna (localhost) |
| 8090 | Serviço de conversão de documentos | Interna (localhost) |
| 8092 | Serviço de assinatura digital PAdES | Interna (localhost) |
| 61616 | Mensageria (ActiveMQ) | Interna (localhost) |
| 5432 | Banco de dados (PostgreSQL) | Interna (localhost) |

Apenas **80/443 e SSH** ficam acessíveis na rede; o restante só responde
localmente, por segurança. Firewall (UFW) e proteção de SSH (fail2ban) ativos.

---

## 3. Testes de gestão de documentos (ECM)

Faça login no Share como **admin** e valide:

1. **Criar um Site** — menu superior *Sites → Criar Site* (ex.: "Documentos Cliente").
2. **Upload de documento** — entre no site → *Biblioteca de Documentos* →
   *Carregar* → selecione um arquivo (PDF, Word, Excel).
3. **Pré-visualização** — clique no documento; ele deve abrir o preview no
   navegador (validação do serviço de conversão).
4. **Versionamento** — *Carregar Nova Versão* sobre um documento existente e
   confira o histórico de versões.
5. **Metadados/propriedades** — *Editar Propriedades* (título, descrição, tags).
6. **Busca** — use a busca no topo por nome **e por conteúdo** (digite uma
   palavra que esteja dentro do PDF). Os resultados validam o Solr.
7. **Permissões** — convide/!crie um usuário e teste compartilhamento e acesso.

---

## 4. Teste da assinatura digital (PAdES / ICP-Brasil)

O fluxo é por pasta: documento colocado em **"A Assinar"** é assinado
automaticamente e movido para **"Assinados"**.

### Passo a passo (no Share)
1. Vá em *Repositório* → **Company Home**. Existem as pastas **"A Assinar"** e
   **"Assinados"**.
2. Faça **upload de um PDF** dentro de **"A Assinar"**.
3. Aguarde até ~1 minuto.
4. Atualize a tela: o PDF **sai de "A Assinar"** e **aparece em "Assinados"** —
   agora assinado digitalmente (PAdES).

### Como comprovar a validade jurídica
- Baixe o PDF assinado da pasta "Assinados".
- Abra no **Adobe Reader** (mostra o painel de assinaturas) **ou** valide no
  **Verificador oficial do ITI**: **https://validar.iti.gov.br**
- Com um certificado **A1 ICP-Brasil real**, a validação confirma o signatário,
  a integridade e a conformidade ICP-Brasil. (Em homologação, usando um
  certificado de teste, a assinatura aparece como íntegra porém "não confiável" —
  comportamento esperado por não ser um certificado ICP real.)

> Os certificados A1 (.p12) dos signatários ficam num cofre protegido no servidor
> (`/opt/alfresco/certificados`), acessível somente pela conta de serviço.

---

## 5. Verificação de saúde (equipe de TI)

```bash
# Todos os serviços devem estar "active"
systemctl status alfresco-tomcat alfresco-search alfresco-transform \
                 alfresco-activemq alfresco-signer postgresql nginx

# Repositório pronto (deve responder 200)
curl -s -o /dev/null -w "Repo: %{http_code}\n" \
  "http://localhost:8080/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-"

# Serviço de assinatura (deve responder OK)
curl -s http://localhost:8092/health

# Log do fluxo de assinatura
journalctl -u alfresco-assinar -f
```

---

## 6. Backup e suporte

- **Backup diário automático** às 02:00 (banco + documentos + configurações),
  com retenção de 7 dias. Backup manual: `sudo /usr/local/bin/alfresco-backup.sh`.
- **Monitoramento** básico de saúde a cada 5 minutos (reinício automático de
  serviço que cair).
- **Suporte pós go-live:** 30 dias corridos, em horário comercial, via abertura
  de chamados (GLPI) e VPN quando autorizado.

---

## 7. Próximas etapas (consultoria — proposta)

- Modelagem de até **3 workflows BPMN** com os usuários-chave da Cliente.
- Integração com **LDAP/Active Directory** (se desejado).
- Definição da assinatura **A3 (token/cartão)** — feita no equipamento do
  usuário (client-side) — conforme necessidade.
- **Transferência de conhecimento** à equipe de TI da Cliente.

---

*Dúvidas técnicas: Heitor Medrado de Faria — OpenTechs.*
