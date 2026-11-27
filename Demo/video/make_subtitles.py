"""Burns subtitles of the narration into the rendered presentation.

    python3 Demo/video/make_subtitles.py [NAME]

NAME is the rendered video in out/ (default phophy-talk).

Reads out/phophy-talk.mp4 (left untouched), remotion/src/talk.json and
talk-timing.json. Each spoken line is split into short cues timed within the
line (by length, with longer gaps at commas and full stops, and matched to the
pauses heard in the recording). Each cue is drawn as an image, white text on a
dark rounded box near the bottom, and laid over the video. Writes:

    out/phophy-talk.srt                  the subtitles as a file
    out/phophy-talk-subtitled.mp4        with subtitles, compressed
    out/phophy-talk-small.mp4            the original, compressed

(This ffmpeg has no text or subtitle filter, which is why cues are images.)
"""
import json, re, subprocess, sys, tempfile, textwrap
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
OUT = HERE / "out"
NAME = sys.argv[1] if len(sys.argv) > 1 else "phophy-talk"
SOURCE = OUT / f"{NAME}.mp4"
talk = json.loads((HERE / "remotion/src/talk.json").read_text())
timing = json.loads((HERE / "remotion/src/talk-timing.json").read_text())

W, H = 1920, 1080
FONT = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 36)
FONT.set_variation_by_name("Medium") if hasattr(FONT, "set_variation_by_name") else None
LINE_CHARS = 62          # one line holds about this many characters at this size
BOTTOM = 1012            # the box ends here, above the part bar and footnotes
WEIGHT = {".": 8, "?": 8, "!": 8, ":": 8, ";": 8, ",": 4}


def pauses_in(audio):
    log = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(audio), "-af", "silencedetect=noise=-35dB:d=0.18", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return list(zip(map(float, re.findall(r"silence_start: ([0-9.]+)", log)), map(float, re.findall(r"silence_end: ([0-9.]+)", log))))


def chunks(text):
    """Pieces of at most two lines: whole sentences when short, else split at commas, else at words."""
    out = []
    for sentence in re.split(r"(?<=[.?!])\s+", text.strip()):
        if len(sentence) <= LINE_CHARS * 2 - 10:
            out.append(sentence)
            continue
        parts, current = re.split(r"(?<=[,:;])\s+", sentence), ""
        for part in parts:
            if current and len(current) + 1 + len(part) > LINE_CHARS * 2 - 10:
                out.append(current)
                current = part
            else:
                current = f"{current} {part}".strip()
        if current:
            out.append(current)
    # A piece that is still too long is cut at a word near its middle.
    final = []
    for piece in out:
        while len(piece) > LINE_CHARS * 2 - 4:
            cut = piece.rfind(" ", 0, len(piece) // 2 + 10)
            final.append(piece[:cut])
            piece = piece[cut + 1:]
        final.append(piece)
    return final


def times(text, pieces, speech, audio):
    """Start and end of each piece within its line, from letter counts corrected by the heard pauses."""
    beats = lambda s: sum(WEIGHT.get(c, 1) for c in s)
    total = beats(text)
    pauses = [p for p in pauses_in(audio) if 0.05 < p[0] and p[1] < speech - 0.05]
    lead = next((end for start, end in pauses_in(audio) if start <= 0.05), 0.0)
    spans, at = [], 0
    for piece in pieces:
        start_i = text.index(piece, at)
        end_i = start_i + len(piece)
        at = end_i
        s = lead + (speech - lead) * beats(text[:start_i]) / total
        e = lead + (speech - lead) * beats(text[:end_i]) / total
        # A boundary that falls near a heard pause snaps to it.
        for ps, pe in pauses:
            if abs(e - ps) < 0.8:
                e = ps
            if abs(s - pe) < 0.8:
                s = pe
        spans.append([s, e])
    for a, b in zip(spans, spans[1:]):   # no gaps that flicker, no overlaps
        a[1] = b[0] = (a[1] + b[0]) / 2 if b[0] - a[1] < 0.6 else a[1]
    return spans


def stamp(t):
    ms = round(t * 1000)
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def draw(text, path):
    lines = textwrap.wrap(text, LINE_CHARS)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    gap, pad_x, pad_y = 10, 26, 14
    sizes = [d.textbbox((0, 0), line, font=FONT) for line in lines]
    line_h = max(b[3] - b[1] for b in sizes)
    box_w = max(b[2] - b[0] for b in sizes) + pad_x * 2
    box_h = line_h * len(lines) + gap * (len(lines) - 1) + pad_y * 2 + 8
    x0, y0 = (W - box_w) // 2, BOTTOM - box_h
    d.rounded_rectangle((x0, y0, x0 + box_w, BOTTOM), radius=14, fill=(8, 6, 24, 190))
    y = y0 + pad_y
    for line, b in zip(lines, sizes):
        w = b[2] - b[0]
        d.text(((W - w) // 2 - b[0], y - b[1] + 2), line, font=FONT, fill=(255, 255, 255, 255))
        y += line_h + gap
    img.save(path)
    return len(lines)


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    cues = []
    for number, (page, t) in enumerate(zip(talk["pages"], timing["pages"]), 1):
        audio = HERE / f"remotion/public/voice-talk/{number:02d}.m4a"
        text = page["voice"]          # what is said, as it should read
        spoken = page.get("say", text)  # what the voice was given; same pauses
        pieces = chunks(text)
        spans = times(text, pieces, t["speech"], audio) if spoken == text else times(text, pieces, t["speech"], audio)
        for piece, (s, e) in zip(pieces, spans):
            begin = t["starts"] + timing["lead"] + s
            cues.append((begin, t["starts"] + timing["lead"] + e + 0.15, piece))
    # Neighbouring cues never overlap on screen.
    for i in range(len(cues) - 1):
        if cues[i][1] > cues[i + 1][0] - 0.02:
            cues[i] = (cues[i][0], cues[i + 1][0] - 0.02, cues[i][2])

    (OUT / f"{NAME}.srt").write_text("".join(f"{i}\n{stamp(s)} --> {stamp(e)}\n{c}\n\n" for i, (s, e, c) in enumerate(cues, 1)))

    # One transparent image per cue, and an empty one for the gaps, played as a timed slideshow.
    blank = tmp / "blank.png"
    Image.new("RGBA", (W, H), (0, 0, 0, 0)).save(blank)
    listing, at, two_lines = [], 0.0, 0
    for i, (s, e, c) in enumerate(cues):
        png = tmp / f"c{i:03d}.png"
        two_lines += draw(c, png) == 2
        if s > at:
            listing += [f"file '{blank}'", f"duration {s - at:.3f}"]
        listing += [f"file '{png}'", f"duration {e - s:.3f}"]
        at = e
    listing += [f"file '{blank}'", "duration 5", f"file '{blank}'"]
    (tmp / "subs.txt").write_text("\n".join(listing) + "\n")
    print(f"{len(cues)} cues, {two_lines} on two lines; longest {max(len(c) for *_, c in cues)} characters")

    encode = ["-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(SOURCE), "-f", "concat", "-safe", "0", "-i", str(tmp / "subs.txt"),
                    "-filter_complex", "[1:v]fps=60,format=rgba[s];[0:v][s]overlay=0:0:eof_action=pass:format=auto[v]",
                    "-map", "[v]", "-map", "0:a", *encode, str(OUT / f"{NAME}-subtitled.mp4")], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(SOURCE), "-map", "0:v", "-map", "0:a", *encode, str(OUT / f"{NAME}-small.mp4")], check=True)

for name in (f"{NAME}.mp4", f"{NAME}-small.mp4", f"{NAME}-subtitled.mp4"):
    print(f"{name:<28} {(OUT / name).stat().st_size / 1e6:5.1f} MB")
