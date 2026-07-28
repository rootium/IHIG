#!/usr/bin/env python3
"""Renders Tessera's music.

Two ambient loops, additively synthesised from scratch — no samples, no
library, no download. Everything is sine partials, a filtered noise wash and a
scatter of struck bells over a slow chord cycle.

Making a loop seamless is the only fiddly part, and it is handled twice over:
every oscillator's frequency is nudged to the nearest value that completes a
whole number of cycles in the loop, and the tail is then folded back over the
head with an equal-power crossfade so the noise layer and any bell still
ringing at the end wrap cleanly.

Run:  python3 tools/tessera/make_music.py
Writes: games/tessera/audio/*.wav
"""

from __future__ import annotations

import math
import random
import struct
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "games/tessera/audio"

RATE = 22050
FADE = 1.25          # seconds folded from the tail back over the head


def snap(freq: float, n: int) -> float:
    """Nearest frequency completing a whole number of cycles in n samples."""
    cycles = max(1, round(freq * n / RATE))
    return cycles * RATE / n


def midi(note: float) -> float:
    return 440.0 * (2.0 ** ((note - 69.0) / 12.0))


class Track:
    def __init__(self, seconds: float, seed: int):
        self.n = int(seconds * RATE)
        self.tail = int(FADE * RATE)
        self.buf = array("d", bytes(8 * (self.n + self.tail)))
        self.rng = random.Random(seed)

    # -- layers

    def drone(self, note: float, gain: float, partials, wobble: float):
        """A sustained tone. `partials` are (multiple, level) pairs."""
        n = self.n
        base = snap(midi(note), n)
        # The slow beating that keeps a drone from sounding dead, at an
        # integer number of cycles per loop so it too wraps.
        lfo = snap(wobble, n)
        for mult, level in partials:
            f = snap(base * mult, n)
            w = 2.0 * math.pi * f / RATE
            wl = 2.0 * math.pi * lfo / RATE
            for i in range(n + self.tail):
                amp = 0.72 + 0.28 * math.sin(wl * i + mult)
                self.buf[i] += math.sin(w * i) * level * gain * amp

    def pad(self, chords, gain: float):
        """A chord cycle. Each chord fades in and out over its own span."""
        n = self.n
        span = n // len(chords)
        for ci, notes in enumerate(chords):
            start = ci * span
            for note in notes:
                f = snap(midi(note), n)
                w = 2.0 * math.pi * f / RATE
                detune = 2.0 * math.pi * snap(midi(note) * 1.003, n) / RATE
                for k in range(span + self.tail):
                    i = start + k
                    if i >= n + self.tail:
                        i -= n
                    # equal-power swell across the chord's span
                    q = k / span
                    env = math.sin(math.pi * min(q, 1.0)) ** 1.4 if q <= 1.0 else 0.0
                    if env <= 0.0005:
                        continue
                    s = start + k
                    v = (math.sin(w * s) * 0.6 + math.sin(detune * s) * 0.4)
                    self.buf[i] += v * env * gain

    def bells(self, scale, count: int, gain: float, decay: float, octave: int):
        """Struck partials scattered over the loop, tails wrapped."""
        n = self.n
        total = n + self.tail
        for _ in range(count):
            at = self.rng.randrange(n)
            note = self.rng.choice(scale) + 12 * octave
            f = snap(midi(note), n)
            dur = int(decay * RATE)
            level = gain * self.rng.uniform(0.5, 1.0)
            for mult, amt, sharp in ((1.0, 1.0, 1.0), (2.01, 0.34, 1.7), (3.02, 0.15, 2.6)):
                w = 2.0 * math.pi * f * mult / RATE
                for k in range(dur):
                    i = at + k
                    if i >= total:
                        i -= n
                    e = math.exp(-3.4 * sharp * k / dur)
                    self.buf[i] += math.sin(w * k) * e * amt * level

    def air(self, gain: float, cutoff: float):
        """A one-pole lowpassed noise wash, breathing very slowly."""
        n = self.n + self.tail
        a = math.exp(-2.0 * math.pi * cutoff / RATE)
        state = 0.0
        breathe = 2.0 * math.pi * snap(0.055, self.n) / RATE
        for i in range(n):
            state = a * state + (1.0 - a) * (self.rng.random() * 2.0 - 1.0)
            self.buf[i] += state * gain * (0.55 + 0.45 * math.sin(breathe * i))

    # -- output

    def write(self, path: Path):
        n, tail = self.n, self.tail
        # Fold the tail back over the head, equal power, so the loop point is
        # inaudible even for the noise layer.
        for k in range(tail):
            q = k / tail
            fade_in = math.sin(0.5 * math.pi * q)
            fade_out = math.cos(0.5 * math.pi * q)
            self.buf[k] = self.buf[k] * fade_in + self.buf[n + k] * fade_out

        peak = max(abs(v) for v in self.buf[:n]) or 1.0
        norm = 0.82 / peak
        pcm = array("h", bytes(2 * n))
        for i in range(n):
            v = self.buf[i] * norm
            # gentle saturation keeps the swells from sounding brittle
            v = math.tanh(v * 1.15) * 0.92
            pcm[i] = max(-32767, min(32767, int(v * 32767)))

        data = pcm.tobytes()
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as f:
            f.write(b"RIFF")
            f.write(struct.pack("<I", 36 + len(data)))
            f.write(b"WAVEfmt ")
            f.write(struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16))
            f.write(b"data")
            f.write(struct.pack("<I", len(data)))
            f.write(data)
        print(f"  {path.name}  {n / RATE:.1f}s  {len(data) / 1e6:.2f} MB")


# D natural minor, which is where this game lives.
D, F, G, A, Bb, C, E = 50, 53, 55, 57, 58, 60, 52
PENT = [D, F, G, A, C]


def bed():
    """The chamber loop: slow, patient, mostly out of the way."""
    t = Track(64.0, 4)
    t.drone(D - 12, 0.30, ((1.0, 1.0), (2.0, 0.34), (3.0, 0.12), (5.0, 0.05)), 0.031)
    t.pad([
        [D, F, A, C + 12],          # Dm7
        [Bb - 12, D, F, A + 12],    # Bbmaj7
        [F, A, C, E + 12],          # Fmaj7
        [G, Bb, D + 12, F + 12],    # Gm7
    ], 0.22)
    t.bells(PENT, 26, 0.16, 2.4, 1)
    t.bells(PENT, 10, 0.10, 4.2, 2)
    t.air(0.030, 900.0)
    t.write(OUT / "bed.wav")


def title():
    """Sparser, higher, colder — the void before you step into it."""
    t = Track(36.0, 11)
    t.drone(D - 12, 0.26, ((1.0, 1.0), (2.0, 0.28), (4.0, 0.10)), 0.042)
    t.pad([
        [D, A, C + 12, E + 12],
        [Bb - 12, F, A, D + 12],
    ], 0.20)
    t.bells(PENT, 14, 0.19, 3.4, 2)
    t.air(0.026, 1500.0)
    t.write(OUT / "title.wav")


if __name__ == "__main__":
    print("rendering music")
    bed()
    title()
