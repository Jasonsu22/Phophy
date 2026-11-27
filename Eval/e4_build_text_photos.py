"""Draws the text-heavy photos for experiment E4 (OCR text embeddings).

    python3 Eval/e4_build_text_photos.py OUT_DIR

100 photos with known text: 72 lecture slides photographed in a lecture
hall (10 English NLP lectures, 2 Chinese lectures), 12 documents, 10
screenshots and 6 receipts. Everything is drawn here, so no one's real
photos are used. File names are what Eval/e4_queries.json refers to.
Add them, together with the Flickr30k test photos as everyday distractors,
to a simulator with `xcrun simctl addmedia`.
"""
import random
import zlib
import sys
from datetime import datetime, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

random.seed(4)
out_dir = Path(sys.argv[1])
out_dir.mkdir(parents=True, exist_ok=True)
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, bold=False):
    from PIL import ImageFont
    return ImageFont.truetype(CJK, size, index=1 if bold else 0)


def exif_for(when, screenshot=False):
    exif = Image.Exif()
    exif[0x010F] = "Apple"
    exif[0x0110] = "iPhone 17 Pro"
    stamp = when.strftime("%Y:%m:%d %H:%M:%S")
    exif[0x0132] = stamp
    ifd = exif.get_ifd(0x8769)
    ifd[0x9003] = stamp
    ifd[0x9004] = stamp
    ifd[0x9011] = "+08:00"
    return exif


def save(image, name, when):
    path = out_dir / name
    if path.suffix == ".png":
        image.save(path, exif=exif_for(when))
    else:
        image.convert("RGB").save(path, quality=88, exif=exif_for(when))


# MARK: Drawing (same look as Demo/build_library.py)

def slide(title, lines, course, number):
    W, H = 1600, 900
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 120), fill=(0, 51, 102))
    d.text((50, 22), title, font=font(62, True), fill="white")
    y = 160
    for line in lines:
        sub = line.startswith("  ")
        d.text((90 if sub else 50, y), f"{'–' if sub else '•'} {line.strip()}", font=font(42 if sub else 50), fill=(30, 30, 30))
        y += 74 if sub else 92
    d.text((50, H - 60), course, font=font(26), fill=(110, 110, 110))
    d.text((W - 90, H - 60), str(number), font=font(26), fill=(110, 110, 110))
    return img


def photograph(slide_img, seed):
    rnd = random.Random(seed)
    W, H = 2016, 1512
    room = Image.new("RGB", (W, H), (28, 26, 30))
    d = ImageDraw.Draw(room)
    for _ in range(12):
        x = rnd.randint(0, W); r = rnd.randint(90, 160)
        d.ellipse((x - r, H - r // 2, x + r, H + r), fill=(15, 14, 16))
    sw = int(W * rnd.uniform(0.70, 0.80)); sh = int(sw * 9 / 16)
    s = ImageEnhance.Brightness(slide_img.resize((sw, sh))).enhance(rnd.uniform(0.86, 0.97))
    room.paste(s, ((W - sw) // 2 + rnd.randint(-60, 60), rnd.randint(150, 240)))
    return room.filter(ImageFilter.GaussianBlur(rnd.uniform(0.5, 1.0)))


def paper(lines, width=1100, size=36):
    height = 90 + int(size * 1.6) * len(lines)
    sheet = Image.new("RGB", (width, height), (250, 248, 240))
    d = ImageDraw.Draw(sheet)
    y = 50
    for line in lines:
        bold = line.startswith("**")
        d.text((50, y), line.strip("*"), font=font(size + (8 if bold else 0), bold), fill=(25, 25, 25))
        y += int(size * 1.6)
    bg = random.choice([(118, 104, 88), (90, 72, 58), (60, 60, 64)])
    table = Image.new("RGB", (int(width * 1.4), int(height * 1.25)), bg)
    sheet = sheet.rotate(random.uniform(-2.5, 2.5), expand=True, fillcolor=bg)
    table.paste(sheet, ((table.width - sheet.width) // 2, (table.height - sheet.height) // 2))
    return table.filter(ImageFilter.GaussianBlur(0.7))


def screen(title, rows):
    W, H = 1320, 2868
    img = Image.new("RGB", (W, H), (242, 242, 247))
    d = ImageDraw.Draw(img)
    d.text((110, 60), "9:41", font=font(52, True), fill=(20, 20, 20))
    d.text((W // 2, 290), title, font=font(80, True), fill=(20, 20, 20), anchor="mm")
    y = 420
    for row in rows:
        if row == "---":
            y += 40; continue
        big = row.startswith("**")
        d.text((90, y), row.strip("*"), font=font(70 if big else 56, big), fill=(20, 20, 20))
        y += 120 if big else 96
    return img


# MARK: Content

LECTURES = [
    ("tok", "Natural Language Processing · Lecture 2", [
        ("Why Tokenize?", ["Models read integer IDs, not raw strings", "Word-level vocabularies explode", "Character-level sequences get very long"]),
        ("Byte-Pair Encoding", ["Start from single characters", "Repeatedly merge the most frequent adjacent pair", "Stop when the vocabulary reaches its target size", "  \"lowest\" → low + est"]),
        ("WordPiece and SentencePiece", ["WordPiece: merge by likelihood gain (BERT)", "SentencePiece: treats whitespace as a symbol", "Works for languages without spaces"]),
        ("Vocabulary Size Trade-offs", ["Small vocab: longer sequences", "Large vocab: bigger embedding table", "Typical: 32k–100k entries"]),
        ("Unknown Words", ["Rare names fall back to smaller pieces", "No [UNK] needed with byte-level units", "Numbers split unpredictably"]),
        ("Summary", ["Subword units balance length and coverage", "Next week: vector representations of meaning"]),
    ]),
    ("emb", "Natural Language Processing · Lecture 3", [
        ("Distributional Hypothesis", ["\"You shall know a word by the company it keeps\"", "Co-occurrence statistics capture meaning"]),
        ("word2vec: Skip-gram", ["Given the centre word, predict its context words", "Window of ±5 positions", "One hidden layer, no non-linearity"]),
        ("Negative Sampling", ["Softmax over the whole vocabulary is slow", "Contrast the true context with k random words", "k = 5–20 for small corpora"]),
        ("GloVe", ["Factorise the global co-occurrence matrix", "Weighted least squares on log counts"]),
        ("Vector Arithmetic", ["king − man + woman ≈ queen", "Paris − France + Italy ≈ Rome"]),
        ("Limits of Static Vectors", ["One vector per word type", "\"bank\" of a river vs a bank account", "Fixed by contextual models later"]),
    ]),
    ("rnn", "Natural Language Processing · Lecture 4", [
        ("Recurrent Networks", ["Hidden state carries information forward", "Same weights at every time step"]),
        ("Backpropagation Through Time", ["Unroll the network over the sequence", "Truncate after 50–200 steps"]),
        ("Vanishing Gradients", ["Repeated multiplication by small Jacobians", "Signal from early steps fades away", "Exploding case: clip the norm"]),
        ("LSTM", ["A cell state runs alongside the hidden state", "Forget, input and output gates", "Additive updates keep information alive"]),
        ("GRU", ["Update and reset gates only", "Fewer parameters than LSTM"]),
        ("Encoder–Decoder", ["Encoder reads the source into a vector", "Decoder generates the target one token at a time", "Bottleneck: one vector for a whole sentence"]),
    ]),
    ("attn", "Natural Language Processing · Lecture 5", [
        ("Attention", ["Each output looks at all input positions", "Weights come from a softmax over scores"]),
        ("Scaled Dot-Product", ["score = Q·K^T / √d_k", "Scaling keeps the softmax from saturating", "Then weight the values V"]),
        ("Multi-Head", ["h parallel attention layers", "Each head learns different relations", "Outputs concatenated and projected"]),
        ("Positional Encoding", ["Self-attention ignores order on its own", "Add sine and cosine signals of each position", "Or learn position vectors; RoPE rotates them"]),
        ("Residuals and LayerNorm", ["x + Sublayer(x) eases optimisation", "Normalise before each sublayer (pre-LN)"]),
        ("Encoder vs Decoder", ["Encoder: bidirectional", "Decoder: causal mask, can't see the future"]),
    ]),
    ("pre", "Natural Language Processing · Lecture 6", [
        ("Masked Language Modelling", ["Hide 15% of tokens", "Predict them from both sides", "BERT, RoBERTa"]),
        ("Causal Language Modelling", ["Predict the next token from the left context", "GPT family"]),
        ("Fine-tuning", ["Start from pretrained weights", "Train briefly on labelled task data"]),
        ("LoRA", ["Freeze the base weights", "Learn a rank-r update W + BA", "Under 1% of parameters trained"]),
        ("Scaling Laws", ["Loss falls as a power law in compute", "Grow parameters and tokens together", "Chinchilla: about 20 tokens per parameter"]),
        ("Data Quality", ["Deduplicate web text", "Filter toxic and low-quality pages"]),
    ]),
    ("dec", "Natural Language Processing · Lecture 7", [
        ("Greedy Decoding", ["Take the argmax token at each step", "Fast but often repetitive"]),
        ("Beam Search", ["Keep the k best partial sequences", "Length normalisation avoids short outputs"]),
        ("Top-k Sampling", ["Sample from the k most likely tokens", "k fixed regardless of the distribution"]),
        ("Nucleus Sampling", ["Smallest set whose probability mass ≥ p", "p = 0.9 is common", "Adapts to how peaked the distribution is"]),
        ("Temperature", ["Divide logits by T before the softmax", "T < 1: sharper, safer text", "T > 1: flatter, more diverse text"]),
        ("Repetition Penalty", ["Lower the score of tokens already used", "Stops loops like \"the the the\""]),
    ]),
    ("evl", "Natural Language Processing · Lecture 8", [
        ("BLEU", ["Modified n-gram precision, n = 1..4", "Brevity penalty for short outputs", "Standard for machine translation"]),
        ("ROUGE", ["Recall of overlapping n-grams", "ROUGE-L: longest common subsequence", "Used for summarisation"]),
        ("Perplexity", ["exp of the average negative log-likelihood", "Lower is better; only comparable with the same tokenizer"]),
        ("Human Evaluation", ["Fluency, adequacy, preference", "Expensive but closest to what users feel"]),
        ("Cohen's Kappa", ["Agreement between two annotators", "Corrects for agreement expected by chance", "κ > 0.8: strong"]),
        ("Contamination", ["Test sets leak into pretraining data", "Report results on held-out, recent data"]),
    ]),
    ("aln", "Natural Language Processing · Lecture 9", [
        ("Instruction Tuning", ["Fine-tune on (instruction, response) pairs", "Teaches the model to follow requests"]),
        ("Reward Model", ["Humans compare two responses", "A model learns to score the preferred one higher"]),
        ("RLHF", ["Optimise the policy against the reward model", "PPO with a KL penalty to the original model"]),
        ("DPO", ["Learn directly from preference pairs", "No separate reward model or RL loop"]),
        ("Red Teaming", ["Probe for harmful or unsafe outputs", "Feed failures back into training"]),
        ("Hallucination", ["Fluent but unsupported statements", "Invented citations and numbers", "Mitigate with retrieval and abstaining"]),
    ]),
    ("rag", "Natural Language Processing · Lecture 10", [
        ("Why Retrieve?", ["Knowledge in weights goes stale", "Look up documents at question time", "Answers can cite their sources"]),
        ("Dense Retrieval", ["Encode queries and passages as vectors", "Nearest-neighbour search (FAISS)"]),
        ("Chunking", ["Split long documents into 200–500 token passages", "Overlap neighbouring passages a little"]),
        ("Re-ranking", ["First stage: fast, recall-oriented", "Second stage: a cross-encoder reorders the top 50"]),
        ("Grounded Answers", ["Quote the passage that supports each claim", "Say \"not found\" when nothing supports it"]),
        ("Where RAG Fails", ["Wrong passage retrieved", "Right passage, ignored by the generator"]),
    ]),
    ("prm", "Natural Language Processing · Lecture 11", [
        ("Zero-shot and Few-shot", ["Zero-shot: instruction only", "Few-shot: add a handful of worked examples"]),
        ("Chain-of-Thought", ["Ask for intermediate reasoning before the answer", "Big gains on arithmetic word problems"]),
        ("Self-Consistency", ["Sample several reasoning paths", "Take the majority answer"]),
        ("Tool Use", ["The model calls a calculator, search or code", "Results go back into the context"]),
        ("Prompt Injection", ["Instructions hidden in retrieved web pages or emails", "Can override what the developer intended", "Treat external text as data"]),
        ("Course Project", ["Final report due 15 December, 23:59", "Recorded presentation due 29 November", "Groups of 1–6"]),
    ]),
    ("os", "操作系统 · 第4讲", [
        ("进程与线程", ["进程：资源分配的基本单位", "线程：CPU调度的基本单位", "同一进程的线程共享地址空间"]),
        ("CPU调度算法", ["先来先服务（FCFS）", "短作业优先（SJF）", "时间片轮转（RR）"]),
        ("死锁的四个必要条件", ["互斥", "占有并等待", "不可剥夺", "循环等待"]),
        ("银行家算法", ["分配前检查系统是否仍处于安全状态", "不安全则让进程等待"]),
        ("虚拟内存与分页", ["逻辑地址分为页号和页内偏移", "页表把页映射到物理页框"]),
        ("页面置换", ["缺页时必须选一页换出", "LRU：淘汰最久未使用的页", "FIFO 可能出现 Belady 异常"]),
    ]),
    ("ir", "信息检索 · 第2讲", [
        ("倒排索引", ["词项 → 出现该词项的文档列表", "查询时合并各词项的列表"]),
        ("TF-IDF 权重", ["词频：词在文档中出现越多越重要", "逆文档频率：越少见的词越有区分度"]),
        ("BM25", ["词频饱和，避免长文档占优", "参数 k1 和 b 控制饱和与长度归一"]),
        ("查询扩展", ["加入同义词和相关词", "伪相关反馈：用前几篇结果扩充查询"]),
        ("评价指标", ["准确率：返回结果中相关的比例", "召回率：相关文档被找回的比例"]),
        ("排序融合", ["倒数排名融合（RRF）", "1 / (k + 名次) 相加", "不需要分数可比"]),
    ]),
]

DOCUMENTS = [
    ("doc_library", ["**Main Library · Overdue Notice", "", "Two items were due on 12 November.", "A charge of HK$2.50 per item per day", "applies until they are returned.", "Renew online if no one has requested them."]),
    ("doc_gym", ["**FitZone Membership Terms", "", "Membership runs for 12 months.", "Ending it early needs 30 days' written notice", "and a fee of one month's dues.", "Freezing is allowed for up to 2 months a year."]),
    ("doc_internship", ["**Summer Internship Offer", "", "We are pleased to offer you a place as", "Machine Learning Intern, Data Platform team.", "First day: Monday 15 June 2027, 9:30 am.", "Stipend: HK$18,000 per month."]),
    ("doc_house_rules", ["**Building House Rules", "", "Quiet hours are 11 pm to 7 am.", "No parties or loud music during these hours.", "Bicycles may not be kept in the corridor.", "Rubbish goes out before 9 pm."]),
    ("doc_exam_timetable", ["**Examination Timetable · December", "", "Mon 14 Dec 09:30  COMP5501 Natural Language Processing", "Tue 15 Dec 14:30  COMP7404 Machine Learning", "Thu 17 Dec 09:30  COMP7305 Cluster Computing", "Bring your student card to every paper."]),
    ("doc_warranty", ["**Limited Warranty Card", "", "Product: 14-inch laptop, serial NX4-2291-0071", "Coverage: 24 months from the date of purchase", "Battery covered for 12 months.", "Accidental damage is not included."]),
    ("doc_lab_safety", ["**Wet Lab Safety Rules", "", "Goggles and a lab coat at all times.", "No food or drink at the benches.", "Report every spill to the technician at once.", "Eye-wash station is next to the door."]),
    ("doc_scholarship", ["**Entrance Scholarship", "", "You have been awarded HK$40,000", "for the 2026–27 academic year.", "Keep a GPA of 3.3 or above to remain eligible."]),
    ("doc_conference", ["**Registration Confirmed", "", "EMNLP Student Workshop, 5 March 2027", "Venue: Convention Centre, Hall 3B", "Poster session 14:00–15:30, board 42"]),
    ("doc_insurance", ["**Travel Insurance Claim", "", "Claim number TC-88213", "Baggage delayed 30 hours at Narita", "Receipts for clothes and toiletries attached", "Amount claimed: HK$1,240"]),
    ("doc_recipe", ["**番茄炒蛋", "", "鸡蛋 3 个，番茄 2 个，葱少许", "先把蛋炒到七成熟后盛出", "番茄炒出汁，加一小勺糖", "倒回鸡蛋翻炒，加盐出锅"]),
    ("doc_vaccination", ["**Vaccination Record", "", "Influenza (2026–27 season): 20 Oct 2026", "COVID-19 booster: 3 Mar 2026", "Next flu shot due: October 2027"]),
]

SCREENS = [
    ("screen_flight_delay", "Flight update", ["**CX 543 to Tokyo Haneda", "New departure 21:40 (was 18:55)", "Reason: late arrival of the aircraft", "Gate 61 · Boarding 21:00"]),
    ("screen_weather", "Weather", ["**Hong Kong", "Tropical Cyclone Signal No. 8", "Gale or storm force winds expected", "Classes suspended · Offices closed", "Mon 26°  Tue 28°  Wed 30°"]),
    ("screen_food_order", "Order on its way", ["**Pad Thai with prawns", "Green papaya salad", "Thai milk tea, less sweet", "Arriving 19:25 · Rider: Ken"]),
    ("screen_calendar", "Event", ["**Group 26 project sync", "Thursday 3 Dec · 16:00–17:00", "Room CB-308 and on Zoom", "Agenda: report outline, video edit"]),
    ("screen_parking", "Parking paid", ["**Cyberport car park", "3 h 20 min · HK$80", "Exit before 18:45 to avoid extra charge"]),
    ("screen_cart", "Cart", ["**Mechanical keyboard, brown switches", "USB-C hub, 7 ports", "Total HK$1,036", "Free delivery on Friday"]),
    ("screen_gym_booking", "Class booked", ["**Spin class · Studio 2", "Saturday 9:00–9:45", "Instructor: Mia", "Cancel at least 12 h before"]),
    ("screen_reset", "Mail", ["**Verify your new sign-in", "Someone signed in from a new Mac.", "If this was you, no action is needed.", "Otherwise change your password now."]),
    ("screen_hiking_chat", "周末爬山", ["**周六早上 8 点 鲗鱼涌地铁站 A 出口集合", "路线：柏架山道 → 大风坳", "记得带水和防晒", "下雨就改到下周"]),
    ("screen_bus", "Next buses", ["**Route 4X · HKU West Gate", "4 min · 13 min · 27 min", "Route 23 · 9 min"]),
]

RECEIPTS = [
    ("receipt_pharmacy", ["**Mannings", "Cold & flu tablets 24s   HK$68.00", "Throat lozenges          HK$32.50", "**TOTAL                  HK$100.50"]),
    ("receipt_bookstore", ["**Commercial Press Bookstore", "Speech and Language Processing, 3rd ed.  HK$520.00", "Highlighter set                          HK$28.00", "**TOTAL                                  HK$548.00"]),
    ("receipt_supermarket", ["**Wellcome", "Oat milk 1L x2            HK$47.80", "Bananas                   HK$15.90", "Rice 5kg                  HK$79.00", "**TOTAL                   HK$142.70"]),
    ("receipt_taxi", ["**Urban Taxi", "Central → HKU", "Fare HK$86.50  Tunnel HK$0", "Paid by Octopus"]),
    ("receipt_cinema", ["**Broadway Cinematheque", "2 x Adult, House 3, Row F", "Sat 19:30", "**TOTAL                  HK$190.00"]),
    ("receipt_salon", ["**Cut & Colour Studio", "Haircut and wash           HK$280.00", "**TOTAL                    HK$280.00"]),
]


def main():
    base = datetime(2026, 9, 7, 10, 0)
    count = 0
    for i, (key, course, slides) in enumerate(LECTURES):
        start = base + timedelta(days=7 * i, hours=random.randint(0, 6))
        for n, (title, lines) in enumerate(slides, 1):
            img = photograph(slide(title, lines, course, n), zlib.crc32(f"{key}{n}".encode()) & 0xFFFF)
            save(img, f"e4_{key}_{n}.jpg", start + timedelta(minutes=8 * n)); count += 1
    for j, (name, lines) in enumerate(DOCUMENTS):
        save(paper(lines), f"e4_{name}.jpg", base + timedelta(days=3 * j, hours=20)); count += 1
    for j, (name, title, rows) in enumerate(SCREENS):
        save(screen(title, rows), f"e4_{name}.png", base + timedelta(days=4 * j, hours=13)); count += 1
    for j, (name, lines) in enumerate(RECEIPTS):
        save(paper(lines, width=900, size=32), f"e4_{name}.jpg", base + timedelta(days=5 * j, hours=18)); count += 1
    print(count, "text photos in", out_dir)


if __name__ == "__main__":
    main()
