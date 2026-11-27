"""Cuts the simulator recordings (out/raw/v2-*.mov) into one clip per scene.

    python3 Demo/video/cut_clips.py [scene ...]

With no scene named, every clip is cut again. Each scene lists the stretches of a recording to keep, in seconds. The cuts
fall where the screen is still, so joined stretches play as one take with
the waiting removed. A stretch can be played backwards ("rev") or end on a
held last frame ("hold" seconds). Clips are 60 fps, sized for the phone in
the video, and written to remotion/public/clips with their lengths in
remotion/src/clips.json.
"""
import json, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).parent
RAW, OUT = HERE / "out/raw", HERE / "remotion/public/clips"
OUT.mkdir(parents=True, exist_ok=True)

SCENES = {
    # "whiteboard from last month": typed, sent, photos, answer, photo opened.
    "find": [("find", 11.4, 14.8), ("find", 23.2, 26.4), ("find", 42.6, 46.5)],
    # "Summarise the slides from today's lecture": typed, sent, answer.
    "ask-lecture": [("lecture", 1.1, 2.7), ("lecture", 6.1, 8.3), ("lecture", 13.8, 15.0), ("lecture", 45.0, 49.0)],
    # Make notes, the notes page, key points, a flashcard turned over.
    "notes": [("notes", 0.9, 2.4), ("notes", 12.9, 16.2), ("lecture", 63.0, 68.6), ("cards", 1.3, 4.1, "hold", 2.5)],
    # "How much did I spend at Muji?"
    "muji": [("muji", 8.8, 10.8), ("muji", 16.4, 17.3, "hold", 4.5)],
    # "warmer and more vivid" in the editor.
    "edit": [("edit", 1.9, 3.4), ("edit", 11.8, 19.5)],
    # Collections, then similar photos.
    "collections": [("collections", 1.2, 3.2), ("collections", 14.5, 20.2), ("collections", 21.6, 22.3, "hold", 3.5)],
    # "Tokyo in May": answer, then all results as a grid.
    "place": [("place", 6.2, 8.2), ("place", 15.0, 17.2), ("place", 37.5, 39.6, "hold", 2.4)],
    # Settings: which AI is used.
    "settings": [("settings", 1.2, 5.1, "hold", 3.5)],

    # For the five-minute presentation.
    # "skiing, white hat, big smile": ask bar opened, typed, sent, the answer, the photo opened.
    "ski": [("ski", 1.2, 2.8), ("ski", 3.7, 5.3), ("ski", 6.5, 8.3), ("ski", 13.5, 16.5), ("ski", 31.5, 32.7, "hold", 2.2)],
    # The Muji question in Chinese: the question, then the answer.
    "zh": [("zh", 6.15, 6.55, "hold", 1.2), ("zh", 13.95, 14.4, "hold", 3.9)],
    # "add a red hot air balloon in the sky": editor opened, typed, read on the phone, the card that asks before sending.
    # The wait for the image service (about 40 s) is cut; the result arrives with the balloon.
    "aiedit": [("aiedit3", 11.3, 13.2), ("aiedit3", 15.8, 16.9), ("aiedit3", 27.45, 27.75, "hold", 1.2), ("aiedit3", 27.75, 29.4),
               ("aiedit3", 34.8, 36.9), ("aiedit3", 44.1, 46.4), ("aiedit3", 81.9, 85.5, "hold", 2.6)],
    # The notes and collections clips, a little shorter.
    "notes-short": [("notes", 0.9, 2.4), ("notes", 12.9, 16.2), ("lecture", 63.0, 67.0), ("cards", 1.3, 4.1, "hold", 1.4)],
    "collections-short": [("collections", 1.2, 3.2), ("collections", 14.5, 19.5), ("collections", 21.6, 22.3, "hold", 2.8)],
}
only = sys.argv[1:]
unknown = [name for name in only if name not in SCENES]
if unknown:
    sys.exit(f"no such scene: {', '.join(unknown)}")

SCALE = "scale=660:1434:flags=lanczos,setsar=1"
ENCODE = ["-c:v", "libx264", "-crf", "21", "-preset", "slow", "-g", "30", "-pix_fmt", "yuv420p", "-an"]
lengths_file = HERE / "remotion/src/clips.json"
lengths = json.loads(lengths_file.read_text()) if only and lengths_file.exists() else {}
with tempfile.TemporaryDirectory() as tmp:
    for scene, parts in SCENES.items():
        if only and scene not in only:
            continue
        files = []
        for i, (source, start, end, *extra) in enumerate(parts):
            # The recordings have no frames while the screen is still: fill them in
            # first, so a cut inside a still stretch has frames to keep.
            chain = f"fps=60,trim={start}:{end},setpts=PTS-STARTPTS,{SCALE}"
            if "rev" in extra:
                chain += ",reverse"
            if "hold" in extra:
                chain += f",tpad=stop_mode=clone:stop_duration={extra[extra.index('hold') + 1]}"
            part = Path(tmp) / f"{scene}-{i}.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(RAW / f"v2-{source}.mov"), "-vf", chain, *ENCODE, str(part)], check=True)
            files.append(part)
        listing = Path(tmp) / f"{scene}.txt"
        listing.write_text("".join(f"file '{f}'\n" for f in files))
        target = OUT / f"{scene}.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", "-movflags", "+faststart", str(target)], check=True)
        seconds = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(target)], capture_output=True, text=True).stdout)
        lengths[scene] = round(seconds, 2)
        print(scene, lengths[scene], f"{target.stat().st_size / 1e6:.1f} MB")
lengths_file.write_text(json.dumps(lengths, indent=1) + "\n")
