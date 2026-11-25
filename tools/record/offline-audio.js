// Renderiza a trilha do vídeo fora de tempo real com o mesmo motor de áudio do
// jogo (src/core/audio.js): os eventos registrados pelo piloto (passos, saltos,
// maré, guardião, ecos…) e a automação musical (maré e alerta) são agendados
// num OfflineAudioContext. Devolve um WAV mono 16 bits em base64, por partes.
import { AudioEngine } from '/src/core/audio.js';

export async function renderOfflineAudio({ events, samples, duration, rate = 44100, volumes }) {
  const ctx = new OfflineAudioContext(2, Math.ceil((duration + 1) * rate), rate);
  const eng = new AudioEngine();
  if (volumes) eng.vol = { ...eng.vol, ...volumes };
  eng.start(ctx);
  for (const s of samples) { eng.at = s.t; eng.update(s.tide, s.alert); }
  // sinos de vidro ambientes (como o chimeLoop ao vivo), com semente fixa
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const tideAt = (t) => { let v = 1; for (const s of samples) { if (s.t > t) break; v = s.tide; } return v; };
  const scale = [587.33, 659.25, 880, 987.77, 1174.66, 1318.51];
  for (let t = 1.5; t < duration; t += 2.5 + rnd() * 5) {
    eng.at = t;
    eng.bell(scale[Math.floor(rnd() * scale.length)] * (tideAt(t) > 0.5 ? 1 : 0.75), 0.05 + rnd() * 0.04, 2.5, eng.music);
  }
  for (const e of events) { eng.at = e.t; eng.play(e.name); }
  const buf = await ctx.startRendering();

  // mixa para mono e codifica WAV PCM 16 bits
  const n = Math.ceil(duration * rate);
  const L = buf.getChannelData(0), R = buf.getChannelData(1);
  const bytes = new Uint8Array(44 + n * 2);
  const dv = new DataView(bytes.buffer);
  const str = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
  str(0, 'RIFF'); dv.setUint32(4, 36 + n * 2, true); str(8, 'WAVE'); str(12, 'fmt ');
  dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true);
  dv.setUint32(24, rate, true); dv.setUint32(28, rate * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true);
  str(36, 'data'); dv.setUint32(40, n * 2, true);
  let peak = 0;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs((L[i] + R[i]) / 2));
  const gain = peak > 0 ? Math.min(4, 0.89 / peak) : 1;
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, ((L[i] + R[i]) / 2) * gain));
    dv.setInt16(44 + i * 2, v * 32767, true);
  }
  // base64 em partes (evita strings gigantes de uma vez)
  const chunks = [];
  const CH = 3 * 1024 * 1024;
  for (let o = 0; o < bytes.length; o += CH) {
    let s = '';
    const part = bytes.subarray(o, o + CH);
    for (let i = 0; i < part.length; i += 0x8000) s += String.fromCharCode.apply(null, part.subarray(i, i + 0x8000));
    chunks.push(btoa(s));
  }
  return { chunks, peak, gain };
}
