"""Original 84 BPM lo-fi bed with a tanpura drone for the Bolkit brag v2.

numpy renders dry stems; mix.sh filters, adds space and masters them with ffmpeg.
Bars (2.857 s): 1 intro keys + drone, 2-7 full groove, 8 breakdown (no kick/snare),
9-10 groove + bansuri-style phrase, then a ringing tail to 29 s.
"""
import wave
import numpy as np

SR = 44100
BPM = 84
BEAT = 60 / BPM
BAR = 4 * BEAT
DUR = 29.0
N = int(SR * DUR)
rng = np.random.default_rng(7)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def buf():
    return np.zeros(N, dtype=np.float64)


def place(dst, sig, t):
    i = int(t * SR)
    if i >= N:
        return
    j = min(N, i + len(sig))
    dst[i:j] += sig[: j - i]


def env_exp(n, decay):
    return np.exp(-np.arange(n) / (decay * SR))


def attack(n, a):
    e = np.ones(n)
    k = max(1, int(a * SR))
    e[:k] = np.linspace(0, 1, k)
    return e


def swing(t_beats):
    # delay off-beat eighths for a lazy feel
    frac = t_beats % 1.0
    return t_beats + (0.07 if abs(frac - 0.5) < 1e-6 else 0.0)


# ---- tanpura drone: Pa Sa Sa Sa(low), rich buzzy plucks ----
def tanpura_pluck(f, length=6.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for h in range(1, 16):
        buzz = 1 + 0.35 * np.sin(2 * np.pi * (0.4 + 0.07 * h) * t + h)  # jawari shimmer
        sig += (1 / h ** 1.1) * buzz * np.sin(2 * np.pi * f * h * t + rng.uniform(0, 6.28))
    return sig * env_exp(n, 2.2) * attack(n, 0.02)


drone = buf()
D2, A2, D3 = 38, 45, 50
cycle = [(A2, 0.0), (D3, 0.75), (D3, 1.5), (D2, 2.25)]
t = 0.0
while t < DUR:
    for note, off in cycle:
        place(drone, tanpura_pluck(hz(note)), t + off * BAR / 3.0)
    t += BAR
drone /= np.max(np.abs(drone)) + 1e-9

# ---- electric piano chords ----
def ep_note(f, length, vel):
    n = int(length * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t)
    bell = 0.25 * np.sin(2 * np.pi * 7 * f * t) * env_exp(n, 0.05)
    trem = 1 + 0.12 * np.sin(2 * np.pi * 4.2 * t)
    return vel * (body * env_exp(n, 1.6) + bell) * trem * attack(n, 0.004)


CHORDS = {
    "Dm9": [50, 53, 57, 60, 64],
    "G13": [43, 53, 59, 64],
    "Am7": [45, 55, 60, 64],
    "Bbmaj7": [46, 53, 57, 62],
    "Dadd9": [50, 57, 62, 64, 69],
}
prog = ["Dm9", "G13", "Dm9", "Am7", "Dm9", "G13", "Dm9", "Bbmaj7", "Am7", "Dadd9", "Dadd9"]
keys = buf()
bass = buf()
for b, name in enumerate(prog):
    start = b * BAR
    notes = CHORDS[name]
    for k, m in enumerate(notes):
        place(keys, ep_note(hz(m), BAR * 1.2, 0.5 + 0.1 * rng.random()), start + 0.012 * k)
        if b not in (0, 10):
            place(keys, ep_note(hz(m), BAR * 0.6, 0.28), start + swing(2.5) * BEAT + 0.01 * k)
    root = notes[0] - 12
    if 1 <= b <= 9:
        for beat_pos, ln in ((0.0, 1.4), (swing(2.5), 1.0)):
            n = int(ln * SR)
            tt = np.arange(n) / SR
            s = np.sin(2 * np.pi * hz(root) * tt) + 0.2 * np.sin(2 * np.pi * 2 * hz(root) * tt)
            place(bass, s * env_exp(n, 0.6) * attack(n, 0.01), start + beat_pos * BEAT)
keys /= np.max(np.abs(keys)) + 1e-9
bass /= np.max(np.abs(bass)) + 1e-9

# ---- drums ----
def kick():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 80 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(n, 0.16)


def rim():
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    return (0.6 * rng.standard_normal(n) + np.sin(2 * np.pi * 190 * t)) * env_exp(n, 0.05)


def hat(vel):
    n = int(0.06 * SR)
    return vel * rng.standard_normal(n) * env_exp(n, 0.012)


drums_low, drums_hi = buf(), buf()
for b in range(1, 10):
    start = b * BAR
    breakdown = b == 7
    if not breakdown:
        for pos in (0.0, swing(2.5)):
            place(drums_low, kick(), start + pos * BEAT)
        for pos in (1.0, 3.0):
            place(drums_hi, 0.8 * rim(), start + pos * BEAT)
    for e in range(8):
        pos = swing(e / 2)
        vel = 0.55 if e % 2 == 0 else 0.32
        place(drums_hi, hat(vel * (0.8 + 0.4 * rng.random())), start + pos * BEAT)
drums_low /= np.max(np.abs(drums_low)) + 1e-9
drums_hi /= np.max(np.abs(drums_hi)) + 1e-9

# ---- bansuri-style phrase over bars 8-9 (Kafi flavour) ----
def flute(f, length):
    n = int(length * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t * 3, 0, 1)
    phase = 2 * np.pi * np.cumsum(f * vib) / SR
    tone = np.sin(phase) + 0.12 * np.sin(2 * phase)
    breath = 0.05 * rng.standard_normal(n)
    e = np.clip(t / 0.08, 0, 1) * np.clip((length - t) / 0.25, 0, 1)
    return (tone + breath) * e


lead = buf()
phrase = [(74, 0.0, 0.9), (76, 1.0, 0.45), (77, 1.5, 0.45), (76, 2.0, 0.9), (74, 3.0, 0.9), (69, 4.0, 1.8), (74, 6.0, 1.9)]
for m, pos, ln in phrase:
    place(lead, flute(hz(m), ln * BEAT * 1.05), 8 * BAR + pos * BEAT)
lead /= np.max(np.abs(lead)) + 1e-9

# ---- vinyl crackle ----
crackle = 0.015 * rng.standard_normal(N)
pops = rng.random(N) < 18 / SR
crackle[pops] += rng.uniform(0.2, 0.6, pops.sum()) * rng.choice([-1, 1], pops.sum())


def write(name, x):
    x = np.clip(x, -1, 1)
    with wave.open(f"{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


for name, x in {
    "stem-drone": drone,
    "stem-keys": keys,
    "stem-bass": bass,
    "stem-kick": drums_low,
    "stem-hats": drums_hi,
    "stem-lead": lead,
    "stem-crackle": crackle,
}.items():
    write(name, x * 0.9)
print("stems written, bar =", round(BAR, 4), "s")
