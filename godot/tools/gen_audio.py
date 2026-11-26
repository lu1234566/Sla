#!/usr/bin/env python3
"""Gera os efeitos (WAV) e trilhas em loop (OGG) de Maré de Vidro.

Síntese procedural (mesma linguagem do protótipo web): sinos de vidro com
parciais inarmônicas, pads com LFO, sopros de ruído filtrado para a maré.
Uso: python3 tools/gen_audio.py  (a partir da pasta godot/)
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT_SFX = 'assets/audio/sfx'
OUT_MUS = 'assets/audio/music'
rng = np.random.default_rng(2026)


def t_axis(d):
    return np.arange(int(SR * d)) / SR


def env_exp(n, attack, decay):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


def bell(freq, dur=1.6, vol=0.3):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for mult, amp in ((1, 1), (2.76, 0.4), (5.4, 0.18), (8.93, 0.08)):
        out += amp * np.sin(2 * np.pi * freq * mult * t) * env_exp(len(t), 0.004, dur / (mult ** 0.3) / 4)
    return out * vol


def tone(freq, dur, kind='sine', vol=0.3, slide=0.0):
    t = t_axis(dur)
    f = freq + slide * (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == 'sine':
        w = np.sin(ph)
    elif kind == 'triangle':
        w = 2 / np.pi * np.arcsin(np.sin(ph))
    elif kind == 'square':
        w = np.sign(np.sin(ph)) * 0.6
    else:  # saw
        w = 2 * ((ph / (2 * np.pi)) % 1) - 1
    e = np.minimum(1, t / 0.01) * np.exp(-t / (dur / 3))
    return w * e * vol


def lowpass(x, cutoff):
    """Passa-baixa de um polo; corte variável aproximado em blocos de 256 amostras."""
    from scipy.signal import lfilter
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    y = np.empty_like(x)
    zi = np.zeros(1)
    B = 256
    for o in range(0, len(x), B):
        a = 1 - np.exp(-2 * np.pi * float(cutoff[o]) / SR)
        y[o:o + B], zi = lfilter([a], [1, a - 1], x[o:o + B], zi=zi)
    return y


def noise_sweep(dur, f0, f1, vol=0.3):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    cut = np.geomspace(f0, f1, n)
    lp = lowpass(x, cut)
    hp = lp - lowpass(lp, cut * 0.35)
    e = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    return hp * e * vol * 3


def reverb(x, seconds=1.8, mix=0.3):
    n = int(SR * seconds)
    ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 6, n))
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = np.convolve(x, ir)
    wet = np.concatenate([wet, np.zeros(len(x) + n - len(wet))])[: len(x) + n]
    dry = np.concatenate([x, np.zeros(n)])
    return dry * (1 - mix) + wet * mix


def mix(*parts):
    n = max(len(p) for _, p in parts)
    out = np.zeros(n)
    for off, p in parts:
        o = int(off * SR)
        out[o:o + len(p)] += p[: max(0, n - o)]
    return out


def save_wav(path, x, peak=0.85):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def sfx():
    os.makedirs(OUT_SFX, exist_ok=True)
    s = {}
    s['step'] = tone(200, 0.06, 'triangle', 0.4, -40)
    s['jump'] = tone(330, 0.18, 'triangle', 0.5, 260)
    s['land'] = mix((0, tone(140, 0.16, 'sine', 0.6, -60)), (0, noise_sweep(0.12, 900, 300, 0.15)))
    s['glide'] = noise_sweep(0.7, 300, 1800, 0.35)
    s['dodge'] = noise_sweep(0.32, 2400, 400, 0.45)
    s['scan'] = reverb(mix((0, tone(880, 0.6, 'sine', 0.35, 880)), (0.12, bell(1760, 1.2, 0.25))), 1.2, 0.35)
    s['confirm'] = reverb(bell(1174.66, 1.2, 0.4), 1.0, 0.3)
    s['activate'] = reverb(mix(*[(i * 0.09, bell(f, 2.2, 0.35)) for i, f in enumerate((587.33, 880, 1174.66))]), 1.6, 0.35)
    s['tide_up'] = reverb(mix((0, noise_sweep(2.5, 200, 1600, 0.5)), (0, bell(440, 3, 0.25))), 1.8, 0.3)
    s['tide_down'] = reverb(mix((0, noise_sweep(2.5, 1600, 180, 0.5)), (0, bell(293.66, 3, 0.25))), 1.8, 0.3)
    s['fail'] = mix((0, tone(220, 0.25, 'square', 0.3, -80)), (0.12, tone(165, 0.3, 'square', 0.25)))
    s['success'] = reverb(mix(*[(i * 0.12, bell(f, 2.5, 0.3)) for i, f in enumerate((587.33, 739.99, 880, 1174.66, 1479.98))]), 2.0, 0.35)
    s['echo'] = reverb(mix(*[(i * 0.18, bell(f, 3, 0.3)) for i, f in enumerate((880, 1108.73, 1318.51, 1760))]), 2.2, 0.4)
    s['alert'] = mix((0, tone(98, 0.6, 'saw', 0.5, 40)), (0, tone(196, 0.35, 'square', 0.2)))
    s['hit'] = mix((0, tone(120, 0.35, 'square', 0.5, -70)), (0, noise_sweep(0.4, 1800, 200, 0.4)))
    s['pacify'] = reverb(mix(*[(i * 0.15, bell(f, 3, 0.3)) for i, f in enumerate((392, 523.25, 659.25, 783.99))]), 2.0, 0.35)
    s['fall'] = noise_sweep(0.8, 1600, 150, 0.5)
    s['rotate'] = mix((0, tone(160, 0.8, 'saw', 0.25, 60)), (0.7, bell(523.25, 1.5, 0.3)))
    s['ui'] = tone(660, 0.07, 'triangle', 0.4)
    s['ui_back'] = tone(520, 0.08, 'triangle', 0.35, -120)
    s['lume'] = mix((0, tone(1318.51, 0.09, 'sine', 0.3)), (0.07, tone(1760, 0.09, 'sine', 0.22)))
    s['relay'] = reverb(mix((0, tone(440, 0.5, 'sine', 0.3, 1320)), (0.35, bell(1567.98, 1.5, 0.3))), 1.2, 0.35)
    s['portal'] = reverb(mix((0, noise_sweep(1.6, 150, 3000, 0.4)), (0.2, bell(659.25, 2.5, 0.3)), (0.5, bell(987.77, 2.5, 0.25))), 2.0, 0.4)
    s['unlock'] = reverb(mix(*[(i * 0.1, bell(f, 2.6, 0.3)) for i, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.51))]), 2.0, 0.4)
    s['plate'] = mix((0, tone(330, 0.2, 'triangle', 0.35)), (0.05, bell(990, 0.8, 0.2)))
    s['plate_wrong'] = mix((0, tone(180, 0.3, 'square', 0.25, -40)),)
    s['door'] = mix((0, noise_sweep(1.4, 120, 600, 0.45)), (0, tone(70, 1.4, 'saw', 0.15, 20)))
    for name, x in s.items():
        save_wav(f'{OUT_SFX}/{name}.wav', x, 0.8)
    print(f'{len(s)} efeitos gerados')


def pad_loop(chord, seconds, bright, bell_scale, bell_every, seed, drone=None, pulse=0.0):
    r = np.random.default_rng(seed)
    t = t_axis(seconds)
    pad = np.zeros_like(t)
    for i, f in enumerate(chord):
        # LFOs com período que divide o loop (loop sem emenda)
        k = 1 + (i % 3)
        lfo = 0.6 + 0.4 * np.sin(2 * np.pi * k * t / seconds + i)
        w = np.sin(2 * np.pi * f * t) if i % 2 == 0 else 2 / np.pi * np.arcsin(np.sin(2 * np.pi * f * t))
        pad += w * lfo / (1 + i * 0.35)
    if drone:
        pad += 0.6 * np.sin(2 * np.pi * drone * t) * (0.7 + 0.3 * np.sin(2 * np.pi * t / seconds))
    cut = bright * (0.75 + 0.25 * np.sin(2 * np.pi * 2 * t / seconds))
    pad = lowpass(pad, cut) * 0.5
    if pulse:
        beat = 0.5 + 0.5 * np.sin(2 * np.pi * pulse * t) ** 8
        pad *= 0.8 + 0.2 * beat
    bells = np.zeros(len(t) + SR * 4)
    tt = 1.0
    while tt < seconds - 1:
        f = bell_scale[r.integers(len(bell_scale))]
        b = bell(f, 2.8, 0.06 + r.random() * 0.05)
        o = int(tt * SR)
        bells[o:o + len(b)] += b
        tt += bell_every * (0.6 + r.random() * 0.9)
    # dobra a cauda dos sinos para o início (loop contínuo)
    tail = bells[len(t):]
    bells = bells[: len(t)]
    bells[: len(tail)] += tail
    wind = lowpass(r.standard_normal(len(t)), np.full(len(t), 500.0)) * 0.08
    x = pad + bells + wind
    x = reverb(x, 2.5, 0.35)
    tail = x[len(t):]
    x = x[: len(t)]
    x[: len(tail)] += tail
    return x


def music():
    os.makedirs(OUT_MUS, exist_ok=True)
    D = [146.83, 220.0, 293.66, 329.63, 440.0]
    tracks = {
        'farol': (D, 60, 1300, [587.33, 659.25, 880, 987.77, 1174.66, 1318.51], 4.0, 1, None, 0),
        'menu': (D, 48, 900, [587.33, 880, 1174.66], 6.0, 2, 73.42, 0),
        'jardim': ([196.0, 246.94, 293.66, 369.99, 493.88], 60, 1600, [587.33, 739.99, 880, 987.77, 1174.66, 1479.98], 3.2, 3, None, 0),
        'cidade': ([220.0, 261.63, 329.63, 493.88, 659.25], 64, 1200, [659.25, 783.99, 987.77, 1046.5, 1318.51], 3.6, 4, 110.0, 2.0),
        'coracao': ([164.81, 246.94, 369.99, 415.3], 64, 800, [493.88, 554.37, 739.99, 830.61, 987.77], 5.0, 5, 82.41, 0),
        'final_liberar': ([261.63, 329.63, 392.0, 493.88, 659.25], 56, 2200, [783.99, 987.77, 1046.5, 1318.51, 1567.98], 2.6, 6, 130.81, 0),
        'final_manter': ([185.0, 277.18, 369.99, 493.88], 56, 700, [739.99, 1108.73, 1479.98], 5.5, 7, 92.5, 0),
    }
    for name, (chord, secs, bright, scale, every, seed, drone, pulse) in tracks.items():
        x = pad_loop(chord, secs, bright, scale, every, seed, drone, pulse)
        wav = f'{OUT_MUS}/{name}.wav'
        save_wav(wav, x, 0.7)
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', wav, '-c:a', 'libvorbis', '-q:a', '4', f'{OUT_MUS}/{name}.ogg'], check=True)
        os.remove(wav)
    # camada de alerta do guardião (loop curto)
    t = t_axis(4.0)
    alert = np.sin(2 * np.pi * 55 * t) * 0.5 + np.sign(np.sin(2 * np.pi * 55 * t)) * 0.15
    alert = lowpass(alert, np.full(len(t), 240.0)) * (0.5 + 0.5 * np.sin(2 * np.pi * 3.2 * t) ** 2)
    save_wav(f'{OUT_MUS}/alert.wav', alert, 0.6)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', f'{OUT_MUS}/alert.wav', '-c:a', 'libvorbis', '-q:a', '4', f'{OUT_MUS}/alert.ogg'], check=True)
    os.remove(f'{OUT_MUS}/alert.wav')
    print(f'{len(tracks) + 1} trilhas geradas')


if __name__ == '__main__':
    sfx()
    music()
