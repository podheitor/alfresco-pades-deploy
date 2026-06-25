// =============================================================================
//  Captura automatica de prints do Alfresco Share (Playwright + Chromium)
//  Roda NO SERVIDOR Alfresco (acessa http://localhost:8080/share).
//  Config via env: BASE_URL, ALF_USER, ALF_PASS
// =============================================================================
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.BASE_URL || 'http://localhost:8080/share';
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

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    ignoreHTTPSErrors: true,
  });
  const page = await ctx.newPage();

  console.log('1) Tela de login...');
  await goto(page, `${BASE}/page/repository`);   // sem sessao -> redireciona p/ login
  await shot(page, '02-login', 'tela de login');

  console.log('2) Autenticando...');
  try {
    await page.fill('input[name="username"]', USER);
    await page.fill('input[name="password"]', PASS);
    await page.press('input[name="password"]', 'Enter');
    await wait(page, 6000);
  } catch (e) { console.log('  erro no login:', e.message); }

  console.log('3) Painel inicial (dashboard)...');
  await goto(page, `${BASE}/page/user/${encodeURIComponent(USER)}/dashboard`);
  await shot(page, '03-painel-inicial', 'painel do usuario');

  console.log('4) Repositorio (Company Home)...');
  await goto(page, `${BASE}/page/repository`);
  await shot(page, '05-repositorio', 'repositorio - raiz com as pastas');

  console.log('5) Pasta "A Assinar"...');
  try { await page.getByText('A Assinar', { exact: true }).first().click(); }
  catch (e) { console.log('  nao achei link A Assinar:', e.message); }
  await shot(page, '13-a-assinar', 'pasta A Assinar');

  console.log('6) Pasta "Assinados"...');
  await goto(page, `${BASE}/page/repository`);
  try { await page.getByText('Assinados', { exact: true }).first().click(); }
  catch (e) { console.log('  nao achei link Assinados:', e.message); }
  await shot(page, '13-assinados', 'pasta Assinados');

  console.log('7) Documento assinado (detalhe)...');
  try {
    await page.locator('a.filename, td a').filter({ hasText: /\.pdf/i }).first().click();
    await shot(page, '13-documento-assinado', 'pagina de detalhes do documento');
  } catch (e) { console.log('  sem documento p/ abrir:', e.message); }

  console.log('8) Busca...');
  await goto(page, `${BASE}/page/search?t=${encodeURIComponent('documento')}&all=true`);
  await shot(page, '10-busca', 'resultados de busca');

  console.log('9) Minhas tarefas...');
  await goto(page, `${BASE}/page/my-tasks`);
  await shot(page, '12-tarefas', 'minhas tarefas');

  console.log('10) Ferramentas de administracao...');
  await goto(page, `${BASE}/page/console/admin-console/application`);
  await shot(page, '99-admin', 'console de administracao');

  await browser.close();
  console.log('\nConcluido. PNGs em ./' + OUT + '/');
})();
