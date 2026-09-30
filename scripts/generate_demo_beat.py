#!/usr/bin/env python3
"""Generates the house beat of the onboarding Beat demo (RENN/Resources/Demo/renn_demo_dance.mp4).

The audio is RENN's own: synthesized here with numpy, no samples or third-party recordings.
124 BPM, A minor (Am7 - Fmaj7 - Cmaj7 - G): four-on-the-floor kick, clap on 2 and 4, offbeat
open hats, 16th shakers, offbeat bass, syncopated piano stabs and a sidechained pad.

The beat phase (28/192 s, about 0.146 s) was measured once from the dancers' motion in the Pexels clip so the
kicks land on their moves; it is fixed here so the output is reproducible.

Usage:
  python3 scripts/generate_demo_beat.py out.wav
  python3 scripts/generate_demo_beat.py out.wav --video dance_source.mp4 --ffmpeg /path/to/ffmpeg --mux out.mp4
The mux step crops the 1080x2048 Pexels source to 1080x1920 (y offset 64) and normalizes loudness.
"""
import argparse
import subprocess
import wave

import numpy as np

SR = 48000
DURATION = 11.83
BPM = 124.0
PHASE = 28 / 192  # 0.146 s, on the 1/192 s search grid


def synthesize():
    rng = np.random.default_rng(11)
    beat = 60 / BPM
    n_total = int(SR * DURATION)
    drums = np.zeros(n_total)
    music = np.zeros(n_total)
    sidechain = np.ones(n_total)

    def env(n, d):
        return np.exp(-np.arange(n) / (d * SR))

    def add(buf, sig, at, gain=1.0):
        i = int(round(at * SR))
        if i >= n_total or i + len(sig) <= 0:
            return
        a = max(0, -i)
        j = min(n_total, i + len(sig))
        buf[max(i, 0):j] += sig[a:j - i] * gain

    def bp(sig, lo, hi):
        spectrum = np.fft.rfft(sig)
        freqs = np.fft.rfftfreq(len(sig), 1 / SR)
        spectrum[(freqs < lo) | (freqs > hi)] = 0
        return np.fft.irfft(spectrum, len(sig))

    def lp(sig, cut):
        spectrum = np.fft.rfft(sig)
        freqs = np.fft.rfftfreq(len(sig), 1 / SR)
        spectrum *= 1 / (1 + (freqs / cut) ** 4)
        return np.fft.irfft(spectrum, len(sig))

    def kick():
        n = int(0.4 * SR)
        tt = np.arange(n) / SR
        f = 48 + 110 * np.exp(-tt * 38)
        s = np.tanh(1.6 * np.sin(2 * np.pi * np.cumsum(f) / SR)) * env(n, 0.16)
        c = int(0.003 * SR)
        s[:c] += bp(rng.uniform(-1, 1, c + 64), 2000, 9000)[:c] * 0.5
        return s

    def clap():
        n = int(0.25 * SR)
        s = np.zeros(n)
        for o in (0, 0.009, 0.019, 0.03):
            k = int(o * SR)
            s[k:] += bp(rng.uniform(-1, 1, n - k), 1000, 6000) * env(n - k, 0.012 if o < 0.03 else 0.08)
        return s

    def hat(dec, lo=8000):
        n = int(dec * 6 * SR)
        return bp(rng.uniform(-1, 1, n), lo, 17000) * env(n, dec)

    def bass(f, length):
        n = int(length * SR)
        tt = np.arange(n) / SR
        saw = 2 * ((f * tt) % 1) - 1
        s = 0.6 * np.sin(2 * np.pi * f * tt) + 0.5 * lp(saw, f * 6)
        return s * np.minimum(1, tt / 0.004) * env(n, length * 0.7)

    def piano(freqs, length=0.32):
        n = int(length * SR)
        tt = np.arange(n) / SR
        s = np.zeros(n)
        for f in freqs:
            for h, a in ((1, 1), (2, 0.45), (3, 0.25), (4, 0.12)):
                s += a * np.sin(2 * np.pi * f * h * tt + rng.uniform(0, 6)) * env(n, 0.12 / h ** 0.3)
        return s * np.minimum(1, tt / 0.002)

    def pad(freqs, length):
        n = int(length * SR)
        tt = np.arange(n) / SR
        s = np.zeros(n)
        for f in freqs:
            for d in (-0.15, 0, 0.15):
                s += np.sign(np.sin(2 * np.pi * f * (1 + d / 100) * tt)) * 0.33
        s = lp(s, 1400)
        a = np.minimum(1, tt / 0.3) * np.minimum(1, (length - tt) / 0.3)
        return s * a

    step = beat / 4
    roots = [55.0, 43.65, 65.41, 49.0]  # A, F, C, G
    chords = [[220, 261.6, 329.6, 392], [174.6, 220, 261.6, 329.6],
              [261.6, 329.6, 392, 493.9], [196, 246.9, 293.7, 392]]  # Am7 Fmaj7 Cmaj7 G
    k_sig, clap_sig = kick(), clap()
    start = PHASE - 8 * beat
    bar = 0
    while start + bar * 16 * step < DURATION:
        b0 = start + bar * 16 * step
        ch = bar % 4
        add(music, pad([f / 2 for f in chords[ch]], 16 * step), b0, 0.10)
        for s_ in range(16):
            at = b0 + s_ * step
            if s_ % 4 == 0:
                add(drums, k_sig, at, 1.0)
                i = int(round(at * SR))
                if 0 <= i < n_total:
                    n = min(n_total - i, int(beat * SR))
                    tt = np.arange(n) / SR
                    sidechain[i:i + n] = np.minimum(
                        sidechain[i:i + n], 0.35 + 0.65 * np.clip(tt / (beat * 0.8), 0, 1) ** 1.5)
            if s_ in (4, 12):
                add(drums, clap_sig, at, 0.6)
            if s_ in (2, 6, 10, 14):
                add(drums, hat(0.035, 6000), at, 0.32)  # open-ish offbeat hat
            add(drums, hat(0.008), at, 0.10 if s_ % 2 else 0.06)  # 16th shaker
            if s_ in (2, 6, 10, 14):
                add(music, bass(roots[ch], step * 1.7), at, 0.55)  # offbeat house bass
            if s_ in (3, 6, 11, 14):
                add(music, piano(chords[ch]), at, 0.16)  # syncopated piano stabs
        bar += 1
    out = drums + music * sidechain
    fade_in = int(0.02 * SR)
    out[:fade_in] *= np.linspace(0, 1, fade_in)
    fade_out = int(0.7 * SR)
    out[-fade_out:] *= np.linspace(1, 0, fade_out)
    out = np.tanh(out * 1.1)
    out /= np.abs(out).max() / 0.89
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("wav")
    parser.add_argument("--video", help="Pexels dance source (1080x2048, 24 fps)")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--mux", help="output mp4 (requires --video)")
    args = parser.parse_args()

    samples = synthesize()
    with wave.open(args.wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((samples * 32767).astype(np.int16).tobytes())

    if args.mux:
        if not args.video:
            parser.error("--mux requires --video")
        subprocess.run([
            args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", args.video, "-i", args.wav, "-map", "0:v", "-map", "1:a",
            "-vf", "crop=1080:1920:0:64", "-c:v", "libx264", "-preset", "slow", "-crf", "22",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            "-af", "loudnorm=I=-16:TP=-1.5", "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-ac", "2",
            "-shortest", args.mux,
        ], check=True)


if __name__ == "__main__":
    main()
