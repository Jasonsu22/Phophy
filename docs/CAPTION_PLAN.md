# Plan: describe photos cheaply, then search the descriptions

*Approved 20 Nov 2026 with the cloud layer included. Built 20 Nov: see "Status" at the end.*

## 1. The problem

Search today has two parts (`Phophy/Index/SearchEngine.swift`):

- **Words in the photo:** OCR text plus up to 10 Vision labels, in an FTS5 trigram index.
- **Visual similarity:** a MobileCLIP S0 embedding, compared to the query by cosine similarity, then merged by reciprocal rank fusion.

The embedding misses whenever the query word sits far from the photo in CLIP's space: specific objects ("Muji receipt", "red torii gate"), counts and relations ("two cats on a sofa"), activities, and most Chinese queries. Vision's 1,303 fixed labels are too coarse to cover the gap. What's missing is **a text description of each photo** that keyword search (BM25) and fuzzy matching can work on.

The constraint: describing 10,000–50,000 photos with GPT or Claude per photo is too slow and too expensive. The goal is the best description per photo at the lowest cost.

## 2. What the research found

### On-device describers (free per photo)

| Option | Size | Runs on | Notes |
|---|---|---|---|
| **Apple Foundation Models, image input** (new in iOS 27) | 0 MB, built in | Apple Intelligence phones: iPhone 15 Pro and later | Free, private, nothing to download. Supports guided generation (typed Swift structs). Apple says larger images cost more tokens and time, so send a downscaled copy. No published per-image timings yet. |
| **SmolVLM2 256M / 500M** (Hugging Face) | about 0.3–1 GB | any recent iPhone, via MLX Swift | Apache-2.0. Runs in the HuggingSnap iOS app. Weaker on details. |
| **FastVLM 0.5B** (Apple, CVPR 2025) | about 0.5–1 GB | any recent iPhone, via MLX | Very fast image encoding (85× faster time-to-first-token than LLaVA-OneVision-0.5B). Has an iOS demo app. Its model licence is research-only, which is fine for the course but not for a shipped app. |
| **Florence-2 base** | 0.23B params, 229 MB Core ML | iOS 17+ | Captions in three detail levels. The Core ML port reports about 1.2 GB peak RAM and a CPU-only encoder. |
| **Qwen3-VL 2B** | about 1.2 GB at 4 bit | newest iPhones only | Best quality of the small models. About 33 tokens/s on an iPhone 17 Pro (self-reported). Too heavy for older phones. |
| **RAM++ tagger** | Swin-L, large | needs conversion | 4,585 tags per photo. No Core ML port exists, so converting it would take days. Its **tag list** is still useful (see 3.2). |

**Your test phone is an iPhone 13 Pro Max on iOS 27.0.1.** It has no Apple Intelligence, so the free built-in path won't run on it. Any phone like it needs a downloaded fallback model, and testing the built-in path needs a newer phone or the Mac simulator.

### Cloud describers (opt-in only)

| Option | Price | Cost per photo* | 10,000 photos |
|---|---|---|---|
| Gemini 2.5 Flash-Lite, Batch API | $0.05 per M input tokens, $0.20 per M output | about $0.00003 | **about $0.35** |
| Gemini 2.5 Flash-Lite, standard | $0.10 per M input, $0.40 per M output | about $0.00007 | about $0.70 |
| GPT-5 nano | $0.05 per M input | more: about 1,250 tokens per image, and `detail: low` reportedly has no effect | about $1–2 |

\* Assumes a 384 px image (258 tokens on Gemini; verify), a 100-token prompt and an 80-token answer.

Cloud is cheap enough, but it **breaks the promise in the proposal that photos never leave the phone**. So it can only be an explicit opt-in that uses the user's own key. Batch jobs also take minutes to hours to return.

### Search side

- A study on slide retrieval found **BM25 over VLM captions, fused with neural search, beat either alone**, and CLIP alone trailed BM25. The Sage image-search project uses the same design: captions plus keywords, then BM25 and CLIP with a hybrid ranker.
- FTS5 has `bm25()` with per-column weights. The trigram tokenizer gives substring matching but can't match words shorter than 3 characters (most Chinese words). The default tokenizer can't split Chinese at all. On iOS the fix is to segment Chinese with Apple's `NLTokenizer` before indexing.
- FTS5 has no typo tolerance. That has to be added on top, for example as edit-distance correction against the index's own vocabulary (`fts5vocab`).

## 3. Proposed design: five layers, cheapest first

Each layer only spends effort where the cheaper ones haven't already done the job.

### 3.1 Layer 0: keep what exists

Keep metadata, OCR, Vision labels and the MobileCLIP vector for every photo. This stays as it is.

### 3.2 Layer 1: CLIP tags. Free, every photo, no image reload

- Ship a vocabulary of about 5,000 concepts in English and Chinese, built from RAM++'s 4,585-tag list plus common Chinese names.
- Embed each concept once with the MobileCLIP text encoder and ship the result: about 5 MB at float16.
- For each photo, one matrix-vector product against the photo's existing embedding gives its top concepts. Keep those above a per-concept threshold and margin as words in the index ("torii", "鸟居", "latte art", "whiteboard").
- Cost: under 1 ms per photo. It can **back-fill the whole existing index in seconds**, because the embeddings are already stored.
- This turns visual similarity into words BM25 can find, and it covers Chinese.

### 3.3 Layer 2: real descriptions on the device, only where they're worth it

- Ask for **structured output, not prose**, to keep output short: decoding time dominates, so this is the biggest speed lever.

  ```
  caption (≤ 20 words), objects[], scene, activity, people count,
  notable text summary, keywords_en[], keywords_zh[]
  ```

  On Apple Intelligence phones this is a `@Generable` struct. On the fallback model it's a JSON prompt capped at about 80 tokens.
- **Image size:** reuse the 2,048 px image already loaded for OCR, downscaled in memory to about 448 px. No second fetch from Photos.
- **Skip photos that don't need a description:**
  - **Near-duplicates:** bursts and series, found by CLIP similarity above 0.95 within 2 minutes of each other. Describe one photo per group and copy the result to the rest. Libraries are often 20–40% near-duplicates.
  - **Text-heavy photos:** slides, documents, screenshots and receipts with long OCR text. OCR already describes them; they only get a short type tag.
- **Order of work:** favourites, then the newest 2,000 photos, then the rest. Photos whose CLIP tags are weak, meaning nothing scored well, move up.
- **When it runs:**
  - While the app is open and the screen is still, through the existing `IndexThrottle`.
  - Overnight in a `BGProcessingTask` that requires the charger, so the user never sees the cost.
  - It stops when the phone is hot or in Low Power Mode, as indexing already does.
- **Which model:**
  - Phones with Apple Intelligence on iOS 27: the built-in model. Nothing to download.
  - Other phones: an optional download in Settings ("Better search, about 500 MB"). The model is chosen in day 2's benchmark: SmolVLM2-500M, with FastVLM-0.5B as the alternative.
  - If the user says no: Layers 0, 1, 4 and 5 still work.

### 3.4 Layer 3: cloud, optional

Off by default, with the user's own Gemini key from the Keychain:

- Send 384 px copies of the photos Layer 2 hasn't reached yet, through the Batch API.
- Show the estimated cost before starting ("About $0.35 for 10,000 photos").

This changes the proposal's "photos never leave the phone" line, so the proposal needs one sentence updated if we keep this layer.

### 3.5 Layer 4: describe on demand at search time

When a search comes back weak, take the top 30 CLIP candidates that have no description, describe them right then (a few seconds, shown as "Looking closer…"), and rank again.

This aims the expensive model at exactly the photos the user is trying to find, so a fresh install with nothing described yet still gets good results.

### 3.6 Layer 5: better ranking

1. **Index layout:**
   - Split `asset_fts` into weighted columns: caption, keywords, tags, OCR, labels, place.
   - Add a second FTS5 table with the `unicode61` tokenizer and Porter stemming ("dogs" finds "dog").
   - Run Chinese text through `NLTokenizer` first, so words are separated by spaces.
   - Keep the trigram table for substrings and short-word fallback.
2. **Typo tolerance:** if a query word isn't in the index vocabulary, swap in the closest vocabulary word within edit distance 1–2 ("recipt" → "receipt").
3. **Query expansion with no LLM needed:** embed the query with the CLIP text encoder, find the nearest concepts in the Layer 1 vocabulary, and add them as optional terms ("coffee" also matches "latte", "espresso").
4. **Three ranked lists fused with weighted RRF:**
   - BM25 over the text columns;
   - CLIP image similarity;
   - similarity between the query and the caption text, using Apple's built-in `NLContextualEmbedding`: free and multilingual.

## 4. Expected cost and speed

| Layer | Time per photo | Money | Coverage |
|---|---|---|---|
| 0 (today) | about 0.3 s | $0 | 100% |
| 1 CLIP tags | under 1 ms | $0 | 100%, back-filled at once |
| 2 on device | about 2–4 s (estimate, to be measured on day 2) | $0 | 40–60% of photos after the skips; the rest are covered by copies or OCR |
| 3 cloud | 0 s on the phone, hours of batch wait | about $0.35 per 10k | opt-in |
| 4 on demand | about 3–6 s per weak search | $0 | the photos being searched for |

For 10,000 photos with half needing Layer 2, at 3 s each, that's about 4 hours, or **one night on the charger**.

## 5. How we'll know it works (the proposal's E1)

- Build a **test set of 60 queries** over a fixed library of about 1,000 photos: 20 object or scene queries, 15 detail and relation queries, 15 Chinese queries and 10 typo queries. Each query gets its correct photos marked by hand.
- **Measures:**
  - Recall@10 and MRR;
  - seconds per photo;
  - battery percentage used per 1,000 photos;
  - model download size.
- **Compare five setups:**
  1. today's search;
  2. plus CLIP tags;
  3. plus the new ranking;
  4. plus on-device captions;
  5. plus on-demand describing.
- A debug screen (`Phophy/Debug`) runs the whole set in one tap and prints the table.
- **Target:** Recall@10 rises from today's number by at least 20 points on detail and relation queries, with no loss on the others.

## 6. Schedule (20–30 Nov)

| Day | Date | Work | Done when |
|---|---|---|---|
| 1 | Thu 20 | Test set: 60 queries, labelled photos, debug runner. Record today's numbers. | Baseline table exists |
| 2 | Fri 21 | Spike: run SmolVLM2-500M and FastVLM-0.5B on the iPhone 13 Pro Max, and Foundation Models image input in the simulator. Time each and compare captions on 30 photos. **Pick the fallback model.** | Choice written down with numbers |
| 3 | Sat 22 | Layer 1: concept vocabulary (EN and ZH), shipped text embeddings, tag back-fill, new `tags` column. | Back-fill under 10 s; E1 re-run |
| 4 | Sun 23 | Layer 5, part 1: new FTS tables, column weights, Chinese segmentation, migration. | Chinese and stemmed queries pass |
| 5 | Mon 24 | Layer 5, part 2: typo correction, CLIP query expansion, three-way RRF. | E1 re-run |
| 6 | Tue 25 | Layer 2, part 1: `Describer` protocol; Foundation Models describer (iOS 27, Apple Intelligence check); description table; skip rules (near-duplicates, text-heavy photos). | Simulator describes photos |
| 7 | Wed 26 | Layer 2, part 2: fallback MLX describer, the download in Settings, priority queue. | Phone describes photos |
| 8 | Thu 27 | Layer 2, part 3: background task on the charger, progress in Settings and Search, throttle hooks. Overnight run on the phone. | One night of describing done |
| 9 | Fri 28 | Layer 4: describe on demand for weak searches. Assistant tools read the descriptions. | Weak queries improve |
| 10 | Sat 29 | Full E1 run on all five setups, battery and speed measurements, tuning thresholds and weights. | Results table for the report |
| 11 | Sun 30 | Buffer, bug fixes, report section and demo. | Submit |

Layer 3 (cloud) is left out of the schedule. If you want it, it fits into day 9 at about half a day.

## 7. Decisions (20 Nov)

1. **Cloud describing is in**, as an option the user picks: Google Gemini or OpenAI, with their own key. Before the first upload the app shows a plain warning that photos are sent to that company and there's no privacy guarantee once they leave the iPhone, and shows the estimated cost.
2. **Fallback model:** SmolVLM2 500M (Apache-2.0), an optional download of about 1 GB. FastVLM stays selectable but isn't the default: its licence is research-only, and its Python tooling needs PyTorch, so it couldn't be benchmarked the same way.
3. **The app stays on iOS 26;** describing on the iPhone needs iOS 27 and is behind `if #available(iOS 27.0, *)`.

## Sources

- [What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/) · [Foundation Models image input in iOS 27](https://blakecrosley.com/blog/foundation-models-image-input-ios-27) · [Apple Intelligence devices](https://support.apple.com/en-en/121115)
- [apple/ml-fastvlm](https://github.com/apple/ml-fastvlm) · [FastVLM paper](https://arxiv.org/html/2412.13303v2)
- [SmolVLM2 blog](https://huggingface.co/blog/smolvlm2) · [SmolVLM paper](https://arxiv.org/html/2504.05299v1)
- [Florence-2 base Core ML](https://huggingface.co/mlboydaisuke/Florence-2-base-CoreML) · [Qwen3-VL 2B Core AI](https://huggingface.co/mlboydaisuke/Qwen3-VL-2B-CoreAI)
- [Recognize Anything (RAM++)](https://github.com/xinyu1205/recognize-anything)
- [Google Cloud generative AI pricing](https://cloud.google.com/gemini-enterprise-agent-platform/generative-ai/pricing) · [GPT-5 nano image-token reports](https://community.openai.com/t/responses-api-gpt-5-nano-ignores-the-detail-parameter-on-image-inputs/1371216)
- [Slide retrieval: multimodal vs caption vs hybrid](https://arxiv.org/pdf/2509.15211) · [Sage image search](https://sagecontinuum.org/labs/image-search)
- [SQLite FTS5](https://sqlite.org/fts5.html) · [FTS5 and Chinese](https://dev.to/foxck016077/sqlite-fts5-wont-tokenize-chinese-heres-the-7-line-bigram-fix-that-did-4fcc) · [FTS5 typo tolerance](https://dev.to/ahmet_gedik778845/how-i-added-typo-tolerant-video-title-search-with-opensearch-and-cjk-3e5d)

## Status (20 Nov)

Days 1–9 are built; day 10's test run and tuning are done in the simulator. Not yet tested: the iPhone (it wasn't connected) and cloud describing (needs a Gemini or OpenAI key in Settings).

### Results

Flickr30k 1K test split, 1,006 photos in an iOS 27 simulator, every photo described by Apple's built-in model. `Eval/results-final-apple.json` has every number.

| Search | Measure | Before | No descriptions | With descriptions |
|---|---|---|---|---|
| Objects and scenes ("dog", "wedding") | P@10 | 0.46 | 0.55 | **0.60** |
| | R@50 | 0.51 | 0.84 | **0.89** |
| … in Chinese ("狗", "婚礼") | P@10 | 0.02 | 0.47 | **0.51** |
| … with typos ("bicyle") | P@10 | 0.13 | 0.52 | **0.59** |
| Detailed descriptions | R@1 | 0.76 | 0.57 | **0.76** |
| | R@10 | 0.96 | 0.95 | **0.975** |
| … in Chinese | R@1 | 0 | 0.37 | **0.43** |

Searches take 10–30 ms on the Mac simulator; the iPhone is still to be timed.

- **What fixed long sentences:** counting how far ahead each visual match is, not only its place in the list (for searches of four words or more). With place only, keyword matches on common words ("man", "shirt") outvoted a clear visual winner and the right photo came first only 0.69 of the time. Short searches do slightly better without it, so it's off for them.
- **Tried and dropped:** letting keywords only reorder the visual model's top 100 for long searches. No gain.
- **SmolVLM2 500M vs Apple:** SmolVLM2's one-line captions (no keyword list) did almost the same: P@10 0.60, Chinese 0.48–0.50, detailed R@1 0.765. So phones without Apple Intelligence lose little with the downloaded model.

### Describing speed

| Describer | Where measured | Per photo |
|---|---|---|
| Apple's built-in model | Mac simulator | 3.7–5 s warm, 17–19 s for the first few |
| SmolVLM2 500M | M5 Mac, MLX | 0.93 s median |
| SmolVLM2 500M | **iPhone 13 Pro Max (A15), iOS 27.0.1** | **1.2–1.5 s** (first photo 6.5 s while the model warms up) |
| Gemini / OpenAI | not run yet | — |

On the iPhone 13 Pro Max (20 Nov, `-PhophyPhoneBench`, 16,080 photos, 3,487 indexed at the time):

- **Search:** 13–22 ms per query, English, Chinese, typo and long sentence alike.
- **Model download:** about 1 GB, downloaded and loaded in 62 s on Wi-Fi.
- **Memory:** 1.2 GB while the model is loaded (49 MB without it).
- **Describing:** 12 photos in 29 s. Battery didn't move (75% → 75%), but the phone reported "serious" heat; indexing was running at the same time. The real queue pauses at "serious" heat; the test bypassed that.
- **Quality:** good on real scenes ("A person is cooking a dish in a pot on a stove"), poor on screenshots: SmolVLM2 tends to invent "a person holding a smartphone". Screenshots are already searchable by their text, so they should be skipped.

### Still to do

- Check battery and heat over a full night of describing on the iPhone. (Apple's model can't be timed on this phone: it has no Apple Intelligence.)
- Test cloud describing with a real key.
- In Xcode, approve the MLX and Hugging Face package macros ("Trust & Enable") on the first build.
