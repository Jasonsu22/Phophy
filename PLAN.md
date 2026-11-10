# Phophy — project plan

An iOS app that puts an AI agent on top of your photo library: find any photo by describing it, auto-organize, turn lecture-slide photos into study notes, and edit photos with AI.

Written 2026-11-10. Prices and iOS 27 API details come from web research and are marked where they need re-checking.

---

## 1. The key idea: almost nothing needs a paid LLM

Sending thousands of photos to a cloud model is the wrong shape for this app. The work splits into four tiers, and only the last one costs money.

| Tier | What it does | Runs where | Cost |
|---|---|---|---|
| 0. Metadata | Date, location, screenshot flag, favorites, albums | PhotoKit | Free |
| 1. Classic vision | OCR of text in photos, scene labels, faces, duplicates | Apple Vision framework, on device | Free |
| 2. Embeddings | Turn each photo into a vector so "brown dog on a bench" finds it | MobileCLIP via Core ML, on device | Free |
| 3. On-device LLM | Captions, short summaries, query understanding | Apple Foundation Models (Apple Intelligence devices) | Free |
| 4. Cloud LLM | Agent reasoning, lecture-note synthesis, generative edits | API, only when you ask | Pay per use |

Every photo is indexed once by tiers 0–2 and the result is stored in a local database. Search then runs against the database, never against a model that bills per photo. The cloud model only ever sees the handful of photos (or just their OCR text) relevant to one request.

### What the cloud would cost if you did use it

Rough estimate for captioning 10,000 photos, downscaled, about 1,000 input and 150 output tokens each:

| Model | Price per 1M tokens (in / out) | 10,000 photos | With Batch API (50% off) |
|---|---|---|---|
| Claude Haiku 5.5 | $0.10 / $0.50 | about $1.75 | about $0.90 |
| Claude Sonnet 5.5 | $2 / $10 | about $35 | about $17 |
| Claude Opus 5.5 | $4 / $20 | about $70 | about $35 |

So a small model makes bulk analysis cheap, but on-device is still free, private, and works offline. Recommendation: on-device for all bulk work, cloud only for the agent and the lecture digest.

### Other cost levers, in order of impact

1. **Index once, cache forever.** Key results by the photo's `localIdentifier`; only new photos get processed.
2. **Send text, not pixels.** For lecture slides, OCR on device and send the text. Send the image only when OCR confidence is low or the slide is a diagram.
3. **Downscale.** A 512–768 px image is enough for understanding; full 12–48 MP originals multiply cost for nothing.
4. **Retrieve, then reason.** The agent gets the top 10–20 candidates from local search, not the library.
5. **Small model first.** Haiku-class for routine calls, a larger model only for the lecture synthesis step.
6. **Batch API and prompt caching** for anything not interactive.

---

## 2. Similar projects on GitHub and what to take from each

| Project | What it is | What we reuse |
|---|---|---|
| [mazzzystar/Queryable](https://github.com/mazzzystar/Queryable) (about 3k stars, MIT, Swift, active) | Offline natural-language photo search for iPhone using MobileCLIP S2. On the App Store. | The whole indexing and search pipeline is our Phase 2 blueprint. Ships pre-exported Core ML encoders. |
| [apple/ml-mobileclip](https://github.com/apple-aiml-research/ml-mobileclip) | Apple's official MobileCLIP and MobileCLIP2 models, with an iOS demo app. | The embedding model itself. Note the weights use Apple's research model licence: fine for personal use, read it before an App Store release. |
| [fguzman82/CLIP-Finder2](https://github.com/fguzman82/CLIP-Finder2) (MIT, Swift) | MobileCLIP-S0 search tuned for the Neural Engine, with a Swift tokenizer and GPU similarity. | Cleaner Swift reference for the tokenizer and performance tricks. |
| [apple/ml-fastvlm](https://github.com/apple-aiml-research/ml-fastvlm) (about 7k stars) | Apple's small vision-language model that runs on iPhone. | Fallback on-device captioner if Foundation Models image input is not available on your phone. |
| [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | Run open LLMs and VLMs in Swift on Apple silicon. | Runtime for FastVLM or other local models. |
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) (about 9k stars) | SQLite toolkit for Swift, with full-text search. | Our local database. |
| [asg017/sqlite-vec](https://github.com/asg017/sqlite-vec) (about 8k stars) | Vector search extension for SQLite. | Optional; only needed past roughly 100k photos. |
| [immich-app/immich](https://github.com/immich-app/immich) (about 119k stars) | Self-hosted Google Photos alternative with CLIP search, face clustering, OCR. | Not code we can reuse (server, AGPL), but the best reference for feature design. |
| [greyovo/PicQuery](https://github.com/greyovo/PicQuery) | Android counterpart of Queryable, with Chinese support. | Reference for multilingual search. |

### The two projects you sent

| Project | What it is | What we take |
|---|---|---|
| [julyx10/lap](https://github.com/julyx10/lap) (about 4.3k stars, GPL-3.0, Tauri + Rust + Vue) | Offline desktop photo manager: CLIP search via ONNX Runtime, InsightFace face clustering, smart albums, duplicate cleanup, map view, multilingual search in 50+ languages. | Feature ideas, not code: it is a desktop app, and GPL-3.0 would force Phophy to be GPL too if we copied code. Worth borrowing: rule-based smart albums, duplicate cleanup that shows reclaimable space, multilingual search (it proves a multilingual CLIP text encoder works locally), a four-up compare view for picking the best shot. |
| [LinkMind](https://github.com/lzllzllzllzllzl/LinkMind) (your friend's, Next.js + Neon + DeepSeek) | Paste a link, get an AI summary, outline and tags, then ask follow-up questions grounded in the original text. | The lecture digest is the same pattern with OCR text instead of a web page: one JSON response with `summary`, `outline`, `tags`, then a chat panel that answers only from the source. His prompt and JSON shape in `lib/ai.ts` are a good starting template. It also shows DeepSeek's OpenAI-compatible API as a cheap text-only option, which fits because we send OCR text rather than images. The README says MIT but the repo has no licence file; ask him before copying code. |

Nothing found combines search, an agent, and lecture-slide digests in one iOS app. The search half is well-trodden; the agent and study-notes half is where this project is new.

---

## 3. Tech stack

| Layer | Choice | Why |
|---|---|---|
| Language and UI | Swift 6, SwiftUI | Native, required for Liquid Glass and PhotoKit |
| Minimum iOS | iOS 26 | Liquid Glass and Foundation Models both start there |
| Tooling | Xcode 27.1 (already installed), iOS 27 simulators | Checked on this Mac |
| Photo access | PhotoKit (`PHPhotoLibrary`, `PHAsset`, `PHImageManager`) | The only way to reach iCloud Photos; there is no separate iCloud API |
| OCR, labels, subject cut-out | Vision framework | Free, on device, fast |
| Semantic search | MobileCLIP S2 image and text encoders via Core ML | Proven in Queryable |
| Local database | GRDB (SQLite) with FTS5 full-text index | OCR text search plus metadata plus vectors in one file |
| Vector search | Brute force with Accelerate | 10k photos × 512 floats is about 20 MB and searches in milliseconds |
| On-device LLM | Apple Foundation Models | Free; image input reported for iOS 27, to verify in Xcode |
| Cloud LLM | Claude API (Haiku 5.5 for routine, larger for digests) | Tool calling for the agent |
| Basic edits | Core Image, Vision subject lifting | Free: enhance, crop, filters, background removal |
| Generative edits | An image-editing model API (Google's Gemini image models were about $0.03–0.04 per image; re-check) | Claude models do not generate images |
| Background work | `BGProcessingTask` / continued processing | Index while charging |
| Secrets | Keychain for a personal API key; a small proxy (for example a Supabase edge function) before any public release | Never ship a key inside the app |

### How iCloud photos actually reach the app

- The app asks for photo permission once; PhotoKit then exposes the whole library, including photos whose originals live only in iCloud.
- For indexing we request a small thumbnail, which is normally already on the phone. Originals are downloaded only when you open or edit a photo.
- Albums the agent creates and edits it saves go back through PhotoKit and sync to iCloud normally. Edits are non-destructive and revertible in Apple Photos. Deleting always shows Apple's own confirmation.

---

### Visual style: Liquid Glass (chosen 2026-11-10)

Photo-forward screens with floating glass controls: a glass tab bar with a separate round search button, glass chips for categories, a glass ask bar, and glass cards for digests. In SwiftUI this is the native iOS 26 material (`glassEffect`, `GlassEffectContainer`, standard `TabView` and toolbars pick it up automatically), so we use system components rather than faking blur. Reference mockups: https://claude.ai/artifact/VZFCRTm96DGZdXu7FGsfbQ (boards A).

## 4. Architecture

```
Photos library (PhotoKit)
        │  new/changed assets
        ▼
Indexer (background)
  ├─ metadata        → date, place, type
  ├─ Vision OCR      → text
  ├─ Vision classify → labels
  └─ MobileCLIP      → 512-d vector
        ▼
Local SQLite (GRDB): assets, ocr_fts, vectors, categories, digests
        ▲
Tools:  search_photos · get_photo · list_by_date/place · create_album
        add_to_album · make_digest · edit_photo
        ▲
Agent loop (on-device LLM or Claude API) ◄── chat / search bar
```

The agent never touches photos directly. It calls a small set of tools that read the local index, and anything that changes the library (albums, edits, deletes) asks you first.

---

### Phones without Apple Intelligence (decided 2026-11-10)

The app must work fully on phones such as the iPhone 13 Pro Max, which have no Apple Intelligence. Two rules follow.

**Nothing in Phases 1–3 may depend on Apple Intelligence.** Browsing, text recognition, labels, MobileCLIP search, auto-categories and duplicate detection use Vision and Core ML only, which run on the A15 and older chips.

**Everything that needs a language model goes through one interface with interchangeable backends.** The agent, the lecture digest and captions call a single `LanguageModel` protocol and never a specific provider.

| Backend | When it is used | Cost |
|---|---|---|
| Cloud small model (Claude Haiku 5.5 or similar) | Default on every phone | Well under a cent per request |
| Apple Foundation Models | Automatically, when the phone has Apple Intelligence | Free |
| Downloadable local model (1–3B parameters via MLX) | Optional offline mode, later | Free; 0.5–2 GB download, weaker results |

Cloud requests carry text wherever possible: recognised slide text for digests, and the question plus a handful of search results for the agent. A digest of about 3,000 input and 800 output tokens costs roughly $0.0007 on Haiku 5.5 (estimate).

If other people use the app, cloud calls are billed to the developer. Before any public release that needs a small proxy server with per-user limits, or user-supplied API keys, or a subscription. For personal use, a key in the Keychain is enough.

## 5. Build phases

Each phase ends with something you can run on your phone.

| Phase | Goal | Done when |
|---|---|---|
| 0. Setup (1–2 days) | Xcode project, git repo, app runs in simulator and on your iPhone | "Hello" screen on your phone |
| 1. Browse (week 1) | Permission flow, photo grid, detail view | You can scroll your real library |
| 2. Index and search (weeks 2–3) | OCR + MobileCLIP indexing, database, search bar | Typing "whiteboard" or "receipt" finds the right photos |
| 3. Organize (week 4) | Auto categories (screenshots, documents, slides, food, people, places), duplicate finder, suggested albums | A "Categories" screen you would actually use |
| 4. Agent (week 5) | Chat screen with tool calling over the index | "Find the photos from the Kyoto trip with the red gate and put them in an album" works |
| 5. Lecture digest (week 6) | Detect slide sessions (same hour, same place, slide-like), OCR, summarise into notes and flashcards | Photos from one lecture become one readable page |
| 6. AI edit (week 7) | Enhance, crop, background removal on device; generative edit via API | "Make this brighter and remove the background" works |
| 7. Polish | Performance on the full library, battery, error states, TestFlight | Stable daily use |

Phases 2 and 5 carry the most value; 6 is the most optional.

### Phase 2 as built

- **Index:** `Phophy/Index/`. A SQLite file (`index.sqlite` in the app's Application Support folder, via GRDB) with one row per photo: recognized text, Vision labels, MobileCLIP embedding. A trigram full-text table covers text and labels. Deleting the file is safe; it is rebuilt.
- **Indexer:** runs after photo access is granted and whenever the library changes. Photos only; videos are skipped for now.
- **Search:** word matches on text and labels first, then "looks like" matches ranked by MobileCLIP similarity. The cutoff (score of at least 0.20 and within 0.05 of the best hit) was tuned on MobileCLIP S0 with 7 test photos; re-check it on a real library and after changing the model.
- **Search field** is pinned under the Search title, not merged into the tab bar: the tab-bar search field did not appear in the iOS 27 simulator.

### MobileCLIP models (not in git)

The models are about 120 MB and are ignored by git. Without them the app still builds and search falls back to text and labels. To install them, run this from the project folder:

```bash
for k in image text; do d=Phophy/CLIP/Models/mobileclip_s0_$k.mlpackage; mkdir -p $d/Data/com.apple.CoreML/weights; for f in Manifest.json Data/com.apple.CoreML/model.mlmodel Data/com.apple.CoreML/weights/weight.bin; do curl -fL "https://huggingface.co/apple/coreml-mobileclip/resolve/main/mobileclip_s0_$k.mlpackage/$f" -o "$d/$f"; done; done
```

To use the more accurate S2 model on a phone, download `mobileclip_s2_*` the same way and change `modelName` in `Phophy/CLIP/CLIPEncoder.swift`; photos are re-embedded automatically. The tokenizer in `Phophy/CLIP/Tokenizer/` comes from Apple's `ml-mobileclip` demo app (originally Hugging Face's swift-coreml-transformers).

---

## 6. iOS development basics for a first app

### Simulator

1. Open the project in Xcode, pick a simulator such as iPhone 18 Pro in the toolbar, press Run (⌘R).
2. The simulator has only a few stock photos. Drag your own images onto the simulator window, or run:
   ```bash
   xcrun simctl addmedia booted ~/Pictures/test/*.jpg
   ```
3. Claude Code can also build, launch, tap through and screenshot the simulator for you.

Limits: no Neural Engine (models run slower on CPU), no real iCloud library, and Apple Intelligence behaves differently. Use it for UI and logic, not for performance.

### Your iPhone

1. In Xcode: Settings → Accounts → add your Apple ID. A free account works.
2. In the project's Signing & Capabilities tab, tick "Automatically manage signing" and choose your personal team.
3. Plug the phone in (or pair over Wi-Fi), tap Trust on the phone.
4. On the phone: Settings → Privacy & Security → Developer Mode → on, then restart.
5. Choose your phone as the run target and press Run.
6. First launch only: Settings → General → VPN & Device Management → trust your developer certificate.

A free Apple ID signs apps for 7 days at a time (re-run from Xcode to renew). The $99/year developer programme gives one-year signing, TestFlight and App Store access; not needed until Phase 7.

### Required privacy strings

`NSPhotoLibraryUsageDescription` and `NSPhotoLibraryAddUsageDescription` in Info.plist, or the app crashes when it asks for photos.

---

## 7. Risks and open questions

- **Which iPhone?** Apple's on-device LLM needs an Apple Intelligence device (iPhone 15 Pro or newer). On older phones tier 3 falls back to the cloud or to FastVLM.
- **Foundation Models image input** is reported for iOS 27 by secondary sources only; confirm in Xcode before depending on it.
- **MobileCLIP licence** is a research licence. Personal use is fine; an App Store release needs a licence check or a swap to an openly licensed CLIP/SigLIP.
- **Non-English search.** MobileCLIP is English-centric. If you want to search in Chinese, plan for a multilingual text encoder or query translation.
- **First index time.** Thousands of photos take a while (Queryable reports minutes, not hours, on recent phones); do it in the background with progress shown.
- **Image-edit model pricing** changes quickly; re-check before Phase 6.
