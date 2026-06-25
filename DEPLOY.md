# Runbook de Implantação — Cliente (Alfresco Community 23.2 + Assinatura PAdES)

Passo a passo para implantar do zero num servidor **Ubuntu Server 22.04 LTS**
limpo (10 vCPU / 24 GB / 2 TB, acesso root/sudo, internet liberada).

Três componentes, nesta ordem:
1. `deploy/` — plataforma Alfresco (ECM + workflow + busca + infra)
2. `alfresco-signer-service/` — microsserviço de assinatura PAdES (A1)
3. `alfresco-signer-integration/` — fluxo "A Assinar → Assinados" no Alfresco

---

## 0. Levar os arquivos para o servidor

Se tiver o tarball (`alfresco-deploy.tar.gz`):

```bash
cd /root
# (coloque o arquivo aqui por USB/share interno, ou wget do link temporario fornecido)
tar xzf alfresco-deploy.tar.gz
ls    # deploy/  alfresco-signer-service/  alfresco-signer-integration/
```

---

## 1. Plataforma Alfresco

```bash
cd /root/deploy

# 1.1 Editar os segredos e o hostname (OBRIGATORIO)
nano 00-variaveis.sh
#   DB_PASS=...                (openssl rand -base64 24)
#   ALF_ADMIN_PASS=...         senha do admin do Alfresco
#   SOLR_SHARED_SECRET=...     (openssl rand -base64 24)
#   ALF_HOSTNAME=...           dominio/IP de acesso

# 1.2 Implantar tudo (Java17, PostgreSQL, ActiveMQ, Transform, Solr/Java, Tomcat10.1, Alfresco, Nginx/TLS, backup)
sudo bash install-all.sh

# 1.3 Acompanhar o 1o boot (cria schema; varios minutos)
tail -f /opt/alfresco/tomcat/logs/catalina.out
#   aguarde: "Alfresco Content Services started"
```

Validação:

```bash
./11-validacao.sh
curl -s -o /dev/null -w "Repo: %{http_code}\n" \
  "http://localhost:8080/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-"
# Repo: 200  => plataforma OK.  Share: https://<ALF_HOSTNAME>/share/ (admin / sua senha)
```

> O `install-all.sh` já corrige tudo que custou caro: Tomcat 10.1 + overlay,
> diretórios `modules/`, keystore via `-D`, Solr em Java 17 + G1GC, NT hash do
> admin, WorkingDirectory dos logs, repositório de terceiros quebrado tolerado.

---

## 2. Microsserviço de assinatura PAdES

```bash
cd /root/alfresco-signer-service
sudo ./install-signer.sh        # instala Maven, compila, sobe na porta 8092 (localhost)
curl http://localhost:8092/health   # -> OK
```

Certificados ICP-Brasil (responsabilidade da Cliente):

```bash
# Depositar os A1 reais no cofre (dono alfresco, 600):
cp /caminho/CERT_DO_SIGNATARIO.p12 /opt/alfresco/certificados/
chown alfresco:alfresco /opt/alfresco/certificados/*.p12
chmod 600 /opt/alfresco/certificados/*.p12

# Importar a cadeia ICP-Brasil no truststore (validacao):
#   copie os .crt da cadeia em /opt/alfresco/certificados/cadeia-icpbrasil/ e rode:
cd /root/deploy && sudo ./08-assinatura-digital-pades.sh
```

---

## 3. Fluxo de assinatura no Alfresco

```bash
cd /root/alfresco-signer-integration

# 3.1 Config: senha do admin + certificado a usar
nano assinar-config.sh
#   ALF_ADMIN_PASS="<senha admin>"
#   SIGN_CERT="<arquivo.p12 do cofre>"   SIGN_PASS="<senha do A1>"
chmod 600 assinar-config.sh

# 3.2 Criar pastas "A Assinar" / "Assinados" no Alfresco
./assinar-alfresco.sh setup

# 3.3 Ligar o fluxo automatico (assina e move a cada 1 min)
sudo ./assinar-alfresco.sh enable-timer
```

Pronto: no Share (Repositório → Company Home), suba um PDF em **"A Assinar"** →
em até 1 min ele é assinado (PAdES) e movido para **"Assinados"**.

---

## 4. Pós-implantação (proposta)
- Modelar até 3 workflows BPMN (Activiti) com os usuários-chave da Cliente.
- Integrar LDAP/AD se aplicável (subsistema de autenticação).
- Definir A3 (client-side) no survey, se for usar token.
- Knowledge transfer + 30 dias de suporte (GLPI).

## 5. Operação
```bash
systemctl status alfresco-tomcat alfresco-search alfresco-transform alfresco-activemq alfresco-signer postgresql nginx
sudo /usr/local/bin/alfresco-backup.sh        # backup manual
journalctl -u alfresco-assinar -f             # log do fluxo de assinatura
```
