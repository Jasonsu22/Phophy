"""Draws the still cards for the demo video (1920×1080), in the app's colours.

    python3 Demo/video/make_cards.py OUT_DIR ARCHITECTURE_PNG
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out, architecture = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
W, H = 1920, 1080
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"


def font(size, bold=False):
    return ImageFont.truetype(FONT, size, index=1 if bold else 0)


def background():
    """Deep indigo to teal, like the app."""
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        for x in range(0, W):
            t = x / W * 0.6 + y / H * 0.4
            r = int(38 + (12 - 38) * t)
            g = int(24 + (70 - 24) * t)
            b = int(92 + (98 - 92) * t)
            px[x, y] = (r, g, b)
    return img


BASE = background()
BASE.save(out / "background.png")


def card(name, title, lines=(), subtitle=None, draw_extra=None):
    img = BASE.copy()
    d = ImageDraw.Draw(img)
    d.text((140, 150), title, font=font(84, True), fill="white")
    y = 290
    if subtitle:
        d.text((140, 270), subtitle, font=font(40), fill=(190, 200, 255))
        y = 380
    for line in lines:
        if line == "":
            y += 30
            continue
        d.text((160, y), "•  " + line, font=font(44), fill=(235, 238, 255))
        y += 84
    if draw_extra:
        draw_extra(img, d)
    img.save(out / f"{name}.png")


card("01", "Phophy", subtitle="Find anything in your photos, on your iPhone",
     draw_extra=lambda img, d: (
         d.text((140, 520), "An AI photo app for iPhone", font=font(48, True), fill="white"),
     ))

card("02", "The problem", [
    "Thousands of photos: receipts, slides, screenshots, trips",
    "Finding one means minutes of scrolling",
    "Lecture slides are photographed, then never used again",
    "Sending every photo to a cloud AI costs money and privacy",
])


def place_architecture(img, d):
    diagram = Image.open(architecture).convert("RGB")
    diagram = diagram.crop((0, 0, diagram.width, int(diagram.height * 0.74)))
    diagram.thumbnail((1600, 740))
    x = (W - diagram.width) // 2
    d.rounded_rectangle((x - 20, 270, x + diagram.width + 20, 290 + diagram.height), 28, fill="white")
    img.paste(diagram, (x, 280))


card("03", "How it works", draw_extra=place_architecture)


def results(img, d):
    rows = [
        ("Objects and scenes, found in top 50", 0.51, 0.89),
        ("Chinese searches, top-10 correct", 0.02, 0.51),
        ("Misspelled searches, top-10 correct", 0.13, 0.59),
        ("Long descriptions, right photo first", 0.76, 0.77),
    ]
    y = 330
    d.text((140, 250), "Flickr30k test, 1,000 photos, 362 searches", font=font(38), fill=(190, 200, 255))
    d.text((1180, 250), "first version", font=font(32), fill=(170, 170, 200))
    d.text((1500, 250), "Phophy now", font=font(32, True), fill=(120, 230, 220))
    for label, before, after in rows:
        d.text((140, y), label, font=font(40), fill="white")
        for value, x0, colour in ((before, 1180, (150, 150, 190)), (after, 1500, (90, 220, 210))):
            d.rounded_rectangle((x0, y + 8, x0 + int(260 * value), y + 48), 12, fill=colour)
            d.text((x0 + int(260 * value) + 14, y + 4), f"{round(value * 100)}%", font=font(36, True), fill="white")
        y += 130


card("14", "Search, measured", draw_extra=results)

card("15", "On a real iPhone 13 Pro Max", [
    "No Apple Intelligence: a small open model runs on the phone",
    "Search: under 25 ms per query, on 16,000 photos",
    "Describing a photo: about 1.5 s, with no cloud",
    "Indexing pauses while you scroll, or when the phone is hot",
])

card("16", "Thank you", [
    "Find any photo by describing it",
    "Ask about what's inside a photo",
    "Turn lecture slides into notes",
    "Edit a photo by typing the change",
], subtitle="github.com/Jasonsu22/Phophy")
print("cards in", out)
