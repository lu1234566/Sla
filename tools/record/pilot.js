// Piloto automático para gravar a fatia vertical. Roda dentro da página e
// joga com as mesmas entradas de um jogador: vetor analógico de movimento
// (como o analógico do controle) e as ações do GDD (salto/planar, E, Q, R,
// Shift). A câmera segue atrás da Íris como um jogador faria. Nada de
// teletransporte: tudo é percorrido andando, saltando e planando.
//
// Também desenha duas camadas só para o vídeo: o capítulo do roteiro do GDD
// (topo) e as teclas pressionadas (canto inferior direito).

const FPS = 30;
const dampAngle = (a, b, k, dt) => {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * (1 - Math.exp(-k * dt));
};

export class Pilot {
  constructor(game, script = null, opts = {}) {
    this.g = game;
    Object.assign(this, opts);
    this.t = 0;
    this.frame = 0;
    this.wish = null; // direção desejada no mundo {dx, dz, speed}
    this.move = { x: 0, y: 0 };
    this.keys = new Set();
    this.taps = new Set();
    this.lit = new Set();
    this.lookSpec = null;
    this.log = [];
    this.failures = [];
    this.audioLog = [];
    this.samples = [];
    this.done = false;

    const input = game.input;
    input.move = () => ({ x: this.move.x, y: this.move.y });
    input.look = () => ({ dx: 0, dy: 0, wheel: 0 });
    input.requestLock = () => {};
    const play = game.audio.play.bind(game.audio);
    game.audio.play = (name) => { this.audioLog.push({ t: this.t, name }); play(name); };
    game.guardian.on((type, d) => { if (type === 'state') this.note(`guardião: ${d.state}`); else this.note(`guardião ${type}`); });

    this.buildOverlay();
    this.it = (script || defaultScript)(this, game);
  }

  note(msg) { this.log.push(`[${this.t.toFixed(1)}s] ${msg}`); }
  fail(msg) { const p = this.g.player.pos; const m = `FALHA ${msg} @ (${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)})`; this.failures.push(m); this.note(m); }

  // --- chamado antes de cada game.frame(dt) ------------------------------------
  tick(dt) {
    const g = this.g;
    this.taps.clear();
    if (!this.done) {
      const r = this.it.next();
      if (r.done) this.done = true;
    }

    // câmera: atrás da Íris, ou olhando para um ponto de interesse
    if (g.mode === 'play') {
      const cr = g.camRig, p = g.player.pos;
      const look = this.lookSpec && this.t < this.lookSpec.until ? this.lookSpec : null;
      let yawT = g.player.yaw + Math.PI, pitchT = 0.36, distT = 6.4, k = 1.7;
      if (look) {
        yawT = Math.atan2(p.x - look.target.x, p.z - look.target.z);
        pitchT = look.pitch ?? 0.45;
        distT = look.dist ?? 7;
        k = 2.4;
      }
      cr.yaw = dampAngle(cr.yaw, yawT, k, dt);
      cr.pitch += (pitchT - cr.pitch) * (1 - Math.exp(-2 * dt));
      cr.targetDist = distT;

      // direção no mundo -> vetor do analógico relativo à câmera
      if (this.wish) {
        const s = Math.sin(cr.yaw), c = Math.cos(cr.yaw);
        const { dx, dz, speed } = this.wish;
        this.move = { x: (c * dx - s * dz) * speed, y: -(s * dx + c * dz) * speed };
      } else this.move = { x: 0, y: 0 };
    } else this.move = { x: 0, y: 0 };

    // aplica teclas
    const inp = g.input;
    inp.down.clear();
    for (const k of this.keys) inp.down.add(k);
    for (const k of this.taps) { inp.pressed.add(k); inp.down.add(k); }

    // animações CSS seguem o relógio do vídeo
    for (const a of document.getAnimations()) {
      try {
        if (a.__vt === undefined) { a.__vt = a.currentTime || 0; a.pause(); }
        a.__vt += dt * 1000;
        const end = a.effect?.getComputedTiming().endTime;
        if (Number.isFinite(end) && a.__vt >= end) a.finish();
        else a.currentTime = a.__vt;
      } catch { /* animação já removida */ }
    }
    this.updateOverlay(dt);
  }

  /** Chamado depois de game.frame(dt). */
  after(dt) {
    if (this.frame % 3 === 0) this.samples.push({ t: this.t, tide: this.g.tide.level, alert: this.g.guardian.alertLevel });
    this.t += dt;
    this.frame++;
  }

  status() { return { t: this.t, done: this.done, failures: this.failures.length }; }

  // --- primitivas de roteiro (geradores: um passo por quadro) -----------------

  *wait(sec) { const n = Math.round(sec * FPS); for (let i = 0; i < n; i++) yield; }

  *until(fn, timeout = 30, label = 'condição') {
    let n = 0;
    while (!fn()) {
      if (++n > timeout * FPS) { this.fail(`esperando ${label}`); return false; }
      yield;
    }
    return true;
  }

  *goto(x, z, o = {}) {
    const tol = o.tol ?? 0.45, timeout = o.timeout ?? 25;
    let n = 0;
    for (;;) {
      const p = this.g.player.pos;
      const dx = x - p.x, dz = z - p.z, d = Math.hypot(dx, dz);
      if (d < tol) break;
      if (++n > timeout * FPS) { this.fail(`ir até (${x}, ${z})`); break; }
      const speed = o.slow ? Math.max(0.35, Math.min(1, d / 1.5)) * (o.speed ?? 1) : (o.speed ?? 1);
      this.wish = { dx: dx / d, dz: dz / d, speed };
      yield;
    }
    if (!o.keep) this.wish = null;
  }

  *path(points, o = {}) {
    for (let i = 0; i < points.length; i++) {
      const last = i === points.length - 1;
      yield* this.goto(points[i][0], points[i][1], { ...o, tol: last ? (o.tol ?? 0.45) : (o.passTol ?? 0.9), keep: !last || o.keep, slow: last && o.slow !== false });
    }
  }

  tap(action) { this.taps.add(action); this.flash(action); }

  *hold(action, sec) { this.keys.add(action); yield* this.wait(sec); this.keys.delete(action); }

  *holdUntil(action, fn, timeout = 6, label = action) {
    this.keys.add(action);
    const ok = yield* this.until(fn, timeout, label);
    this.keys.delete(action);
    return ok;
  }

  /** Corre até (x,z), salta quando faltar `jumpDist` e segura o salto no ar (planar). */
  *hop(x, z, o = {}) {
    const b = this.g.player.body;
    const jumpDist = o.jumpDist ?? 2.4, timeout = o.timeout ?? 12;
    let jumped = false, air = 0, n = 0;
    for (;;) {
      const p = b.pos;
      const dx = x - p.x, dz = z - p.z, d = Math.hypot(dx, dz);
      if (++n > timeout * FPS) { this.fail(`salto até (${x}, ${z})`); break; }
      if (jumped && b.grounded && air > 2) {
        if (d > (o.tol ?? 1.6)) this.fail(`pouso longe de (${x}, ${z}): ${d.toFixed(2)} m`);
        break;
      }
      this.wish = d > 0.2 ? { dx: dx / d, dz: dz / d, speed: 1 } : null;
      if (!jumped && b.grounded && d < jumpDist) { this.tap('jump'); this.keys.add('jump'); jumped = true; }
      if (jumped && !b.grounded) air++;
      yield;
    }
    this.keys.delete('jump');
    this.wish = null;
    if (o.settle !== false) yield* this.goto(x, z, { tol: 0.35, timeout: 4 });
  }

  lookAt(target, sec, o = {}) { this.lookSpec = { target, until: this.t + sec, ...o }; }

  click(selector, index = 0) {
    const el = document.querySelectorAll(selector)[index];
    if (el) el.click(); else this.fail(`clique em ${selector}`);
  }

  // --- camadas do vídeo -----------------------------------------------------------

  buildOverlay() {
    const css = document.createElement('style');
    css.textContent = `
      #rec-chapter { position: fixed; top: 16px; left: 50%; transform: translateX(-50%); z-index: 50; pointer-events: none;
        background: rgba(13,30,41,.86); border-radius: 8px; padding: 10px 18px; text-align: center; font-family: Lato, system-ui, sans-serif; color: #E9D8AC;
        border-bottom: 3px solid #7CF4DC; max-width: 560px; }
      #rec-chapter b { display: block; font-size: 12px; letter-spacing: .1em; color: #7CF4DC; font-weight: 900; }
      #rec-chapter span { display: block; font-size: 16px; font-weight: 700; margin-top: 3px; }
      #rec-keys { position: fixed; right: 18px; bottom: 18px; z-index: 50; pointer-events: none; display: grid; gap: 5px;
        grid-template-columns: repeat(3, 34px) 10px auto; grid-template-rows: 34px 34px 34px; font-family: Lato, system-ui, sans-serif; }
      #rec-keys i { font-style: normal; display: flex; align-items: center; justify-content: center; border-radius: 6px; font-weight: 900; font-size: 13px;
        background: rgba(13,30,41,.72); color: rgba(233,216,172,.75); border: 1.5px solid rgba(233,216,172,.25); transition: none; padding: 0 8px; }
      #rec-keys i.on { background: #7CF4DC; color: #102331; border-color: #7CF4DC; }
    `;
    document.head.append(css);
    this.chapterEl = document.createElement('div');
    this.chapterEl.id = 'rec-chapter';
    this.chapterEl.innerHTML = '<b></b><span></span>';
    this.chapterEl.style.opacity = 0;
    this.keysEl = document.createElement('div');
    this.keysEl.id = 'rec-keys';
    const cells = [
      ['Q', 'tide', 1, 1], ['W', 'up', 2, 1], ['E', 'interact', 3, 1], ['R', 'scan', 5, 1],
      ['A', 'left', 1, 2], ['S', 'down', 2, 2], ['D', 'right', 3, 2], ['Shift', 'dodge', 5, 2],
      ['Espaço', 'jump', '1 / span 3', 3],
    ];
    this.keyEls = {};
    for (const [label, action, col, row] of cells) {
      const i = document.createElement('i');
      i.textContent = label;
      i.style.gridColumn = col;
      i.style.gridRow = row;
      this.keysEl.append(i);
      this.keyEls[action] = i;
    }
    document.body.append(this.chapterEl, this.keysEl);
    this.chapterT = 0;
    this.flashes = new Map();
  }

  chapter(label, text, seconds = 6) {
    this.chapterEl.querySelector('b').textContent = label;
    this.chapterEl.querySelector('span').textContent = text;
    this.chapterT = seconds;
    this.chapterDur = seconds;
    this.note(`capítulo: ${label} — ${text}`);
  }

  flash(action) { this.flashes.set(action, 0.22); }

  updateOverlay(dt) {
    this.chapterT = Math.max(0, this.chapterT - dt);
    const shown = (this.chapterDur || 0) - this.chapterT;
    this.chapterEl.style.opacity = this.chapterT > 0 ? Math.min(1, shown / 0.4, this.chapterT / 0.5) : 0;
    const active = new Set(this.keys);
    for (const [a, tLeft] of this.flashes) { if (tLeft > 0) { active.add(a); this.flashes.set(a, tLeft - dt); } }
    if (this.move.y > 0.3) active.add('up');
    if (this.move.y < -0.3) active.add('down');
    if (this.move.x > 0.3) active.add('right');
    if (this.move.x < -0.3) active.add('left');
    for (const [a, el] of Object.entries(this.keyEls)) el.classList.toggle('on', active.has(a));
    this.keysEl.style.opacity = this.g.mode === 'play' ? 1 : 0;
  }
}

// --- roteiro da gravação: a fatia vertical inteira ------------------------------

export function* defaultScript(p, g) {
  const L = g.level;
  const V = (x, y, z) => ({ x, y, z });
  const guard = g.guardian;

  // menu inicial e cinemática de chegada
  yield* p.wait(4);
  p.click('#menu button.primary');
  p.note('Novo jogo');
  yield* p.until(() => g.mode === 'play', 20, 'fim da cinemática');

  // 00–02 · Chegada
  p.chapter('00–02 · CHEGADA', 'Íris acorda no Farol Nulo. Lume aponta o santuário.');
  yield* p.wait(2.5);
  yield* p.path([[0, 37.5], [0, 35.8]], { slow: false });
  p.chapter('MOVIMENTO', 'Salto com tolerância de borda para subir no mirante');
  yield* p.hop(0, 31.4, { jumpDist: 2.6 });
  yield* p.goto(0, 30.4, { slow: true });
  p.lookAt(V(0, 0, 16), 2.2, { pitch: 0.3, dist: 6.5 });
  yield* p.wait(1.6);
  yield* p.goto(0, 32.4);
  p.chapter('PLANAR', 'Saltar e segurar Espaço no ar: planar por até 3 s');
  yield* p.hop(0, 20.0, { jumpDist: 10.1, tol: 3.5 });
  yield* p.goto(0.5, 20.6);

  // 02–05 · Descoberta
  p.chapter('02–05 · DESCOBERTA', 'Escanear o nó de ressonância (R)');
  yield* p.path([[3.0, 20.2], [4.5, 18.9]]);
  yield* p.wait(0.6);
  p.tap('scan');
  yield* p.until(() => g.world.nodeScanned, 3, 'nó escaneado');
  yield* p.wait(2.6);
  p.chapter('MARÉ BAIXA', 'Segurar Q perto do nó por 1 s: a cisterna drena');
  yield* p.holdUntil('tide', () => g.tide.state === 'low', 4, 'maré baixa');
  p.lookAt(V(0, -2.5, 14), 4.5, { pitch: 0.75, dist: 7.5 });
  yield* p.wait(4.2);

  // 05–08 · Travessia
  p.chapter('05–08 · TRAVESSIA', 'Descer a escada de cristal e girar o condutor (E)');
  yield* p.path([[4.3, 13.0], [3.2, 10.2], [-2.38, 10.3], [-2.38, 12.0], [-2.38, 16.2], [-0.9, 15.3]], { passTol: 0.6 });
  p.lookAt(V(0, -3.3, 14), 3.5, { pitch: 0.55, dist: 5 });
  yield* p.wait(0.6);
  p.tap('interact');
  yield* p.until(() => g.world.conductorRotated, 2, 'condutor girado');
  yield* p.wait(3.2);
  yield* p.path([[-2.38, 16.3], [-2.38, 12.0], [-2.38, 10.3], [3.2, 10.2], [4.3, 13.0], [4.5, 18.9]], { passTol: 0.6 });
  yield* p.until(() => !g.tide.transitioning && g.tide.cooldown === 0, 10, 'cooldown do nó');
  p.chapter('MARÉ ALTA', 'Com o condutor alinhado, a maré alta forma a ponte líquida');
  yield* p.holdUntil('tide', () => g.tide.state === 'high', 4, 'maré alta');
  p.lookAt(V(0, 0, 0.5), 5.5, { pitch: 0.42, dist: 8.5 });
  yield* p.wait(5.2);

  // eco opcional: plataformas de flutuação (só sobem na maré alta)
  p.chapter('ECO OPCIONAL', 'Plataformas de flutuação só sobem na maré alta');
  yield* p.path([[7.0, 15.5], [8.3, 13.0]]);
  yield* p.hop(11.9, 13.0, { jumpDist: 3.1 });
  yield* p.hop(14.6, 11.0, { jumpDist: 2.6 });
  yield* p.hop(17.0, 8.6, { jumpDist: 2.6 });
  yield* p.hop(19.0, 5.6, { jumpDist: 2.8 });
  yield* p.until(() => g.collected.includes('float'), 3, 'eco flutuante');
  yield* p.wait(3.0);
  yield* p.hop(17.0, 8.6, { jumpDist: 2.7 });
  yield* p.hop(14.6, 11.0, { jumpDist: 2.6 });
  yield* p.hop(11.9, 13.0, { jumpDist: 2.6 });
  yield* p.hop(8.0, 13.2, { jumpDist: 2.8 });

  // ponte líquida
  p.chapter('PONTE LÍQUIDA', 'Ela só segura enquanto a maré estiver alta');
  yield* p.path([[3.0, 9.0], [0, 7.2], [0, 1.0], [0, -4.4]], { passTol: 0.7 });
  yield* p.wait(1.5);

  // eco opcional: torre de pedra e ilhota (planar)
  p.chapter('ECO OPCIONAL', 'Subir a torre de pedra e planar até a ilhota');
  yield* p.path([[-5.5, -6.0], [-10.6, -12.5], [-7.2, -21.5]], { passTol: 0.9 });
  yield* p.hop(-9.8, -22.0, { jumpDist: 2.3 });
  yield* p.hop(-11.0, -21.2, { jumpDist: 1.25 });
  yield* p.hop(-10.5, -19.0, { jumpDist: 1.9 });
  p.lookAt(V(-20.5, 0.5, -19), 2, { pitch: 0.3, dist: 6.5 });
  yield* p.wait(1.4);
  yield* p.hop(-20.5, -19.0, { jumpDist: 8.75, tol: 3 });
  yield* p.goto(-20.5, -19.0);
  yield* p.until(() => g.collected.includes('islet'), 3, 'eco da ilhota');
  yield* p.wait(3.0);
  yield* p.goto(-21.6, -18.6);
  yield* p.hop(-11.6, -16.2, { jumpDist: 7.15, tol: 3 });

  // 08–11 · Guardião
  p.chapter('08–11 · GUARDIÃO', 'Baixar a maré do jardim expõe as placas e acorda o guardião');
  yield* p.path([[-11.0, -12.0], [-7.8, -8.4]]);
  yield* p.until(() => !g.tide.transitioning && g.tide.cooldown === 0, 10, 'cooldown do nó');
  yield* p.holdUntil('tide', () => g.tide.state === 'low', 4, 'maré baixa no jardim');
  p.lookAt(V(0, -2, -16), 6.5, { pitch: 0.7, dist: 10 });
  yield* p.wait(6.2);
  yield* p.path([[-4.5, -6.2], [0, -6.6]]);

  // demonstração: ser visto, esquivar e sair do piso seco
  p.chapter('ENCONTRO', 'Ele só vê o piso seco: o cone coral no chão é a visão dele');
  yield* p.until(() => guard.state === 'patrol' && guard.wp === 5, 30, 'guardião vindo para o sul');
  yield* p.path([[0, -8.6], [0, -10.4]], { slow: false });
  const seen = yield* p.until(() => ['alert', 'chase'].includes(guard.state), 5, 'alerta do guardião');
  if (seen) {
    p.chapter('ALERTA', 'Detectada! Esquiva (Shift) e saída do piso seco');
    const gd = () => Math.hypot(guard.pos.x - g.player.pos.x, guard.pos.z - g.player.pos.z);
    p.note(`distância no alerta: ${gd().toFixed(1)} m`);
    p.wish = null;
    yield* p.until(() => guard.state === 'chase', 3, 'perseguição');
    p.note(`distância na perseguição: ${gd().toFixed(1)} m`);
    p.wish = { dx: 0, dz: 1, speed: 1 };
    yield* p.wait(0.1);
    p.tap('dodge');
    yield* p.path([[0, -8.6], [0, -6.4]], { slow: false });
    yield* p.until(() => ['rest', 'patrol'].includes(guard.state), 6, 'guardião desiste');
  }
  yield* p.wait(1.5);

  // furtividade até a placa conectada
  p.chapter('FURTIVIDADE', 'Esperar a patrulha passar e usar os cristais como cobertura');
  yield* p.until(() => guard.state === 'patrol' && guard.wp === (p.sneakWp ?? 3), 40, 'janela de patrulha');
  yield* p.path([[0, -8.6], [-1.2, -11.0], [-5.6, -13.6], [-5.4, -19.8], [-2.4, -22.6], [1.2, -21.9]], { passTol: 0.7, slow: false });
  p.tap('scan');
  yield* p.until(() => g.world.platesScanned, 2, 'placas escaneadas');
  yield* p.wait(0.5);
  p.chapter('RELÉ REMOTO', 'Placa conectada (▲) + E: Lume leva o sinal ao relé');
  p.tap('interact');
  p.lookAt(L.relay.pos, 3.2, { pitch: 0.2, dist: 6 });
  yield* p.until(() => g.world.relayActive, 8, 'relé ativo');
  yield* p.wait(2.5);
  p.lookAt(V(0, 1.5, L.gate.z), 3, { pitch: 0.3, dist: 7 });
  yield* p.wait(3);

  // 11–15 · Recompensa
  p.chapter('11–15 · RECOMPENSA', 'Portão aberto: subir ao Santuário das Marés');
  yield* p.path([[3.6, -19.6], [5.0, -16.0], [9.0, -16.0], [9.8, -19.8], [6.3, -23.6], [2.0, -26.5], [0.3, -28.0], [0, -30.0], [0, -35.4]], { passTol: 0.8 });
  const f = L.fountain.pos;
  yield* p.path([[f.x, f.z + 2.2]]);
  p.chapter('ECO', 'Recuperar o eco preso no anel (E)');
  p.tap('interact');
  p.lookAt(L.mainEcho.pos, 4, { pitch: 0.15, dist: 6 });
  yield* p.until(() => g.world.echoRecovered, 2, 'eco recuperado');
  yield* p.wait(6.5);
  p.chapter('DESCANSO', 'Descansar na fonte restaura a integridade e salva');
  yield* p.wait(1.0);
  p.tap('interact');
  yield* p.until(() => g.mode === 'end', 6, 'tela final');
  yield* p.wait(6);
  p.click('#menu button.primary'); // continuar explorando
  yield* p.wait(1.2);
  p.tap('pause');
  yield* p.wait(1.2);
  p.click('#menu button', 1); // diário
  yield* p.wait(6);
  p.note('fim do roteiro');
}
