// Teste ponta a ponta: joga a fatia vertical inteira num Chromium real.
// Uso: npm run dev (ou preview) em outro terminal, depois
//   node tests/e2e/smoke.mjs [url] [pasta_de_screenshots]
// Usa entrada de teclado real para andar, saltar, planar, escanear, alternar a
// maré e interagir; usa teleporte (window.__mdv) só para encurtar travessias.
import { createRequire } from 'node:module';
import fs from 'node:fs';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }

const URL = process.argv[2] || 'http://127.0.0.1:5173/?quality=low';
const SHOTS = process.argv[3] || null;
if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });

const results = [];
const check = (name, ok, info = '') => { results.push({ name, ok, info }); console.log(`${ok ? '✔' : '✘'} ${name}${info ? ' — ' + info : ''}`); };

const browser = await chromium.launch({ args: ['--use-gl=angle', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error' && !/favicon|fonts\.g/.test(m.text())) errors.push(m.text()); });

const g = (fn, arg) => page.evaluate(fn, arg);
const state = () => g(() => {
  const m = window.__mdv;
  const p = m.player.pos;
  return { mode: m.mode, x: p.x, y: p.y, z: p.z, area: m.area, obj: m.objective, tide: m.tide.state, lvl: m.tide.level, world: m.world, integrity: m.integrity, falls: m.stats.falls, guard: m.guardian.state, grounded: m.player.body.grounded, resp: m.respawning };
});
async function waitFor(pred, timeout = 20000, label = '') {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const s = await state();
    if (pred(s)) return s;
    await page.waitForTimeout(100);
  }
  const s = await state();
  console.log(`  (timeout ${label})`, JSON.stringify({ ...s, world: undefined }));
  return null;
}
const teleport = (x, y, z, yaw = Math.PI) => g(([x, y, z, yaw]) => {
  const m = window.__mdv;
  m.player.teleport({ x, y, z }, yaw);
  m.camRig.snapBehind(yaw);
  m.lume.place({ x: x + 0.8, y: y + 1.9, z });
}, [x, y, z, yaw]);
const shot = async (name) => { if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png` }); };
const hold = async (key, ms) => { await page.keyboard.down(key); await page.waitForTimeout(ms); await page.keyboard.up(key); };
/** Segura uma tecla até a condição (em tempo de jogo) ou timeout. */
async function holdUntil(key, pred, timeout = 15000, label = '') {
  await page.keyboard.down(key);
  const s = await waitFor(pred, timeout, label);
  await page.keyboard.up(key);
  return s;
}
const press = (key) => page.keyboard.press(key);

try {
  await page.goto(URL);
  await page.waitForFunction(() => window.__mdv && window.__mdv.mode === 'menu', null, { timeout: 120000 });
  check('carrega e mostra o menu', true);
  const fps = await g(() => new Promise((res) => { const t0 = performance.now(); let n = 0; const f = () => { n++; if (performance.now() - t0 < 2000) requestAnimationFrame(f); else res(n / 2); }; requestAnimationFrame(f); }));
  console.log(`  fps no navegador de teste: ${fps.toFixed(1)}`);
  await shot('01-menu');

  // limpa saves anteriores e inicia
  await g(() => { window.__mdv.saves.clear(); window.__mdv.newGame(true); });
  let s = await waitFor((x) => x.mode === 'play' && x.grounded, 10000, 'start');
  check('novo jogo começa na chegada', !!s && s.area === 'chegada' && s.obj === 'reach_cistern', s && `${s.area} / ${s.obj}`);
  await shot('02-chegada');

  // andar e saltar com o teclado
  const z0 = s.z;
  s = await holdUntil('KeyW', (x) => x.z < z0 - 2, 8000, 'andar');
  check('W move a Íris para o norte', !!s, s && `z ${z0.toFixed(1)} -> ${s.z.toFixed(1)}`);
  await page.keyboard.down('Space');
  const jumped = await waitFor((x) => x.y > 0.6, 3000, 'pulo');
  await page.keyboard.up('Space');
  check('Espaço salta', !!jumped, jumped && `y=${jumped.y.toFixed(2)}`);
  await waitFor((x) => x.grounded, 5000);

  // planar do mirante até a ilha da cisterna
  await teleport(0, 0.9, 32.3);
  await waitFor((x) => x.grounded, 3000);
  await page.keyboard.down('KeyW');
  await waitFor((x) => x.z < 30.2, 6000, 'corrida até a borda'); // salta na borda, já correndo
  await page.keyboard.down('Space');
  const glided = await waitFor((x) => x.area === 'cisterna' && x.grounded, 15000, 'planar');
  await page.keyboard.up('Space');
  await page.keyboard.up('KeyW');
  check('salta do mirante e plana até a cisterna', !!glided, glided && `z=${glided.z.toFixed(1)}`);
  await shot('03-cisterna');

  // queda no abismo volta ao último piso seguro
  const falls0 = (await state()).falls;
  await teleport(-14, 1, 14);
  s = await waitFor((x) => x.falls > falls0 && x.grounded && !x.resp, 15000, 'queda');
  check('queda retorna ao último piso seguro', !!s, s && `area=${s.area}`);

  // escanear o nó e baixar a maré
  await teleport(6.0, 0, 19.6, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await press('KeyR');
  s = await waitFor((x) => x.world.nodeScanned, 4000, 'scan nó');
  check('R escaneia o nó de ressonância', !!s);
  await shot('04-scan-no');
  s = await holdUntil('KeyQ', (x) => x.tide === 'low', 6000, 'maré baixa');
  check('segurar Q por 1 s baixa a maré', !!s);
  s = await waitFor((x) => x.lvl === 0, 30000, 'transição');
  check('transição da maré termina (2,5 s)', !!s);
  await shot('05-mare-baixa');

  // descer a escada de cristal andando
  await teleport(-2.38, 0.05, 11.4, 0); // topo da escada, olhando para o sul
  await waitFor((x) => x.grounded, 3000);
  s = await holdUntil('KeyW', (x) => x.y < -3.3 && x.grounded, 12000, 'descer escada');
  check('desce a escada de cristal até o fundo', !!s, s && `y=${s.y.toFixed(2)}`);

  // girar o condutor
  await teleport(0, -3.2, 15.3, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await press('KeyE');
  s = await waitFor((x) => x.world.conductorRotated, 4000, 'condutor');
  check('E gira o condutor no fundo da cisterna', !!s);
  await shot('06-condutor');

  // subir a escada andando
  await teleport(-2.38, -3.45, 16.9, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  s = await holdUntil('KeyW', (x) => x.y > -0.05 && x.grounded, 15000, 'subir escada');
  check('sobe a escada de cristal até o topo', !!s, s && `y=${s.y.toFixed(2)}`);

  // subir a maré: a ponte líquida se forma
  await teleport(6.0, 0, 19.6, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await page.waitForFunction(() => !window.__mdv.tide.transitioning && window.__mdv.tide.cooldown === 0, null, { timeout: 40000 }); // cooldown de 5 s
  s = await holdUntil('KeyQ', (x) => x.tide === 'high', 9000, 'maré alta');
  check('maré volta a subir', !!s);
  s = await waitFor(() => true);
  const bridgeOk = await page.waitForFunction(() => window.__mdv.level.bridgeCol.enabled, null, { timeout: 15000 }).then(() => true).catch(() => false);
  check('ponte líquida fica atravessável', bridgeOk);

  // atravessar a ponte andando
  await teleport(0, 0, 6.6, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await shot('07-ponte');
  s = await holdUntil('KeyW', (x) => x.z < -4.5 && x.grounded, 15000, 'atravessar');
  check('atravessa a ponte líquida até o jardim', !!s && s.area === 'jardim', s && `${s.area} z=${s.z.toFixed(1)}`);
  check('checkpoint do jardim registrado', await g(() => window.__mdv.checkpoint === 'jardim'));
  await shot('08-jardim');

  // baixar a maré do jardim: guardião acorda
  await teleport(-9.0, 0, -7.2, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await page.waitForFunction(() => !window.__mdv.tide.transitioning && window.__mdv.tide.cooldown === 0, null, { timeout: 40000 });
  s = await holdUntil('KeyQ', (x) => x.tide === 'low', 9000, 'maré baixa jardim');
  check('nó do jardim baixa a maré', !!s);
  s = await waitFor((x) => ['waking', 'patrol', 'alert', 'chase'].includes(x.guard), 8000, 'guardião');
  check('guardião acorda no piso seco', !!s, s && s.guard);
  await waitFor((x) => x.lvl === 0, 8000);
  await shot('09-praca-seca');

  // guardião: vê quem pisa no piso seco, alerta, persegue e atinge (sem combate)
  await waitFor((x) => x.guard === 'patrol', 20000, 'patrulha');
  const ahead = await g(() => { const gd = window.__mdv.guardian; return { x: gd.pos.x + Math.sin(gd.yaw) * 3, z: gd.pos.z + Math.cos(gd.yaw) * 3 }; });
  await teleport(ahead.x, -2.15, ahead.z, 0);
  s = await waitFor((x) => ['alert', 'chase'].includes(x.guard), 6000, 'alerta');
  check('guardião detecta Íris no piso seco (alerta)', !!s, s && s.guard);
  await shot('09b-alerta');
  s = await waitFor((x) => x.integrity === 2 && !x.resp, 15000, 'contato');
  check('contato tira 1 segmento de integridade e devolve Íris ao terraço', !!s && s.y > -0.5, s && `integridade=${s.integrity} y=${s.y.toFixed(2)}`);

  // descer à praça, escanear placas e ativar o relé
  await teleport(1.2, -2.15, -20.8, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await press('KeyR');
  s = await waitFor((x) => x.world.platesScanned, 4000, 'scan placas');
  check('R revela a placa conectada', !!s);
  await teleport(1.2, -2.15, -21.9, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await press('KeyE');
  s = await waitFor((x) => x.world.relayActive, 12000, 'relé');
  check('E na placa envia Lume ao relé e pacifica o guardião', !!s && (await state()).guard === 'pacified', s && (await state()).guard);
  await shot('10-rele');
  const gateOpen = await page.waitForFunction(() => !window.__mdv.level.gate.col.enabled, null, { timeout: 10000 }).then(() => true).catch(() => false);
  check('portão norte abre', gateOpen);

  // subir a escadaria até o santuário andando
  await teleport(0, 0, -27.4, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  s = await holdUntil('KeyW', (x) => x.area === 'santuario' && x.grounded && x.y > 3, 15000, 'escadaria');
  check('sobe a escadaria até o santuário', !!s, s && `y=${s.y.toFixed(2)}`);
  check('checkpoint do santuário registrado', await g(() => window.__mdv.checkpoint === 'santuario'));
  await shot('11-santuario');

  // recuperar o eco e descansar
  const f = await g(() => { const p = window.__mdv.level.fountain.pos; return { x: p.x, y: p.y, z: p.z }; });
  await teleport(f.x, f.y + 0.3, f.z + 1.6, Math.PI);
  await waitFor((x) => x.grounded, 3000);
  await press('KeyE');
  s = await waitFor((x) => x.world.echoRecovered, 4000, 'eco');
  check('E recupera o eco do anel', !!s);
  await page.waitForTimeout(1200);
  await shot('12-eco');
  const shortcut = await page.waitForFunction(() => window.__mdv.level.shortcutCol.enabled, null, { timeout: 12000 }).then(() => true).catch(() => false);
  check('atalho de cerâmica se ergue', shortcut);
  await page.waitForTimeout(800);
  await press('KeyE');
  s = await waitFor((x) => x.mode === 'end', 8000, 'fim');
  check('descansar salva e mostra a tela final', !!s);
  await shot('13-fim');

  // save/load
  const saved = await g(() => window.__mdv.saves.load());
  check('save gravado com checkpoint do santuário', saved?.data?.checkpoint === 'santuario' && saved.data.world.rested === true);
  await page.reload();
  await page.waitForFunction(() => window.__mdv && window.__mdv.mode === 'menu', null, { timeout: 120000 });
  const hasContinue = await page.locator('#menu button.primary').first().textContent();
  check('menu oferece Continuar após recarregar', /Continuar|Continue/.test(hasContinue || ''), hasContinue);
  await page.locator('#menu button.primary').first().click();
  s = await waitFor((x) => x.mode === 'play' && x.grounded, 10000, 'continuar');
  check('continuar restaura o mundo (portão aberto, eco recuperado)', !!s && s.world.relayActive && s.world.echoRecovered && s.area === 'santuario', s && s.area);

  check('sem erros de página', errors.length === 0, errors.slice(0, 3).join(' | '));
} catch (err) {
  check('execução do teste', false, err.stack);
} finally {
  await browser.close();
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} verificações passaram`);
process.exit(failed.length ? 1 : 0);
