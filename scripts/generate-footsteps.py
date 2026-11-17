"""Rebuild original, deterministic shoe foley; Python standard library only.

Layer filtered sole impacts, a later toe contact, and a short grit/cloth scuff.
No sustained oscillator: the low end comes from damped, filtered noise.
Run from any directory; replaces the six bundled player footstep WAVs.
"""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050


def make_step(name, seed, wet=False):
    rng = random.Random(seed)
    duration = 0.30 if wet else 0.25
    samples = [0.0] * int(RATE * duration)

    def contact(start, length, gain, smoothing):
        low = 0.0
        count = int(length * RATE)
        for i in range(count):
            low += smoothing * (rng.uniform(-1, 1) - low)
            t = i / RATE
            envelope = (1 - math.exp(-t / 0.002)) * math.exp(-t / (length / 5))
            index = int(start * RATE) + i
            if index < len(samples):
                samples[index] += low * gain * envelope

    contact(0, 0.15, 2.4, 0.045)  # Weight landing on the heel.
    contact(rng.uniform(0.045, 0.065), 0.105, 1.05, 0.12)  # Toe rolls down.
    contact(0.02, 0.21 if wet else 0.16, 0.38, 0.55 if wet else 0.25)
    if wet:
        for _ in range(8):
            contact(rng.uniform(0.035, 0.16), 0.025, 0.16, 0.70)
    # DC removal and a smooth tail prevent clicks on playback/retrigger.
    mean = sum(samples) / len(samples)
    samples = [(v - mean) * min(1, i / (RATE * 0.003),
                (len(samples) - 1 - i) / (RATE * 0.025)) for i, v in enumerate(samples)]
    scale = 0.66 / max(abs(v) for v in samples)
    pcm = b''.join(struct.pack('<h', round(v * scale * 32767)) for v in samples)
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(pcm)


if __name__ == '__main__':
    for i, name in enumerate(['step-a', 'step-b', 'step-c', 'step-d',
                              'garden-step-a', 'garden-step-b']):
        make_step(name, 301 + i, wet=name.startswith('garden'))
