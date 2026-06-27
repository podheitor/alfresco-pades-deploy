# Módulo: Fluxo de Compras (workflow Activiti / BPMN)

Processo de compras como **workflow Activiti nativo** do Alfresco Community 23.2:
**Solicitação → Triagem → Cotação → (Avaliação técnica?) → Avaliação do Gestor
Imediato → Avaliação Financeira → Compra**, com os laços de retrabalho (devolução
por inconformidade e nova cotação). Sem infraestrutura extra — roda no engine
Activiti embarcado no ACS.

> Extraído de um projeto real e **generalizado**. Os setores e grupos são exemplos:
> **adapte a lista de setores e os grupos ao seu ambiente** (ver "Atribuição").

## Mapa do processo

```
 Solicitante ── Solicitar ─▶ [Compras] Triagem ─◇ conforme?
        ▲ não ── Ajustar ◀────────────────────────┘ sim
                                                     ▼
                              [Compras] Cotação ─◇ bem sucedida? ─ não ─▶ (fim)
                                   ▲                         │ sim
                                   │                         ▼
                                   │            ◇ necessita avaliação técnica?
                                   │           sim │                 │ não
                          (nova cotação)  [Solicitante] Avaliação    │
                                   │        técnica ─◇ aprovada?     │
                                   └── não ──────────┘ sim ──────────┤
                                                                     ▼
                          [Líder do setor] Avaliação ─◇ aprovada? ─ não ─▶ (fim)
                                                                     │ sim
                                                                     ▼
                          [Financeiro] Avaliação ─◇ aprovada? ─ não ─▶ (fim)
                                                                     │ sim
                                                                     ▼
                          [Compras] Realizar a compra ─▶ (concluído)
```

## Conteúdo

| Arquivo | Vai para | O que é |
|---|---|---|
| `platform/compras-fluxo.bpmn20.xml` | `…/shared/classes/alfresco/extension/` | Processo Activiti (BPMN 2.0). |
| `platform/compras-workflow-model.xml` | idem | Content/task model — campos dos formulários. |
| `platform/compras-workflow.properties` | idem | Rótulos (i18n). |
| `platform/compras-workflow-context.xml` | idem | Spring: registra modelo + implanta o processo. |
| `share/share-config-custom.xml` | `…/shared/classes/alfresco/web-extension/` | Formulários de cada tarefa (**mesclar** se já existir). |
| `install-compras-workflow.sh` | (roda no servidor) | Instala, reinicia e valida. |

## Atribuição (assignment)

- **Solicitante** = quem inicia o fluxo (`initiator`). Recebe também o "Ajustar" e a "Avaliação técnica".
- **Compras** = grupo **`GROUP_COMPRAS`** (tarefas pooled: triagem, cotação, compra).
- **Gestor Imediato** = **dinâmico**: o solicitante escolhe o **Setor** na abertura
  (campo `cpr:setorLider`), e a aprovação vai para o **grupo-líder daquele setor**
  via `activiti:candidateGroups="${cpr_setorLider}"`.
- **Gestor Financeiro** = grupo **`GROUP_FINANCEIRO`** (pooled).

### Adapte ao seu ambiente
A lista de setores é uma **constraint LIST** em `compras-workflow-model.xml`
(`cpr:setorList`), cujos **valores são os nomes dos grupos-líder** (autoridades
Alfresco, ex.: `GROUP_lider-operacional`), com rótulos amigáveis em
`compras-workflow.properties` (`listconstraint.cpr_setorList.<valor>=<rótulo>`).
Substitua os exemplos pelos **seus** setores/grupos. Os grupos podem vir do AD/LDAP
(ex.: um grupo por OU/cargo) ou ser criados no Alfresco. Garanta que cada
grupo-líder tenha ao menos um membro, senão a aprovação daquele setor fica sem
destinatário.

## Como as decisões funcionam (e 3 detalhes importantes)

Cada tarefa de decisão grava um booleano (`cpr:conforme`, `cpr:cotacaoBemSucedida`,
`cpr:aprovadaGestor`, …); os `exclusiveGateway` roteiam por `${cpr_<bool> == true}`.
O desfecho de cada tarefa é o botão **Task Done** (sem Aprovar/Rejeitar separados).

Para isso funcionar de forma robusta, o BPMN já trata 3 armadilhas conhecidas:
1. **Inicialização das variáveis de decisão** — `executionListener` no `startEvent`
   seta todas como `false`. Sem isso, o gateway lança
   `PropertyNotFoundException: Cannot resolve identifier 'cpr_conforme'` (HTTP 500
   ao concluir a tarefa).
2. **Promoção das decisões** — `taskListener event="complete"` em cada tarefa de
   decisão copia a variável da tarefa para o **processo**
   (`execution.setVariable(v, task.getVariableLocal(v))`). Sem isso, a propriedade
   do formulário fica local à tarefa e o gateway lê sempre o default.
3. **Formulário de abertura** — em `share-config-custom.xml`, o start-form é casado
   por `evaluator="string-compare" condition="activiti$comprasFluxo"` (pelo **nome
   do processo**), não por task-type. Sem isso, o formulário de início mostra
   **todos** os campos do modelo.

## Instalação

Transfira a pasta para o servidor e:

```bash
cd alfresco-compras-workflow
sudo ./install-compras-workflow.sh
```

Copia os arquivos, reinicia o `alfresco-tomcat` e confirma que o fluxo
**comprasFluxo** ficou registrado. Crie/garanta os grupos `GROUP_COMPRAS`,
`GROUP_FINANCEIRO` e os grupos-líder de cada setor (em **Admin Tools → Groups** ou
via sincronização AD/LDAP) e adicione os respectivos responsáveis.

### Validação

```bash
curl -s -u admin:SENHA "http://localhost:8080/alfresco/s/api/workflow-definitions" | grep -i compra
```

Depois, em **Share → Tarefas → Iniciar fluxo de trabalho**, selecione
**"Fluxo de Compras"**, escolha o **Setor**, anexe a solicitação/cotação e percorra
as etapas.

## Notas / simplificações

- O "Devolver solicitação por inconformidades" foi modelado como o **resultado da
  triagem** (`conforme=false` + motivo) que devolve ao solicitante na tarefa
  **Ajustar**.
- "Solicitar nova cotação" (técnica reprovada) **volta direto** para a tarefa de
  **Cotação**, com o parecer técnico visível.
- Em produção, considere remover `redeploy=true` do `*-context.xml` quando o
  processo estabilizar.
