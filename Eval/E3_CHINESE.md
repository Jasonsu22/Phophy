# E3: Chinese searches

MobileCLIP's text encoder only reads English, so a Chinese search can't be
matched to how a photo looks unless something turns it into English first.
E3 compares the options on the Flickr30k 1K test photos, using the two
Chinese sets from `eval.json`:

- **Objects and scenes, Chinese:** 44 short concepts (狗, 自行车, 攀岩). Scored with P@10, R@50 and MRR.
- **Detailed descriptions, Chinese:** 30 full sentences translated by hand from a Flickr30k caption, each with one right photo. Scored with R@1, R@5, R@10 and MRR.

## Conditions

| | What the search gets | How |
|---|---|---|
| a | The Chinese as typed | `SearchOptions.chineseConcepts = false`: the raw Chinese goes to the visual model. Keyword search still matches the index's bilingual concept tags ("playground / 操场"), so short concepts are not at zero |
| a+ | The Chinese, read through the concept dictionary | What the app does today (`ConceptTagger.englishConcepts`) |
| b | An English rewrite by Apple's on-device model | Same instruction the assistant gets for `find_photos`; Foundation Models with the content-transformation guardrails |
| b2 | An English rewrite by Claude Haiku 5.5 | Same instruction; `Eval/e3_claude_rewrite.py` (needs an API key) |
| c | A translation on the device | Apple's Translation framework, zh-Hans → en |
| upper bound | The human English | The concept's English name, or the caption the sentence was translated from |

Conditions b and c run Apple's on-device models on the Mac (macOS 26)
rather than in the simulator, whose Apple Intelligence doesn't load on a
macOS 26 host. They are the same frameworks the iPhone has, though not
necessarily the same model version as iOS 27. When a condition has no
English for a query (a refusal, say), that query is searched in Chinese
and counted as such.

## Running it

1. `python3 Eval/e3_prepare.py path/to/test_1k_flickr.csv` builds `e3_queries.json` with the human English.
2. Compile and run the Mac script that adds conditions b and c: `swiftc -parse-as-library Eval/e3_translate.swift -o /tmp/e3_translate && /tmp/e3_translate`. Optionally, run `Eval/e3_claude_rewrite.py` for b2.
3. Put the 1,000 Flickr30k test photos in an English simulator (`xcrun simctl addmedia`) and build a Debug app.
4. Run `Eval/run_e3.sh <sim-udid>`. The app indexes the photos, searches every query under each condition with the app's own ranking, prints lines starting with `E3`, and saves `Eval/results-e3.json`.

Run with `-describer off`, so no photo descriptions are used (Apple
Intelligence isn't available in this simulator). The numbers are therefore
lower than the lead's runs that used descriptions
(`results-final-apple.json`). Compare conditions within one run, not
across runs.

## Results (27 Nov 2026)

iPhone simulator, iOS 27.2, 1,006 photos, MobileCLIP S0, no photo
descriptions. Raw numbers are in `results-e3.json`. No query fell back to
Chinese in any condition.

**Full sentences** (30, one right photo each):

| Condition | R@1 | R@5 | R@10 | MRR |
|---|---|---|---|---|
| a. Chinese as typed | 0.000 | 0.000 | 0.000 | 0.013 |
| a+. Concept dictionary (app today) | 0.467 | 0.600 | 0.667 | 0.540 |
| b. Apple on-device model rewrite | 0.700 | 0.800 | 0.900 | 0.754 |
| **c. Apple Translation** | **0.733** | **0.867** | **0.900** | **0.785** |
| Upper bound: human English | 0.800 | 0.867 | 0.967 | 0.849 |

**Short concepts** (44):

| Condition | P@10 | R@50 | MRR |
|---|---|---|---|
| a. Chinese as typed | 0.370 | 0.489 | 0.656 |
| a+. Concept dictionary (app today) | 0.457 | 0.718 | 0.815 |
| b. Apple on-device model rewrite | 0.473 | 0.769 | 0.775 |
| **c. Apple Translation** | **0.495** | **0.781** | **0.871** |
| Upper bound: human English | 0.545 | 0.839 | 0.951 |

### What this shows

- **On-device translation wins on both sets.** For full sentences it lifts R@5 from 0.600 to 0.867, which equals the human-English upper bound. MRR rises from 0.540 to 0.785. For short concepts, MRR rises from 0.815 to 0.871. It is free, private and runs on the phone.
- **The dictionary only knows concepts.** For short words it holds up (P@10 0.457), but a sentence keeps only the few words it knows, so "a man with red hair and dreadlocks playing an acoustic guitar" loses most of its detail.
- **Rewriting with Apple's small on-device model is unreliable.**
  - It helps sentences (R@5 0.800), but often fails on single words: it echoes the Chinese back (棒球 → 棒球) or invents a whole scene (船 → "A traditional Japanese boat... light blue hull").
  - That's why its short-concept MRR (0.775) falls below the dictionary's.
  - It's also slower than translation and needs an Apple Intelligence phone.
- **Translation mistakes remain.** 打鼓 → "feel uncertain", 长椅 → "settee", 涂鸦 → "scrawl", 木吉他 → "ukulele". The concept dictionary has the right English for these words, so the next step is to try translation and the dictionary together.

### Next

- Try **c + a+**: translate the query for the visual model, and keep the Chinese words and dictionary concepts for keyword search.
- If it holds, make it the app's default for Chinese searches, falling back to the dictionary when the Translation languages aren't installed.
- Run b2 (Claude) once a key is available.
