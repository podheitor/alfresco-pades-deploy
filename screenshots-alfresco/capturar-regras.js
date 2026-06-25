// =============================================================================
//  Recaptura SOMENTE as telas de Regras de pasta (26/27) do 2o manual.
//  O robo principal falhou nelas por usar um nodeRef invalido; aqui buscamos
//  o nodeRef real do Company Home via CMIS (browser binding) e abrimos a tela
//  de Gerenciar Regras + o editor de nova regra.
//  Roda NO SERVIDOR (mesmo dir do robo principal, ja com Playwright instalado).
//    node capturar-regras.js
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
  } catch (e) { console.log(`  FALHOU ${name}.png  -> ${e.message}`); }
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 1000 }, ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  const auth = 'Basic ' + Buffer.from(`${USER}:${PASS}`).toString('base64');

  console.log('0) Login no Share...');
  await page.goto(`${BASE}/page/repository`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  try {
    await page.fill('input[name="username"]', USER);
    await page.fill('input[name="password"]', PASS);
    await page.press('input[name="password"]', 'Enter');
    await wait(page, 6000);
  } catch (e) { console.log('  (login):', e.message); }

  console.log('1) Descobrindo o nodeRef do Company Home...');
  let nodeRef = '';
  const norm = (id) => {
    id = String(id || '').split(';')[0];
    if (!id) return '';
    return id.startsWith('workspace://') ? id : `workspace://SpacesStore/${id}`;
  };

  // Fonte A: doclist do Company Home -> metadata.parent.nodeRef
  try {
    const r = await ctx.request.get(
      `${REPO}/s/slingshot/doclib/doclist/all/node/alfresco/company/home`,
      { headers: { Authorization: auth }, timeout: 20000 });
    const j = await r.json();
    nodeRef = norm(j && j.metadata && j.metadata.parent && j.metadata.parent.nodeRef);
    if (nodeRef) console.log('  [A doclist] nodeRef:', nodeRef);
    else console.log('  [A doclist] sem parent.nodeRef. keys:', JSON.stringify(Object.keys(j || {})));
  } catch (e) { console.log('  [A doclist] erro:', e.message); }

  // Fonte B: CMIS browser binding (cmisselector=object)
  if (!nodeRef) try {
    const r = await ctx.request.get(
      `${REPO}/api/-default-/public/cmis/versions/1.1/browser/root?cmisselector=object`,
      { headers: { Authorization: auth }, timeout: 20000 });
    const j = await r.json();
    let id = (j.properties && j.properties['cmis:objectId'] && j.properties['cmis:objectId'].value)
          || (j.succinctProperties && j.succinctProperties['cmis:objectId']) || '';
    nodeRef = norm(id);
    if (nodeRef) console.log('  [B cmis] nodeRef:', nodeRef);
    else console.log('  [B cmis] sem objectId. amostra:', JSON.stringify(j).slice(0, 240));
  } catch (e) { console.log('  [B cmis] erro:', e.message); }

  // Fonte C: treenode -> usa a 1a pasta filha do Company Home (qualquer pasta serve p/ ilustrar Regras)
  if (!nodeRef) try {
    const r = await ctx.request.get(
      `${REPO}/s/slingshot/doclib/treenode/node/alfresco/company/home?children=true`,
      { headers: { Authorization: auth }, timeout: 20000 });
    const j = await r.json();
    const it = (j && j.items && j.items[0]) || null;
    nodeRef = norm(it && it.nodeRef);
    if (nodeRef) console.log('  [C treenode] usando pasta filha:', it && it.name, nodeRef);
    else console.log('  [C treenode] amostra:', JSON.stringify(j).slice(0, 240));
  } catch (e) { console.log('  [C treenode] erro:', e.message); }

  if (!nodeRef) { console.log('  ABORTANDO: sem nodeRef por nenhuma fonte.'); await browser.close(); return; }

  console.log('2) Tela Gerenciar Regras...');
  // nodeRef cru (sem url-encode) e como o proprio Share monta o parametro
  await page.goto(`${BASE}/page/folder-rules?nodeRef=${nodeRef}`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await shot(page, '26-gerenciar-regras', 'gerenciar regras (estado inicial)');

  console.log('3) Editor de nova regra...');
  try {
    await page.locator(
      'button:has-text("Criar regra"), a:has-text("Criar regra"), button:has-text("Criar regras"), ' +
      'a:has-text("Criar regras"), button:has-text("Create Rule"), a:has-text("Create Rule"), ' +
      'button:has-text("Create Rules"), a:has-text("Create Rules")'
    ).first().click({ timeout: 7000 });
    await wait(page, 4000);
  } catch (e) { console.log('  (botao criar regra nao encontrado):', e.message); }
  await shot(page, '27-regra-editor', 'editor de regra (When/If/Action)');

  await browser.close();
  console.log('\nConcluido. Reveja prints/26-*.png e prints/27-*.png');
})();
