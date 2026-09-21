#!/usr/bin/env python3
"""Generate the keyboard's built-in Typewriter sound theme.

The clacks are synthesised rather than sampled so the repo carries no recorded
audio: white noise through a couple of resonators, plus a low body thump, with
an exponential decay envelope. Output is 44.1 kHz mono 16-bit WAV, which is
what AudioServicesCreateSystemSoundID will play.

    ./scripts/make-typewriter-sounds.py        # rewrites Sounds/tw-*.wav
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "Sounds")


def noise(n, seed):
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def resonate(x, freq, q):
    """Two-pole resonator: rings `x` at `freq`, sharpness from `q` (0-1)."""
    w = 2 * math.pi * freq / RATE
    a1, a2 = 2 * q * math.cos(w), -q * q
    y1 = y2 = 0.0
    out = []
    for s in x:
        y = s * (1 - q) + a1 * y1 + a2 * y2
        y2, y1 = y1, y
        out.append(y)
    return out


def decay(n, tau, attack=0.0015):
    """Fast attack, exponential tail."""
    rise = max(int(attack * RATE), 1)
    return [(min(i / rise, 1.0)) * math.exp(-i / (tau * RATE)) for i in range(n)]


def tone(n, freq, tau, phase=0.0):
    env = decay(n, tau)
    return [env[i] * math.sin(2 * math.pi * freq * i / RATE + phase) for i in range(n)]


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for layer in layers:
        for i, s in enumerate(layer):
            out[i] += s
    return out


def normalise(x, peak):
    high = max(abs(s) for s in x) or 1.0
    return [s * peak / high for s in x]


def click(ms, seed, body, ring, tau, q=0.96):
    """One mechanical clack: a resonant noise burst over a low body thump."""
    n = int(RATE * ms / 1000)
    burst = [s * e for s, e in zip(noise(n, seed), decay(n, tau))]
    return mix(resonate(burst, ring, q),
               [s * 0.6 for s in resonate(burst, ring * 1.87, q * 0.97)],
               [s * 0.9 for s in tone(n, body, tau * 2.2)])


def write(name, samples, peak=0.85):
    samples = normalise(samples, peak)
    # 3 ms fade-out so nothing ends on a step.
    fade = int(RATE * 0.003)
    for i in range(1, min(fade, len(samples)) + 1):
        samples[-i] *= i / fade
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
                               for s in samples))
    print(f"{name}  {len(samples) / RATE * 1000:.0f} ms")


def main():
    # A type bar hitting the platen: bright, short.
    write("tw-key.wav", click(70, 1, body=190, ring=2600, tau=0.012))
    # The space bar is wider and duller, and the carriage moves further.
    write("tw-space.wav", click(110, 2, body=120, ring=1500, tau=0.022, q=0.94), peak=0.8)
    # Backspace: quieter, with the ratchet's second tick.
    n = int(RATE * 0.09)
    tick = click(55, 3, body=230, ring=3100, tau=0.009)
    lag = [0.0] * int(RATE * 0.028) + [s * 0.45 for s in click(45, 4, body=260, ring=3400, tau=0.007)]
    write("tw-delete.wav", mix(tick + [0.0] * (n - len(tick)), lag), peak=0.7)
    # Carriage return: the margin bell, then the carriage sliding home.
    slide = [s * e for s, e in zip(noise(int(RATE * 0.34), 5),
                                   [min(i / (RATE * 0.06), 1.0) * math.exp(-i / (RATE * 0.10))
                                    for i in range(int(RATE * 0.34))])]
    bell = mix(tone(int(RATE * 0.55), 1430, 0.16),
               [s * 0.5 for s in tone(int(RATE * 0.55), 2870, 0.10)],
               [s * 0.25 for s in tone(int(RATE * 0.55), 4310, 0.06)])
    write("tw-return.wav", mix(bell, [s * 0.5 for s in resonate(slide, 900, 0.9)],
                              [0.0] * int(RATE * 0.30) + click(60, 6, body=140, ring=1800, tau=0.014)),
          peak=0.8)
    # Shift / 123 / globe: a soft lever, no platen strike.
    write("tw-modifier.wav", click(60, 7, body=210, ring=1900, tau=0.010, q=0.93), peak=0.55)


if __name__ == "__main__":
    main()
