// TideManager — estado binário da maré por setor (GDD 04 / Sistemas).
// Regras: alternar só perto de nós, após 1 s de confirmação; transição de 2,5 s;
// cooldown de 5 s após a conclusão; o nó não ativa se Íris estiver em volume
// inseguro. Sem relógio global. Lógica pura, testável sem renderização.

import { TIDE } from './PuzzleGraph.js';

export const TIDE_RULES = Object.freeze({
  CONFIRM_TIME: 1.0,
  TRANSITION_TIME: 2.5,
  COOLDOWN: 5.0,
});

export const REFUSAL = Object.freeze({
  TRANSITIONING: 'transitioning',
  COOLDOWN: 'cooldown',
  UNSAFE: 'unsafe',
});

const smooth = (t) => t * t * (3 - 2 * t);

export class TideManager {
  constructor(initial = TIDE.HIGH, rules = TIDE_RULES) {
    this.rules = rules;
    this.state = initial; // estado lógico alvo
    this.from = initial;
    this.progress = 1; // 0..1 da transição atual
    this.cooldown = 0;
    this.listeners = new Set();
  }

  on(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  emit(type, data) { for (const fn of this.listeners) fn(type, data); }

  get transitioning() { return this.progress < 1; }

  /** Nível visual contínuo: 0 = maré baixa, 1 = maré alta. */
  get level() {
    const a = this.from === TIDE.HIGH ? 1 : 0;
    const b = this.state === TIDE.HIGH ? 1 : 0;
    return a + (b - a) * smooth(this.progress);
  }

  /** Verifica se um nó pode alternar agora. Devolve null se pode, ou um motivo. */
  refusal({ playerUnsafe = false } = {}) {
    if (this.transitioning) return REFUSAL.TRANSITIONING;
    if (this.cooldown > 0) return REFUSAL.COOLDOWN;
    // Só subir a maré pode aprisionar Íris num volume que vai inundar.
    if (playerUnsafe && this.state === TIDE.LOW) return REFUSAL.UNSAFE;
    return null;
  }

  /** Tenta alternar. Devolve {ok, reason}. */
  toggle(opts = {}) {
    const reason = this.refusal(opts);
    if (reason) { this.emit('refused', { reason }); return { ok: false, reason }; }
    this.from = this.state;
    this.state = this.state === TIDE.HIGH ? TIDE.LOW : TIDE.HIGH;
    this.progress = 0;
    this.emit('start', { from: this.from, to: this.state });
    return { ok: true };
  }

  /** Define o estado instantaneamente (carregar save, reinício). */
  set(state) {
    this.state = state;
    this.from = state;
    this.progress = 1;
    this.cooldown = 0;
  }

  update(dt) {
    if (this.transitioning) {
      this.progress = Math.min(1, this.progress + dt / this.rules.TRANSITION_TIME);
      if (!this.transitioning) {
        this.cooldown = this.rules.COOLDOWN;
        this.emit('end', { state: this.state });
      }
    } else if (this.cooldown > 0) {
      this.cooldown = Math.max(0, this.cooldown - dt);
      if (this.cooldown === 0) this.emit('ready', { state: this.state });
    }
  }

  serialize() { return { state: this.state }; }
}

/**
 * Confirmação por segurar o botão perto do nó (1 s). Guarda o progresso e
 * dispara uma única vez por pressão.
 */
export class HoldToConfirm {
  constructor(duration = TIDE_RULES.CONFIRM_TIME) {
    this.duration = duration;
    this.t = 0;
    this.fired = false;
  }
  /** Devolve true no quadro em que a confirmação completa. */
  update(dt, holding) {
    if (!holding) { this.t = 0; this.fired = false; return false; }
    if (this.fired) return false;
    this.t += dt;
    if (this.t >= this.duration) { this.fired = true; return true; }
    return false;
  }
  get ratio() { return this.fired ? 1 : Math.min(1, this.t / this.duration); }
}
