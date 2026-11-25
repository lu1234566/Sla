// Áudio provisório 100% procedural (WebAudio): pads suaves, sinos de vidro,
// percussão discreta e sinais distintos para ativação, falha e sucesso
// (GDD 14). Camadas musicais mudam com a maré e com o alerta do guardião.

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.vol = { master: 0.8, music: 0.6, sfx: 0.8 };
    this.tide = 1;
    this.alert = 0;
    this.started = false;
  }

  /** Precisa ser chamado após um gesto do usuário. */
  start() {
    if (this.started) { this.ctx?.resume(); return; }
    const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    const c = this.ctx;
    this.master = c.createGain();
    this.master.connect(c.destination);
    this.music = c.createGain();
    this.sfx = c.createGain();
    // reverb simples (eco de vidro)
    this.verb = c.createConvolver();
    this.verb.buffer = this.impulse(2.8, 2.5);
    const verbGain = c.createGain();
    verbGain.gain.value = 0.35;
    this.music.connect(this.master);
    this.sfx.connect(this.master);
    this.music.connect(this.verb);
    this.sfx.connect(this.verb);
    this.verb.connect(verbGain).connect(this.master);
    this.applyVolumes();
    this.startPad();
    this.startAmbience();
    this.started = true;
    this.chimeLoop();
  }

  setVolumes(v) { Object.assign(this.vol, v); this.applyVolumes(); }
  applyVolumes() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(this.vol.master, t, 0.1);
    this.music.gain.setTargetAtTime(this.vol.music * 0.5, t, 0.1);
    this.sfx.gain.setTargetAtTime(this.vol.sfx, t, 0.1);
  }

  impulse(seconds, decay) {
    const c = this.ctx, len = c.sampleRate * seconds;
    const b = c.createBuffer(2, len, c.sampleRate);
    for (let ch = 0; ch < 2; ch++) {
      const d = b.getChannelData(ch);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
    }
    return b;
  }

  noiseBuffer(seconds = 2) {
    const c = this.ctx, len = c.sampleRate * seconds;
    const b = c.createBuffer(1, len, c.sampleRate);
    const d = b.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    return b;
  }

  startPad() {
    const c = this.ctx;
    this.padFilter = c.createBiquadFilter();
    this.padFilter.type = 'lowpass';
    this.padFilter.frequency.value = 900;
    this.padFilter.Q.value = 0.7;
    this.padGain = c.createGain();
    this.padGain.gain.value = 0.18;
    this.padFilter.connect(this.padGain).connect(this.music);
    // acorde aberto (Ré suspenso) — sobe uma terça na maré alta
    this.padOscs = [146.83, 220.0, 293.66, 329.63, 440.0].map((f, i) => {
      const o = c.createOscillator();
      o.type = i % 2 ? 'triangle' : 'sine';
      o.frequency.value = f;
      o.detune.value = (i - 2) * 4;
      const g = c.createGain();
      g.gain.value = 0.22 / (1 + i * 0.4);
      const lfo = c.createOscillator();
      lfo.frequency.value = 0.07 + i * 0.03;
      const lg = c.createGain();
      lg.gain.value = 0.06;
      lfo.connect(lg).connect(g.gain);
      o.connect(g).connect(this.padFilter);
      o.start(); lfo.start();
      return { o, base: f };
    });
    // camada de alerta: pulso grave
    this.alertGain = c.createGain();
    this.alertGain.gain.value = 0;
    const bass = c.createOscillator();
    bass.type = 'sawtooth';
    bass.frequency.value = 55;
    const bf = c.createBiquadFilter();
    bf.type = 'lowpass';
    bf.frequency.value = 220;
    const trem = c.createOscillator();
    trem.frequency.value = 3.2;
    const tg = c.createGain();
    tg.gain.value = 0.5;
    const alertAmp = c.createGain();
    alertAmp.gain.value = 0.5;
    trem.connect(tg).connect(alertAmp.gain);
    bass.connect(bf).connect(alertAmp).connect(this.alertGain).connect(this.music);
    bass.start(); trem.start();
  }

  startAmbience() {
    const c = this.ctx;
    const src = c.createBufferSource();
    src.buffer = this.noiseBuffer(3);
    src.loop = true;
    const f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 500;
    f.Q.value = 0.4;
    const g = c.createGain();
    g.gain.value = 0.05;
    const lfo = c.createOscillator();
    lfo.frequency.value = 0.09;
    const lg = c.createGain();
    lg.gain.value = 0.035;
    lfo.connect(lg).connect(g.gain);
    src.connect(f).connect(g).connect(this.sfx);
    src.start(); lfo.start();
    this.windFilter = f;
  }

  chimeLoop() {
    if (!this.ctx) return;
    const scale = [587.33, 659.25, 880, 987.77, 1174.66, 1318.51];
    const f = scale[Math.floor(Math.random() * scale.length)] * (this.tide > 0.5 ? 1 : 0.75);
    this.bell(f, 0.05 + Math.random() * 0.04, 2.5, this.music);
    setTimeout(() => this.chimeLoop(), 2500 + Math.random() * 5000);
  }

  /** Sino de vidro: parciais inarmônicas com decaimento. */
  bell(freq, vol = 0.1, decay = 1.6, dest = this.sfx, when = 0) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime + when;
    for (const [mult, amp] of [[1, 1], [2.76, 0.4], [5.4, 0.18], [8.93, 0.08]]) {
      const o = c.createOscillator();
      o.frequency.value = freq * mult;
      const g = c.createGain();
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(vol * amp, t + 0.005);
      g.gain.exponentialRampToValueAtTime(0.0001, t + decay / mult ** 0.3);
      o.connect(g).connect(dest);
      o.start(t); o.stop(t + decay + 0.1);
    }
  }

  tone(freq, dur, { type = 'sine', vol = 0.15, slide = 0, when = 0 } = {}) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime + when;
    const o = c.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + slide), t + dur);
    const g = c.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.sfx);
    o.start(t); o.stop(t + dur + 0.05);
  }

  whoosh(dur = 2.5, up = true, vol = 0.25) {
    if (!this.ctx) return;
    const c = this.ctx, t = c.currentTime;
    const src = c.createBufferSource();
    src.buffer = this.noiseBuffer(dur + 0.2);
    const f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.Q.value = 1.2;
    f.frequency.setValueAtTime(up ? 200 : 1600, t);
    f.frequency.exponentialRampToValueAtTime(up ? 1600 : 180, t + dur);
    const g = c.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + dur * 0.3);
    g.gain.linearRampToValueAtTime(0, t + dur);
    src.connect(f).connect(g).connect(this.sfx);
    src.start(t); src.stop(t + dur + 0.2);
  }

  // --- eventos de jogo ---
  play(name) {
    if (!this.ctx) return;
    switch (name) {
      case 'step': this.tone(180 + Math.random() * 60, 0.05, { type: 'triangle', vol: 0.035 }); break;
      case 'jump': this.tone(330, 0.15, { type: 'triangle', vol: 0.08, slide: 220 }); break;
      case 'land': this.tone(140, 0.12, { type: 'sine', vol: 0.12, slide: -60 }); break;
      case 'glide': this.whoosh(0.6, true, 0.08); break;
      case 'dodge': this.whoosh(0.3, false, 0.15); break;
      case 'scan':
        this.tone(880, 0.6, { vol: 0.08, slide: 880 });
        this.bell(1760, 0.05, 1.2, this.sfx, 0.12);
        break;
      case 'confirm': this.bell(1174.66, 0.08, 1.2); break;
      case 'activate': [587.33, 880, 1174.66].forEach((f, i) => this.bell(f, 0.1, 2.2, this.sfx, i * 0.09)); break;
      case 'tideUp': this.whoosh(2.5, true); this.bell(440, 0.08, 3); break;
      case 'tideDown': this.whoosh(2.5, false); this.bell(293.66, 0.08, 3); break;
      case 'fail': this.tone(220, 0.25, { type: 'square', vol: 0.05, slide: -80 }); this.tone(165, 0.3, { type: 'square', vol: 0.04, when: 0.12 }); break;
      case 'success': [587.33, 739.99, 880, 1174.66, 1479.98].forEach((f, i) => this.bell(f, 0.09, 2.5, this.sfx, i * 0.12)); break;
      case 'echo': [880, 1108.73, 1318.51, 1760].forEach((f, i) => this.bell(f, 0.08, 3, this.sfx, i * 0.18)); break;
      case 'alert': this.tone(98, 0.6, { type: 'sawtooth', vol: 0.12, slide: 40 }); this.tone(196, 0.35, { type: 'square', vol: 0.05 }); break;
      case 'hit': this.tone(120, 0.35, { type: 'square', vol: 0.14, slide: -70 }); this.whoosh(0.4, false, 0.2); break;
      case 'pacify': [392, 523.25, 659.25, 783.99].forEach((f, i) => this.bell(f, 0.09, 3, this.sfx, i * 0.15)); break;
      case 'fall': this.whoosh(0.8, false, 0.18); break;
      case 'rotate': this.tone(160, 0.8, { type: 'sawtooth', vol: 0.05, slide: 60 }); this.bell(523.25, 0.06, 1.5, this.sfx, 0.7); break;
      case 'ui': this.tone(660, 0.06, { type: 'triangle', vol: 0.05 }); break;
      case 'lume': this.tone(1318.51, 0.08, { vol: 0.04 }); this.tone(1760, 0.08, { vol: 0.03, when: 0.07 }); break;
      default:
    }
  }

  /** Atualiza camadas musicais. tide: 0..1, alert: 0..1. */
  update(tide, alert) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.tide = tide;
    this.padFilter.frequency.setTargetAtTime(500 + tide * 900, t, 0.5);
    this.padOscs.forEach(({ o, base }, i) => {
      const f = i === 3 ? base * (tide > 0.5 ? 1 : 0.94387) : base; // F# na maré alta, F na baixa
      o.frequency.setTargetAtTime(f, t, 0.8);
    });
    this.alertGain.gain.setTargetAtTime(alert * 0.12, t, 0.3);
    this.windFilter.frequency.setTargetAtTime(380 + tide * 400, t, 1);
  }
}
