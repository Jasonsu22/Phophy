"""Speaks the narration in script.json with Kokoro, a small open neural voice
that runs on this Mac (nothing is sent anywhere).

    uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python kokoro-onnx soundfile
    .venv/bin/python Demo/video/make_voice.py MODELS_DIR [voice]

MODELS_DIR holds kokoro-v1.0.onnx and voices-v1.0.bin, from
https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0.
Each scene's line is written to remotion/public/voice/NN.m4a. A line that
would run past its scene is spoken a little faster, up to 15%; if it still
doesn't fit, it's reported so the line can be shortened.
"""
import json, subprocess, sys, tempfile
from pathlib import Path
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = Path(__file__).parent
models = Path(sys.argv[1])
voice = sys.argv[2] if len(sys.argv) > 2 else "af_heart"
kokoro = Kokoro(str(models / "kokoro-v1.0.onnx"), str(models / "voices-v1.0.bin"))
out = HERE / "remotion/public/voice"
out.mkdir(parents=True, exist_ok=True)
LEAD, TAIL = 0.45, 0.35  # silence before the line starts and before the scene ends

for scene in json.loads((HERE / "script.json").read_text()):
    room = scene["seconds"] - LEAD - TAIL
    for speed in (1.0, 1.05, 1.1, 1.15):
        samples, rate = kokoro.create(scene["voice"], voice=voice, speed=speed, lang="en-us")
        length = len(samples) / rate
        if length <= room:
            break
    with tempfile.NamedTemporaryFile(suffix=".wav") as wav:
        sf.write(wav.name, samples, rate)
        target = out / f"{scene['scene']:02d}.m4a"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav.name, "-c:a", "aac", "-b:a", "128k", str(target)], check=True)
    note = "" if length <= room else f"  TOO LONG by {length - room:.1f} s"
    print(f"{scene['scene']:2d} {scene['name']:<24} {length:5.1f} s of {room:4.1f} s  speed {speed}{note}")
