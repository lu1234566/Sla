// Grava um vídeo da fatia vertical jogada pelo piloto automático.
//
//   npm run dev                                   (em outro terminal)
//   node tools/record/record.mjs --tune           ensaio rápido, sem vídeo
//   node tools/record/record.mjs --out gameplay.mp4 [--size 1280x720] [--quality high]
//
// O relógio da página é controlado (Playwright clock): cada quadro avança
// exatamente 1/30 s de jogo, então o vídeo sai em velocidade real mesmo que a
// renderização aqui seja lenta. O áudio é gerado depois, em tempo diferido,
// com o mesmo motor de áudio do jogo, a partir dos eventos registrados.
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : def; };
const TUNE = args.includes('--tune');
const URL = opt('url', 'http://127.0.0.1:5173/');
const OUT = path.resolve(opt('out', 'gameplay.mp4'));
const [W, H] = opt('size', '1280x720').split('x').map(Number);
const QUALITY = opt('quality', 'high');
const FPS = 30;
const MAX_SECONDS = +opt('max', 420);
const pilotOpts = JSON.parse(opt('pilot', '{}'));

const browser = await chromium.launch({ args: ['--use-gl=angle', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error' && !/favicon|fonts\.g/.test(m.text())) errors.push(m.text()); });

await page.clock.install();
await page.goto(`${URL}?quality=${QUALITY}`);
await page.waitForFunction(() => window.__mdv && window.__mdv.mode === 'menu', null, { timeout: 180000 });
await page.evaluate(() => document.fonts.ready);
const now = await page.evaluate(() => Date.now());
await page.clock.pauseAt(now + 100);

await page.evaluate(async ({ tune, pilotOpts }) => {
  const { Pilot } = await import('/tools/record/pilot.js');
  const g = window.__mdv;
  g.loop = () => {}; // o gravador dirige os quadros
  if (tune) g.composer.render = () => {};
  g.saves.clear();
  g.showMainMenu();
  window.__pilot = new Pilot(g, null, pilotOpts);
}, { tune: TUNE, pilotOpts });

let ffmpeg = null;
const silent = OUT.replace(/\.mp4$/, '.video.mp4');
if (!TUNE) {
  ffmpeg = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', silent], { stdio: ['pipe', 'inherit', 'inherit'] });
}

const t0 = Date.now();
let frame = 0, status;
for (;;) {
  status = await page.evaluate(() => {
    const p = window.__pilot, g = window.__mdv;
    p.tick(1 / 30);
    g.frame(1 / 30);
    p.after(1 / 30);
    return p.status();
  });
  await page.clock.runFor(frame % 3 === 0 ? 34 : 33);
  if (ffmpeg) {
    const jpg = await page.screenshot({ type: 'jpeg', quality: 92 });
    if (!ffmpeg.stdin.write(jpg)) await new Promise((r) => ffmpeg.stdin.once('drain', r));
  }
  frame++;
  if (frame % 300 === 0) {
    const el = (Date.now() - t0) / 1000;
    console.log(`  ${(frame / FPS).toFixed(0)} s de vídeo · ${el.toFixed(0)} s reais · falhas: ${status.failures}`);
  }
  if (status.done || frame / FPS > MAX_SECONDS) break;
}

const report = await page.evaluate(() => {
  const p = window.__pilot, g = window.__mdv;
  return { log: p.log, failures: p.failures, events: p.audioLog.length, world: g.world, collected: g.collected, stats: g.stats, integrity: g.integrity, mode: g.mode };
});
console.log(report.log.join('\n'));
console.log(`\nquadros: ${frame} (${(frame / FPS).toFixed(1)} s) · falhas: ${report.failures.length} · ecos: ${report.collected.join(', ')} · stats: ${JSON.stringify(report.stats)} · integridade: ${report.integrity}`);
if (errors.length) console.log('erros da página:', errors.slice(0, 5));

if (ffmpeg) {
  ffmpeg.stdin.end();
  await new Promise((r) => ffmpeg.on('close', r));
  console.log('renderizando áudio…');
  const duration = frame / FPS;
  const audio = await page.evaluate(async (duration) => {
    const { renderOfflineAudio } = await import('/tools/record/offline-audio.js');
    const p = window.__pilot;
    return renderOfflineAudio({ events: p.audioLog, samples: p.samples, duration });
  }, duration);
  const wav = OUT.replace(/\.mp4$/, '.wav');
  fs.writeFileSync(wav, Buffer.concat(audio.chunks.map((c) => Buffer.from(c, 'base64'))));
  console.log(`áudio: pico ${audio.peak.toFixed(3)}, ganho ${audio.gain.toFixed(2)}`);
  await new Promise((resolve, reject) => {
    const mux = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-i', silent, '-i', wav, '-c:v', 'copy', '-af', 'loudnorm=I=-18:TP=-1.5:LRA=11', '-ar', '44100', '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', OUT], { stdio: 'inherit' });
    mux.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`ffmpeg saiu com ${code}`))));
  });
  fs.rmSync(silent);
  fs.rmSync(wav);
  console.log(`vídeo salvo em ${OUT}`);
}
await browser.close();
process.exit(report.failures.length ? 1 : 0);
