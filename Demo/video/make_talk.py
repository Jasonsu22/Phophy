"""Speaks the narration of the five-minute presentation with Kokoro (a small
open neural voice that runs on this Mac; nothing is sent anywhere) and works
out how long each page lasts.

    uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python kokoro-onnx soundfile
    .venv/bin/python Demo/video/make_talk.py MODELS_DIR [page-id ...]

A line is only spoken again if its words changed, or its page is named.

MODELS_DIR holds kokoro-v1.0.onnx and voices-v1.0.bin, from
https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0.

Reads remotion/src/talk.json. For each page it writes
remotion/public/voice-talk/NN.m4a and then remotion/src/talk-timing.json:

- an animated page lasts as long as its narration, plus a short pause;
- a page with a recording lasts as long as the recording, so its line is
  spoken up to 15% faster if it would run over, and reported if it still does.

A page's "cues" name words in its line; the time each is spoken is written
too, so the animations can follow the narration. That time is worked out
from where the word falls in the line, corrected by the pauses actually
heard in the recording (each pause is matched to a comma or full stop).
"""
import json, math, re, subprocess, sys, tempfile
from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = Path(__file__).parent
SRC = HERE / "remotion/src"
OUT = HERE / "remotion/public/voice-talk"
LEAD = 0.45          # silence before a line starts
PAUSE = 0.6          # after the line on an animated page
CLIP_TAIL = 0.35     # least silence before a recording ends
TRANSITION = 0.5     # two pages overlap this long while one fades into the next



PAUSE_WEIGHT = {".": 8, "?": 8, "!": 8, ":": 8, ";": 8, ",": 4}


def pauses_in(audio):
    """(start, end) of every silence of 0.18 s or more in a recording."""
    log = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(audio), "-af", "silencedetect=noise=-35dB:d=0.18", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", log)]
    return list(zip(starts, ends))


def cue_times(text, cues, speech, audio):
    """Seconds into the page at which each cue's phrase is said.

    A first guess counts letters: one beat each, four for a comma, eight for
    a full stop. Then every pause heard in the recording is matched to the
    punctuation mark nearest that guess, and the guess is stretched between
    those fixed points, so a word after a long pause isn't timed early.
    """
    if not cues:
        return {}
    guess = lambda index: speech * sum(PAUSE_WEIGHT.get(c, 1) for c in text[:index]) / sum(PAUSE_WEIGHT.get(c, 1) for c in text)
    marks = [i for i, c in enumerate(text) if c in PAUSE_WEIGHT and i < len(text) - 1]
    pauses = [p for p in pauses_in(audio) if 0.05 < p[0] and p[1] < speech - 0.05]
    lead = next((end for start, end in pauses_in(audio) if start <= 0.05), 0.0)
    # Fixed points: (letters before, seconds). A matched mark gives two: where its pause starts and ends.
    fixed, used = [(0, lead)], -1
    for start, end in pauses:
        near = [(abs(guess(i) - start), k) for k, i in enumerate(marks) if k > used and abs(guess(i) - start) < 1.5]
        if not near:
            continue
        used = min(near)[1]
        fixed += [(marks[used], start), (marks[used] + 1, end)]
    fixed.append((len(text), speech))
    times = {}
    for name, phrase in cues.items():
        index = text.index(phrase)
        before = max((f for f in fixed if f[0] <= index), key=lambda f: (f[0], f[1]))
        after = min((f for f in fixed if f[0] > index), key=lambda f: (f[0], f[1]))
        share = (index - before[0]) / max(after[0] - before[0], 1)
        times[name] = round(LEAD + before[1] + (after[1] - before[1]) * share, 2)
    return times


models = Path(sys.argv[1])
only = set(sys.argv[2:])
talk = json.loads((SRC / "talk.json").read_text())
timing_file = SRC / "talk-timing.json"
previous = {p["id"]: p for p in json.loads(timing_file.read_text())["pages"]} if timing_file.exists() else {}
kokoro = Kokoro(str(models / "kokoro-v1.0.onnx"), str(models / "voices-v1.0.bin"))
OUT.mkdir(parents=True, exist_ok=True)

pages = []
for number, page in enumerate(talk["pages"], 1):
    target = OUT / f"{number:02d}.m4a"
    text = page.get("say", page["voice"])
    old = previous.get(page["id"])
    room = page["clipSeconds"] - LEAD - CLIP_TAIL if page["kind"] == "clip" else None
    if old and old.get("text") == text and old.get("n") == number and target.exists() and page["id"] not in only and (room is None or old["speech"] <= room or old["speed"] >= 1.15):
        speech, speed = old["speech"], old["speed"]
    else:
        for speed in (1.0, 1.05, 1.1, 1.15):
            samples, rate = kokoro.create(text, voice=talk["voice"], speed=speed, lang="en-us")
            speech = len(samples) / rate
            if room is None or speech <= room:
                break
        with tempfile.NamedTemporaryFile(suffix=".wav") as wav:
            sf.write(wav.name, samples, rate)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav.name, "-c:a", "aac", "-b:a", "128k", str(target)], check=True)
    if page["kind"] == "clip":
        seconds = page["clipSeconds"]
    else:
        seconds = max(5.0, math.ceil((LEAD + speech + PAUSE) * 10) / 10)
    pages.append({
        "n": number, "id": page["id"], "text": text, "speech": round(speech, 2), "speed": speed, "seconds": seconds,
        "words": len(page["voice"].split()), "fits": room is None or speech <= room,
        "cues": cue_times(text, page.get("cues", {}), speech, target),
    })

starts, at = [], 0.0
for p in pages:
    starts.append(round(at, 2))
    at += p["seconds"] - TRANSITION
total = round(at + TRANSITION, 2)
for p, start in zip(pages, starts):
    p["starts"] = start
timing_file.write_text(json.dumps({"total": total, "transition": TRANSITION, "lead": LEAD, "pages": pages}, indent=1) + "\n")

for p in pages:
    note = "" if p["fits"] else "  TOO LONG for its recording"
    print(f"{p['n']:2d} {p['id']:<17} starts {p['starts']:6.1f}  lasts {p['seconds']:5.1f}  speech {p['speech']:5.1f} s  {p['words']:3d} words  speed {p['speed']}{note}")
print(f"whole video: {int(total // 60)}:{total % 60:04.1f}  ({sum(p['words'] for p in pages)} words)")
