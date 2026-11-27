# Progress log and handover: Track B (search and assistant)

Last updated: **27 Nov 2026**

Track B covers search quality, the search evaluation set, Chinese queries,
the assistant's tools and backends, and cloud cost. Its experiments in the
proposal are **E1, E3, E4, E7, E11**. Code owned: `Phophy/Assistant/`,
`Phophy/Index/SearchEngine.swift`, `Eval/`.

## Handover: where things stand

### Pull requests

| PR | Branch → base | Contents | State |
|---|---|---|---|
| [Jasonsu22/Phophy#2](https://github.com/Jasonsu22/Phophy/pull/2) | `b-e11-e7-assistant-eval` → `photo-descriptions` | E11 cost per answer, E7 task evaluation, this log | Waiting for the lead's review |
| [Jasonsu22/Phophy#3](https://github.com/Jasonsu22/Phophy/pull/3) | `b-e3-chinese-queries` → `b-e11-e7-assistant-eval` | E3 Chinese-query experiment and results | Stacked on #2: merge #2 first, then retarget this PR to `photo-descriptions` |
| [Jasonsu22/Phophy#4](https://github.com/Jasonsu22/Phophy/pull/4) | `b-e4-ocr-text-vectors` → `b-e3-chinese-queries` | E4 OCR text vectors experiment and results | Stacked on #3: merge #2, then #3, then this one |

### Waiting on others

- **Lead:**
  - Review and merge #2, then the E3 PR.
  - Run the **Apple Intelligence** group of E7 on a macOS 27 Mac: `Eval/run_agent_eval.sh <sim> apple`. This Mac (macOS 26.6) can't load the simulator's on-device model; see Environment.
- **Track B:** a Claude API key (console.anthropic.com; a Claude subscription doesn't include API credit). It unblocks:
  - E7 and E11 on Claude Haiku 5.5;
  - E3 condition b2 (`Eval/e3_claude_rewrite.py`).

  An OpenAI key would add the GPT-5 mini group.

### How to pick this up on another Mac

1. Clone the repository and check out `b-e4-ocr-text-vectors`, which contains everything above.
2. Download the MobileCLIP S0 models (PLAN.md, "MobileCLIP models").
3. Download the Flickr30k 1K test split into a folder outside git: `test_1k_flickr.csv` and `images_flickr_1k_test.zip` from Hugging Face, `nlphuji/flickr_1k_test_image_text_retrieval`.
4. Build the demo library: `python3 Demo/build_library.py CAPTIONS.tsv IMAGES_DIR OUT_DIR`. CAPTIONS.tsv has one line per photo, `filename|caption`, made from the CSV's `raw` column.
5. Create two simulators, both iOS 27.2, set to **English with the Hong Kong region**:
   - `simctl spawn <sim> defaults write -g AppleLanguages -array en`
   - `simctl spawn <sim> defaults write -g AppleLocale en_HK`
   - then reboot the simulator.

   | Simulator | Holds | Used for |
   |---|---|---|
   | "Phophy Eval" | the demo library | E7 / E11 |
   | "Phophy Flickr" | the 1,000 Flickr30k photos | E1 / E3 |
   | "Phophy Text" | a clone of "Phophy Flickr" plus the 100 E4 text photos (`python3 Eval/e4_build_text_photos.py OUT_DIR`) | E4 |

6. Build the Debug app:
   `xcodebuild build -project Phophy.xcodeproj -scheme Phophy -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO`
7. Run the experiments:
   - `Eval/run_agent_eval.sh <sim> anthropic|openai|apple` for E7 and E11;
   - `Eval/run_e3.sh <sim>` for E3;
   - `Eval/run_e4.sh <sim>` for E4 (it also computes the text vectors on the Mac, since the simulator can't load Apple's embedding models);
   - `Eval/run_eval.sh <sim>` for E1.

## Deadlines

| Date (HKT) | What | Track B input |
|---|---|---|
| 28 Nov | Results handed to whoever edits the video | E3 table (ready), E7/E11 numbers (need a key), one search before/after slide |
| **29 Nov 23:59** | 5-minute pre-recorded video (we present **online**) | Scenes 9–11 (assistant) and 14 (search results) |
| **15 Dec 23:59** | Final report | Methods and results sections for E1, E3, E4, E7, E11 |

## Status

| Item | Status | Where |
|---|---|---|
| E1 hybrid vs keyword vs CLIP search | ✅ Done by the lead on Flickr30k (1K test split) | `Eval/README.md`, `Eval/results-*.json` |
| E3 Chinese queries | ✅ First round done: on-device translation is best (full sentences R@5 0.600 → 0.867, equal to human English). Open: the Claude condition (needs a key) and translation + dictionary combined | `Eval/E3_CHINESE.md`, `Eval/results-e3.json`, `Phophy/Debug/ChineseQueryEvaluation.swift` |
| E11 cloud cost logging | 🟡 Code done (PR #2); no numbers until a key is set | `Phophy/Assistant/UsageMeter.swift` |
| E7 assistant tasks per backend | 🟡 Tools done (PR #2). Apple Intelligence: lead to run. Cloud: needs a key | `Eval/AGENT_EVAL.md`, `Phophy/Debug/AgentEvaluation.swift` |
| E4 OCR text embeddings | ✅ First round done: fusing text vectors with search lifts R@10 0.50 → 0.74 and MRR 0.306 → 0.421 (Chinese MRR 0.208 → 0.519). Next: agree an index column with the lead and Track A, then ship | `Eval/E4_OCR_EMBEDDINGS.md`, `Eval/results-e4.json`, `Phophy/Debug/OCRTextEvaluation.swift` |
| Bugs #7, #8, #9, #13 (TEAM_PLAN.md) | ⏳ Not started (#8 is what E3 measures) | |

### E4 readiness (assessed 27 Nov; done 27 Nov, see Results)

- **Flickr30k is no use for E4.** Only 55 of its photos have 20 or more characters of text, mostly signs and T-shirts.
- **The demo library has usable data.** It has 39 photos with text, 26 of them text-heavy: 18 lecture slides (networks, machine learning, and a database course in Chinese), 4 receipts, 3 documents, 6 screenshots and a whiteboard. OCR quality is good. The data is synthetic, so nobody's real photos are needed.
- **Missing pieces:**
  1. About 100 more generated text photos (slides, documents, screenshots), so that finding the right one is hard.
  2. 30–50 hand-checked paraphrase queries in English and Chinese, each with its right photo, e.g. "notes about TCP handshakes" → the "Three-Way Handshake" slide. Qin drafts them; the team checks them.
- **Plan:** for the experiment, embed the OCR text inside the evaluation runner, which needs no index change. Agree an index column with the lead and Track A only if E4 helps.
- **Model caveat:** Apple's `NLContextualEmbedding` has separate Latin-script and Chinese-script models, so a Chinese question can't be compared with English slide text directly. Either translate the query first (E3 shows that works) or convert a multilingual sentence model.

## Environment

- [x] Repository cloned to `~/NLP/Phophy`; commits use the GitHub noreply address
- [x] Write access to `Jasonsu22/Phophy` confirmed
- [x] MobileCLIP S0 image and text models downloaded into `Phophy/CLIP/Models/` (ignored by git)
- [x] Xcode 27.2 installed; licence accepted; first-launch components; Metal Toolchain; Swift packages resolved
- [x] Debug build for the iOS Simulator succeeds, with no warnings in the new code
- [x] Flickr30k 1K test photos in `~/NLP/data/flickr1k`; demo library in `~/NLP/data/demo-library` (158 files); both outside git
- [x] "Phophy Eval" simulator (iPhone Duo, iOS 27.2, English): demo library indexed, 162 photos
- [x] "Phophy Flickr" simulator (iPhone Duo, iOS 27.2, English): Flickr30k indexed, 1,006 photos
- [x] "Phophy Text" simulator: a clone of "Phophy Flickr" plus 100 E4 text photos (1,106 photos), indexed
- [ ] Apple's `NLContextualEmbedding` in the simulator: fails with "Embedding model requires compilation". Works on the Mac, so `run_e4.sh` computes the E4 vectors there.
- [ ] iPhone 18 Pro Max simulator (the lead's demo device). The general iOS 27.2 runtime (24B8117) was mounted twice when two downloads ran at once and shows as malformed; restarting the simulator service didn't help, so a Mac restart should. Only the iPhone Duo runtime (24B91016s) works for now. This doesn't change E1/E3/E4/E7/E11 numbers; it matters only for video footage.
- [ ] Apple Intelligence in the simulator: **blocked on this Mac.** Apple Intelligence is on, but every request fails with `Model Catalog error (UnifiedAssetFramework 5000, no underlying assets)`, in a Chinese and in an English simulator. Likely cause: the Mac runs macOS 26.6, while the iOS 27.2 simulator's Foundation Models need the macOS 27 model assets (the lead's Mac and CI run macOS 27). The same Apple frameworks do work on the Mac itself, which is how E3's conditions b and c were produced.
- [ ] API keys for Claude and OpenAI saved in the simulator's Settings (never in git)

## Work log

### 27 Nov 2026

- Checked the state of the repository. Every commit so far is by the lead.
  The newest work is on `photo-descriptions` (11 commits ahead of `main`,
  including the search changes), so Track B branches from there.
- **E11** (branch `b-e11-e7-assistant-eval`):
  - `TokenUsage` reads the `usage` block of Anthropic and OpenAI-compatible responses.
  - `UsageTally` adds up all the rounds of one answer.
  - `ModelPrice` prices them: Claude Haiku 5.5 at $0.10/$0.50 and GPT-5 mini at $0.25/$2.00 per million input/output tokens.
  - Each cloud answer shows a last step such as "Cloud: 3,120 tokens in, 85 out · about $0.0004".
  - Debug builds log token counts per request to `usage-log.jsonl`; lecture digests are logged too.
  - A small macOS test program confirmed the parsing and the price maths ($0.000695 for a Haiku + GPT-5 mini mix, as by hand).
- **E7:**
  - 20 tasks on the demo library: 14 English, 6 Chinese; read, find, library and organise types.
  - The `-PhophyAgentEval` runner checks the reply, the photos shown and any album offered, and records tool calls, time and cost.
  - `PhotoToolbox` logs the tools called in each turn.
  - `agent_report.py` prints the E7 and E11 tables.
- Touched one lead-owned file: `RootView.swift`, Debug-only lines that start the runners. This is flagged in the PRs.
- Two E7 runs on Apple Intelligence both failed on the model error above (0/20 each) and were discarded.
- The simulator was in Chinese, so Apple Maps returned Chinese place names (香港大學) and "Where did I go skiing?" could never match "Zermatt". Switched the simulators to English with the Hong Kong region, as on the lead's, and rebuilt the index. **Run the experiments in an English simulator.**
- Added Hong Kong time and a 30-minute timeout to `Eval/run_agent_eval.sh`.
- Opened [Jasonsu22/Phophy#2](https://github.com/Jasonsu22/Phophy/pull/2).

### 27 Nov 2026 (night): E3

- Built `Eval/e3_queries.json`: the 44 Chinese concepts and 30 Chinese sentences from `eval.json`, each with its human English (the upper bound).
- Produced machine English on the Mac with Apple's on-device frameworks (`Eval/e3_translate.swift`):
  - Translation (zh-Hans → en);
  - a Foundation Models rewrite using the assistant's instruction. The rewrite needed the content-transformation guardrails; with the defaults, one query was refused.
- Added `SearchOptions.chineseConcepts` (to measure "no handling") and the `-PhophyE3` runner (`Phophy/Debug/ChineseQueryEvaluation.swift`, `Eval/run_e3.sh`).
- Indexed the 1,006 Flickr30k test photos on "Phophy Flickr" (English, no descriptions) and ran E3. Results are below and in `Eval/E3_CHINESE.md`.
- Committed on `b-e3-chinese-queries`; opened [Jasonsu22/Phophy#3](https://github.com/Jasonsu22/Phophy/pull/3), stacked on #2.

### 27 Nov 2026 (late night): E4

- Generated 100 text photos with known content (`Eval/e4_build_text_photos.py`): 72 slides from 10 English NLP lectures and 2 Chinese ones, 12 documents, 10 screenshots and 6 receipts. Wrote 50 paraphrase queries (35 English, 15 Chinese) and translated the Chinese ones on the Mac.
- Probed Apple's text vectors on the Mac:
  - `NLEmbedding.sentenceEmbedding` ranked the wrong document first;
  - `NLContextualEmbedding` with mean pooling ranked correctly, so E4 uses it.
- `-PhophyE4` runner (`Phophy/Debug/OCRTextEvaluation.swift`), with a Mac fallback (`Eval/e4_embed.swift`), since the simulator can't load the embedding models. `Eval/run_e4.sh` does all of it.
- Results: in the table below and in `Eval/E4_OCR_EMBEDDINGS.md`. Two full runs gave identical numbers once ties were broken by photo ID.
- Opened [Jasonsu22/Phophy#4](https://github.com/Jasonsu22/Phophy/pull/4), stacked on #3.

## Next steps

1. Get a Claude API key. Then run E7 and E11 on Claude Haiku 5.5, and E3 condition b2.
2. E3 follow-up: try translation for the visual model together with the Chinese words and dictionary for keywords. If it holds, ship on-device translation for Chinese searches in `SearchEngine`, falling back to the dictionary when the languages aren't installed.
3. E4 follow-up: agree an index column for text vectors with the lead and Track A; check the vectors on a real iPhone; ask the team for a held-out query set before fixing the weight at 2.
4. Bug #13 (cap the chat history file).
5. Report sections: methods for E3, E7 and E11 can be written now.

## Results

### E3: Chinese searches (27 Nov, Flickr30k 1K, MobileCLIP S0, no descriptions)

| Condition | Sentences R@5 | Sentences MRR | Concepts P@10 | Concepts MRR |
|---|---|---|---|---|
| a. Chinese as typed | 0.000 | 0.013 | 0.370 | 0.656 |
| a+. Concept dictionary (app today) | 0.600 | 0.540 | 0.457 | 0.815 |
| b. Apple on-device model rewrite | 0.800 | 0.754 | 0.473 | 0.775 |
| **c. Apple on-device translation** | **0.867** | **0.785** | **0.495** | **0.871** |
| Upper bound: human English | 0.867 | 0.849 | 0.545 | 0.951 |

### E4: text vectors (27 Nov, 1,106 photos, 50 paraphrase queries)

| Condition | R@5 | R@10 | MRR | Chinese MRR |
|---|---|---|---|---|
| App search today | 0.420 | 0.500 | 0.306 | 0.208 |
| Text vectors only | 0.480 | 0.740 | 0.346 | 0.465 |
| App + text vectors | 0.520 | 0.640 | 0.406 | 0.422 |
| **App + text vectors ×2, translation for vectors only** | **0.580** | **0.740** | **0.421** | **0.519** |

### E7: assistant tasks

| Backend | Success | Tool calls / task | Seconds / task | Cost / task |
|---|---|---|---|---|
| Apple Intelligence | (lead to run on macOS 27) | | | free |
| Claude Haiku 5.5 | (needs a key) | | | |
| GPT-5 mini | (needs a key) | | | |

### E11: cloud cost

| What | Model | Cost / answer | Target |
|---|---|---|---|
| Assistant answer | Claude Haiku 5.5 | | < $0.01 |
| Assistant answer | GPT-5 mini | | < $0.01 |
| Lecture summary | | | < $0.01 |
