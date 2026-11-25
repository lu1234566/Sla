// Uso: node tools/screenshot.cjs <url> <saida.png> [largura] [altura]
// Abre a URL no Chromium headless, espera document.title === 'done' e salva um screenshot.
const { chromium } = require('playwright');
(async () => {
  const [, , url, out, w = '1200', h = '900'] = process.argv;
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: +w, height: +h } });
  page.on('console', (m) => { if (m.type() === 'error') console.log('console.error:', m.text()); });
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  await page.goto(url);
  await page.waitForFunction(() => document.title === 'done', null, { timeout: 180000 });
  await page.screenshot({ path: out, fullPage: true });
  await browser.close();
})();
