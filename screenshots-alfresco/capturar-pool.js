// =============================================================================
//  Cria UM fluxo pooled atribuido ao grupo ALFRESCO_ADMINISTRATORS (do qual o
//  admin e membro) e captura a tela 25: a tarefa de grupo sob o filtro
//  "Unassigned" + a pagina da tarefa com o botao Reivindicar/Claim.
//    node capturar-pool.js
//  Env: BASE_URL, REPO_URL, ALF_USER, ALF_PASS, GROUP_QUERY
// =============================================================================
const { chromium } = require('playwright');
const fs = require('fs');
const BASE = process.env.BASE_URL || 'http://localhost:8080/share';
const REPO = process.env.REPO_URL || 'http://localhost:8080/alfresco';
const USER = process.env.ALF_USER || 'admin';
const PASS = process.env.ALF_PASS || 'alfresco01';
const GROUP_QUERY = process.env.GROUP_QUERY || 'ALFRESCO_ADMINISTRATORS';
const OUT  = 'prints';
const AUTH = 'Basic ' + Buffer.from(`${USER}:${PASS}`).toString('base64');
const wait = (p, ms = 3000) => p.waitForTimeout(ms);
async function shot(page, name, desc) {
  try { await wait(page); await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
    console.log(`  OK  ${name}.png  (${desc})`); } catch (e) { console.log(`  FALHOU ${name}: ${e.message}`); }
}
const norm = (id) => { id = String(id || '').split(';')[0]; return !id ? '' : (id.startsWith('workspace://') ? id : `workspace://SpacesStore/${id}`); };
async function waitMaskGone(page) {
  for (let i = 0; i < 24; i++) {
    const vis = await page.locator('.mask').evaluateAll(els => els.some(e => e.offsetParent !== null && getComputedStyle(e).display !== 'none')).catch(() => false);
    if (!vis) return; await page.waitForTimeout(500);
  }
}
async function companyHome(ctx) {
  try {
    const r = await ctx.request.get(`${REPO}/s/slingshot/doclib/doclist/all/node/alfresco/company/home`, { headers: { Authorization: AUTH }, timeout: 20000 });
    const j = await r.json(); return norm(j && j.metadata && j.metadata.parent && j.metadata.parent.nodeRef);
  } catch (e) { return ''; }
}
function pdfBuf(t) {
  return Buffer.from(`%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n`, 'latin1');
}
async function upload(ctx, dest) {
  try {
    const r = await ctx.request.post(`${REPO}/s/api/upload`, { headers: { Authorization: AUTH },
      multipart: { filedata: { name: 'Contrato-Pool.pdf', mimeType: 'application/pdf', buffer: pdfBuf('x') }, destination: dest, overwrite: 'false' }, timeout: 30000 });
    const m = (await r.text()).match(/workspace:\/\/SpacesStore\/[0-9a-f-]+/); return m ? m[0] : '';
  } catch (e) { return ''; }
}
// seleciona a 1a autoridade (escopo no dialogo visivel do picker)
async function pick(page, query) {
  await page.locator('button:has-text("Selecionar"), button:has-text("Select")').first().click({ timeout: 8000 });
  const dlg = page.locator('[id$="-cntrl-picker"]:visible').first();
  await dlg.waitFor({ state: 'visible', timeout: 10000 }); await wait(page, 900);
  const search = dlg.locator('input:visible').first();
  await search.click({ timeout: 8000 }).catch(() => {});
  await search.fill(query, { timeout: 8000 });
  await dlg.locator('[id$="searchButton"], button:has-text("Pesquisar"), button:has-text("Search")').first().click({ timeout: 6000 });
  await wait(page, 2500); await waitMaskGone(page);
  const add = dlg.locator('.addIcon, a.add-item, a[title="Adicionar"], a[title="Add"], .yui-dt-col-actions a').first();
  await add.waitFor({ state: 'visible', timeout: 10000 }); await add.click({ timeout: 8000 });
  await wait(page, 1200); await waitMaskGone(page);
  const ok = dlg.locator('button:has-text("OK")').first();
  await ok.click({ timeout: 8000 }).catch(async () => { await page.locator('button:visible:has-text("OK")').first().click({ force: true, timeout: 5000 }); });
  await wait(page, 1500); await waitMaskGone(page);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, ignoreHTTPSErrors: true });
  const page = await ctx.newPage();

  console.log('0) Login...');
  await page.goto(`${BASE}/page/repository`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  try { await page.fill('input[name="username"]', USER); await page.fill('input[name="password"]', PASS); await page.press('input[name="password"]', 'Enter'); await wait(page, 6000); } catch (e) {}

  console.log('1) Doc de teste...');
  const home = await companyHome(ctx);
  const docRef = home ? await upload(ctx, home) : '';
  console.log('  docRef:', docRef || '(sem doc, segue assim mesmo)');

  console.log(`2) Iniciando fluxo POOLED -> grupo "${GROUP_QUERY}"...`);
  const url = docRef ? `${BASE}/page/start-workflow?nodeRef=${docRef}` : `${BASE}/page/start-workflow`;
  await page.goto(url, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await wait(page, 2500);
  await page.locator('button.dijitDownArrowButton, .workflow-definition button, button:has-text("Please select")').first().click({ timeout: 6000 }).catch(() => {});
  await wait(page, 1000);
  await page.getByText(/Review and Approve \(pooled review\)/i).first().click({ timeout: 8000 });
  await wait(page, 2500);
  const msg = page.locator('textarea').first();
  if (await msg.count()) await msg.fill('Favor revisar o documento (tarefa de grupo / pool).').catch(() => {});
  try { await pick(page, GROUP_QUERY); }
  catch (e) { console.log('  picker falhou:', e.message); await shot(page, 'dbg-pool-picker', 'debug'); }
  await page.locator('button:has-text("Start Workflow"), button:has-text("Iniciar fluxo")').first().click({ timeout: 8000 }).catch(e => console.log('  submit:', e.message));
  await wait(page, 4500);
  console.log('  fluxo pooled iniciado (ou tentativa).');

  console.log('3) Minhas Tarefas -> Unassigned...');
  await page.goto(`${BASE}/page/my-tasks`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await wait(page, 2500);
  await page.locator('a:has-text("Unassigned"), a:has-text("Não atribuídas")').first().click({ timeout: 8000 }).catch(() => {});
  await wait(page, 3000);
  await shot(page, '25-tarefa-grupo', 'lista de tarefas de grupo (pool, Unassigned)');

  console.log('4) Abrindo a tarefa de pool (botao Reivindicar)...');
  try {
    await page.locator('a[href*="task-edit"], a[href*="task-details"]').first().click({ timeout: 8000 });
    await wait(page, 3500);
    const claim = page.locator('button:visible:has-text("Reivindicar"), button:visible:has-text("Claim"), button:visible:has-text("Assumir")');
    if (await claim.count()) await shot(page, '25-tarefa-grupo', 'tarefa de pool aberta (botao Reivindicar)');
    else console.log('  (sem botao Claim visivel; mantida a lista Unassigned em 25)');
  } catch (e) { console.log('  (nao abriu):', e.message); }

  await browser.close();
  console.log('\nConcluido. Reveja prints/25-tarefa-grupo.png (+ dbg-pool-picker se houver).');
})();
