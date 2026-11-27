"""Makes the video's sound effects from scratch (sine tones and filtered
noise), so nothing is downloaded and there is no licence to check.

    python3 Demo/video/make_sfx.py

Writes remotion/public/sfx/NAME.wav (48 kHz, mono). They are short and soft
on purpose: in the video they play well under the voice.
"""
import math, random, struct, wave
from pathlib import Path

RATE = 48_000
OUT = Path(__file__).parent / "remotion/public/sfx"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(26)


def envelope(n, attack, decay, hold=0.0):
    """Raised-cosine attack, optional hold, exponential decay; all in seconds."""
    a, h = int(attack * RATE), int(hold * RATE)
    out = []
    for i in range(n):
        if i < a:
            out.append(0.5 - 0.5 * math.cos(math.pi * i / max(a, 1)))
        elif i < a + h:
            out.append(1.0)
        else:
            out.append(math.exp(-(i - a - h) / (decay * RATE)))
    fade = int(0.004 * RATE)  # never end on a click
    for i in range(min(fade, n)):
        out[n - 1 - i] *= i / fade
    return out


def tone(seconds, start_hz, end_hz=None, attack=0.004, decay=0.08, hold=0.0, partials=((1, 1.0),)):
    """A sine that glides from start_hz to end_hz, with optional overtones."""
    n = int(seconds * RATE)
    end_hz = end_hz or start_hz
    env = envelope(n, attack, decay, hold)
    phase, out = 0.0, []
    for i in range(n):
        hz = start_hz * (end_hz / start_hz) ** (i / n)
        phase += 2 * math.pi * hz / RATE
        out.append(env[i] * sum(level * math.sin(phase * k) for k, level in partials))
    return out


def noise(seconds, low_hz, high_hz, attack=0.002, decay=0.02, hold=0.0, sweep_to=None):
    """White noise through a band-pass whose centre can sweep (a state-variable filter)."""
    n = int(seconds * RATE)
    env = envelope(n, attack, decay, hold)
    centre0 = math.sqrt(low_hz * high_hz)
    q = centre0 / max(high_hz - low_hz, 1)
    low = band = 0.0
    out = []
    for i in range(n):
        centre = centre0 if sweep_to is None else centre0 * (sweep_to / centre0) ** (i / n)
        f = 2 * math.sin(math.pi * min(centre, RATE / 6) / RATE)
        high = random.uniform(-1, 1) - low - band / max(q, 0.5)
        band += f * high
        low += f * band
        out.append(env[i] * band)
    return out


def mix(*layers):
    """Layers are (samples, start seconds, level)."""
    n = max(int(start * RATE) + len(samples) for samples, start, _ in layers)
    out = [0.0] * n
    for samples, start, level in layers:
        offset = int(start * RATE)
        for i, v in enumerate(samples):
            out[offset + i] += v * level
    return out


def save(name, samples, peak=0.5):
    top = max(abs(v) for v in samples) or 1
    data = b"".join(struct.pack("<h", int(max(-1, min(1, v / top * peak)) * 32767)) for v in samples)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)
    print(f"{name:<8} {len(samples) / RATE:4.2f} s")


SOFT = ((1, 1.0), (2, 0.18))
BELL = ((1, 1.0), (2, 0.35), (3, 0.12))

# A page or a part of the talk arriving: air moving past.
save("whoosh", noise(0.55, 500, 2600, attack=0.22, decay=0.12, sweep_to=1500))
# Each flick of the library, and an edit being applied: a shorter, lighter brush.
save("swipe", noise(0.24, 1200, 5000, attack=0.08, decay=0.05, sweep_to=3200), peak=0.35)
# A card, tile or bubble appearing.
save("pop", tone(0.11, 520, 260, attack=0.003, decay=0.03, partials=SOFT))
# A list line, a pipeline step, a dot.
save("tick", mix((tone(0.05, 1900, 1700, attack=0.001, decay=0.012), 0, 1.0), (noise(0.012, 3000, 7000, decay=0.004), 0, 0.25)), peak=0.4)
# One key of the on-screen typing.
save("key", mix((noise(0.03, 2200, 5200, attack=0.001, decay=0.008), 0, 1.0), (tone(0.04, 190, 150, attack=0.001, decay=0.012), 0, 0.5)), peak=0.3)
# Four seconds of typing, a little uneven, for searches typed on screen (cut to length in the video).
keys, at = [], 0.0
while at < 4.0:
    keys.append((noise(0.03, 2000 + random.uniform(0, 900), 5200, attack=0.001, decay=0.007), at, random.uniform(0.6, 1.0)))
    keys.append((tone(0.035, random.uniform(170, 210), 150, attack=0.001, decay=0.011), at, 0.45))
    at += random.uniform(0.05, 0.11)
save("typing", mix(*keys), peak=0.3)
# A photo being taken: curtain open, curtain shut.
save("shutter", mix((noise(0.03, 1800, 6000, attack=0.001, decay=0.008), 0, 1.0), (tone(0.03, 950, 800, attack=0.001, decay=0.008), 0, 0.3),
                    (noise(0.04, 1500, 5000, attack=0.001, decay=0.012), 0.07, 0.8)), peak=0.4)
# A bar growing or a number counting up.
save("rise", tone(0.75, 330, 660, attack=0.12, decay=0.16, hold=0.35, partials=SOFT), peak=0.4)
# An answer or a result landing: two bell notes, a fifth apart.
save("chime", mix((tone(0.9, 880, attack=0.004, decay=0.28, partials=BELL), 0, 1.0), (tone(0.8, 1318.5, attack=0.004, decay=0.3, partials=BELL), 0.1, 0.8)))
# "Still not found": two notes going down.
save("low", mix((tone(0.32, 233, 220, attack=0.02, decay=0.14, partials=SOFT), 0, 1.0), (tone(0.5, 175, 165, attack=0.02, decay=0.2, partials=SOFT), 0.2, 1.0)))
# A flashcard turning over.
save("flip", noise(0.18, 900, 6500, attack=0.05, decay=0.035, sweep_to=4200), peak=0.35)
# The five tiers, one note each, climbing (C D E G A).
for i, hz in enumerate((523.25, 587.33, 659.25, 783.99, 880.0), 1):
    save(f"note{i}", tone(0.45, hz, attack=0.004, decay=0.14, partials=BELL), peak=0.42)
