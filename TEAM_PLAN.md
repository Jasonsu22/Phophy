# Phophy — team plan (from 10 November 2026)

What is built, what is broken or weak, and who does what next. Four
people: a lead (the project's owner) and three members, each member on a
track that owns a set of folders so that work rarely collides. PLAN.md
stays the record of how the app was designed; this file is the to-do list.

| | Track | Owns |
|---|---|---|
| **Lead** | Product, integration and release; Study tab; experiments | Shared files, `Phophy/Study/`, README, PLAN.md, this file, TestFlight |
| **A** | Performance, indexing and reliability | `Phophy/Index/`, `Phophy/CLIP/`, `PhophyApp.swift`, background work |
| **B** | Search quality and the assistant | `Phophy/Assistant/`, `SearchEngine.swift`, evals |
| **C** | Viewer, photo editing and Photos-level polish | `Phophy/Viewer/`, grids, `Collections/`, `Settings/`, new `Phophy/Edit/` |

Shared files (`RootView.swift`, `IndexStore.swift`, `PhotoLibrary.swift`)
belong to the lead. Members post a heads-up in the team chat before
changing one, and put the change in a small PR of its own, which the lead
reviews.

### The lead's job

- **Decide** what "like Photos" means when it is unclear. Rank the bug
  list each week, and say yes or no to experiments (section 5).
- **Review and merge** every PR, and build `main` on a real phone at least
  twice a week.
- **Own the shared files** and the index format, so that changes from A,
  B and C fit together. A schema change is agreed with A before it is
  written.
- **Supply real test data.** Write the first 30 eval questions (B1) from
  your own library, and run the iPhone 13 Pro Max checks.
- **Study tab (B4 below).** It is self-contained and fits around review
  work.
- **Release:**
  - App Store Connect and TestFlight;
  - the privacy policy and App Privacy labels (what goes to Apple Maps,
    and what goes to the cloud provider the user chose);
  - the README and screenshots.
- **Spikes.** Run the one-day experiments from section 5 that the team
  picks.

---

## 0. Where the app stands

Working today and checked on the simulator and on an iPhone 13 Pro Max:

- **Library**: Recents and all-photos grids, oldest at the top and newest at
  the bottom, opening at the bottom as in Photos. Albums, Favourites, Videos,
  Live Photos and Screenshots.
- **Viewer**: zoom transition from the tile, swipe between photos, pinch
  and double-tap zoom, swipe down to close. Live Photos play when held,
  videos play, plus favourite, info and delete.
- **Index** (on the phone, saved in `Library/Application Support/index.sqlite`):
  - date, location and type for every photo, read straight from Photos;
  - place names from Apple Maps;
  - text in the photo (Vision OCR on a 2,048 px copy);
  - Vision scene labels;
  - a MobileCLIP S0 image embedding.
- **Search**: filters (place, dates, type, favourites) narrow the library,
  then text and visual similarity are merged into one ranking
  (reciprocal rank fusion, the approach Immich uses).
- **Collections**: automatic categories (slides, documents, receipts, food,
  people, pets, scenery, screenshots) and groups of similar photos.
- **Study tab**: lecture digests written from slide text.
- **Assistant**:
  - runs on Apple Intelligence on the phone, or on Claude, OpenAI or any
    OpenAI-compatible service with the user's own key (kept in the
    Keychain);
  - tools: find_photos, list_places, list_collections, show_photos and
    propose_album;
  - keeps chat history, shows its search steps, and is limited to 6 tool
    rounds.

Test tools already in the repo or used so far:

- the `-PhophyAsk "question"` launch argument (Debug only) asks the
  assistant on launch;
- `-SimulateNoAppleIntelligence` tests the path for phones without Apple
  Intelligence;
- a mock OpenAI-compatible server is used to test the agent loop;
- scripts make test Live Photos and photos with GPS. Move them into
  `Tools/` (task A0).

---

## 1. Known bugs and rough edges (everyone, first week)

Each person takes the bugs in their own area. Every bug fix gets a short
note on how it was reproduced. The lead re-ranks this list every week.

| # | Bug / rough edge | Area | Owner |
|---|---|---|---|
| 1 | Opening and swiping photos is still slower on the iPhone 13 Pro Max than in Photos, worst while indexing runs | Viewer + indexing | C, A |
| 2 | Indexing runs only while the app is open, and competes with scrolling and the viewer for CPU and the Neural Engine | Indexing | A |
| 3 | No thermal or Low Power Mode check: a long first index can warm the phone and drain the battery | Indexing | A |
| 4 | The text model (81 MB) loads on the first search, so the first query takes a moment, and it then stays in memory | CLIP | A |
| 5 | Videos are not indexed (no text, labels or embedding); they are only found by date, place and type | Indexing | A |
| 6 | Place lookup stops at the first error and only resumes on the next run, so a long trip can take several launches to name | Places | A |
| 7 | The on-device model sometimes invents filters (wrong year, unasked category). Filter loosening rescues most cases, but not all | Agent | B |
| 8 | Questions in Chinese or other languages: MobileCLIP's text encoder only understands English, so visual search is weak unless the model translates | Agent/search | B |
| 9 | Strong/weak match thresholds (0.20 score, 0.05 margin) were tuned by hand on a few photos | Search | B |
| 10 | Similar-photo groups can still split bursts or join near-identical slides from different lectures | Collections | C |
| 11 | Deleting from the viewer: the grid and the index must both update without a jump; check with iCloud Shared Library photos | Viewer | C |
| 12 | Typing into the simulator's ask bar sometimes drops keys (a simulator issue, but check the field on a real phone) | Ask bar | C |
| 13 | The assistant's chat history file grows without limit | Agent | B |
| 14 | Accessibility: VoiceOver labels for tiles, the viewer bar and the ask bar; Dynamic Type in Settings and Study | All | C |
| 15 | Index database migrations have no test; a failed migration would leave the app with no index | Index | A |

---

## 2. Track A — performance, indexing and reliability

### Is running the embedding models on the phone a problem?

The short answer is no, as long as the work is scheduled well:

- **The embedding itself is cheap.** MobileCLIP S0 runs on the Neural
  Engine: a few milliseconds per pass, two passes per photo.
- **The slow parts are elsewhere:**
  - OCR at `.accurate` on a 2,048 px image takes about 100–300 ms per
    photo;
  - decoding the image;
  - waiting on iCloud downloads.
- **Search is cheap too.** Brute-force similarity over 10,000 photos is
  about 20 MB of floats and a few milliseconds.
- **What makes the phone feel slow** is that indexing runs in the
  foreground while the user scrolls. It shares the CPU, memory bandwidth
  and Neural Engine with the UI, and holds up to four 2,048 px images in
  memory at once.

The tasks below fix that.

**A1. Scheduling (highest priority)**
- Move bulk indexing to a `BGProcessingTask` that requires external power,
  as Photos does overnight. Register it in `PhophyApp`, add the
  `BGTaskSchedulerPermittedIdentifiers` key and the
  `processing` background mode.
- While the app is open, index slowly: one photo at a time with pauses.
  Stop entirely while the viewer is open or a scroll is in progress, and
  pick up again 2 s after the UI goes idle.
- Watch `ProcessInfo.thermalState` and `isLowPowerModeEnabled`. At
  `.serious` or above, or in Low Power Mode, pause. Show "Paused to keep
  your iPhone cool" in the index status.
- Done when: scrolling and swiping on the iPhone 13 Pro Max hold 120 fps
  in Instruments while an index of more than 5,000 photos is running.

**A2. Measure first**
- Add `os_signpost` intervals for load image, OCR, classify, embed and save,
  and record one Instruments trace on the 13 Pro Max. Put the numbers
  (ms per stage, photos per minute, peak memory, energy impact) in this
  file.
- Try OCR at `.fast` first and `.accurate` only when `.fast` finds text,
  which skips the expensive pass for most photos that have no text at all.
- Try 1,536 px instead of 2,048 px for OCR and check what text is lost on
  20 slide and receipt photos.

**A3. Memory and model loading**
- Load the text encoder when the Search tab or ask bar is first shown
  (warm-up), not on the first query. Release both models on
  `didReceiveMemoryWarning` and when indexing finishes.
- Set `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` explicitly
  and compare with `.all`.
- Check whether the text encoder can be quantised (palettised to 6 or
  8 bits with coremltools) from 81 MB to about 20–40 MB without losing
  search quality. This also makes the app smaller.
- Consider MobileCLIP S2 (more accurate, larger) only after A1, and only
  for phones with 6 GB of RAM or more.

**A4. Videos**
- Index videos from 3 frames (10%, 50%, 90%): average the embeddings, run
  OCR on the middle frame, use `AVAssetImageGenerator`.
- Optional: speech-to-text for short videos with `SpeechAnalyzer`, stored
  as text, so "the video where he says happy birthday" works.

**A5. Reliability**
- Place lookup: retry with backoff (2 s, 10 s, 60 s) instead of stopping
  at the first error; show "N places still to name" in Settings.
- Test every migration on a copy of a real `index.sqlite`, with a unit test
  target (`PhophyTests`) that runs on the simulator.
- Make re-indexing resumable and visible: after a model upgrade, old
  entries keep working until replaced.
- Handle `PHPhotoLibraryChangeObserver` incremental changes (insertions,
  edits, deletions) without re-fetching the whole library.

**A6. Scale**
- Test with a 50,000-photo library (generate one on a spare simulator
  with a script). If brute-force search goes above 30 ms, keep the
  embedding matrix in memory as `Float16`, or add an index (for example
  `sqlite-vec` or a simple IVF), but only if it is needed.

---

## 3. Track B — search quality and a stronger assistant

The agent is limited by what search returns. Fix search first, then the
agent.

**B1. An evaluation set, before any tuning**
- 60–100 real questions with the right photos, from the team's own
  libraries:
  - by place and time ("Hong Kong two years ago");
  - by content ("the whiteboard with the network diagram");
  - by text ("the receipt from Muji");
  - in Chinese and in English;
  - vague ("that sunset at the beach").
- Two scores:
  - search alone: recall@5 and recall@20 of `find_photos`;
  - end to end: did the assistant show the right photo, and in how many
    tool rounds.
- Add a Debug-only eval runner that reads `evals.json` and writes results,
  so any change to ranking or prompts can be compared.

**B2. Better retrieval**
- **Text embeddings of the OCR text.** Today OCR text only goes into a
  keyword (FTS5 trigram) index. Add a small multilingual sentence-embedding
  model (MiniLM-class, Core ML) or Apple's `NLContextualEmbedding`, so
  "notes about TCP handshakes" finds a slide that says "three-way
  handshake".
- **Multilingual queries.** MobileCLIP's text side is English only. Either
  have the assistant always pass an English description (already in the
  prompt; measure it), or translate the query on the phone with Apple's
  Translation framework before the CLIP text encoder.
- **Captions.** On Apple Intelligence phones, write a one-line caption for
  each photo in the background (FoundationModels with image input, when
  available) and index it as text. This is the most direct way to answer
  "what is in this photo" questions.
- **People.** Vision face detection plus face-print clustering, so users
  can name a person once and search "photos of Mum in Kyoto". This is
  large; keep it on the phone only and behind a setting.
- **Tune with the eval set:** RRF constant k, the strong-match thresholds,
  how much labels and captions count, and how far filters loosen.
- **Re-rank the top 30** with the cloud model when the user has chosen
  cloud. Send only text (captions, OCR snippets, dates and places), never
  the image, unless the user turns on "Send thumbnails to improve answers".

**B3. A stronger agent**
- **New tools:**
  - `photo_details(ref)`: full OCR text, labels, place and caption for one
    photo, so the agent can answer "what did the receipt total?";
  - `count_photos(filters)`: for "how many photos did I take in Japan?";
  - `timeline(place|range)`: trips and days with counts, for "when was I
    last in Tokyo?";
  - `similar_to(ref)`.
- **Look at the photo (cloud only, opt in).** Send one or two small
  thumbnails to a vision model when the user asks about what is in a
  specific photo.
- **Actions with confirmation:** add to an album (exists), favourite,
  hide, delete (always confirmed with a button), and share.
- **Memory across chats:** names the user gives ("my dog is called
  Mochi"), stored on the phone and passed in the prompt.
- **Prompt and model per backend:** keep a shorter prompt for the
  on-device model; for Claude and OpenAI, allow parallel tool calls and a
  better plan-then-search pattern. Record which model the user chose next
  to each eval run.
- **Streaming replies** for cloud backends, with steps appearing live.
- Cap and trim the history file (#13); allow "Delete all chats".

**B4. Study tab (owned by the lead; B helps with prompts)**
- Group slides by lecture using time gaps plus visual similarity, not only
  date.
- Ask questions about a lecture ("explain slide 12"), with the slide text
  as context; generate flash cards and export to Markdown or PDF.

**B5. Cost and keys**
- Show the approximate cost of each cloud answer (tokens in and out) in
  the steps.
- Optional team-hosted proxy, so testers can try cloud features without
  their own key. The key stays on the server, with a per-device rate
  limit; never ship a key in the app.

---

## 4. Track C — viewer, photo editing and Photos-level polish

**C1. Make the viewer as fast as Photos (bug #1)**
- Profile opening and swiping with the Animation Hitches instrument on the
  13 Pro Max.
- Show the cached grid thumbnail instantly, then a screen-sized image,
  then the full image only when zoomed (partly done; measure it).
- Preheat ±2 pages with `PHCachingImageManager` (done), and stop
  preheating while the user swipes quickly.
- Avoid SwiftUI `TabView` re-rendering every page: if the hitches persist,
  move the pager to a `UIPageViewController` or a `UICollectionView` with
  paging.
- Live Photo: load the `PHLivePhoto` only after the page settles.

**C2. Photos-level details**
- Filmstrip scrubber at the bottom of the viewer, as in Photos.
- Grid: pinch to change the number of columns (3 / 5 / 9 tiles across);
  years, months and days views; selection mode with drag-to-select, share,
  favourite, delete and add to album.
- Info panel: map of the place, camera and lens, file size; editable
  caption (stored in our index, used by search).
- Haptics on favourite and delete; the context menu on a long press of a
  tile (share, favourite, copy, delete) with a preview.
- Hidden and Recently Deleted albums (read only, through PhotoKit).
- Check every screen in light mode, with large text, and on iPhone SE and
  iPad sizes.

**C3. Photo editing (new `Phophy/Edit/`)**

Save every edit through `PHContentEditingOutput` with
`PHAdjustmentData`, so edits are non-destructive and can be reverted in
Photos.

| Step | What | How |
|---|---|---|
| 1 | Crop, rotate, straighten, aspect ratios | Core Image `CIFilter` + own crop UI |
| 2 | Light and colour: exposure, brilliance, highlights, shadows, contrast, saturation, warmth, sharpness, vignette | Core Image, rendered on Metal with a `CIContext`, live preview at screen size |
| 3 | Filters (a handful of looks) | Core Image colour cube LUTs |
| 4 | Auto enhance | `CIImage.autoAdjustmentFilters()` |
| 5 | Lift the subject: copy, sticker, or new background | Vision `VNGenerateForegroundInstanceMaskRequest` |
| 6 | Mark-up: draw and add text | PencilKit over the image |
| 7 | **AI edit by request** ("remove the person behind me", "make the sky blue", "make it look like film") | Simple looks map to Core Image settings, chosen by the language model, free and on the phone. Generative edits (remove an object, change the background) go to a cloud image-editing API, opt in, with a clear notice that the photo is uploaded |
| 8 | Clean Up (remove objects) | On Apple Intelligence phones, check whether the system offers it to apps; otherwise use the cloud API in step 7 |

The assistant should be able to start an edit: "brighten the photos from
last night" proposes edits, shown as before and after, and nothing is
saved until the user taps Save.

**C4. Collections**
- Similar-photo groups (bug #10): use capture time (within 2 s for
  bursts) plus embedding distance; let the user pick the best one and
  delete the rest (with confirmation).
- Trips (place + date clusters), with a map; "On this day".
- Make collections explain themselves ("Grouped because they were taken
  in Kyoto on 3–6 April").

---

## 5. Experimental ideas (may never ship)

Worth a day's spike each; keep the ones that test well.

- **Memories videos**: a short slideshow with music for a trip, made with
  AVFoundation on the phone.
- **Ask about a photo with the camera**: point the camera at a poster and
  find related photos.
- **Duplicate and clutter clean-up**: screenshots older than 30 days,
  blurry shots, and near-duplicates, with storage saved shown before
  deleting.
- **Receipts to a spreadsheet**: extract merchant, date and total from
  receipt photos and export to CSV.
- **Widgets and App Intents**: "Find my passport photo" from Siri and
  Spotlight; a widget showing a photo from this day.
- **Share extension**: send a photo from another app into Phophy to ask
  about it.
- **Mac and iPad versions** sharing the same index format.
- **Shared albums with friends** through iCloud Shared Library, searchable
  together.
- **Bigger on-device models** (MobileCLIP S2 / B) on newer phones.
- **Handwriting search** for notes photos, with a handwriting-capable OCR.

---

## 6. Order of work

| Weeks | Lead | A | B | C |
|---|---|---|---|---|
| 1 | Rank the bug list, write 30 eval questions, set up branch rules and TestFlight | A2 measure, A0 move test scripts into `Tools/`, A1 scheduling and thermal | B1 eval set and runner | C1 viewer profiling and fixes |
| 2–3 | Review and integrate; B4 grouping slides into lectures | A1 background task, A3 memory and model loading | B2 multilingual queries, OCR text embeddings, tuning | C2 grid pinch, selection, filmstrip |
| 4–5 | B4 lecture questions and flash cards; privacy policy draft | A4 videos, A5 reliability and tests | B3 new tools, streaming, actions | C3 editing steps 1–4 |
| 6–7 | Experiment spikes; App Privacy labels, README and screenshots | A6 scale test, help B with captions | B2 captions, people (spike) | C3 steps 5–7, C4 collections |
| 8 | TestFlight build; all four test on their own phones for a week; the lead picks the top 10 problems to fix | | | |

Milestones:

- **M1, end of week 1**: measured numbers in this file, the eval set, and
  a viewer with no hitches.
- **M2, end of week 3**: indexing no longer slows the phone, and search
  scores at least 15 points higher on recall@5.
- **M3, end of week 7**: editing (steps 1–7) and the new agent tools.
- **M4, week 8**: TestFlight beta.

---

## 7. How we work

- **Branches and PRs.** One branch per task (`a1-background-index`).
  Small PRs, reviewed by the lead (or by another member when the lead is
  away), and merged to `main` after a build on the simulator and a check
  on a real phone for anything you can see or feel. The lead's own PRs are
  reviewed by a member.
- **Builds.**
  - Simulator: `xcodebuild -project Phophy.xcodeproj -scheme Phophy
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
    -derivedDataPath build build`.
  - Phone: add your own team in Signing & Capabilities. Don't commit
    signing changes.
- **Models.** The MobileCLIP models are not in git; see PLAN.md,
  "MobileCLIP models".
- **Privacy rules, which every change must keep:**
  - Photos never leave the phone unless the user turns on a feature that
    says so.
  - Cloud requests carry only the text needed.
  - API keys live only in the Keychain.
  - Place lookups send coordinates only, and can be turned off.
- **Test devices.** Keep at least one older phone (iPhone 13 Pro Max) in
  every performance check; it is the phone users will notice slowness on.
- **Definition of done.** It works on a real phone, it does not slow
  scrolling, it has VoiceOver labels, and PLAN.md or this file is updated
  if the design changed.
