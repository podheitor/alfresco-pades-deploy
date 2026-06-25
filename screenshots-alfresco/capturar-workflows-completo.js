// =============================================================================
//  Captura COMPLETA das telas de workflow com DADOS REAIS (2o manual).
//  Cria um documento de teste e inicia 2 fluxos de verdade:
//   (1) Review And Approve (single reviewer) -> admin   [popula Minhas Tarefas]
//   (2) Review and Approve (pooled review)   -> grupo   [tarefa com "Reivindicar"]
//  Depois captura: 22 (minhas tarefas), 23 (detalhe da tarefa Aprovar/Rejeitar),
//                  24 (fluxos que iniciei), 25 (tarefa de grupo / Claim).
//  NAO mexe em 20/21/26/27 (ja bons).
//  Roda NO SERVIDOR, no mesmo dir do robo (Playwright ja instalado):
//     node capturar-workflows-completo.js
//  Env: BASE_URL (Share), REPO_URL (repo), ALF_USER, ALF_PASS, GROUP_QUERY
// =============================================================================
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.BASE_URL || 'http://localhost:8080/share';
const REPO = process.env.REPO_URL || 'http://localhost:8080/alfresco';
const USER = process.env.ALF_USER || 'admin';
const PASS = process.env.ALF_PASS || 'alfresco01';
const GROUP_QUERY = process.env.GROUP_QUERY || 'admin';   // busca de grupo p/ o pooled
const OUT  = 'prints';
const AUTH = 'Basic ' + Buffer.from(`${USER}:${PASS}`).toString('base64');

const wait = (p, ms = 3000) => p.waitForTimeout(ms);
async function shot(page, name, desc) {
  try { await wait(page); await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
    console.log(`  OK  ${name}.png  (${desc})`);
  } catch (e) { console.log(`  FALHOU ${name}.png  -> ${e.message}`); }
}
const norm = (id) => { id = String(id || '').split(';')[0]; return !id ? '' : (id.startsWith('workspace://') ? id : `workspace://SpacesStore/${id}`); };

// espera qualquer mascara/overlay do picker sumir (senao o clique no OK e interceptado)
async function waitMaskGone(page) {
  for (let i = 0; i < 24; i++) {
    const vis = await page.locator('.mask').evaluateAll(
      els => els.some(e => e.offsetParent !== null && getComputedStyle(e).display !== 'none')
    ).catch(() => false);
    if (!vis) return;
    await page.waitForTimeout(500);
  }
}

async function companyHome(ctx) {
  try {
    const r = await ctx.request.get(`${REPO}/s/slingshot/doclib/doclist/all/node/alfresco/company/home`,
      { headers: { Authorization: AUTH }, timeout: 20000 });
    const j = await r.json();
    return norm(j && j.metadata && j.metadata.parent && j.metadata.parent.nodeRef);
  } catch (e) { console.log('  erro companyHome:', e.message); return ''; }
}

// PDF minimo valido
function pdfBuf(titulo) {
  const body = `%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n` +
    `2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n` +
    `3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 200]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj\n` +
    `4 0 obj<</Length 60>>stream\nBT /F1 14 Tf 30 120 Td (${titulo}) Tj ET\nendstream endobj\n` +
    `5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n` +
    `trailer<</Root 1 0 R>>\n%%EOF\n`;
  return Buffer.from(body, 'latin1');
}

// Sobe um PDF no Company Home pela API do REPOSITORIO (sem CSRF do Share)
async function upload(ctx, dest, filename, titulo) {
  try {
    const r = await ctx.request.post(`${REPO}/s/api/upload`, {
      headers: { Authorization: AUTH },
      multipart: {
        filedata: { name: filename, mimeType: 'application/pdf', buffer: pdfBuf(titulo) },
        destination: dest, overwrite: 'false',
      }, timeout: 30000,
    });
    const t = await r.text();
    const m = t.match(/workspace:\/\/SpacesStore\/[0-9a-f-]+/);
    if (m) { console.log('  upload OK:', filename, '->', m[0]); return m[0]; }
    console.log('  upload sem nodeRef:', t.slice(0, 200));
  } catch (e) { console.log('  erro upload:', e.message); }
  return '';
}

// Abre o picker (botao "Selecionar"/"Select"), busca e adiciona a 1a autoridade, confirma.
// IMPORTANTE: a caixa de busca do dialogo e o input[type=text] imediatamente ANTES do
// botao "Pesquisar"/"Search" — escopo por XPath p/ nao cair no campo de busca do cabecalho.
async function pick(page, query) {
  await page.locator('button:has-text("Selecionar"), button:has-text("Select")').first().click({ timeout: 8000 });
  // ESCOPO: o dialogo visivel do picker (ha varios pickers no DOM; o de Itens fica oculto).
  // O container do picker tem id terminando em "-cntrl-picker".
  const dlg = page.locator('[id$="-cntrl-picker"]:visible').first();
  await dlg.waitFor({ state: 'visible', timeout: 10000 });
  await wait(page, 900);
  // caixa de busca = 1o input visivel dentro do dialogo
  const search = dlg.locator('input:visible').first();
  await search.click({ timeout: 8000 }).catch(() => {});
  await search.fill(query, { timeout: 8000 });
  await dlg.locator('[id$="searchButton"], button:has-text("Pesquisar"), button:has-text("Search")').first().click({ timeout: 6000 });
  await wait(page, 2500);
  await waitMaskGone(page);
  // adiciona o 1o resultado (icone "+") DENTRO do dialogo
  const add = dlg.locator('.addIcon, a.add-item, a[title="Adicionar"], a[title="Add"], .yui-dt-col-actions a').first();
  await add.waitFor({ state: 'visible', timeout: 10000 });
  await add.click({ timeout: 8000 });
  await wait(page, 1200);
  await waitMaskGone(page);
  // confirma
  const ok = dlg.locator('button:has-text("OK")').first();
  await ok.click({ timeout: 8000 })
    .catch(async () => { await page.locator('button:visible:has-text("OK")').first().click({ force: true, timeout: 5000 }); });
  await wait(page, 1500);
  await waitMaskGone(page);
}

async function startWorkflow(page, docRef, typeRegex, query, tag) {
  const url = docRef ? `${BASE}/page/start-workflow?nodeRef=${docRef}` : `${BASE}/page/start-workflow`;
  await page.goto(url, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await wait(page, 2500);
  // abre o seletor de tipo e escolhe
  await page.locator('button.dijitDownArrowButton, .workflow-definition button, button:has-text("select a workflow"), button:has-text("Please select")').first().click({ timeout: 6000 }).catch(() => {});
  await wait(page, 1200);
  await page.getByText(typeRegex).first().click({ timeout: 8000 });
  await wait(page, 2500);
  // mensagem
  const msg = page.locator('textarea').first();
  if (await msg.count()) await msg.fill(`Favor revisar o documento em anexo (${tag}).`).catch(() => {});
  // destinatario / grupo
  try { await pick(page, query); } catch (e) { console.log(`  [${tag}] picker falhou:`, e.message); await shot(page, `dbg-picker-${tag}`, 'debug picker'); }
  // inicia
  await page.locator('button:has-text("Start Workflow"), button:has-text("Iniciar fluxo")').first().click({ timeout: 8000 }).catch((e) => console.log(`  [${tag}] submit falhou:`, e.message));
  await wait(page, 4500);
  console.log(`  [${tag}] fluxo iniciado (ou tentativa).`);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, ignoreHTTPSErrors: true });
  const page = await ctx.newPage();

  console.log('0) Login...');
  await page.goto(`${BASE}/page/repository`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  try {
    await page.fill('input[name="username"]', USER);
    await page.fill('input[name="password"]', PASS);
    await page.press('input[name="password"]', 'Enter');
    await wait(page, 6000);
  } catch (e) { console.log('  (login):', e.message); }

  console.log('1) Company Home + upload do documento de teste...');
  const home = await companyHome(ctx);
  console.log('  Company Home:', home || '(vazio)');
  const docRef = home ? await upload(ctx, home, 'Contrato-Exemplo.pdf', 'Contrato de Exemplo') : '';

  console.log('2) Iniciando fluxo SINGLE REVIEWER (assignee = admin)...');
  await startWorkflow(page, docRef, /Review And Approve \(single reviewer\)|Revisar e Aprovar \(um (revisor|unico)/i, USER, 'single');

  console.log('3) Iniciando fluxo POOLED (grupo)...');
  await startWorkflow(page, docRef, /Review and Approve \(pooled review\)|Revisar e Aprovar \(.*pool/i, GROUP_QUERY, 'pooled');

  console.log('4) Minhas Tarefas (agora populada)...');
  await page.goto(`${BASE}/page/my-tasks`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await shot(page, '22-minhas-tarefas', 'minhas tarefas com itens');

  console.log('5) Detalhe da tarefa (Aprovar/Rejeitar)...');
  try {
    await page.locator('a[href*="task-edit"], a[href*="task-details"]').first().click({ timeout: 10000 });
    await wait(page, 3500);
  } catch (e) {
    console.log('  (sem tarefa p/ abrir):', e.message);
    await shot(page, 'dbg-mytasks', 'debug my-tasks vazia?');
  }
  await shot(page, '23-tarefa-detalhe', 'detalhe da tarefa');

  console.log('6) Fluxos que iniciei (populado)...');
  await page.goto(`${BASE}/page/my-workflows`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await shot(page, '24-fluxos-iniciei', 'fluxos iniciados ativos');

  console.log('7) Tarefa de grupo / Reivindicar...');
  await page.goto(`${BASE}/page/my-tasks`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await wait(page, 2500);
  // percorre as tarefas e captura a que tiver botao Reivindicar/Claim (= pooled nao assumida)
  try {
    const hrefs = await page.locator('a[href*="task-edit"]').evaluateAll(as => as.map(a => a.getAttribute('href')));
    let done = false;
    for (const h of (hrefs || []).slice(0, 5)) {
      if (!h) continue;
      const u = h.startsWith('http') ? h : `http://localhost:8080${h.startsWith('/') ? '' : '/'}${h}`;
      await page.goto(u, { waitUntil: 'load', timeout: 30000 }).catch(() => {});
      await wait(page, 2500);
      const claim = await page.locator('button:has-text("Reivindicar"), button:has-text("Claim"), button:has-text("Assumir")').count();
      if (claim) { await shot(page, '25-tarefa-grupo', 'tarefa de grupo (botao Reivindicar)'); done = true; break; }
    }
    if (!done) { console.log('  (nenhuma tarefa com Claim; capturando lista)'); await shot(page, '25-tarefa-grupo', 'my-tasks (pooled inline)'); }
  } catch (e) { console.log('  (25):', e.message); await shot(page, '25-tarefa-grupo', 'fallback'); }

  await browser.close();
  console.log('\nConcluido. Reveja prints/22,23,24,25 (+ dbg-* se houver).');
})();
