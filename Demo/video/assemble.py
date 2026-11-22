"""Assembles the demo video from cards, screen recordings and narration.

    python3 Demo/video/assemble.py

Reads Demo/video/script.json, Demo/video/out/cards/NN.png (title cards),
Demo/video/out/raw/NN.mov (screen recordings) and Demo/video/out/voice/NN.*
(narration, any format ffmpeg reads; a team member's recording can replace
the synthetic one with the same number). Writes Demo/video/out/phophy-demo.mp4.

Each scene lasts as long as its narration plus a short pause, or as long as
its recording if that's longer. The phone recording is shown on the left,
the scene's caption on the right.
"""
import json, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).parent
OUT = ROOT / "out"
W, H = 1920, 1080
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"

CAPTIONS = {
    4: ("Library", "Every photo read once, on the phone:\nplace, description and text."),
    5: ("Search", "Scenes, places, typos and Chinese.\nAbout 20 ms per search."),
    6: ("Search", "Words written in photos,\nand photos described in a sentence."),
    7: ("Collections", "Sorted automatically.\nNear-identical shots found."),
    8: ("Study", "Lecture slides become a summary,\nkey points and flashcards."),
    9: ("Ask", "The assistant reads the total\nfrom the receipt."),
    10: ("Ask", "…and the departure time\nfrom a booking screenshot."),
    11: ("Ask", "It can organise too:\nan album, confirmed with one tap."),
    12: ("Edit", "Describe the change.\nIt runs on the phone, for free."),
    13: ("Privacy", "On the phone by default.\nA clear warning before any upload."),
}


# Scenes that wait for the AI are played faster; the narration isn't.
SPEED = {8: 2.0, 11: 2.0}


def font(size, bold=False):
    return ImageFont.truetype(FONT, size, index=1 if bold else 0)


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def backdrop(scene):
    """The card background with the scene's caption on the right."""
    img = Image.open(OUT / "cards" / "background.png").convert("RGB")
    title, body = CAPTIONS[scene]
    d = ImageDraw.Draw(img)
    d.text((900, 380), title, font=font(96, True), fill="white")
    d.multiline_text((900, 520), body, font=font(48), fill=(215, 222, 255), spacing=18)
    path = OUT / "build" / f"backdrop-{scene:02d}.png"
    img.save(path)
    return path


def voice_file(scene):
    for ext in ("m4a", "wav", "mp3", "aiff"):
        path = OUT / "voice" / f"{scene:02d}.{ext}"
        if path.exists():
            return path
    return None


def render(scene):
    voice = voice_file(scene)
    speech = duration(voice) if voice else 0
    out = OUT / "build" / f"scene-{scene:02d}.mp4"
    card = OUT / "cards" / f"{scene:02d}.png"
    raw = OUT / "raw" / f"{scene:02d}.mov"
    audio = ["-i", str(voice)] if voice else ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
    common = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "160k"]
    if card.exists():
        length = speech + 1.2
        run("ffmpeg", "-y", "-loop", "1", "-t", f"{length:.2f}", "-i", str(card), *audio,
            "-filter_complex", "[1:a]adelay=400|400,apad[a]", "-map", "0:v", "-map", "[a]",
            "-t", f"{length:.2f}", *common, str(out))
    elif raw.exists():
        speed = SPEED.get(scene, 1.0)
        clip = duration(raw) / speed
        # NN-end.png, a screenshot of the final screen: the recorder drops
        # the last frames when stopped, so an answer that just appeared is
        # added back as a still.
        end = OUT / "raw" / f"{scene:02d}-end.png"
        hold = 3.5 if end.exists() else 2.5
        length = max(speech + 1.5, clip + hold)
        back = backdrop(scene)
        phone = "scale=-2:980,fps=30,format=yuv420p,setsar=1"
        if end.exists():
            inputs = ["-i", str(raw), "-loop", "1", "-t", "60", "-i", str(end), "-loop", "1", "-i", str(back), *audio]
            graph = (
                f"[0:v]setpts=PTS/{speed},{phone}[clip];[1:v]{phone}[still];"
                "[clip][still]concat=n=2:v=1:a=0[phone];"
                "[2:v][phone]overlay=x=260:y=50[v];"
                "[3:a]adelay=400|400,apad[a]"
            )
        else:
            inputs = ["-i", str(raw), "-loop", "1", "-i", str(back), *audio]
            graph = (
                f"[0:v]setpts=PTS/{speed},{phone},tpad=stop_mode=clone:stop_duration=60[phone];"
                "[1:v][phone]overlay=x=260:y=50[v];"
                "[2:a]adelay=400|400,apad[a]"
            )
        run("ffmpeg", "-y", *inputs,
            "-filter_complex", graph, "-map", "[v]", "-map", "[a]", "-t", f"{length:.2f}", *common, str(out))
    else:
        return None
    return out


def main():
    (OUT / "build").mkdir(parents=True, exist_ok=True)
    scenes = [row["scene"] for row in json.loads((ROOT / "script.json").read_text())]
    parts = []
    for scene in scenes:
        part = render(scene)
        if part:
            parts.append(part)
            print(f"scene {scene:2d}: {duration(part):5.1f} s")
        else:
            print(f"scene {scene:2d}: missing, skipped")
    listing = OUT / "build" / "parts.txt"
    listing.write_text("".join(f"file '{p.resolve()}'\n" for p in parts))
    final = OUT / "phophy-demo.mp4"
    run("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", "-movflags", "+faststart", str(final))
    print(f"{final}: {duration(final):.0f} s")


if __name__ == "__main__":
    main()
