"""Makes the README's animated pictures from the app recordings of the demo
library (Demo/video/remotion/public/clips, made by Demo/video/cut_clips.py).

    python3 Demo/readme_media.py

Writes to docs/media:
- hero.gif: three phones side by side (Find, Ask, Edit) on the app's colours;
- card-*.gif: one phone per feature, all the same size and frame, for the
  feature table.
Every picture shows only the made-up demo library.
"""
import subprocess, tempfile
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CLIPS = ROOT / "Demo/video/remotion/public/clips"
OUT = ROOT / "docs/media"
FPS = 10
FONT = "/System/Library/Fonts/SFNS.ttf"
TEAL = (94, 230, 217)
ASPECT = 1434 / 660


def gradient(w, h):
    """The app's background: indigo to teal at 135°, with two soft glows."""
    stops = [(0, (28, 18, 80)), (0.35, (34, 25, 94)), (0.75, (15, 53, 80)), (1, (13, 74, 85))]
    y, x = np.mgrid[0:h, 0:w]
    t = (x / w + y / h) / 2
    img = np.zeros((h, w, 3))
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        m = (t >= a) & (t <= b)
        k = ((t - a) / (b - a))[m][:, None]
        img[m] = np.array(ca) * (1 - k) + np.array(cb) * k
    def glow(cx, cy, r, color, strength):
        d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
        a = np.clip(1 - d, 0, 1) ** 2 * strength
        return a[..., None] * (np.array(color) - img)
    img += glow(w * 0.15, h * 0.05, max(w, h) * 0.6, (124, 92, 255), 0.45)
    img += glow(w * 0.9, h * 1.0, max(w, h) * 0.55, (32, 200, 190), 0.3)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def phone_layers(screen_w):
    """A phone body (with shadow) and a mask for its screen, for a screen this wide."""
    screen_h = round(screen_w * ASPECT)
    bezel = max(6, screen_w // 32)
    w, h = screen_w + 2 * bezel, screen_h + 2 * bezel
    r_out, r_in = round(w * 0.16), round(screen_w * 0.15)
    body = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    shadow = Image.new("L", body.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle((20, 30, 20 + w, 30 + h), r_out, fill=150)
    body.paste((5, 4, 20, 255), (0, 0), shadow.filter(ImageFilter.GaussianBlur(12)))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((20, 20, 20 + w, 20 + h), r_out, fill=(30, 30, 36, 255), outline=(78, 78, 90, 255), width=2)
    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_w - 1, screen_h - 1), r_in, fill=255)
    return body, mask, (20 + bezel, 20 + bezel)


def frames(clip, screen_w, seconds, speed=1.0, start=0.0):
    """The clip's frames at FPS, `seconds` long (the last frame held if the clip is shorter)."""
    h = round(screen_w * ASPECT)
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", str(CLIPS / f"{clip}.mp4"),
           "-vf", f"setpts=PTS/{speed},fps={FPS},scale={screen_w}:{h}:flags=lanczos", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    n = len(raw) // (screen_w * h * 3)
    out = [Image.frombytes("RGB", (screen_w, h), raw[i * screen_w * h * 3:(i + 1) * screen_w * h * 3]) for i in range(n)]
    want = round(seconds * FPS)
    return (out + [out[-1]] * want)[:want]


def save_gif(images, path, keep_colours=None):
    """Encodes with one palette for the whole GIF, so colours don't flicker and
    unchanged areas are reused. `keep_colours` is an image whose colours must be
    in the palette (a small bright detail, like the red balloon): it is weighed
    in as if it filled many frames, but not shown."""
    with tempfile.TemporaryDirectory() as tmp:
        for i, im in enumerate(images):
            im.save(f"{tmp}/{i:04d}.png")
        palette_from = list(images)
        if keep_colours is not None:
            palette_from += [keep_colours.resize(images[0].size)] * max(8, len(images) // 6)
        for i, im in enumerate(palette_from):
            im.save(f"{tmp}/p{i:04d}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/p%04d.png",
                        "-vf", "palettegen=max_colors=128:stats_mode=full", f"{tmp}/palette.png"], check=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/%04d.png", "-i", f"{tmp}/palette.png",
                        "-lavfi", "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle", "-loop", "0", str(path)], check=True)
    print(f"{path.name:<24} {images[0].size} {len(images)} frames  {path.stat().st_size / 1e6:.1f} MB")


def compose(canvas, layers, clips_frames, labels=()):
    """Every frame: the background, each phone with its screen, and its label."""
    out = []
    for i in range(len(clips_frames[0])):
        im = canvas.copy()
        for (body, mask, (sx, sy), (x, y)), seq in zip(layers, clips_frames):
            im.paste(body, (x - 20, y - 20), body)
            im.paste(seq[i], (x - 20 + sx, y - 20 + sy), mask)
        for draw in labels:
            draw(im)
        out.append(im)
    return out


def label(text, sub, cx, y, size=26):
    def draw(im):
        d = ImageDraw.Draw(im)
        f, fs = ImageFont.truetype(FONT, size), ImageFont.truetype(FONT, round(size * 0.6))
        try:
            f.set_variation_by_name("Bold")
        except Exception:
            pass
        w = d.textlength(text, font=f)
        d.text((cx - w / 2, y), text, font=f, fill=(255, 255, 255))
        ws = d.textlength(sub, font=fs)
        d.text((cx - ws / 2, y + size + 8), sub, font=fs, fill=TEAL)
    return draw


def balloon():
    """The edited photo's sky and balloon, from the last frame of the AI edit."""
    last = frames("aiedit", 330, 30, 1.0, 0.0)[-1]
    return last.crop((100, 180, 150, 230))


OUT.mkdir(parents=True, exist_ok=True)

# The hero: three phones, eleven seconds, one loop.
W, H, SCREEN = 880, 520, 180
hero_clips = [("ski", 1.0, 0.0, "Find", "“skiing, white hat, big smile”"),
              ("muji", 1.0, 0.0, "Ask", "“How much did I spend at Muji?”"),
              ("aiedit", 1.55, 1.0, "Edit", "“add a hot air balloon”")]
body, mask, offset = phone_layers(SCREEN)
phone_h = round(SCREEN * ASPECT) + 2 * max(6, SCREEN // 32)
gap = (W - 3 * body.size[0] + 3 * 40) // 4
xs = [gap + i * (body.size[0] - 40 + gap) + 20 for i in range(3)]
top = H - phone_h - 28
seconds = 10
seqs = [frames(c, SCREEN, seconds, speed, start) for c, speed, start, *_ in hero_clips]
labels = [label(t, s, x - 20 + body.size[0] / 2, 22, 28) for x, (*_, t, s) in zip(xs, hero_clips)]
save_gif(compose(gradient(W, H), [(body, mask, offset, (x, top)) for x in xs], seqs, labels), OUT / "hero.gif", keep_colours=balloon())

# The cards: one phone each, the same size and frame.
CW, CH, CS = 264, 500, 200
body, mask, offset = phone_layers(CS)
x = (CW - body.size[0] + 40) // 2 + 20
y = (CH - round(CS * ASPECT) - 2 * max(6, CS // 32)) // 2
for name, clip, seconds, speed, start in [
    ("search", "ski", 11.4, 1.0, 0.0), ("ask", "muji", 7.4, 1.0, 0.0), ("chinese", "zh", 6.0, 1.0, 0.0),
    ("study", "notes-short", 11.0, 1.2, 0.0), ("edit", "aiedit", 13.0, 1.3, 0.6), ("collections", "collections-short", 9.0, 1.15, 0.0),
]:
    seq = frames(clip, CS, seconds / speed if speed != 1 else seconds, speed, start)
    save_gif(compose(gradient(CW, CH), [(body, mask, offset, (x, y))], [seq]), OUT / f"card-{name}.gif", keep_colours=balloon() if name == "edit" else None)
