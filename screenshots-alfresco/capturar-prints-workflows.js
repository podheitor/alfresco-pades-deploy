// =============================================================================
//  Captura automatica de prints de WORKFLOWS do Alfresco Share
//  (Playwright + Chromium). Roda NO SERVIDOR Alfresco (http://localhost:8080).
//  Companion do capturar-prints.js (1o manual). Gera as telas do 2o manual:
//  fluxos de trabalho (iniciar, tarefas, fluxos iniciados, regras de pasta).
//
//  Config via env: BASE_URL (Share), REPO_URL (repositorio), ALF_USER, ALF_PASS
//
//  Para popular "Minhas tarefas" e "Fluxos que iniciei", o robo cria um
//  documento de teste e inicia um fluxo "Revisar e Aprovar" atribuido ao admin.
// =============================================================================
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.BASE_URL || 'http://localhost:8080/share';
const REPO = process.env.REPO_URL || 'http://localhost:8080/alfresco';
const USER = process.env.ALF_USER || 'admin';
const PASS = process.env.ALF_PASS || 'alfresco01';
const OUT  = 'prints';

const wait = (p, ms = 3500) => p.waitForTimeout(ms);

async function shot(page, name, desc) {
  try {
    await wait(page);
    await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
    console.log(`  OK  ${name}.png  (${desc})`);
  } catch (e) {
    console.log(`  FALHOU ${name}.png  -> ${e.message}`);
  }
}

async function goto(page, url) {
  try { await page.goto(url, { waitUntil: 'load', timeout: 45000 }); }
  catch (e) { console.log(`  aviso goto ${url}: ${e.message}`); }
}

// Cria um PDF minimo e o envia ao Company Home via API REST do repositorio,
// devolvendo o nodeRef (para iniciar o fluxo em cima dele).
async function criarDocTeste(ctx) {
  const auth = 'Basic ' + Buffer.from(`${USER}:${PASS}`).toString('base64');
  const pdf = Buffer.from(
    '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n' +
    'trailer<</Root 1 0 R>>\n%%EOF\n', 'latin1');
  try {
    // upload multipart para a pasta raiz (Company Home) via API Share proxy
    const form = {
      filedata: { name: 'Contrato-Exemplo.pdf', mimeType: 'application/pdf', buffer: pdf },
      siteid: '', containerid: '', uploaddirectory: '/',
      destination: 'workspace://SpacesStore/',  // sera resolvido p/ Company Home se vazio
    };
    const resp = await ctx.request.post(`${BASE}/proxy/alfresco/api/upload`, {
      headers: { Authorization: auth },
      multipart: form,
      timeout: 30000,
    });
    const txt = await resp.text();
    const m = txt.match(/workspace:\/\/SpacesStore\/[0-9a-f-]+/);
    if (m) { console.log('  doc de teste criado:', m[0]); return m[0]; }
    console.log('  upload sem nodeRef claro:', txt.slice(0, 160));
  } catch (e) { console.log('  aviso ao criar doc de teste:', e.message); }
  return null;
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    ignoreHTTPSErrors: true,
  });
  const page = await ctx.newPage();

  console.log('0) Login...');
  await goto(page, `${BASE}/page/repository`);
  try {
    await page.fill('input[name="username"]', USER);
    await page.fill('input[name="password"]', PASS);
    await page.press('input[name="password"]', 'Enter');
    await wait(page, 6000);
  } catch (e) { console.log('  (ja logado ou erro):', e.message); }

  console.log('1) Preparando documento de teste...');
  const nodeRef = await criarDocTeste(ctx);

  console.log('2) Tela "Iniciar fluxo de trabalho" (selecao de tipo)...');
  const swUrl = nodeRef
    ? `${BASE}/page/start-workflow?nodeRef=${encodeURIComponent(nodeRef)}`
    : `${BASE}/page/start-workflow`;
  await goto(page, swUrl);
  // abre o seletor de tipos de fluxo
  try {
    await wait(page, 2500);
    await page.locator('button:has-text("fluxo"), button:has-text("Workflow"), .workflow-selection button').first().click({ timeout: 5000 });
  } catch (e) { console.log('  (seletor de tipo nao abriu automaticamente)'); }
  await shot(page, '20-iniciar-fluxo-menu', 'selecao do tipo de fluxo');

  console.log('3) Formulario do fluxo (Revisar e Aprovar)...');
  // tenta escolher "Review And Approve" e preencher a mensagem
  try {
    await page.getByText(/Revisar e Aprovar|Review And Approve/i).first().click({ timeout: 5000 });
    await wait(page, 2500);
    const msg = page.locator('textarea').first();
    if (await msg.count()) await msg.fill('Favor revisar o contrato em anexo ate sexta-feira.');
  } catch (e) { console.log('  (nao consegui selecionar/preencher o tipo):', e.message); }
  await shot(page, '21-iniciar-fluxo-form', 'formulario de inicio de fluxo preenchido');

  // de fato inicia o fluxo (assignee = admin) para popular as proximas telas
  console.log('4) Iniciando o fluxo (para popular tarefas)...');
  try {
    // seletor de destinatario -> admin
    await page.locator('button:has-text("Selecionar"), button:has-text("Select")').first().click({ timeout: 4000 });
    await wait(page, 1500);
    await page.locator('input[type="text"]').last().fill(USER);
    await page.keyboard.press('Enter');
    await wait(page, 2500);
    await page.locator('button:has-text("Adicionar"), button:has-text("Add"), .add-button').first().click({ timeout: 4000 });
    await page.locator('button:has-text("OK")').first().click({ timeout: 4000 });
    await wait(page, 1500);
    await page.locator('button:has-text("Iniciar"), button:has-text("Start Workflow")').first().click({ timeout: 4000 });
    await wait(page, 4000);
    console.log('  fluxo iniciado (ou tentativa concluida).');
  } catch (e) { console.log('  (inicio automatico falhou, seguindo):', e.message); }

  console.log('5) Minhas tarefas...');
  await goto(page, `${BASE}/page/my-tasks`);
  await shot(page, '22-minhas-tarefas', 'minhas tarefas (pendentes)');

  console.log('6) Detalhe de uma tarefa (Aprovar/Rejeitar)...');
  try {
    await page.locator('a:has-text("Revisar"), a:has-text("Tarefa"), .task-title a').first().click({ timeout: 5000 });
    await wait(page, 3000);
  } catch (e) { console.log('  (sem tarefa para abrir):', e.message); }
  await shot(page, '23-tarefa-detalhe', 'detalhe da tarefa com botoes Aprovar/Rejeitar');

  console.log('7) Fluxos de trabalho que iniciei...');
  await goto(page, `${BASE}/page/my-workflows`);
  await shot(page, '24-fluxos-iniciei', 'fluxos de trabalho que iniciei');

  console.log('8) Gerenciar regras (Company Home)...');
  // pagina de regras de pasta; sem nodeRef abre o gerenciador a partir do repo
  await goto(page, `${BASE}/page/repository`);
  await wait(page, 2500);
  try {
    // abre o gerenciador de regras da raiz via URL direta se tivermos um nodeRef de pasta
    await goto(page, `${BASE}/page/folder-rules?nodeRef=workspace://SpacesStore/`);
    await wait(page, 2500);
  } catch (e) { /* ignore */ }
  await shot(page, '26-gerenciar-regras', 'tela Gerenciar regras');

  console.log('9) Editor de nova regra...');
  try {
    await page.locator('button:has-text("Criar regra"), a:has-text("Criar regra"), button:has-text("Create Rules")').first().click({ timeout: 5000 });
    await wait(page, 3000);
  } catch (e) { console.log('  (botao criar regra nao encontrado):', e.message); }
  await shot(page, '27-regra-editor', 'editor de regra (acao Iniciar fluxo)');

  await browser.close();
  console.log('\nConcluido. PNGs de workflows em ./' + OUT + '/');
  console.log('Copie 20*/21*/22*/23*/24*/26*/27* para ../images/ e revise os enquadramentos.');
})();
