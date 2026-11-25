// Uso: node tools/shot.cjs <url> <saida.png> [espera_ms] [script_js]
// Abre o jogo, espera, opcionalmente executa um script na página e salva screenshot.
const { chromium } = require('playwright');
(async () => {
  const [, , url, out, wait = '4000', script = ''] = process.argv;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) console.log(`console.${m.type()}:`, m.text().slice(0, 300)); });
  page.on('pageerror', (e) => console.log('pageerror:', e.message, e.stack?.split('\n').slice(0, 3).join(' | ')));
  await page.goto(url);
  await page.waitForTimeout(+wait);
  if (script) console.log('script ->', JSON.stringify(await page.evaluate(script)).slice(0, 1500));
  await page.waitForTimeout(800);
  await page.screenshot({ path: out });
  await browser.close();
})();
