# E4: sentence vectors of the text in photos

Search today finds text in photos with keywords: BM25 over the OCR text,
plus trigram matching. That fails when the search uses other words than
the photo, for example "notes about TCP handshakes" against a slide titled
"The Three-Way Handshake". E4 asks whether adding sentence vectors of the
OCR text, matched against a vector of the search, finds those photos.

## Test set

- **Photos:** `e4_build_text_photos.py` draws 100 text-heavy photos with known content. Everything is synthetic, so no one's real photos are used.

  | Kind | Count | What |
  |---|---|---|
  | Lecture slides | 72 | Photographed in a lecture hall: 10 English NLP lectures (tokenisation to prompting) and 2 Chinese ones (operating systems, information retrieval) |
  | Documents | 12 | |
  | Screenshots | 10 | |
  | Receipts | 6 | |

  They are mixed with the 1,006 Flickr30k test photos as everyday distractors. 55 of those also carry some text (signs, shirts).
- **Queries:** `e4_queries.json` has 50 searches: 35 English and 15 Chinese. Each is worded differently from its photo ("fill in the blank pretraining objective" → *Masked Language Modelling*; 程序互相等待对方释放资源卡住了 → 死锁的四个必要条件). Each lists every photo that answers it, and a query counts as found when any of them is ranked. Chinese queries also carry an on-device translation, `q_en` (from `e4_translate.swift`; E3 showed translation works best).
- **Scores:**
  - R@k: share of queries whose photo is in the top k;
  - MRR: mean of 1 / rank of the first right photo.

## Method

- **Vectors:** Apple's `NLContextualEmbedding`, with the token vectors averaged and normalised.
  - Latin-script text and queries go into the English model.
  - Mostly-Chinese text (more than 20% CJK) goes into the Chinese model.

  The two models are separate spaces. An English query is compared with English text. A Chinese query is compared with Chinese text as typed, and with English text through its translation.
- **Fusion:** the vector rankings are merged with the app's own search ranking by weighted reciprocal rank fusion, with k = 60, the same as `SearchEngine`.
- **No index change:** for the experiment, vectors are computed when the evaluation runs. A shipped version would compute them once, when indexing.

**The simulator can't load these models** ("Embedding model requires compilation"; real iPhones and Macs can). `run_e4.sh` therefore works in three steps:
1. The app exports each photo's text (`e4-ocr.json`).
2. `e4_embed.swift` computes the vector rankings on the Mac, with the same model, pooling and script rule.
3. The app runs again and fuses them with its live search.

Two complete runs gave identical numbers.

## Results (27 Nov 2026)

iPhone simulator, iOS 27.2; 1,106 photos; MobileCLIP S0; no photo descriptions. Vectors were computed on macOS 26.6. Raw numbers and the missed queries are in `results-e4.json`.

| Condition | R@1 | R@5 | R@10 | MRR | Chinese MRR |
|---|---|---|---|---|---|
| 1. App search today | 0.200 | 0.420 | 0.500 | 0.306 | 0.208 |
| 2. App + query translation | 0.220 | 0.420 | 0.460 | 0.321 | 0.255 |
| 3. Text vectors only | 0.200 | 0.480 | 0.740 | 0.346 | 0.465 |
| 4. App + text vectors | 0.300 | 0.520 | 0.640 | 0.406 | 0.422 |
| 5. App + translation + text vectors | 0.260 | 0.520 | 0.640 | 0.383 | 0.346 |
| 6. App + text vectors, translation for vectors only | 0.280 | 0.560 | 0.700 | 0.415 | 0.452 |
| **7. Same as 6, vectors weighted 2** | **0.300** | **0.580** | **0.740** | **0.421** | **0.519** |
| 8. Same as 6, vectors weighted 3 | 0.300 | 0.560 | 0.720 | 0.426 | 0.519 |

### What this shows

- **Text vectors find what keywords miss.** Search today misses 25 of the 50 queries in its top 10; condition 7 misses 13. Gains with condition 7:

  | Metric | Today | Condition 7 |
  |---|---|---|
  | R@5 | 0.42 | 0.58 |
  | R@10 | 0.50 | 0.74 |
  | MRR | 0.306 | 0.421 |
  | Chinese MRR | 0.208 | 0.519 |

- **Keywords and vectors fail on different queries, so fusing them helps.**
  - Vectors alone miss searches that share an exact word with the photo ("fine for returning library books late", "how to quit my gym contract early"), which keywords find.
  - Keywords miss the paraphrases ("predicting the neighbours of a word from the word itself" → skip-gram).
  - Fused, both kinds are found.
- **Translate for the vectors, not for the keywords.** Translating the whole Chinese query (conditions 2 and 5) loses keyword matches on the Chinese slides, so condition 5 is worse than condition 4. Keeping the Chinese for the app's own search and feeding the translation only to the English vectors (condition 6) is better on both.
- **Weight 2 is the best balance.** Raising the vector weight above 1 helps, mostly for Chinese: R@1 0.267 → 0.467. Weight 3 adds nothing more.
- **Still missed by condition 7:**
  - abstract paraphrases with little word or topic overlap ("fill in the blank pretraining objective", "cheap fine-tuning that trains only a tiny add-on", 模型一本正经地胡说八道);
  - short receipts whose text is mostly item names and prices ("how much was the flu medicine" → "Cold & flu tablets").

### Limits

- 50 queries is small, and the fusion weight was chosen on the same queries. Re-check weight 2 on a separate set before trusting the exact numbers.
- The photos and queries were made by one person. A query set written by the other team members would be fairer.
- The vectors came from macOS 26.6. The iPhone has the same framework, but its model version may differ.
- Only 155 of the 1,106 photos have text, so the Flickr30k distractors make the task easier than a real library full of screenshots.

## Next

- Agree with the lead and Track A on storing one vector per text-heavy photo (512 floats, for photos with at least 20 recognised characters) at indexing time.
- Then add the vector list to `SearchEngine.rank` with weight 2, translating Chinese searches for the vector side only.
- Check the vectors load and run fast enough on a real iPhone (iPhone 13 Pro Max).
- Write a second, held-out query set with the team.
