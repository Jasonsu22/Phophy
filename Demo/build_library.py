"""Builds the demo photo library for the Phophy video.

    python3 Demo/build_library.py CAPTIONS.tsv SIM_MEDIA_DIR OUT_DIR

CAPTIONS.tsv has one line per test photo, "DCIM/100APPLE/IMG_0001.JPG|caption"
(exported from the evaluation simulator, whose photos are the Flickr30k test
split). Everyday photos are picked from it by subject. Everything else
(lecture slides, receipts, documents, a whiteboard, screenshots) is drawn
here, so the library shows every feature without anyone's real photos.

Every file gets a date and, where it makes sense, a place in its EXIF data,
so date and place search, lecture grouping and similar-photo detection work
as on a real phone. Add the output to a simulator with
`xcrun simctl addmedia <sim> OUT_DIR/*`.
"""
import math, random, subprocess, sys
from datetime import datetime, timedelta
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont
from PIL.PngImagePlugin import PngInfo

random.seed(7)
captions_path, media_dir, out_dir = map(Path, sys.argv[1:4])
out_dir.mkdir(parents=True, exist_ok=True)

LATIN = "/System/Library/Fonts/Helvetica.ttc"
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, bold=False, chinese=False):
    # One family for everything: Hiragino Sans GB covers Latin, Chinese,
    # arrows and symbols, so mixed lines ("MUJI 無印良品") render.
    return ImageFont.truetype(CJK, size, index=1 if bold else 0)


# Places (latitude, longitude).
HKU = (22.2830, 114.1371)
CENTRAL = (22.2819, 114.1580)
MONG_KOK = (22.3193, 114.1694)
SHEK_O = (22.2300, 114.2510)
TOKYO = (35.6595, 139.7005)
ZERMATT = (46.0207, 7.7491)
SHANGHAI = (31.2304, 121.4737)


def dms(value):
    value = abs(value)
    d = int(value); m = int((value - d) * 60); s = (value - d - m / 60) * 3600
    return (float(d), float(m), round(s, 4))


def exif_for(when, place=None, model="iPhone 17 Pro", screenshot=False):
    exif = Image.Exif()
    exif[0x010F] = "Apple"
    exif[0x0110] = model
    exif[0x0132] = when.strftime("%Y:%m:%d %H:%M:%S")
    ifd = exif.get_ifd(0x8769)
    ifd[0x9003] = when.strftime("%Y:%m:%d %H:%M:%S")
    ifd[0x9004] = when.strftime("%Y:%m:%d %H:%M:%S")
    ifd[0x9011] = "+08:00" if not place or place[1] > 100 else ("+09:00" if place == TOKYO else "+01:00")
    if screenshot:
        ifd[0x9286] = b"ASCII\x00\x00\x00Screenshot"
    if place:
        gps = exif.get_ifd(0x8825)
        gps[1] = "N" if place[0] >= 0 else "S"
        gps[2] = dms(place[0])
        gps[3] = "E" if place[1] >= 0 else "W"
        gps[4] = dms(place[1])
    return exif


made = []


def save(image, name, when, place=None, screenshot=False, quality=88):
    path = out_dir / name
    exif = exif_for(when, place, screenshot=screenshot)
    if path.suffix.lower() == ".png":
        info = PngInfo()
        if screenshot:
            # Photos marks a PNG as a screenshot from this XMP comment, as on an iPhone.
            info.add_itxt("XML:com.adobe.xmp", (
                '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
                '<rdf:Description rdf:about="" xmlns:exif="http://ns.adobe.com/exif/1.0/">'
                f'<exif:PixelXDimension>{image.width}</exif:PixelXDimension><exif:PixelYDimension>{image.height}</exif:PixelYDimension>'
                '<exif:UserComment>Screenshot</exif:UserComment></rdf:Description></rdf:RDF></x:xmpmeta>'))
        image.save(path, exif=exif, pnginfo=info)
    else:
        image.convert("RGB").save(path, quality=quality, exif=exif)
    made.append(path)
    return path


def jitter(base, minutes):
    return base + timedelta(minutes=random.uniform(0, minutes))


# MARK: Everyday photos, picked from the test set by subject

captions = []
for line in captions_path.read_text().splitlines():
    if "|" in line:
        rel, caption = line.split("|", 1)
        captions.append((media_dir / rel, caption.lower()))

used = set()


def pick(words, count, avoid=()):
    found = []
    for path, caption in captions:
        if path in used or not path.exists():
            continue
        if any(w in caption for w in words) and not any(a in caption for a in avoid):
            found.append(path)
    random.shuffle(found)
    chosen = found[:count]
    used.update(chosen)
    return chosen


# (subject words, how many, place, first day, days spread, hour range)
SETS = [
    (["dog", "puppy"], 12, None, datetime(2026, 6, 1), 160, (8, 19)),
    (["beach", "ocean", "surf", "wave"], 12, SHEK_O, datetime(2026, 7, 18), 2, (10, 18)),
    (["food", "restaurant", "eating", "meal", "kitchen", "cook"], 12, MONG_KOK, datetime(2026, 9, 1), 75, (12, 21)),
    (["city street", "crowd", "night", "building", "market"], 12, CENTRAL, datetime(2026, 10, 3), 40, (17, 23)),
    (["snow", "ski", "mountain"], 10, ZERMATT, datetime(2026, 1, 12), 4, (9, 16)),
    (["climb", "rock", "hiking", "hiker"], 8, SHEK_O, datetime(2026, 3, 8), 30, (9, 16)),
    (["wedding", "bride"], 6, CENTRAL, datetime(2025, 12, 20), 0.3, (15, 20)),
    (["soccer", "football", "basketball", "baseball"], 8, HKU, datetime(2026, 4, 1), 60, (15, 19)),
    (["bike", "bicycle", "cyclist"], 7, TOKYO, datetime(2026, 5, 2), 4, (9, 18)),
    (["child", "kid", "boy", "girl", "playground"], 10, None, datetime(2026, 2, 1), 200, (9, 18)),
    (["guitar", "concert", "music", "singer", "stage"], 7, TOKYO, datetime(2026, 5, 3), 3, (19, 23)),
    (["flower", "garden", "park", "tree"], 8, HKU, datetime(2026, 3, 20), 50, (10, 17)),
    (["cat", "horse", "bird", "animal"], 6, None, datetime(2026, 8, 1), 90, (9, 18)),
]

photo_count = 0
for words, count, place, first, spread, hours in SETS:
    for path in pick(words, count, avoid=["dog"] if "dog" not in words else ()):
        day = first + timedelta(days=random.uniform(0, spread))
        when = day.replace(hour=random.randint(*hours), minute=random.randint(0, 59), second=random.randint(0, 59))
        image = Image.open(path)
        photo_count += 1
        save(image, f"photo_{photo_count:03d}.jpg", when, place)

# Bursts: the same moment shot a few times, for "Similar photos".
for words, place, when, shots in [(["dog"], None, datetime(2026, 11, 8, 16, 20), 4), (["sunset", "beach"], SHEK_O, datetime(2026, 7, 19, 18, 42), 3)]:
    base = pick(words, 1)
    if not base:
        continue
    source = Image.open(base[0]).convert("RGB")
    w, h = source.size
    for i in range(shots):
        dx, dy = random.randint(0, w // 30), random.randint(0, h // 30)
        shot = source.crop((dx, dy, w - w // 30 + dx, h - h // 30 + dy)).resize((w, h))
        shot = ImageEnhance.Brightness(shot).enhance(random.uniform(0.93, 1.07))
        photo_count += 1
        save(shot, f"burst_{photo_count:03d}.jpg", when + timedelta(seconds=2 * i), place)


# MARK: Lecture slides, photographed from a seat

def slide(title, lines, course, number, chinese=False, diagram=None):
    W, H = 1600, 900
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 120), fill=(0, 51, 102))
    d.text((50, 22), title, font=font(62, True, chinese), fill="white")
    y = 160
    if diagram:
        diagram(d)
    else:
        for line in lines:
            indent = 90 if line.startswith("  ") else 50
            bullet = "–" if line.startswith("  ") else "•"
            d.text((indent, y), f"{bullet} {line.strip()}", font=font(50 if indent == 50 else 42, False, chinese), fill=(30, 30, 30))
            y += 92 if indent == 50 else 74
    d.text((50, H - 60), course, font=font(26, False, chinese), fill=(110, 110, 110))
    d.text((W - 90, H - 60), str(number), font=font(26), fill=(110, 110, 110))
    return img


def photograph(slide_img, seed):
    """Puts a slide on a dark lecture-hall wall, seen at an angle, a bit soft."""
    rnd = random.Random(seed)
    W, H = 2016, 1512
    room = Image.new("RGB", (W, H), (28, 26, 30))
    d = ImageDraw.Draw(room)
    for _ in range(12):  # heads and desks in the foreground
        x = rnd.randint(0, W); r = rnd.randint(90, 160)
        d.ellipse((x - r, H - r // 2, x + r, H + r), fill=(15, 14, 16))
    sw, sh = int(W * rnd.uniform(0.68, 0.78)), 0
    sh = int(sw * 9 / 16)
    s = slide_img.resize((sw, sh)).convert("RGB")
    s = ImageEnhance.Brightness(s).enhance(rnd.uniform(0.86, 0.97))
    x0, y0 = (W - sw) // 2 + rnd.randint(-80, 80), rnd.randint(150, 260)
    skew = rnd.randint(-40, 40)
    quad = (x0 + max(skew, 0), y0, x0 + sw - max(-skew, 0), y0 + abs(skew) // 2, x0 + sw, y0 + sh, x0, y0 + sh - abs(skew) // 2)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon([(quad[i], quad[i + 1]) for i in range(0, 8, 2)], fill=255)
    # Map the slide's corners onto the quad by placing it, then masking.
    canvas = Image.new("RGB", (W, H))
    canvas.paste(s, (x0, y0))
    room.paste(canvas, (0, 0), mask)
    room = room.filter(ImageFilter.GaussianBlur(rnd.uniform(0.6, 1.2)))
    return room


def network_diagram(d):
    boxes = {"Internet": (650, 170), "Firewall": (650, 330), "Router": (650, 490), "Switch": (650, 650),
             "Web server": (250, 650), "Laptop": (1050, 650)}
    for a, b in [("Internet", "Firewall"), ("Firewall", "Router"), ("Router", "Switch"), ("Switch", "Web server"), ("Switch", "Laptop")]:
        (x1, y1), (x2, y2) = boxes[a], boxes[b]
        d.line((x1 + 150, y1 + 40, x2 + 150, y2 + 40), fill=(40, 40, 40), width=5)
    for name, (x, y) in boxes.items():
        d.rounded_rectangle((x, y, x + 300, y + 80), 14, fill=(230, 240, 255), outline=(0, 51, 102), width=4)
        d.text((x + 150, y + 40), name, font=font(34, True), fill=(0, 51, 102), anchor="mm")


LECTURES = [
    ("COMP3234 Computer Networks · Lecture 8", datetime(2026, 11, 10, 14, 32), HKU, False, [
        ("TCP: Reliable Transport", ["Connection-oriented, byte stream", "Sequence numbers and ACKs", "Flow control with a receive window", "Congestion control"]),
        ("The Three-Way Handshake", ["Client sends SYN (seq = x)", "Server replies SYN-ACK (seq = y, ack = x + 1)", "Client sends ACK (ack = y + 1)", "  Both sides now ESTABLISHED"]),
        ("Closing a Connection", ["FIN from the side that is done sending", "Peer ACKs, then sends its own FIN", "TIME_WAIT lasts 2 × MSL", "  Old segments die out first"]),
        ("Flow Control", ["Receiver advertises rwnd in each ACK", "Sender keeps unACKed data ≤ rwnd", "Zero window: sender probes periodically"]),
        ("Congestion Control", ["Slow start: cwnd doubles each RTT", "Congestion avoidance: +1 MSS per RTT", "On loss: halve cwnd (Reno)", "  Timeout: cwnd back to 1 MSS"]),
        ("Our Lab Network", None),
        ("Summary", ["Handshake sets up sequence numbers", "Windows control how much is in flight", "Midterm: Lecture 6–8, 20 November"]),
    ]),
    ("COMP3314 Machine Learning · Lecture 5", datetime(2026, 11, 12, 10, 35), HKU, False, [
        ("Gradient Descent", ["Minimise a loss L(θ)", "Step against the gradient: θ ← θ − η · grad L(θ)", "η is the learning rate"]),
        ("Choosing the Learning Rate", ["Too small: slow convergence", "Too large: overshoot and diverge", "Schedules: step decay, cosine, warm-up"]),
        ("Stochastic Gradient Descent", ["Estimate the gradient from a mini-batch", "Noisy but much cheaper per step", "Batch size 32–512 is typical"]),
        ("Momentum and Adam", ["Momentum averages past gradients", "Adam: per-parameter step sizes", "  β1 = 0.9, β2 = 0.999 by default"]),
        ("Overfitting", ["Training loss falls, validation loss rises", "Fixes: more data, regularisation, early stopping", "Always keep a held-out test set"]),
        ("Assignment 2", ["Implement SGD and Adam from scratch", "Compare on MNIST", "Due Friday 27 November, 23:59"]),
    ]),
    ("数据库系统 · 第6讲", datetime(2026, 11, 13, 9, 34), HKU, True, [
        ("事务与ACID", ["原子性：全部完成或全部撤销", "一致性：约束始终成立", "隔离性：并发事务互不干扰", "持久性：提交后不会丢失"]),
        ("并发控制", ["两阶段锁协议（2PL）", "  扩展阶段只加锁，收缩阶段只解锁", "死锁检测与超时"]),
        ("隔离级别", ["读未提交", "读已提交", "可重复读", "可串行化"]),
        ("日志与恢复", ["先写日志（WAL）", "检查点减少恢复时间", "撤销（Undo）与重做（Redo）"]),
        ("本讲小结", ["ACID 是事务的基本保证", "下周：索引与B+树", "作业三：11月25日截止"]),
    ]),
]

for course, start, place, chinese, slides in LECTURES:
    for i, (title, lines) in enumerate(slides, 1):
        img = slide(title, lines or [], course, i, chinese, diagram=network_diagram if lines is None else None)
        when = start + timedelta(minutes=6 * i + random.uniform(0, 3))
        save(photograph(img, hash((course, i)) & 0xFFFF), f"slide_{len(made):03d}.jpg", when, place)


# MARK: Receipts and documents

def paper(width, height, lines, chinese=False, size=34, tilt=2.5, background=(118, 104, 88)):
    sheet = Image.new("RGB", (width, height), (250, 248, 240))
    d = ImageDraw.Draw(sheet)
    y = 50
    for line in lines:
        align = line[0] if line and line[0] in "^>" else ""
        body = line[1:] if align else line
        bold = body.startswith("**")
        text = align + body.strip("*")
        f = font(size + (8 if bold else 0), bold, chinese)
        if text.startswith(">"):
            d.text((width - 50, y), text[1:], font=f, fill=(25, 25, 25), anchor="ra")
        elif text.startswith("^"):
            d.text((width // 2, y), text[1:], font=f, fill=(25, 25, 25), anchor="ma")
        else:
            d.text((50, y), text, font=f, fill=(25, 25, 25))
        y += int(size * 1.6)
    table = Image.new("RGB", (int(width * 1.5), int(height * 1.25)), background)
    sheet = sheet.rotate(random.uniform(-tilt, tilt), expand=True, fillcolor=background)
    table.paste(sheet, ((table.width - sheet.width) // 2, (table.height - sheet.height) // 2))
    return table.filter(ImageFilter.GaussianBlur(0.7))


RECEIPTS = [
    ("receipt_muji.jpg", datetime(2026, 11, 2, 15, 47), CENTRAL, False, [
        "^**MUJI 無印良品", "^IFC Mall, Central, Hong Kong", "^Tel 2234 5678", "", "Gel ink pen 0.5mm  x3     HK$45.00",
        "Notebook B5 6mm ruled     HK$18.00", "Aroma diffuser            HK$390.00", "Linen shirt, navy, M      HK$249.00", "",
        "**TOTAL                  HK$702.00", "Octopus                   HK$702.00", "", "^2026-11-02 15:47  #0312", "^Thank you"]),
    ("receipt_711.jpg", datetime(2026, 11, 15, 8, 12), HKU, False, [
        "^**7-ELEVEN", "^Pok Fu Lam Road", "", "Vita lemon tea 500ml      HK$8.90", "Egg sandwich              HK$16.50",
        "Pocari Sweat             HK$10.50", "", "**TOTAL                  HK$35.90", "Octopus remaining        HK$112.40", "", "^15/11/2026 08:12"]),
    ("receipt_chachaanteng.jpg", datetime(2026, 10, 24, 12, 58), MONG_KOK, True, [
        "^**澳洲牛奶公司", "^九龍佐敦白加士街47號", "", "炒蛋多士            $28", "火腿通粉            $32", "凍奶茶（少甜）       $22",
        "燉奶                $30", "", "**合計              $112", "現金               $120", "找續                 $8", "", "^2026年10月24日 12:58"]),
    ("receipt_starbucks.jpg", datetime(2026, 11, 18, 9, 5), HKU, False, [
        "^**STARBUCKS", "^Centennial Campus", "", "Oat latte, grande         HK$47.00", "Blueberry muffin          HK$26.00", "",
        "**TOTAL                  HK$73.00", "Visa •••• 4821            HK$73.00", "", "^18/11/2026 09:05"]),
]
for name, when, place, chinese, lines in RECEIPTS:
    save(paper(620, 70 + 56 * len(lines), lines, chinese, 30, background=random.choice([(118, 104, 88), (60, 60, 64), (150, 140, 128)])), name, when, place)

DOCUMENTS = [
    ("doc_offer.jpg", datetime(2026, 4, 18, 21, 3), None, False, [
        "**THE UNIVERSITY OF HONG KONG", "Graduate School", "", "Dear Applicant,", "",
        "We are pleased to offer you admission to the", "Master of Science in Computer Science,", "full-time, starting September 2026.", "",
        "Please accept this offer by 15 May 2026", "through the online portal.", "", "Yours sincerely,", "Admissions Office"]),
    ("doc_lease.jpg", datetime(2026, 8, 20, 19, 40), MONG_KOK, False, [
        "**TENANCY AGREEMENT", "", "Premises: Flat 12B, 88 Argyle Street, Mong Kok", "Term: 1 September 2026 to 31 August 2027",
        "Monthly rent: HK$14,500, due on the 1st", "Deposit: two months' rent (HK$29,000)", "", "The tenant shall keep the premises clean",
        "and shall not sublet without consent.", "", "Landlord: ____________   Tenant: ____________"]),
    ("doc_wifi.jpg", datetime(2026, 9, 2, 20, 15), MONG_KOK, False, [
        "**Home Wi-Fi", "", "Network: Flat12B-5G", "Password: harbour-lights-2026", "", "Router admin: 192.168.1.1"]),
]
for name, when, place, chinese, lines in DOCUMENTS:
    save(paper(1100, 90 + 62 * len(lines), lines, chinese, 36, tilt=3, background=(90, 72, 58)), name, when, place)

# The whiteboard with the network diagram.
board = Image.new("RGB", (1900, 1150), (238, 240, 238))
d = ImageDraw.Draw(board)
marker = lambda size: font(size, True)
d.text((60, 40), "Group project – office network", font=marker(54), fill=(20, 60, 160))
nodes = {"ISP": (820, 150), "Firewall": (820, 360), "Core switch": (820, 570), "VLAN 10 Staff": (260, 830),
         "VLAN 20 Guest": (820, 830), "NAS": (1380, 830)}
for a, b in [("ISP", "Firewall"), ("Firewall", "Core switch"), ("Core switch", "VLAN 10 Staff"), ("Core switch", "VLAN 20 Guest"), ("Core switch", "NAS")]:
    (x1, y1), (x2, y2) = nodes[a], nodes[b]
    d.line((x1 + 130, y1 + 50, x2 + 130, y2 + 50), fill=(30, 30, 30), width=7)
for name, (x, y) in nodes.items():
    d.rectangle((x, y, x + 300, y + 100), outline=(200, 30, 30) if name == "Firewall" else (30, 30, 30), width=7, fill=(238, 240, 238))
    d.text((x + 150, y + 50), name, font=marker(34), fill=(30, 30, 30), anchor="mm")
d.text((1250, 380), "TODO: DHCP on VLAN 20\nask IT about ports 443/8443", font=marker(32), fill=(20, 120, 40))
wall = Image.new("RGB", (2300, 1500), (170, 165, 150))
wall.paste(board.rotate(1.5, expand=True, fillcolor=(170, 165, 150)), (180, 150))
save(wall.filter(ImageFilter.GaussianBlur(1.0)), "whiteboard.jpg", datetime(2026, 10, 29, 16, 20), HKU)


# MARK: Screenshots

SW, SH = 1320, 2868


def screen(title, rows, chinese=False, accent=(0, 122, 255), dark=False):
    bg, fg = ((0, 0, 0), (240, 240, 240)) if dark else ((242, 242, 247), (20, 20, 20))
    img = Image.new("RGB", (SW, SH), bg)
    d = ImageDraw.Draw(img)
    d.text((110, 60), "9:41", font=font(52, True), fill=fg)
    d.text((SW // 2, 290), title, font=font(84, True, chinese), fill=fg, anchor="mm")
    y = 420
    for row in rows:
        if row == "---":
            y += 40; continue
        if isinstance(row, tuple):  # chat bubble (mine?, text)
            mine, text = row
            f = font(56, False, chinese)
            tw = d.textlength(text, font=f)
            x = SW - 90 - tw - 60 if mine else 90
            d.rounded_rectangle((x, y, x + tw + 60, y + 116), 44, fill=accent if mine else (255, 255, 255))
            d.text((x + 30, y + 24), text, font=f, fill="white" if mine else fg)
            y += 160; continue
        big = row.startswith("**")
        d.text((90, y), row.strip("*"), font=font(74 if big else 58, big, chinese), fill=fg)
        y += 124 if big else 96
    return img


SCREENS = [
    ("screen_train.png", datetime(2026, 11, 6, 22, 41), screen("Booking confirmed", [
        "**G1234  Hong Kong West Kowloon", "**→ Shanghai Hongqiao", "Friday 19 December 2026", "Departs 08:15 · Arrives 16:47", "---",
        "Passenger: CHAN, ALEX", "Coach 6 · Seat 12F · Second class", "Fare: HK$1,128", "---", "Order no. E829104417",
        "Show your ID at the gate."], accent=(0, 140, 90))),
    ("screen_chat.png", datetime(2026, 11, 14, 18, 3), screen("Project group", [
        (False, "Dinner after the demo on Saturday?"), (True, "Yes! Hot pot in Mong Kok?"), (False, "Book for 4 at 7pm"),
        (True, "Booked: Haidilao, 7:00pm, table for 4"), (False, "Great, see you there")], chinese=False)),
    ("screen_boarding.png", datetime(2026, 4, 30, 6, 55), screen("Boarding pass", [
        "**HKG → NRT", "Cathay Pacific CX 504", "Saturday 2 May 2026", "Boarding 08:20 · Gate 23", "Seat 41A · Economy", "---",
        "Booking ref: 7KQ2LP"], dark=True)),
    ("screen_order.png", datetime(2026, 10, 12, 23, 17), screen("订单详情", [
        "**降噪耳机 Pro 2", "实付款 ¥1,299.00", "预计 10月15日 送达", "---", "收货地址：香港 旺角 亚皆老街 88 号", "订单编号 2026101223170042",
        "支付方式：支付宝"], chinese=True, accent=(255, 80, 0))),
    ("screen_map.png", datetime(2026, 5, 2, 13, 2), screen("Directions", [
        "**Shibuya Station → Meiji Shrine", "Walk 22 min · 1.6 km", "---", "Head north on Meiji-dori", "Turn left at Jingumae 6-chome",
        "Arrive at the south gate"])),
    ("screen_timetable.png", datetime(2026, 9, 3, 11, 30), screen("Semester 1 timetable", [
        "**Monday", "COMP3234 Networks · 14:30 · CPD-3.04", "**Wednesday", "COMP3314 Machine Learning · 10:30 · MWT-1",
        "**Friday", "Databases · 09:30 · KK-201", "---", "Midterms: 20–24 November"])),
]
for name, when, img in SCREENS:
    save(img, name, when, screenshot=True)


# MARK: Short videos

def video(source_name, out_name, when, place_note):
    src = out_dir / source_name
    if not src.exists():
        return
    out = out_dir / out_name
    stamp = (when - timedelta(hours=8)).strftime("%Y-%m-%dT%H:%M:%S.000000Z")
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-i", str(src), "-t", "6",
        "-vf", "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,zoompan=z='min(zoom+0.0012,1.15)':d=180:s=1920x1080:fps=30",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-metadata", f"creation_time={stamp}", str(out)], check=True)
    made.append(out)

beach = sorted(out_dir.glob("burst_*.jpg"))
if beach:
    video(beach[-1].name, "video_beach.mp4", datetime(2026, 7, 19, 18, 45), "Shek O")
dogs = sorted(out_dir.glob("burst_*.jpg"))
if dogs:
    video(dogs[0].name, "video_dog.mp4", datetime(2026, 11, 8, 16, 22), "home")

print(f"{len(made)} files in {out_dir}: {photo_count} photos, the rest drawn")
