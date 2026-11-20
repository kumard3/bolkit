"""Original 84 BPM minimal electronic bed for the Bolkit speaker-detection brag.

Same bar grid as the video (bar = 2.857 s). Bar 1 pad + arp, bars 2-6 groove, bar 7 breakdown with
a riser, bars 8-9 lift under the outro, ringing tail. Renders straight to mix.wav (stereo 44.1 kHz).
"""
import wave
import numpy as np

SR = 44100
BPM = 84
BEAT = 60 / BPM
BAR = 4 * BEAT
DUR = 24.6
N = int(SR * DUR)
rng = np.random.default_rng(11)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def buf():
    return np.zeros(N)


def place(dst, sig, t):
    i = int(t * SR)
    if i >= N:
        return
    j = min(N, i + len(sig))
    dst[i:j] += sig[: j - i]


def env(n, decay, a=0.003):
    e = np.exp(-np.arange(n) / (decay * SR))
    k = max(1, int(a * SR))
    e[:k] *= np.linspace(0, 1, k)
    return e


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


def reverb(x, seconds=1.8, wet=0.35):
    n = int(seconds * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (0.35 * SR))
    ir[: int(0.012 * SR)] = 0
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]
    return (1 - wet) * x + wet * norm(y) * np.max(np.abs(x))


PROG = [[57, 60, 64, 67, 71], [53, 57, 60, 64], [48, 55, 60, 62, 64], [55, 59, 62, 64]]  # Am9 Fmaj7 Cadd9 G6
bar_chord = lambda b: PROG[b % 4]
GROOVE = range(1, 6)
BREAK = 6
LIFT = (7, 8)

pad = buf()
for b in range(9):
    for m in bar_chord(b):
        n = int(BAR * 1.3 * SR)
        t = np.arange(n) / SR
        f = hz(m)
        s = sum(np.sin(2 * np.pi * f * d * t) for d in (0.997, 1.0, 1.003)) / 3
        e = np.clip(t / 0.6, 0, 1) * np.clip((BAR * 1.3 - t) / 0.8, 0, 1)
        place(pad, 0.5 * s * e, b * BAR)
pad = reverb(norm(pad), 2.5, 0.45)

arp = buf()
for b in range(9):
    notes = [m + 12 for m in bar_chord(b)]
    pattern = [0, 2, 1, 3, 2, 4 % len(notes), 1, 3] * 2
    for k in range(16):
        m = notes[pattern[k] % len(notes)]
        n = int(0.32 * SR)
        t = np.arange(n) / SR
        f = hz(m)
        s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 30)
        vel = 0.55 if k % 4 == 0 else 0.35
        if b == 0 or b == BREAK:
            vel *= 0.8
        place(arp, vel * s * env(n, 0.09), b * BAR + k * BEAT / 4)
arp = reverb(norm(arp), 1.6, 0.3)

sub = buf()
kick = buf()
clap = buf()
shaker = buf()
for b in list(GROOVE) + list(LIFT):
    root = bar_chord(b)[0] - 24
    for pos, ln in ((0.0, 1.6), (2.5, 1.2)):
        n = int(ln * BEAT * SR)
        t = np.arange(n) / SR
        place(sub, np.sin(2 * np.pi * hz(root) * t) * env(n, 0.5, 0.01), b * BAR + pos * BEAT)
    for pos in (0.0, 2.5):
        n = int(0.4 * SR)
        t = np.arange(n) / SR
        f = 48 + 90 * np.exp(-t * 32)
        place(kick, np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.14), b * BAR + pos * BEAT)
    for pos in (1.0, 3.0):
        n = int(0.22 * SR)
        noise = rng.standard_normal(n)
        burst = sum(np.roll(env(n, 0.012), int(d * SR)) for d in (0, 0.009, 0.018))
        place(clap, noise * (burst + 0.6 * env(n, 0.06)), b * BAR + pos * BEAT)
    for k in range(16):
        n = int(0.05 * SR)
        vel = 0.5 if k % 2 else 0.3
        place(shaker, vel * rng.standard_normal(n) * env(n, 0.01), b * BAR + k * BEAT / 4)

riser = buf()
n = int(BAR * SR)
t = np.arange(n) / SR
noise = np.convolve(rng.standard_normal(n), np.ones(6) / 6, mode="same")
place(riser, noise * (t / BAR) ** 3, BREAK * BAR)

bell = buf()
for m, pos in ((76, 0.0), (79, 1.5), (81, 3.0), (79, 4.5), (76, 6.0)):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    f = hz(m)
    s = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t * 6)
    place(bell, s * env(n, 0.8), LIFT[0] * BAR + pos * BEAT)
bell = reverb(norm(bell), 2.2, 0.4)

duck = np.ones(N)
for b in list(GROOVE) + list(LIFT):
    for pos in (0.0, 2.5):
        i = int((b * BAR + pos * BEAT) * SR)
        k = min(int(0.18 * SR), N - i)
        if k <= 0:
            continue
        duck[i:i + k] = np.minimum(duck[i:i + k], 0.55 + 0.45 * np.linspace(0, 1, k))

mono_body = 0.42 * pad * duck + 0.55 * norm(sub) + 0.7 * norm(kick) + 0.13 * norm(clap) + 0.06 * norm(riser)
left = mono_body + 0.36 * arp + 0.06 * norm(shaker) + 0.28 * bell
d = int(0.011 * SR)
right = mono_body + 0.36 * np.concatenate([np.zeros(d), arp[:-d]]) + 0.05 * norm(shaker) + 0.28 * np.concatenate([np.zeros(d), bell[:-d]])
fade = np.ones(N)
fade[: int(0.05 * SR)] = np.linspace(0, 1, int(0.05 * SR))
stereo = np.stack([left * fade, right * fade], axis=1)
stereo = 0.9 * stereo / np.max(np.abs(stereo))
with wave.open("mix.wav", "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((stereo * 32767).astype(np.int16).tobytes())
print("mix.wav written, bar =", round(BAR, 4), "s, duration", DUR)
