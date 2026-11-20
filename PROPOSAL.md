# Project Proposal: Phophy

**An on-device AI assistant for your photo library: search by description, automatic organisation, study notes from lecture slides, and AI photo editing.**

---

## 1. Team members

**Team ID: 26**

| Name | Student ID |
|---|---|
| Wang Zhengyao | 3036795675 |
| Yin Fengling | 3036807375 |
| Qin Mengmeng | 3036843769 |
| Su Chuanzhou | 3036837980 |

---

## 2. Project goal

### The problem

A typical phone holds thousands to tens of thousands of photos, and they are hard to use:

- **Finding a photo is slow.** Built-in search works mostly by date, place and a fixed set of labels. A question such as "the whiteboard with the network diagram", "the receipt from Muji" or "the slide about the TCP handshake" usually ends in minutes of scrolling.
- **The library is unorganised.** Screenshots, documents, receipts, slides and near-identical burst shots are mixed in with personal photos, and cleaning them up by hand is tedious.
- **Students photograph lecture slides but rarely use them again.** The slides sit in the camera roll as images, with no text, no grouping by lecture and no notes.
- **Sending everything to a cloud AI is the wrong answer.** It is slow, it costs money for every photo, and it uploads private pictures.

### Objectives

Build an iOS app, **Phophy**, that:

1. **Indexes the whole photo library on the phone.** For each photo it records the text in the image, scene labels and a semantic embedding, with no photo leaving the device.
2. **Finds photos from a natural-language description.** Search combines text in the photo, labels, date, place and visual similarity, in English and Chinese.
3. **Organises the library automatically.** It sorts photos into categories (slides, documents, receipts, food, people, pets, scenery, screenshots) and finds near-duplicate shots, suggesting which one to keep.
4. **Answers questions through an AI assistant.** The assistant uses tools over the local index, for example "find my photos from the Kyoto trip with the red gate and put them in an album". It runs on Apple Intelligence where available, or on a cloud model the user chooses (Claude, OpenAI or any OpenAI-compatible service).
5. **Turns lecture-slide photos into study material.** Slides are grouped by lecture and become a summary, key points and flashcards. Only the recognised text is sent to the model, never the images.
6. **Edits photos from a typed request.** Requests such as "brighter and blur the background" run on the phone for free; generative edits go to an image API only when the user asks.
7. **Stays fast and respects the phone.** Browsing must feel like Apple's Photos app on a large library, and indexing must not drain the battery or overheat the phone. The app must also work on phones without Apple Intelligence, such as the iPhone 13 Pro Max.

**Optional stretch goal: an Android version.** If time allows after the iOS objectives are met, build an Android app with the same core features (on-device indexing, search by description, categories and lecture notes), so the project is not limited to iPhone users. This is lower priority than objectives 1–7 and will not delay them.

---

## 3. Potential solutions

### 3.1 Key idea: tiered processing, with the cloud last

Most of the work does not need a paid language model. Each photo is processed once, on the phone, and the results are stored in a local database. Search then runs against the database, not against a model that charges per photo.

| Tier | What it does | Runs where | Cost |
|---|---|---|---|
| 0. Metadata | Date, location, type, favourites | PhotoKit | Free |
| 1. Classic vision | Text recognition (OCR), scene labels, subject masks | Apple Vision, on device | Free |
| 2. Embeddings | One vector per photo, so a description can find it | MobileCLIP via Core ML, on device | Free |
| 3. On-device LLM | Query understanding, notes, edit requests | Apple Foundation Models (Apple Intelligence phones) | Free |
| 4. Cloud LLM | Assistant reasoning and lecture notes on other phones | User-chosen API, only on request | Pay per use |

### 3.2 Architecture

Figure 1 shows how the parts of the app fit together:

1. **Indexing.** New and changed photos from the photo library go to a background indexer. It reads the date and place, recognises text, assigns scene labels and computes a MobileCLIP vector. It waits while the user scrolls or views a photo, and pauses when the phone is hot.
2. **Local index.** The results are stored in a SQLite database on the phone. Every feature reads from it, so photos are never analysed twice.
3. **Features.** Search, Collections, Study and the viewer and editor all work from the index and the photo library.
4. **Assistant.** The user asks a question in the ask bar. The assistant uses a language model to understand it, then calls tools (search, by date, collections, show photos, make album) that read the local index.
5. **Language model.** The model is Apple Intelligence on phones that have it. Otherwise it is a cloud model the user chooses, which receives only text.
6. **Cloud editing.** Generative photo edits go to an AI image service, and only after the user confirms.

The assistant never touches photos directly. It calls a small set of tools that read the local index, and anything that changes the library, such as creating an album, needs the user's confirmation.

![Figure 1. How Phophy works: everything inside the blue area runs on the iPhone; the cloud services on the right are optional and only used when the user asks.](docs/architecture.svg)

### 3.3 Methods per feature

- **Hybrid search.**
  - Keyword search on OCR text and labels, using an SQLite FTS5 trigram index.
  - Semantic search by cosine similarity between the MobileCLIP text embedding of the query and the image embeddings of photos.
  - The two result lists are merged with reciprocal rank fusion, and date and place filters are applied on top.
  - Brute-force similarity over 10,000 photos takes a few milliseconds, so no vector database is needed at this scale.
- **Categories.**
  - Zero-shot classification: each photo's embedding is compared with a few text prompts per category, plus an "other" class so ordinary photos stay uncategorised.
  - Slides, documents and receipts also need a minimum amount of recognised text.
- **Near-duplicates.**
  - Cosine similarity between photos taken close together in time.
  - The suggested keeper is a favourite if there is one, otherwise the largest image.
  - Deleting goes through iOS's own confirmation and into Recently Deleted.
- **Assistant.**
  - Tool calling through one `LanguageModel` interface, with interchangeable backends: Apple Foundation Models, Claude, OpenAI and custom OpenAI-compatible services.
  - The model only receives text (dates, categories, labels, recognised text), never images.
- **Lecture notes.**
  - Slide photos taken less than 30 minutes apart are grouped into one lecture.
  - The OCR text is sent to the model, which returns structured output: a title, a summary, key points with slide numbers, and flashcards.
- **Editing.**
  - Core Image handles light, colour, looks and crop; Vision's subject mask handles background replacement.
  - Typed requests are read by word rules on every phone, and by the on-device model on Apple Intelligence phones.
  - Edits are saved through Photos' editing API, so they can be reverted.
- **Performance.**
  - Lists and grids use reusable cells (UICollectionView), so cost does not grow with library size.
  - Indexing yields to the user interface: it pauses while anything scrolls or a photo is open, and when the phone is hot or in Low Power Mode.
- **Privacy and keys.**
  - Indexing and search are fully on device.
  - API keys are stored only in the iPhone's Keychain and sent only to their own provider.

### 3.4 Optional: Android version

The Android app would follow the same design, with Android counterparts for each part:

| Part | iOS (built) | Android (optional) |
|---|---|---|
| Photo access | PhotoKit | MediaStore |
| Text recognition and labels | Apple Vision | Google ML Kit (on device) |
| Embeddings | MobileCLIP via Core ML | The same MobileCLIP model, exported to ONNX Runtime or LiteRT (TensorFlow Lite) |
| Database | SQLite (GRDB) with FTS5 | SQLite (Room) with FTS |
| On-device LLM | Apple Foundation Models | Gemini Nano on supported phones; otherwise the cloud backend |
| Cloud assistant | Claude, OpenAI or OpenAI-compatible | The same APIs and the same tool definitions |
| UI | SwiftUI | Jetpack Compose |

Using the same embedding model, the same tool definitions and the same note format means the search evaluation set and the prompts can be reused, and results on both platforms can be compared directly. A cross-platform framework (Flutter or React Native) was considered. It was rejected because most of the work happens in native photo, vision and machine-learning APIs, which such frameworks would have to call through platform-specific code anyway.

### 3.5 Alternatives considered

| Option | Why not chosen (or kept only as an option) |
|---|---|
| Caption every photo with a cloud vision model | Costs money for every photo, is slow on large libraries, and uploads private photos |
| Larger CLIP models (MobileCLIP S2, B) | More accurate but larger and slower; to be compared in the experiments below |
| A vector database (sqlite-vec, IVF) | Not needed below about 100,000 photos; kept as a fallback if search exceeds 30 ms |
| A server-side app (like Immich) | Needs a server, and doesn't work offline or on the phone alone |

---

## 4. Experimental plan

All experiments run on the team's own iPhones (including an iPhone 13 Pro Max without Apple Intelligence) and on the iOS simulator. Each one is repeatable from a fixed dataset or a built-in debug test.

### 4.1 Datasets

- **Search evaluation set.**
  - About 50 real questions written by the four team members about their own libraries, each with its correct photo or photos marked.
  - The questions mix five types: place and time ("Hong Kong two years ago"), content ("the whiteboard with the network diagram"), text in the photo ("the receipt from Muji"), vague ("that sunset at the beach"), and language (English and Chinese).
- **Category labels.** About 300 photos labelled by hand into the app's categories, including "none".
- **Near-duplicate pairs.** About 100 photo pairs labelled as same shot or different.
- **Lecture slides.** Photos of at least 5 real lectures, with slide text checked by hand.
- **Edit requests.** About 30 typed requests in English and Chinese, each with its expected edits.
- **Scale test.** A generated library of 50,000 photos in the simulator.

### 4.2 Experiments and metrics

| # | Question | Method | Metrics |
|---|---|---|---|
| E1 | Does hybrid search beat simpler search? | Compare keyword only, CLIP only, and hybrid (reciprocal rank fusion), plus the iPhone's built-in Photos search as a manual baseline | Recall@5, recall@20, mean reciprocal rank |
| E2 | Which embedding model is worth its cost? | MobileCLIP S0 against S2 on the same evaluation set | Recall@5, index time per photo, model size, memory |
| E3 | How to handle Chinese queries, when MobileCLIP only understands English? | (a) no handling, (b) the assistant rewrites the query in English, (c) on-device translation before encoding | Recall@5 on the Chinese questions |
| E4 | Do OCR text embeddings help text-heavy questions? | Add a multilingual sentence embedding of the OCR text and compare | Recall@5 on text questions ("notes about TCP handshakes") |
| E5 | How good are automatic categories? | Run on the labelled set and tune the thresholds on a separate part of it | Precision, recall and F1 per category |
| E6 | Where should the duplicate threshold be? | Sweep the cosine similarity threshold from 0.85 to 0.97 | Precision–recall curve; choose the threshold with high precision, since deleting is costly |
| E7 | Can the assistant complete tasks? | 20 end-to-end tasks run on each backend (Apple Intelligence, Claude Haiku, an OpenAI model) | Task success rate, number of tool calls, response time, cost per task |
| E8 | Are the lecture notes useful and faithful? | Each team member rates notes for lectures they attended; key points are checked against the slide text | 1–5 ratings for usefulness and accuracy; unsupported statements per summary; flashcard correctness |
| E9 | Are edit requests understood? | Run the request set through word rules alone, and word rules plus the on-device model | Exact-match rate, response time |
| E10 | Does the app stay fast on a large library? | Built-in debug test (`-PhophyOpenTest`) and Instruments traces on the iPhone 13 Pro Max | Worst frame time when opening a photo, dropped frames while scrolling during indexing, photos indexed per minute, memory, battery drain and thermal state per 1,000 photos |
| E11 | How much does the cloud cost? | Log tokens per request | Cost per assistant answer and per lecture summary |

### 4.3 Success criteria

- **Search:** hybrid search reaches clearly higher recall@5 than keyword-only search and the built-in Photos search on the evaluation set.
- **Speed:** scrolling and swiping hold full frame rate on the iPhone 13 Pro Max while an index of more than 5,000 photos is running, and opening a photo never freezes the screen.
- **Phones without Apple Intelligence:** every feature works through the word rules or a cloud backend.
- **Lecture notes:** they average at least 4/5 for accuracy, with no unsupported key points.
- **Cost:** cloud cost stays under one cent per assistant answer or lecture summary.

### 4.4 Current status and early measurements

The app already has working first versions of browsing, indexing and search, categories and duplicates, the assistant, lecture notes, and the editor. Figure 2 shows screens from the current build, running in the iOS simulator.

![Library](docs/media/library.png)
![Search](docs/media/search.png)
![Collections](docs/media/collections.png)
![Assistant](docs/proposal/assistant.png)
![Study](docs/proposal/study.png)
![Viewer](docs/proposal/viewer.png)

*Figure 2. Screens from the current app. Library: recent photos, categories and the newest lecture. Search: "pink flowers" found by how the photo looks, with no text in it. Collections: photos sorted into categories on the phone. Assistant: "show me photos of waterfalls", answered by Apple Intelligence. Study: notes made from a lecture's slide photos. Viewer: a full-screen receipt, whose text the index has read.*

Early measurements:

- **Speed:**
  - Opening a photo in a library of about 16,000 photos used to freeze the screen for 1.5–3 seconds. After switching the viewer to a collection view that reuses its pages, the worst frame is 17–80 ms.
  - Indexing now pauses while the user scrolls or views a photo, to remove the remaining stutters. This still needs to be measured in E10.
- **Edit requests:** in a first test, 12 sample requests were all read correctly by the on-device model, in about 1–3.5 seconds each. E9 will repeat this on the full request set.
- **Tuning:** the search and category thresholds were set by hand on a few test photos. Experiments E1, E5 and E6 will replace them with values tuned on the datasets above.

### 4.5 Work arrangement

| Member | Role | Responsible for | Experiments |
|---|---|---|---|
| Su Chuanzhou | Lead | Overall design and integration, the Study tab (lecture notes), reviewing and merging code, the report and the demo | E8 |
| Yin Fengling | Track A: performance and indexing | Indexing speed, memory and battery, background indexing, the embedding models, reliability | E2, E10 |
| Qin Mengmeng | Track B: search and assistant | Search quality, the search evaluation set, Chinese queries, the assistant's tools and backends, cloud cost | E1, E3, E4, E7, E11 |
| Wang Zhengyao | Track C: viewer, editing and collections | The photo viewer and grids, the editor, categories and similar photos | E5, E6, E9 |

All four members write search questions about their own libraries and test the app on their own phones.

### 4.6 Timeline

The project is submitted on **30 November 2026**, about two weeks after this proposal. This is enough because the core app already works (section 4.4), so the time goes mainly into experiments, tuning and the report. The four members work in parallel on their own tracks.

| Dates | Su Chuanzhou (Lead) | Yin Fengling (A) | Qin Mengmeng (B) | Wang Zhengyao (C) |
|---|---|---|---|---|
| 16–19 Nov | Collect lecture photos; set up the shared dataset format; review the first changes | Measure the current app (E10 baseline); start background indexing while charging | Write the search questions; build the in-app evaluation runner; E1 baseline | Label category photos and duplicate pairs; write the edit requests |
| 20–23 Nov | Improve lecture grouping and the notes prompts | Compare MobileCLIP S0 and S2 (E2); memory and model loading | Chinese queries (E3) and OCR text embeddings (E4); tune search | Tune categories (E5) and the duplicate threshold (E6) |
| 24–27 Nov | Rate lecture notes (E8); integrate all tracks; draft the report | Scale test with 50,000 photos; battery and heat (E10) | Assistant tasks on each backend (E7); cost logging (E11) | Edit requests (E9); polish the viewer and editor |
| 28–30 Nov | Final report, demo and submission | Final speed numbers; fix speed problems | Final search numbers; fix search problems | Screenshots and demo video; fix interface problems |

Optional: the Android version of indexing and search is started only if the iOS work is ahead of schedule; otherwise it is listed as future work.

---

## 5. Code repository

The code is on GitHub at **https://github.com/Jasonsu22/Phophy** (public). It is a native iOS app written in Swift and SwiftUI, for iOS 26 and later, and builds with Xcode.

| Folder | What it contains |
|---|---|
| `Phophy/Index/` | The background indexer, the SQLite index, the search engine, place names, and the code that pauses indexing while the screen is busy |
| `Phophy/CLIP/` | MobileCLIP image and text encoders and the tokenizer (the model files are downloaded separately, not stored in git) |
| `Phophy/Collections/` | Categories and similar-photo detection |
| `Phophy/Assistant/` | The assistant, its tools, and the Apple Intelligence and cloud backends |
| `Phophy/Study/` | Lecture grouping and the lecture notes |
| `Phophy/Viewer/` | The full-screen photo and video viewer |
| `Phophy/Editor/` | The photo editor and the AI image service |
| `Phophy/Settings/` | Settings, including API keys kept in the Keychain |
| `Phophy/Debug/` | Debug-only measuring tools, such as the frame-time monitor |
| `PLAN.md`, `TEAM_PLAN.md`, `README.md` | The design, the team plan with known bugs, and how to build and run the app |

How the team works in the repository:

- One branch per task, merged into `main` through a pull request reviewed by another member.
- Every change is built in the simulator and checked on a real phone, including the iPhone 13 Pro Max, before it is merged.
- Rules every change must keep: no API keys or personal photos in the repository; keys stay in the Keychain; photos never leave the phone unless the user turns on a feature that says so.
- Results of each experiment are recorded in the repository, so they can be repeated.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| MobileCLIP understands only English | Experiment E3 (query rewriting and on-device translation) |
| Apple's on-device model is small and sometimes invents filters | Loosen filters when results are empty; prefer cloud backends for complex tasks; measure in E7 |
| The search evaluation set is small and personal | Mix question types and include all four members' libraries; report results per question type |
| Battery and heat from indexing | Indexing pauses when the phone is hot or in Low Power Mode, with overnight indexing while charging; measured in E10 |
| Privacy | All indexing on device; the cloud receives only text, and only for the request the user makes |
| Licences | MobileCLIP weights use Apple's research licence; check before any public release |
| Building for Android splits the team's time | Android is a stretch goal, started only once the iOS objectives are met |
| Two weeks is a short time | The app is already built; the datasets are kept small, the four members work in parallel, and E2–E4 are dropped first if time runs short |
