"""Builds the storyboard of the five-minute presentation: one self-contained
HTML page with a frame of every page of the video, what happens on it, the
words spoken (with their audio) and its sound effects, for review before the
video is rendered.

    cd Demo/video/remotion && node stills.mjs STILLS_DIR     # one frame per page
    python3 Demo/video/make_storyboard.py STILLS_DIR

Reads remotion/src/talk.json and talk-timing.json (from make_talk.py), the
narration in remotion/public/voice-talk and the effects in remotion/public/sfx.
Writes out/storyboard.html. Needs Pillow and ffmpeg.
"""
import base64, html, io, json, subprocess, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).parent
SRC = HERE / "remotion/src"
PUBLIC = HERE / "remotion/public"
stills = Path(sys.argv[1])
talk = json.loads((SRC / "talk.json").read_text())
timing = json.loads((SRC / "talk-timing.json").read_text())
pages = [page | time for page, time in zip(talk["pages"], timing["pages"])]
total = timing["total"]
e = html.escape


def clock(seconds):
    return f"{int(seconds // 60)}:{int(seconds % 60):02d}"


def uri(data, mime):
    return f"data:{mime};base64,{base64.b64encode(data).decode()}"


def frame(number):
    image = Image.open(stills / f"{number:02d}.jpeg").convert("RGB")
    image = image.resize((1120, 630), Image.LANCZOS)
    out = io.BytesIO()
    image.save(out, "JPEG", quality=80, optimize=True)
    return uri(out.getvalue(), "image/jpeg")


def voice(number):
    source = PUBLIC / f"voice-talk/{number:02d}.m4a"
    mp3 = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(source), "-ac", "1", "-c:a", "libmp3lame", "-b:a", "64k", "-f", "mp3", "-"],
        check=True, capture_output=True,
    ).stdout
    return uri(mp3, "audio/mpeg")


PART_CLASS = {"Opening": "p0", "Motivation": "p1", "Methodology": "p2", "Implementation": "p3", "Key results": "p4", "Closing": "p0"}


def source_class(source):
    if source.startswith("New recording"):
        return "s-record"
    if source.startswith("New"):
        return "s-new"
    if source.startswith("Updated"):
        return "s-updated"
    return "s-reused"


# Where each part starts and how long it runs (fades are shared between neighbours).
spans = []
for page in pages:
    if spans and spans[-1]["part"] == page["part"]:
        spans[-1]["pages"].append(page["n"])
    else:
        spans.append({"part": page["part"], "start": page["starts"], "pages": [page["n"]]})
for span, following in zip(spans, spans[1:] + [None]):
    span["end"] = following["start"] if following else total
    span["seconds"] = span["end"] - span["start"]

SFX = [
    ("whoosh", "A new part of the talk arrives"),
    ("swipe", "A flick of the photo library; an edit applied"),
    ("pop", "A card, tile or bubble appears"),
    ("tick", "A list line, a pipeline step, a dot"),
    ("typing", "Typing, while a search is typed on screen"),
    ("shutter", "A slide is photographed"),
    ("rise", "A bar grows or a number counts up"),
    ("chime", "An answer or a result lands"),
    ("low", "“Still not found”"),
    ("flip", "A flashcard turns over"),
    ("note1", "The five tiers: first note"),
    ("note5", "The five tiers: last note"),
]

count = lambda prefix: sum(1 for p in pages if p["source"].startswith(prefix))
words = sum(p["words"] for p in pages)

# MARK: Pieces of the page

timeline = "".join(
    f'<a class="seg {PART_CLASS[s["part"]]}" href="#part-{i}" style="flex:{s["seconds"]:.1f}" title="{e(s["part"])}: {clock(s["start"])} to {clock(s["end"])}">'
    f'<span>{e(s["part"]) if s["seconds"] > 30 else ""}</span></a>'
    for i, s in enumerate(spans)
)
legend = "".join(
    f'<li><span class="dot {PART_CLASS[s["part"]]}"></span><a href="#part-{i}"><b>{e(s["part"])}</b></a> '
    f'<span class="dim">{clock(s["start"])}–{clock(s["end"])} · {s["seconds"]:.0f} s · '
    f'{"page" if len(s["pages"]) == 1 else "pages"} {s["pages"][0]}{"" if len(s["pages"]) == 1 else "–" + str(s["pages"][-1])}</span></li>'
    for i, s in enumerate(spans)
)
rows = "".join(
    f'<tr><td class="num">{p["n"]}</td><td><a href="#page-{p["n"]}">{e(p["title"])}</a></td>'
    f'<td><span class="tag {PART_CLASS[p["part"]]}">{e(p["part"])}</span></td><td class="num">{clock(p["starts"])}</td>'
    f'<td class="num">{p["seconds"]:.1f} s</td><td><span class="tag {source_class(p["source"])}">{e(p["source"])}</span></td></tr>'
    for p in pages
)
effects = "".join(
    f'<li><audio controls preload="none" src="{uri((PUBLIC / f"sfx/{name}.wav").read_bytes(), "audio/wav")}"></audio>'
    f'<span><b>{name}</b><br><span class="dim">{e(use)}</span></span></li>'
    for name, use in SFX
)


def card(p):
    respelled = "<p class=\"dim small\">A few terms on this page are respelled for the voice only. Please listen to how they sound.</p>" if "say" in p else ""
    check = f'<h4>Worth knowing</h4><p class="check">{e(p["check"])}</p>' if "check" in p else ""
    sounds = "".join(f"<li>{e(s)}</li>" for s in p["sfx"])
    end = p["starts"] + p["seconds"]
    return f"""
<article class="page" id="page-{p['n']}">
  <div class="frame"><img loading="lazy" src="{frame(p['n'])}" alt="Preview frame of page {p['n']}: {e(p['title'])}" title="Click to enlarge"></div>
  <div class="body">
    <div class="kicker">
      <span class="pagenum">{p['n']}</span>
      <span class="tag {PART_CLASS[p['part']]}">{e(p['part'])}</span>
      <span class="tag {source_class(p['source'])}">{e(p['source'])}</span>
      <span class="dim">{clock(p['starts'])}–{clock(end)} · {p['seconds']:.1f} s</span>
    </div>
    <h3>{e(p['title'])}</h3>
    <h4>On screen</h4>
    <p>{e(p['screen'])}</p>
    <h4>Narration</h4>
    <blockquote>{e(p['voice'])}</blockquote>
    <div class="listen"><audio controls preload="metadata" src="{voice(p['n'])}"></audio><span class="dim small">{p['words']} words · {p['speech']:.1f} s spoken</span></div>
    {respelled}
    <h4>Sound effects</h4>
    <ul class="sounds">{sounds}</ul>
    {check}
  </div>
</article>"""


sections = ""
for i, span in enumerate(spans):
    cards = "".join(card(p) for p in pages if p["n"] in span["pages"])
    sections += (
        f'<section class="part" id="part-{i}"><h2><span class="dot {PART_CLASS[span["part"]]}"></span>{e(span["part"])} '
        f'<span class="dim">{clock(span["start"])}–{clock(span["end"])} · {span["seconds"]:.0f} seconds</span></h2>{cards}</section>'
    )

transcript = "".join(f'<p><span class="dim">{p["n"]}.</span> {e(p["voice"])}</p>' for p in pages)

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Phophy storyboard</title>
<style>
:root { --bg:#f5f5fa; --card:#ffffff; --ink:#17182b; --soft:#45475f; --dim:#6f7189; --line:#dfe0ec; --accent:#4a3ad0;
  --p0:#6f7189; --p1:#a25a00; --p2:#5a43d8; --p3:#08807a; --p4:#b3264e; --quote:#f0effa; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#10101a; --card:#191a29; --ink:#f1f1fa; --soft:#c5c6dd; --dim:#9092ae; --line:#2b2c44; --accent:#a99bff;
    --p0:#9092ae; --p1:#ffc27a; --p2:#b7a8ff; --p3:#5ee6d9; --p4:#ff9db0; --quote:#22233a; }
}
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.55 -apple-system, "SF Pro Text", "Helvetica Neue", "PingFang SC", sans-serif; }
main { max-width:1180px; margin:0 auto; padding:28px 16px 90px; }
h1 { font-size:34px; line-height:1.15; margin:0 0 8px; letter-spacing:-0.5px; }
h2 { font-size:25px; margin:54px 0 14px; display:flex; align-items:baseline; gap:10px; flex-wrap:wrap; }
h2 .dim { font-size:16px; font-weight:400; }
h3 { font-size:22px; margin:8px 0 2px; line-height:1.25; }
h4 { font-size:12.5px; letter-spacing:1.2px; text-transform:uppercase; color:var(--dim); margin:16px 0 4px; }
p { margin:0 0 10px; }
a { color:var(--accent); }
.lede { font-size:18px; color:var(--soft); max-width:860px; }
.dim { color:var(--dim); } .small { font-size:13.5px; }
.panel { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:20px 22px; margin-top:18px; }
.panel h2 { margin-top:0; }
.panel ul, .panel ol { margin:6px 0 0; padding-left:22px; } .panel li { margin-bottom:7px; }
.facts { display:flex; flex-wrap:wrap; gap:10px; margin:18px 0 4px; padding:0; list-style:none; }
.facts li { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:10px 16px; }
.facts b { display:block; font-size:22px; line-height:1.2; }
.timeline { display:flex; height:42px; border-radius:10px; overflow:hidden; margin-top:14px; }
.seg { display:flex; align-items:center; justify-content:center; color:#fff; font-size:13.5px; font-weight:600; text-decoration:none; min-width:6px; }
@media (prefers-color-scheme: dark) { .seg { color:#10101a; } }
.seg.p0 { background:var(--p0); } .seg.p1 { background:var(--p1); } .seg.p2 { background:var(--p2); } .seg.p3 { background:var(--p3); } .seg.p4 { background:var(--p4); }
.legend { list-style:none; padding:0; margin:12px 0 0; display:grid; grid-template-columns:repeat(auto-fit, minmax(300px, 1fr)); gap:4px 20px; }
.dot { display:inline-block; width:11px; height:11px; border-radius:6px; margin-right:8px; }
.dot.p0 { background:var(--p0); } .dot.p1 { background:var(--p1); } .dot.p2 { background:var(--p2); } .dot.p3 { background:var(--p3); } .dot.p4 { background:var(--p4); }
.tag { display:inline-block; font-size:12.5px; font-weight:600; padding:2px 10px; border-radius:999px; border:1.5px solid currentColor; white-space:nowrap; }
.tag.p0 { color:var(--p0); } .tag.p1 { color:var(--p1); } .tag.p2 { color:var(--p2); } .tag.p3 { color:var(--p3); } .tag.p4 { color:var(--p4); }
.tag.s-new { color:var(--p3); } .tag.s-record { color:var(--p1); } .tag.s-updated { color:var(--p2); } .tag.s-reused { color:var(--dim); }
.scroll { overflow-x:auto; }
table { border-collapse:collapse; width:100%; font-size:14.5px; min-width:640px; }
th { text-align:left; font-size:12.5px; letter-spacing:1px; text-transform:uppercase; color:var(--dim); padding:6px 10px; border-bottom:1px solid var(--line); }
td { padding:6px 10px; border-bottom:1px solid var(--line); vertical-align:top; }
td.num, th.num { text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }
.play { font:inherit; font-weight:600; color:#fff; background:var(--accent); border:0; border-radius:999px; padding:10px 20px; cursor:pointer; margin-top:12px; }
@media (prefers-color-scheme: dark) { .play { color:#10101a; } }
.effects { list-style:none; padding:0; margin:12px 0 0; display:grid; grid-template-columns:repeat(auto-fit, minmax(330px, 1fr)); gap:10px 20px; }
.effects li { display:flex; align-items:center; gap:12px; margin:0; }
.effects audio { width:150px; height:34px; flex-shrink:0; }
.page { display:grid; grid-template-columns:minmax(0, 1.15fr) minmax(0, 1fr); gap:22px; background:var(--card); border:1px solid var(--line);
  border-radius:16px; padding:16px; margin-bottom:18px; scroll-margin-top:16px; }
.page.now { outline:3px solid var(--accent); }
.page.wide { grid-template-columns:1fr; }
.frame img { cursor:zoom-in; } .page.wide .frame img { cursor:zoom-out; }
@media (max-width:860px) { .page { grid-template-columns:1fr; } }
.frame img { width:100%; height:auto; aspect-ratio:16/9; border-radius:10px; display:block; background:#1c1250; }
.kicker { display:flex; flex-wrap:wrap; align-items:center; gap:8px; font-size:13.5px; }
.pagenum { display:inline-flex; align-items:center; justify-content:center; min-width:30px; height:30px; padding:0 8px; border-radius:15px; background:var(--ink); color:var(--card); font-weight:700; }
blockquote { margin:0; padding:10px 14px; background:var(--quote); border-left:4px solid var(--accent); border-radius:6px; font-size:17px; line-height:1.5; }
.listen { display:flex; flex-wrap:wrap; align-items:center; gap:12px; margin-top:8px; }
.listen audio { height:36px; width:270px; max-width:100%; }
.sounds { margin:0; padding-left:20px; } .sounds li { margin:0; }
.check { border-left:4px solid var(--p1); padding:6px 12px; background:var(--quote); border-radius:6px; }
details { margin-top:18px; } summary { cursor:pointer; font-weight:600; }
</style>
</head>
<body>
<main>
<h1>Phophy: five-minute presentation, storyboard</h1>
<p class="lede">Every page of the video, in order, with what happens on it and the exact words spoken. It matches the draft video <code>phophy-talk.mp4</code>, which has your four changes in it.</p>
<ul class="facts">
  <li><b>__TOTAL__</b>of the 5:00 limit</li>
  <li><b>__PAGES__ pages</b>__NEW__ new animations</li>
  <li><b>__WORDS__ words</b>of narration</li>
  <li><b>__REUSED__ kept</b>from the last video</li>
  <li><b>Student IDs</b>on the last page</li>
</ul>

<div class="panel">
  <h2>The four parts the instructor asked for</h2>
  <p class="dim">“Please briefly cover the project motivation, methodology, implementation, and key results.” A small bar in the corner of the video shows which part is on.</p>
  <div class="timeline">__TIMELINE__</div>
  <ul class="legend">__LEGEND__</ul>
</div>

<div class="panel">
  <h2>How to review</h2>
  <ol>
    <li>Each page below shows a frame of the page as it will look once everything on it has appeared, what happens on it, the words spoken, and its sound effects. Click a picture to enlarge it.</li>
    <li>Press play on a page to hear its narration in the voice the video will use. I can’t hear audio, so the voice and the sound effects are yours to judge.</li>
    <li>Tell me the page number and what to change. When it all looks right, say so and I’ll build the video.</li>
  </ol>
  <button class="play" id="playall" type="button">Play the whole narration, page by page</button>
</div>

<div class="panel">
  <h2>What changed after your review</h2>
  <ul>
    <li><b>No real-iPhone test.</b> The page with the iPhone 13 Pro Max figures is gone, and nothing else mentions it. Every recording is labelled “iPhone 18 Pro Max simulator”, and page 12 says so too.</li>
    <li><b>A more conversational script.</b> Lines now open the way a presenter would: “Take a look at this situation”, “Or let’s say you’re in a lecture”, “So why is this so hard?”, “Let’s see it in action”, “So, does it work?”.</li>
    <li><b>Scenario 1 is a travel photo.</b> A photo of a friend from a ski trip, remembered only as snow, a white hat and a big smile. It runs through the video: the problem (page 2), how the photo is indexed (page 7), how the search finds it (page 8), and the real app finding it from “skiing, white hat, big smile” (page 13).</li>
    <li><b>The edit demo is an AI edit</b> (page 18): “add a red hot air balloon in the sky”. The phone can’t do this itself, so the app asks first, then sends the photo to the image service you set up; about 40 seconds later (cut from the video) the photo comes back with a red balloon over the mountains.</li>
    <li><b>“What’s next” is gone,</b> and the last page lists the four of you with your student IDs.</li>
    <li><b>Page 22 has clean numbers:</b> three runs of the assistant test on the final build passed 14, 15 and 17 of 20.</li>
  </ul>
  <p class="dim">Still as before: the diagrams are drawn in code so they animate with the narration; only measured results are shown; the voice is the one from last time.</p>
</div>

<div class="panel">
  <h2>All pages at a glance</h2>
  <div class="scroll"><table>
    <thead><tr><th class="num">#</th><th>Page</th><th>Part</th><th class="num">Starts</th><th class="num">Lasts</th><th>Made from</th></tr></thead>
    <tbody>__ROWS__</tbody>
  </table></div>
</div>

<div class="panel">
  <h2>Sound effects</h2>
  <p class="dim">The sounds in the video (the tiers have five notes; the first and last are here). Each page lists where they are used. They play at about a quarter of the voice’s loudness.</p>
  <ul class="effects">__EFFECTS__</ul>
</div>

__SECTIONS__

<div class="panel">
  <h2>What is still open</h2>
  <ul>

    <li><b>Numbers from the other tracks</b> (model comparison, categories, duplicates, notes ratings, speed at scale) can be added as a results page if they arrive.</li>
    <li><b>The voice and the sounds are yours to judge.</b> I can’t hear them. Any page’s line can be reworded and re-spoken on its own.</li>
  </ul>
</div>

<div class="panel">
  <h2>How the voice is made</h2>
  <ul>
    <li><b>The model:</b> Kokoro, a small open text-to-speech model (82 million parameters) that runs on this Mac. No account, no key, no cost, and no text leaves the computer. The voice is “af_heart”, one of 54 that come with it.</li>
    <li><b>The script:</b> each page’s line is in <code>remotion/src/talk.json</code>. <code>make_talk.py</code> speaks every line, saves one audio file per page, measures it, and sets the page’s length to fit.</li>
    <li><b>Fitting recordings:</b> a page with a screen recording keeps the recording’s length, so its line is spoken up to 15% faster if it would run over.</li>
    <li><b>In the video:</b> each line starts 0.45 seconds after its page appears, and each animation is timed to the word it illustrates.</li>
  </ul>
</div>

<details>
  <summary>The whole narration in one piece (__WORDS__ words)</summary>
  <div class="panel">__TRANSCRIPT__</div>
</details>
</main>
<script>
(() => {
  const audios = [...document.querySelectorAll('article.page audio')];
  const everything = [...document.querySelectorAll('audio')];
  const button = document.getElementById('playall');
  let running = -1;
  // Only one thing plays at a time.
  everything.forEach((a) => a.addEventListener('play', () => everything.forEach((b) => { if (b !== a) b.pause(); })));
  const mark = (i, on) => audios[i] && audios[i].closest('article').classList.toggle('now', on);
  const stop = () => { if (running >= 0) { audios[running].pause(); mark(running, false); } running = -1; button.textContent = 'Play the whole narration, page by page'; };
  const play = (i) => {
    if (i >= audios.length) { stop(); return; }
    running = i;
    const audio = audios[i];
    mark(i, true);
    audio.closest('article').scrollIntoView({ behavior: 'smooth', block: 'center' });
    audio.currentTime = 0;
    audio.onended = () => { mark(i, false); if (running === i) setTimeout(() => play(i + 1), 650); };
    audio.play().catch(() => stop());
    button.textContent = 'Stop';
  };
  button.addEventListener('click', () => (running >= 0 ? stop() : play(0)));
  document.querySelectorAll('.frame img').forEach((img) => img.addEventListener('click', () => img.closest('article').classList.toggle('wide')));
})();
</script>
</body>
</html>
"""

out = HERE / "out/storyboard.html"
out.parent.mkdir(exist_ok=True)
page = (
    PAGE.replace("__TOTAL__", clock(total))
    .replace("__PAGES__", str(len(pages)))
    .replace("__NEW__", str(count("New animation")))
    .replace("__WORDS__", str(words))
    .replace("__REUSED__", str(count("Reused") + count("Updated")))
    .replace("__TIMELINE__", timeline)
    .replace("__LEGEND__", legend)
    .replace("__ROWS__", rows)
    .replace("__EFFECTS__", effects)
    .replace("__SECTIONS__", sections)
    .replace("__TRANSCRIPT__", transcript)
)
out.write_text(page)
print(f"{out}  {out.stat().st_size / 1e6:.1f} MB  ·  {len(pages)} pages  ·  {clock(total)}  ·  {words} words")
for span in spans:
    print(f"  {span['part']:<15} {clock(span['start'])}–{clock(span['end'])}  {span['seconds']:5.1f} s  pages {span['pages'][0]}–{span['pages'][-1]}")
