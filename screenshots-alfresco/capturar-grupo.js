// =============================================================================
//  Recaptura SO a tela 25 (tarefa de grupo / Reivindicar). Reaproveita a tarefa
//  pooled ja criada pelo capturar-workflows-completo.js (NAO cria novos fluxos).
//  A tarefa de pool nao assumida aparece sob o filtro "Unassigned" de Minhas
//  Tarefas; ao abri-la, a pagina mostra o botao Reivindicar/Claim.
//    node capturar-grupo.js
// =============================================================================
const { chromium } = require('playwright');
const fs = require('fs');
const BASE = process.env.BASE_URL || 'http://localhost:8080/share';
const USER = process.env.ALF_USER || 'admin';
const PASS = process.env.ALF_PASS || 'alfresco01';
const OUT  = 'prints';
const wait = (p, ms = 3000) => p.waitForTimeout(ms);
async function shot(page, name, desc) {
  try { await wait(page); await page.screenshot({ path: `${OUT}/${name}.png`, fullPage: true });
    console.log(`  OK  ${name}.png  (${desc})`); } catch (e) { console.log(`  FALHOU ${name}: ${e.message}`); }
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

  console.log('1) Minhas Tarefas -> filtro "Unassigned" (pool)...');
  await page.goto(`${BASE}/page/my-tasks`, { waitUntil: 'load', timeout: 45000 }).catch(() => {});
  await wait(page, 2500);
  try {
    await page.locator('a:has-text("Unassigned"), a:has-text("Não atribuídas"), a:has-text("Nao atribuidas")').first().click({ timeout: 8000 });
    await wait(page, 3000);
  } catch (e) { console.log('  (sem filtro Unassigned):', e.message); }
  // captura a LISTA de pool (ja mostra a acao de reivindicar inline)
  await shot(page, '25-tarefa-grupo', 'lista de tarefas de grupo (pool)');

  console.log('2) Abrindo a tarefa de pool (mostra botao Reivindicar/Claim)...');
  try {
    await page.locator('a[href*="task-edit"], a[href*="task-details"]').first().click({ timeout: 8000 });
    await wait(page, 3500);
    // so sobrescreve se houver botao Reivindicar/Claim VISIVEL
    const claim = page.locator('button:visible:has-text("Reivindicar"), button:visible:has-text("Claim"), button:visible:has-text("Assumir")');
    if (await claim.count()) {
      await shot(page, '25-tarefa-grupo', 'tarefa de grupo aberta (botao Reivindicar)');
    } else {
      console.log('  (sem botao Claim visivel; mantida a lista de pool em 25)');
    }
  } catch (e) { console.log('  (nao abriu tarefa de pool):', e.message); }

  await browser.close();
  console.log('\nConcluido. Reveja prints/25-tarefa-grupo.png');
})();
