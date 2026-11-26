"""Corta as gerações de narração em uma fala por arquivo.

Uso: python split_voice.py <lote> <saida_dir> <relatorio.json> take1.mp3 [take2.mp3 ...]

Cada lote do tools/voice_script.json foi gerado como um só áudio, com
[long pause] entre as falas. O script transcreve cada tomada com o Whisper
(marcas de tempo por palavra), alinha as palavras ao roteiro, corta no
silêncio mais próximo de cada fronteira e, para cada fala, fica com a tomada
cuja transcrição mais se parece com o texto. Grava <chave>.ogg (mono, com
fade curto e volume normalizado) e um relatório com a similaridade.
Requer: faster-whisper, ffmpeg.
"""
import difflib
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))


def norm_words(text):
    text = re.sub(r"\[[^\]]*\]", " ", text)
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.findall(r"[a-z0-9]+", text)


def silences(path, noise="-38dB", dur=0.18):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", f"silencedetect=noise={noise}:d={dur}", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", out)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", out)]
    return list(zip(starts, ends))


def load_pcm(path):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def transcribe(model, path):
    segs, _ = model.transcribe(load_pcm(path), language="pt", word_timestamps=True, beam_size=5, vad_filter=False)
    words = []
    for s in segs:
        for w in s.words or []:
            for tok in norm_words(w.word):
                words.append((tok, w.start, w.end))
    return words


def boundaries(lines, words, sil):
    """Tempos de corte entre falas consecutivas."""
    exp = []
    for i, (_, text) in enumerate(lines):
        for tok in norm_words(text):
            exp.append((tok, i))
    rec = [w[0] for w in words]
    sm = difflib.SequenceMatcher(a=[e[0] for e in exp], b=rec, autojunk=False)
    # índice esperado -> índice reconhecido
    amap = {}
    for blk in sm.get_matching_blocks():
        for k in range(blk.size):
            amap[blk.a + k] = blk.b + k
    first_idx = []
    for i in range(len(lines)):
        idxs = [j for j, e in enumerate(exp) if e[1] == i]
        first_idx.append(idxs[0] if idxs else None)
    cuts = []
    for i in range(1, len(lines)):
        # primeira palavra reconhecida da fala i e última da fala i-1
        a_first = [amap[j] for j, e in enumerate(exp) if e[1] == i and j in amap]
        a_prev = [amap[j] for j, e in enumerate(exp) if e[1] == i - 1 and j in amap]
        if a_first and a_prev:
            t0 = words[max(a_prev)][2]
            t1 = words[min(a_first)][1]
        elif a_first:
            t1 = words[min(a_first)][1]
            t0 = t1 - 0.5
        elif a_prev:
            t0 = words[max(a_prev)][2]
            t1 = t0 + 0.5
        else:
            cuts.append(None)
            continue
        mid = (t0 + t1) / 2
        # encaixa no maior silêncio entre o fim da fala anterior e o início da seguinte
        best = None
        for s0, s1 in sil:
            if s1 >= t0 - 0.35 and s0 <= t1 + 0.35:
                if best is None or (s1 - s0) > (best[1] - best[0]):
                    best = (s0, s1)
        cuts.append((best[0] + best[1]) / 2 if best else mid)
    return cuts


def similarity(a, b):
    return difflib.SequenceMatcher(a=norm_words(a), b=norm_words(b)).ratio()


def main():
    batch_id, out_dir, report_path = sys.argv[1:4]
    takes = sys.argv[4:]
    script = json.load(open(os.path.join(HERE, "voice_script.json"), encoding="utf-8"))
    batch = next(b for b in script["batches"] if b["id"] == batch_id)
    lines = batch["lines"]
    from faster_whisper import WhisperModel
    model = WhisperModel(os.environ.get("WHISPER_MODEL", "small"), device="cpu", compute_type="int8")
    os.makedirs(out_dir, exist_ok=True)
    tmp = tempfile.mkdtemp()
    candidates = {key: [] for key, _ in lines}
    for t, take in enumerate(takes):
        words = transcribe(model, take)
        sil = silences(take)
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", take],
                                   capture_output=True, text=True).stdout.strip())
        cuts = boundaries(lines, words, sil)
        edges = [0.0] + [c for c in cuts] + [dur]
        for i, (key, text) in enumerate(lines):
            a, b = edges[i], edges[i + 1]
            if a is None or b is None or b - a < 0.3:
                continue
            seg = os.path.join(tmp, f"{key}.{t}.wav")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{a:.3f}", "-to", f"{b:.3f}", "-i", take,
                            "-af", "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
                                   "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.12,areverse",
                            "-ac", "1", "-ar", "44100", seg], check=True)
            heard = " ".join(w[0] for w in transcribe(model, seg))
            candidates[key].append({"take": t, "path": seg, "start": round(a, 2), "end": round(b, 2),
                                    "heard": heard, "score": round(similarity(text, heard), 3)})
    report = []
    for key, text in lines:
        cands = sorted(candidates[key], key=lambda c: -c["score"])
        if not cands:
            report.append({"key": key, "ok": False, "reason": "sem segmento"})
            continue
        best = cands[0]
        dst = os.path.join(out_dir, f"{key}.ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", best["path"],
                        "-af", "afade=t=in:d=0.03,areverse,afade=t=in:d=0.08,areverse,loudnorm=I=-17:TP=-1.5:LRA=9",
                        "-ar", "44100", "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
        report.append({"key": key, "ok": best["score"] >= 0.6, "take": best["take"], "score": best["score"],
                       "expected": " ".join(norm_words(text)), "heard": best["heard"],
                       "all_scores": [c["score"] for c in cands]})
    json.dump(report, open(report_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    bad = [r for r in report if not r["ok"]]
    print(f"{batch_id}: {len(report) - len(bad)}/{len(report)} falas ok")
    for r in bad:
        print("  REVISAR", r["key"], r.get("score"), "|", r.get("heard", r.get("reason")))


if __name__ == "__main__":
    main()
