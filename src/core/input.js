// Entrada unificada: teclado + mouse (pointer lock) + gamepad (GDD 03).
// WASD / analógico E: mover; mouse / analógico D: câmera; espaço / A: salto
// (segurar: planar); E / X: interagir; Q / Y: maré; R / RB: escanear;
// Shift / B: esquiva; Esc / Start: pausa.

const KEYMAP = {
  KeyW: 'up', ArrowUp: 'up', KeyS: 'down', ArrowDown: 'down',
  KeyA: 'left', ArrowLeft: 'left', KeyD: 'right', ArrowRight: 'right',
  Space: 'jump', KeyE: 'interact', KeyQ: 'tide', KeyR: 'scan',
  ShiftLeft: 'dodge', ShiftRight: 'dodge', Escape: 'pause', KeyP: 'pause', Enter: 'confirm',
};
// Botões padrão (mapeamento "standard" da Gamepad API)
const PAD = { jump: 0, dodge: 1, interact: 2, tide: 3, scan: 5, pause: 9, confirm: 0 };

export class Input {
  constructor(canvas) {
    this.canvas = canvas;
    this.down = new Set();
    this.pressed = new Set();
    this.released = new Set();
    this.mouse = { dx: 0, dy: 0, wheel: 0 };
    this.locked = false;
    this.padPrev = {};
    this.usingPad = false;
    this.sensitivity = 1;
    this.invertY = false;
    this.enabled = true;

    addEventListener('keydown', (e) => {
      const a = KEYMAP[e.code];
      if (!a) return;
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
      if (!this.down.has(a)) this.pressed.add(a);
      this.down.add(a);
      this.usingPad = false;
    });
    addEventListener('keyup', (e) => {
      const a = KEYMAP[e.code];
      if (!a) return;
      this.down.delete(a);
      this.released.add(a);
    });
    addEventListener('blur', () => { this.down.clear(); });
    addEventListener('mousemove', (e) => {
      if (!this.locked) return;
      this.mouse.dx += e.movementX;
      this.mouse.dy += e.movementY;
    });
    canvas.addEventListener('wheel', (e) => { this.mouse.wheel += Math.sign(e.deltaY); e.preventDefault(); }, { passive: false });
    document.addEventListener('pointerlockchange', () => { this.locked = document.pointerLockElement === canvas; });
    // arrastar com o mouse também gira a câmera (sem pointer lock)
    let dragging = false;
    canvas.addEventListener('mousedown', () => { dragging = true; });
    addEventListener('mouseup', () => { dragging = false; });
    addEventListener('mousemove', (e) => {
      if (this.locked || !dragging) return;
      this.mouse.dx += e.movementX;
      this.mouse.dy += e.movementY;
    });
  }

  requestLock() {
    if (this.locked) return;
    try {
      const p = this.canvas.requestPointerLock?.();
      if (p && p.catch) p.catch(() => {});
    } catch { /* ignorado: arrastar com o mouse também funciona */ }
  }
  releaseLock() { if (document.pointerLockElement) document.exitPointerLock(); }

  pollPad() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const gp = [...pads].find((p) => p && p.connected);
    this.pad = gp || null;
    if (!gp) return;
    for (const [action, b] of Object.entries(PAD)) {
      const on = !!gp.buttons[b]?.pressed;
      const was = !!this.padPrev[action];
      if (on && !was) { this.pressed.add(action); this.usingPad = true; }
      if (!on && was) this.released.add(action);
      this.padPrev[action] = on;
    }
  }

  isDown(a) {
    if (this.down.has(a)) return true;
    const b = PAD[a];
    return !!(this.pad && b !== undefined && this.pad.buttons[b]?.pressed);
  }
  wasPressed(a) { return this.pressed.has(a); }
  wasReleased(a) { return this.released.has(a); }

  /** Vetor de movimento (x: direita, y: frente), magnitude <= 1. */
  move() {
    let x = (this.down.has('right') ? 1 : 0) - (this.down.has('left') ? 1 : 0);
    let y = (this.down.has('up') ? 1 : 0) - (this.down.has('down') ? 1 : 0);
    if (this.pad) {
      const ax = this.pad.axes[0] || 0, ay = this.pad.axes[1] || 0;
      if (Math.hypot(ax, ay) > 0.18) { x += ax; y -= ay; this.usingPad = true; }
    }
    const l = Math.hypot(x, y);
    if (l > 1) { x /= l; y /= l; }
    return { x, y };
  }

  /** Delta de câmera em radianos para este quadro. */
  look(dt) {
    let dx = this.mouse.dx * 0.0022 * this.sensitivity;
    let dy = this.mouse.dy * 0.0022 * this.sensitivity;
    if (this.pad) {
      const rx = this.pad.axes[2] || 0, ry = this.pad.axes[3] || 0;
      if (Math.abs(rx) > 0.15) dx += rx * 2.6 * dt * this.sensitivity;
      if (Math.abs(ry) > 0.15) dy += ry * 1.8 * dt * this.sensitivity;
    }
    if (this.invertY) dy = -dy;
    return { dx, dy, wheel: this.mouse.wheel };
  }

  /** Limpa eventos de borda; chamar ao fim de cada quadro. */
  endFrame() {
    this.pressed.clear();
    this.released.clear();
    this.mouse.dx = 0;
    this.mouse.dy = 0;
    this.mouse.wheel = 0;
  }
}
