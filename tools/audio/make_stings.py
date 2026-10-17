#!/usr/bin/env python3
"""Makes the Sovereign's Eye's own bells and music (audio/stings/), CC0.

    python3 tools/audio/make_stings.py [--preview DIR]

Every sound is synthesized here with numpy from fixed seeds, so the same
script always gives the same sounds:

- church bells and hand bells, built from a bell's partials (the hum,
  prime, tierce, quint and nominal), each fading at its own rate and
  beating slightly;
- a harp and a lute, from their harmonics (the lute's body coloring its
  low notes), plucked;
- kettledrums from a drumhead's modes, struck once or rolled;
- a low drone in open fifths, like an organ's or a hurdy-gurdy's;
- a heartbeat;
- for the Legendary landing, the first phrase of RandomMind's "Medieval:
  Victory Theme" (CC0, in audio/music/) with bells and a drum stroke on its
  first beat.

Everything is in C, the fanfare's key, tuned to A = 440 Hz like it. The
rises stay in open fifths (C, G, D), and the landings add the bright third
(E). A small synthetic hall reverb puts them all in one space.

Each tier's cues are listed in data/eye.json. A cue starts on its step, so
the music stays with the picture at any speed: a rise under the clues (cut
short before the card turns), a landing as it turns, a note for each
ability as it shows, the bells at the Eye's opening and the stamp.

--preview DIR also writes each sound as a WAV and a spectrogram PNG there.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio", "stings")
FANFARE = os.path.join(ROOT, "audio", "music", "randommind-medieval", "victory.ogg")
# Where the fanfare's first phrase has died away, just before the second begins (s).
FANFARE_END = 6.80
FANFARE_FADE = 0.55


def hz(note: str) -> float:
    """Equal-tempered pitch, A4 = 440 Hz: "C4", "G#3", "Eb5"."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semis = names[note[0]]
    rest = note[1:]
    if rest[0] in "#b":
        semis += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semis
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def attack(n: int, seconds: float) -> np.ndarray:
    """A short linear fade-in, so nothing starts with a click."""
    a = np.ones(n)
    k = min(n, max(1, int(seconds * SR)))
    a[:k] = np.linspace(0.0, 1.0, k)
    return a


def release(x: np.ndarray, seconds: float = 0.08) -> np.ndarray:
    """A short fade at the end, so a note cut off at its length doesn't click."""
    k = min(len(x), int(seconds * SR))
    x[-k:] *= np.cos(np.linspace(0.0, np.pi / 2, k)) ** 2
    return x


def band_noise(n: int, lo: float, hi: float, rng: np.random.Generator) -> np.ndarray:
    """White noise kept between lo and hi Hz (an FFT mask with soft edges)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mask = np.clip((f - lo * 0.7) / (lo * 0.3 + 1e-9), 0, 1) * np.clip((hi * 1.3 - f) / (hi * 0.3), 0, 1)
    out = np.fft.irfft(spec * mask, n)
    out /= np.abs(out).max() + 1e-12
    return out


# --- Instruments --------------------------------------------------------------------------

# A tuned church bell's partials against its prime: (ratio, level, how long
# it lasts against the bell's own ring time).
BELL = [(0.5, 0.55, 1.0), (1.0, 0.45, 0.72), (1.183, 0.5, 0.6), (1.506, 0.22, 0.4), (2.0, 1.0, 0.55),
        (2.514, 0.32, 0.3), (2.662, 0.22, 0.26), (3.011, 0.18, 0.2), (4.166, 0.1, 0.13), (5.433, 0.05, 0.09)]
# A hand bell: the fundamental and its twelfth, with a little shimmer above.
HANDBELL = [(1.0, 1.0, 1.0), (2.0, 0.08, 0.4), (3.0, 0.38, 0.5), (4.2, 0.1, 0.25), (5.4, 0.12, 0.22), (8.93, 0.04, 0.1)]


def bell(strike: float, seconds: float, seed: int, ring: float = 1.0, partials=BELL) -> np.ndarray:
    """A bell whose strike note (the pitch heard) is `strike` Hz."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    prime = strike / 2.0 if partials is BELL else strike
    base = (6.5 if partials is BELL else 3.2) * ring * (130.0 / max(prime, 40.0)) ** 0.35
    out = np.zeros_like(t)
    for ratio, level, life in partials:
        f = prime * ratio
        if f > 15000:
            continue
        t60 = base * life
        # Two close components beat slowly, as a real bell's do.
        beat = rng.uniform(0.15, 0.7)
        for sign in (-1.0, 1.0):
            out += 0.5 * level * np.sin(2 * np.pi * (f + sign * beat * 0.5) * t + rng.uniform(0, 2 * np.pi)) * np.exp(-6.91 * t / t60)
    # The clapper's strike: a short metallic tick.
    n = int(0.03 * SR)
    tick = band_noise(n, 1800, 7000, rng) * np.exp(-np.arange(n) / (0.004 * SR)) * 0.22
    out[:n] += tick
    return release(out * attack(len(t), 0.0015), 0.3)


def handbell(strike: float, seconds: float, seed: int) -> np.ndarray:
    return bell(strike, seconds, seed, 1.0, HANDBELL)


def pluck(f: float, seconds: float, kind: str, seed: int) -> np.ndarray:
    """A harp or lute string plucked once."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    harp = kind == "harp"
    where = 0.17 if harp else 0.11          # where along the string it is plucked
    stiff = 0.00008 if harp else 0.00022     # inharmonicity
    first = (3.6 if harp else 1.9) * (262.0 / f) ** 0.55
    out = np.zeros_like(t)
    top = 11000 if harp else 7000
    n = 1
    while n * f < top:
        fn = n * f * np.sqrt(1 + stiff * n * n)
        level = abs(np.sin(n * np.pi * where)) / n ** 1.05
        if not harp:
            # The lute's body: a hump around its air and wood resonances, dull above.
            lf = np.log2(fn)
            level *= 1.0 + 1.2 * np.exp(-((lf - np.log2(110)) ** 2) / 0.18) + 0.8 * np.exp(-((lf - np.log2(240)) ** 2) / 0.12) \
                + 0.6 * np.exp(-((lf - np.log2(520)) ** 2) / 0.15)
            level *= 1.0 / (1.0 + (fn / 2500.0) ** 2)
        t60 = first / (1.0 + (0.22 if harp else 0.5) * (n - 1))
        out += level * np.sin(2 * np.pi * fn * t + rng.uniform(0, 2 * np.pi)) * np.exp(-6.91 * t / t60)
        n += 1
    out /= np.abs(out[: int(0.05 * SR)]).max() + 1e-12
    k = int(0.004 * SR)
    out[:k] += band_noise(k, 600, 5000, rng) * np.linspace(0.18, 0, k)
    return release(out * attack(len(t), 0.002 if harp else 0.004), 0.25)


TIMP = [(1.0, 1.0, 1.0), (1.504, 0.5, 0.62), (1.742, 0.25, 0.5), (2.0, 0.32, 0.45), (2.245, 0.18, 0.35), (2.494, 0.14, 0.3), (2.8, 0.08, 0.22)]


def drum(f: float, seconds: float, seed: int, ring: float = 2.0) -> np.ndarray:
    """A kettledrum stroke tuned to `f` Hz."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    glide = 1.0 + 0.035 * np.exp(-t / 0.03)
    out = np.zeros_like(t)
    for ratio, level, life in TIMP:
        phase = 2 * np.pi * np.cumsum(f * ratio * glide) / SR
        out += level * np.sin(phase + rng.uniform(0, 2 * np.pi)) * np.exp(-6.91 * t / (ring * life))
    n = int(0.06 * SR)
    out[:n] += band_noise(n, 60, 1800, rng) * np.exp(-np.arange(n) / (0.012 * SR)) * 0.6
    return release(out * attack(len(t), 0.001), 0.2)


def roll(f: float, seconds: float, seed: int, start: float = 0.25, rate: float = 16.0) -> np.ndarray:
    """A kettledrum roll swelling from `start` to full over `seconds`."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int((seconds + 2.0) * SR))
    t = 0.0
    while t < seconds:
        swell = start + (1.0 - start) * (t / seconds) ** 1.6
        hit = drum(f, 1.6, int(rng.integers(1 << 30)), 1.4) * swell * rng.uniform(0.78, 1.0)
        i = int((t + rng.uniform(-0.006, 0.006)) * SR)
        i = max(i, 0)
        out[i:i + len(hit)] += hit[: len(out) - i]
        t += 1.0 / (rate * (1.0 + 0.25 * t / seconds))
    return out


def drone(freqs: list, seconds: float, seed: int) -> np.ndarray:
    """A soft reed-and-pipe drone on these pitches, breathing slightly."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for f in freqs:
        for voice in (-1.0, 1.0):
            vib = 1.0 + 0.0025 * np.sin(2 * np.pi * 4.7 * t + rng.uniform(0, 6.28)) + voice * 0.0012
            n = 1
            while n * f < 4000:
                fn = n * f
                # A vowel-like color ("o"): formants near 450, 800 and 2800 Hz.
                form = 0.25 + np.exp(-((fn - 450) / 160) ** 2) + 0.7 * np.exp(-((fn - 800) / 220) ** 2) + 0.2 * np.exp(-((fn - 2800) / 400) ** 2)
                level = form / n ** 1.4
                out += level * np.sin(2 * np.pi * np.cumsum(fn * vib) / SR + rng.uniform(0, 6.28))
                n += 1
    return release(out / (np.abs(out).max() + 1e-12), 0.3)


def heartbeat(seconds: float, seed: int) -> np.ndarray:
    """One beat, lub-dub."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int(seconds * SR))
    for at, f0, level in ((0.0, 62.0, 1.0), (0.27, 72.0, 0.7)):
        n = int(0.45 * SR)
        t = np.arange(n) / SR
        f = f0 * (1.0 + 0.5 * np.exp(-t / 0.025))
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)
        body += band_noise(n, 30, 300, rng) * np.exp(-t / 0.03) * 0.35
        i = int(at * SR)
        beat = release(level * body * attack(n, 0.004), 0.1)
        out[i:i + n] += beat[: len(out) - i]
    return out


def fanfare() -> np.ndarray:
    """The victory theme's first phrase (stereo), fading as it dies away."""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", FANFARE, "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)
    x = x[: int(FANFARE_END * SR)].copy()
    k = int(FANFARE_FADE * SR)
    x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k))[:, None] ** 2
    return x


# --- Mixing -------------------------------------------------------------------------------

class Mix:
    """A stereo bus: place mono sounds at times with a pan and level, add a
    stereo track, then put it all in the hall."""

    def __init__(self, seconds: float):
        self.dry = np.zeros((int(seconds * SR), 2))
        self.send = np.zeros_like(self.dry)

    def add(self, sound: np.ndarray, at: float, level: float = 1.0, pan: float = 0.0, wet: float = 0.3) -> None:
        i = int(at * SR)
        if sound.ndim == 1:
            a = (pan + 1.0) * np.pi / 4.0
            sound = np.stack([sound * np.cos(a), sound * np.sin(a)], axis=1) * np.sqrt(2.0)
        n = min(len(sound), len(self.dry) - i)
        if n <= 0:
            return
        self.dry[i:i + n] += sound[:n] * level
        self.send[i:i + n] += sound[:n] * level * wet

    def render(self, peak_db: float, tail: float = 0.25) -> np.ndarray:
        out = self.dry + hall(self.send)
        # Trim what has died away, then fade the last moment out.
        loud = np.abs(out).max(axis=1)
        floor = loud.max() * 10 ** (-66 / 20.0)
        last = np.nonzero(loud > floor)[0]
        end = min(len(out), (last[-1] if len(last) else len(out) - 1) + int(0.05 * SR))
        out = out[:end]
        k = min(int(tail * SR), len(out))
        out[-k:] *= np.cos(np.linspace(0, np.pi / 2, k))[:, None] ** 2
        out[: int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))[:, None]
        return out * (10 ** (peak_db / 20.0) / (np.abs(out).max() + 1e-12))


_HALL: np.ndarray | None = None


def hall(x: np.ndarray) -> np.ndarray:
    """A stone hall's reverb: a made-up stereo impulse (early reflections,
    then a tail that dies faster in the treble), applied by FFT."""
    global _HALL
    if _HALL is None:
        rng = np.random.default_rng(1187)
        n = int(2.8 * SR)
        t = np.arange(n) / SR
        ir = np.zeros((n, 2))
        for ch in range(2):
            tail = np.zeros(n)
            for lo, hi, rt in ((20, 500, 2.4), (500, 3000, 1.9), (3000, 16000, 1.0)):
                tail += band_noise(n, lo, hi, rng) * np.exp(-6.91 * t / rt)
            tail *= np.clip((t - 0.018) / 0.04, 0, 1)
            for d, g in ((0.011, 0.5), (0.019, 0.4), (0.027, 0.33), (0.041, 0.25), (0.053, 0.2)):
                ir[int((d + rng.uniform(0, 0.004)) * SR), ch] += g * rng.choice([-1.0, 1.0])
            ir[:, ch] += tail * 0.09
        _HALL = ir / np.sqrt((ir ** 2).sum() / 2.0)
    n = len(x) + len(_HALL)
    size = 1 << (n - 1).bit_length()
    out = np.zeros((n - 1, 2))
    for ch in range(2):
        out[:, ch] = np.fft.irfft(np.fft.rfft(x[:, ch], size) * np.fft.rfft(_HALL[:, ch], size), size)[: n - 1]
    return out[: len(x)] * 0.5


# --- The cues -----------------------------------------------------------------------------

def ordinary() -> np.ndarray:
    """Ordinary: a lute's open fifth, then its octave, quietly."""
    m = Mix(4.0)
    m.add(pluck(hz("C3"), 3.0, "lute", 11), 0.0, 0.8, -0.2)
    m.add(pluck(hz("G3"), 3.0, "lute", 12), 0.035, 0.7, 0.2)
    m.add(pluck(hz("C4"), 2.5, "lute", 13), 0.62, 0.55, 0.05)
    return m.render(-4.0)


def skilled_land() -> np.ndarray:
    """Skilled, as the card turns: a harp strummed up C-E-G-C, a hand bell."""
    m = Mix(5.0)
    for k, note in enumerate(["C4", "E4", "G4", "C5", "E5"]):
        m.add(pluck(hz(note), 3.2, "harp", 20 + k), 0.045 * k, 0.6 + 0.08 * k, -0.4 + 0.2 * k)
    m.add(handbell(hz("C6"), 3.0, 26), 0.2, 0.32, 0.25, 0.4)
    return m.render(-3.0)


def rise(build: float, legendary: bool, hold: float = 0.9) -> np.ndarray:
    """Under the clues: a drone swelling in open fifths, a harp turning over
    and over, faster, and the kettledrums rolling up to the break. It peaks
    after `build` seconds (when the tier's clues end and it is cut), then
    holds there for `hold` more, in case the cut comes a moment late."""
    seconds = build + hold
    m = Mix(seconds + 0.3)
    t = t_axis(seconds)
    swell = np.clip(t / build, 0, 1) ** 1.3
    pitches = [hz("C2"), hz("G2"), hz("C3")] if legendary else [hz("C2"), hz("G2")]
    m.add(drone(pitches, seconds, 30) * (0.12 + 0.88 * swell), 0.0, 0.32 if legendary else 0.26, 0.0, 0.35)
    figure = ["G4", "C5", "D5", "C5", "G4", "C5", "G5", "D5"] if legendary else ["G4", "C5", "G4", "D5"]
    at = 0.05
    k = 0
    while at < seconds - 0.1:
        p = min(at / build, 1.0)
        m.add(pluck(hz(figure[k % len(figure)]), 1.6, "harp", 40 + k), at, 0.25 + 0.5 * p, -0.3 + 0.6 * (k % 2))
        k += 1
        at += 0.19 - 0.08 * p
    lead = 0.3 if legendary else 0.4
    m.add(roll(hz("C2"), build - lead, 50, 0.15), lead, 0.42 if legendary else 0.34, 0.0, 0.25)
    m.add(roll(hz("C2"), hold, 51, 1.0, 21.0), build, 0.42 if legendary else 0.34, 0.0, 0.25)
    if legendary:
        for k, note in enumerate(["G5", "C6", "D6", "G6"]):
            m.add(handbell(hz(note), 2.0, 60 + k), 0.4 + build * 0.2 * k, 0.12 + 0.03 * k, -0.5 + 0.33 * k, 0.5)
    return m.render(-4.5, 0.1)


def exceptional_land() -> np.ndarray:
    """Exceptional, as the card turns: a drum stroke, a harp swept upward and
    bells on C, G and E ringing out."""
    m = Mix(7.0)
    m.add(drum(hz("C2"), 3.0, 70), 0.0, 0.9, 0.0, 0.25)
    scale = ["C4", "D4", "E4", "G4", "A4", "C5", "D5", "E5", "G5", "A5", "C6"]
    for k, note in enumerate(scale):
        m.add(pluck(hz(note), 2.6, "harp", 71 + k), 0.03 + 0.032 * k, 0.32 + 0.03 * k, -0.6 + 0.12 * k)
    m.add(bell(hz("C5"), 6.0, 80), 0.0, 0.55, -0.15, 0.35)
    m.add(bell(hz("G5"), 5.0, 81), 0.04, 0.32, 0.3, 0.35)
    m.add(handbell(hz("E6"), 3.5, 82), 0.38, 0.22, 0.45, 0.4)
    return m.render(-2.0)


def legendary_land() -> np.ndarray:
    """Legendary, as the card turns: the victory fanfare's first phrase, with a
    great bell, a drum stroke and a bright bell on its first beat."""
    brass = fanfare()
    m = Mix(len(brass) / SR + 3.0)
    m.add(brass, 0.0, 1.0, 0.0, 0.1)
    m.add(bell(hz("C3"), 7.0, 90, 1.2), 0.0, 0.5, -0.1, 0.3)
    m.add(bell(hz("C5"), 5.0, 91), 0.02, 0.25, 0.25, 0.35)
    m.add(drum(hz("C2"), 3.0, 92), 0.0, 0.7, 0.0, 0.25)
    return m.render(-1.5, 0.6)


def single(sound: np.ndarray, seconds: float, level: float = 1.0, peak: float = -3.0, wet: float = 0.3) -> np.ndarray:
    m = Mix(seconds)
    m.add(sound, 0.0, level, 0.0, wet)
    return m.render(peak)


def row(note: str, seed: int) -> np.ndarray:
    """One ability shown: a harp note, with a quiet hand bell an octave up."""
    m = Mix(3.0)
    m.add(pluck(hz(note), 2.4, "harp", seed), 0.0, 0.9, 0.0, 0.35)
    m.add(handbell(hz(note) * 2, 1.6, seed + 1), 0.0, 0.18, 0.2, 0.4)
    return m.render(-5.0)


def stamp(twice: bool) -> np.ndarray:
    """The greatest gift lands: a bell on C with a deep one under it (twice
    for a legend)."""
    m = Mix(7.0)
    for k in range(2 if twice else 1):
        at = 0.32 * k
        m.add(bell(hz("C5"), 5.0, 100 + k), at, 0.7 if k == 0 else 0.55, -0.1 + 0.2 * k, 0.35)
        m.add(bell(hz("C4"), 6.0, 110 + k), at, 0.45, 0.0, 0.35)
    return m.render(-2.5)


SOUNDS = {
    # The Eye opening, tier by tier.
    "bell_small": lambda: single(handbell(hz("G5"), 3.5, 1), 4.0, peak=-4.0),
    "bell_deep": lambda: single(bell(hz("C4"), 6.5, 2), 7.0, peak=-2.5),
    "bell_great": lambda: single(bell(hz("C3"), 9.0, 3, 1.3), 9.5, peak=-1.5),
    "heartbeat": lambda: single(heartbeat(0.8, 4), 1.2, peak=-2.0, wet=0.12),
    # The tiers' music.
    "ordinary": ordinary,
    "skilled_land": skilled_land,
    # Cut when the clues end: 1.95 s (Exceptional) and 2.55 s (Legendary)
    # after the card appears (data/eye.json).
    "exceptional_rise": lambda: rise(1.95, False),
    "exceptional_land": exceptional_land,
    "legendary_rise": lambda: rise(2.55, True),
    "legendary_land": legendary_land,
    # Each ability as it shows (weakest first, rising), and the stamp.
    "row_1": lambda: row("E5", 120),
    "row_2": lambda: row("G5", 130),
    "row_3": lambda: row("C6", 140),
    "stamp_once": lambda: stamp(False),
    "stamp_twice": lambda: stamp(True),
}


def write_ogg(path: str, x: np.ndarray) -> None:
    pcm = np.clip(x, -1.0, 1.0).astype(np.float32).tobytes()
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                    "-c:a", "libvorbis", "-q:a", "6", path], input=pcm, check=True)


def write_preview(dirname: str, name: str, x: np.ndarray) -> None:
    import wave
    from PIL import Image
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(dirname, name + ".wav"), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    mono = x.mean(axis=1)
    n, hop = 2048, 256
    frames = [np.abs(np.fft.rfft(mono[i:i + n] * np.hanning(n))) for i in range(0, max(1, len(mono) - n), hop)]
    spec = 20 * np.log10(np.array(frames).T + 1e-6)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    rows = np.searchsorted(f, np.geomspace(40, 16000, 300))
    img = np.clip((spec[rows] - spec.max() + 70) / 70, 0, 1)[::-1]
    Image.fromarray((img * 255).astype(np.uint8)).resize((max(200, img.shape[1]), 300)).save(os.path.join(dirname, name + ".png"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    ap.add_argument("--only")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
    for name, make in SOUNDS.items():
        if args.only and name not in args.only.split(","):
            continue
        x = make()
        write_ogg(os.path.join(OUT, name + ".ogg"), x)
        if args.preview:
            write_preview(args.preview, name, x)
        print("%-18s %5.2f s  peak %5.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.abs(x).max())))


if __name__ == "__main__":
    sys.exit(main())
