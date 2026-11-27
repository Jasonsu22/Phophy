<p align="center">
  <img src="docs/media/banner.svg" alt="Phophy: your photos, understood. On your iPhone." width="100%">
</p>

<p align="center">
  <b>An AI photo app for iPhone.</b> Find any photo by describing it, let it sort your library,<br>
  and turn the lecture slides you photographed into notes and flashcards.
</p>

<p align="center">
  <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-131a44?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-5a3fd6?style=flat-square&logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Liquid%20Glass-0f8f9c?style=flat-square">
  <img alt="On-device AI" src="https://img.shields.io/badge/AI-on--device%20first-b4366f?style=flat-square">
</p>

---

## See it move

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/media/assistant.gif" width="240" alt="Asking the assistant for waterfall photos"></td>
    <td align="center" width="33%"><img src="docs/media/viewer.gif" width="240" alt="A photo zooming open from the grid, pinch to zoom, swipe down to close"></td>
    <td align="center" width="33%"><img src="docs/media/study.gif" width="240" alt="A lecture's notes and flashcards"></td>
  </tr>
  <tr>
    <td align="center"><b>Ask</b><br><sub>Type a question; matching photos come back with the answer.</sub></td>
    <td align="center"><b>View</b><br><sub>Photos open and close like Apple's Photos app.</sub></td>
    <td align="center"><b>Study</b><br><sub>Slide photos become a summary, key points and flashcards.</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/media/library.png" width="220" alt="Library home screen"></td>
    <td align="center" width="33%"><img src="docs/media/collections.png" width="220" alt="Automatic collections"></td>
    <td align="center" width="33%"><img src="docs/media/search.png" width="220" alt="Search by description"></td>
  </tr>
  <tr>
    <td align="center"><b>Library</b></td>
    <td align="center"><b>Collections</b></td>
    <td align="center"><b>Search</b></td>
  </tr>
</table>

## What it does

| | |
|---|---|
| 🔎 **Search by description** | Type what you remember: "skiing, white hat, big smile", "whiteboard from last month", a word written in the photo, or a search in Chinese. Only photos that really match are shown. |
| ✨ **Assistant** | Ask about your library in plain words: "How much did I spend at Muji?" It searches with tools, reads the answer from the photo's text, and offers to make albums. |
| 📚 **Lecture notes** | Slides photographed in one lecture become one page: summary, key points with slide numbers, and flip-card flashcards. |
| 🎨 **Edit by describing** | "Warmer and more vivid" is done on the iPhone for free. Bigger requests, like "add a hot air balloon in the sky", go to an AI image service you choose, only after you confirm. |
| 🗂 **Sorts itself** | Slides, documents, receipts, food, people, pets and scenery. Near-duplicates are grouped for clean-up, and any collection can be saved as an album. |
| 🖼 **Viewer** | Zooms out of its thumbnail, pinch or double-tap to zoom, swipe between photos, swipe down to close. |

## How it works

Every photo is read **once, on the iPhone**, by the cheapest tool that works, and the result is stored in a local database:

| Tier | What it gives | Runs on |
|---|---|---|
| 0. Metadata | Date, place, kind of photo | PhotoKit |
| 1. Text and labels | Every word in the photo, scene labels | Apple Vision |
| 2. Embedding | One vector per photo, plus tags from 4,585 English and Chinese concepts | MobileCLIP S0, Core ML |
| 3. Description | One line about what the photo shows | Apple Intelligence, or SmolVLM2 on phones without it |
| 4. Cloud model (optional) | The assistant and notes, text only | Claude, OpenAI or any OpenAI-compatible service |

**Search** runs two rankings and fuses them with reciprocal rank fusion: BM25 keyword matching over descriptions, tags and text, and MobileCLIP similarity between your words and every photo. Before ranking, places and dates become filters, typos are corrected against the index's own vocabulary, and Chinese is translated on the phone.

**The assistant** is a language model that calls five tools over the index (`find_photos`, `list_places`, `list_collections`, `show_photos`, `propose_album`). It only ever sees text, never images, and anything that changes the library waits for your tap.

## Results

Measured in the iOS simulator; the scripts and raw numbers are in [`Eval/`](Eval/README.md).

| What | Before | Now |
|---|---|---|
| Chinese searches, top 10 correct (Flickr30k, 1,000 photos) | 2% | 51% |
| Misspelled searches, top 10 correct | 13% | 59% |
| Objects found in the top 50 | 51% | 89% |
| Chinese sentences, right photo in the top 5 ([E3](Eval/E3_CHINESE.md)) | 60% (dictionary) | 87% (on-device translation) |
| Paraphrased searches for slides and documents, top 10 ([E4](Eval/E4_OCR_EMBEDDINGS.md), experiment) | 50% | 74% |
| Assistant, 20 real tasks on Apple Intelligence ([E7](Eval/AGENT_EVAL.md)) | | 14–17 of 20, about 7 s each |

A search takes about 10–30 ms.

## Private and cheap by design

Indexing and search never leave the phone and cost nothing. A language model is only used for the assistant, lecture notes and reading edit requests, and it receives **text** only: dates, labels and the words read from photos. You choose which model in Settings:

| Model | When |
|---|---|
| Apple Intelligence | Used first on iPhones that have it. Free and offline. |
| Claude, OpenAI, or any OpenAI-compatible service | For other iPhones, or by choice. Bring your own API key; it stays in the Keychain. |

Photos leave the phone in one case only: a generative edit you have confirmed, sent to the image service you chose.

## Run it

Requires Xcode 27 or later and an iPhone or simulator on iOS 26 or later.

1. Clone the repo and open `Phophy.xcodeproj`.
2. Download Apple's MobileCLIP models into `Phophy/CLIP/Models/` (see [PLAN.md](PLAN.md#mobileclip-models-not-in-git)). Without them, the app still runs with text and label search only.
3. Choose a simulator or your iPhone and press **Run** (⌘R). On a real iPhone, select your Apple ID team under *Signing & Capabilities* first; a free account works.

To try it in the simulator with a made-up library (photos, slides, receipts and screenshots with known contents):

```bash
python3 Demo/build_library.py CAPTIONS.tsv IMAGES_DIR OUT_DIR
xcrun simctl addmedia booted OUT_DIR/*
```

## How it's built

A native iOS app in Swift 6 and SwiftUI, about 14,000 lines.

| Path | What's inside |
|---|---|
| `Phophy/RootView.swift`, `LibraryView.swift` | Tabs, ask bar, home screen |
| `Phophy/PhotoLibrary.swift`, `PhotoGridView.swift` | PhotoKit access, filters, grids |
| `Phophy/Viewer/` | Full-screen photo viewer |
| `Phophy/Index/` | On-device index (SQLite via GRDB), indexer, search engine, query filters and translation |
| `Phophy/CLIP/` | MobileCLIP encoder and tokenizer |
| `Phophy/Describe/` | Photo descriptions: Apple Intelligence, SmolVLM2 (MLX) or a cloud model |
| `Phophy/Collections/` | Categories, similar-photo clean-up |
| `Phophy/Assistant/` | Chat, chat history, photo tools, Apple Intelligence and cloud backends, cost per answer |
| `Phophy/Study/` | Lecture grouping, notes, flashcards |
| `Phophy/Editor/` | Photo editor, edit requests, AI image service |
| `Phophy/Settings/` | Settings, AI provider choice, Keychain storage |
| `Phophy/Debug/` | Debug-only evaluation runners |
| `Eval/` | Search benchmark, Chinese queries (E3), text vectors (E4), assistant tasks (E7) |
| `Demo/` | The made-up demo library and the presentation video (Remotion) |

The design, cost reasoning and build phases are in [PLAN.md](PLAN.md); the proposal is in [PROPOSAL.md](PROPOSAL.md).

## Team 26

| | |
|---|---|
| Su Chuanzhou | Lead: design, integration, Study |
| Yin Fengling | Indexing and performance |
| Qin Mengmeng | Search and assistant |
| Wang Zhengyao | Viewer, editor and collections |

## Roadmap

- [x] Library, search, collections, assistant, lecture notes
- [x] Photo descriptions on the device, Chinese search, AI photo editing
- [ ] Sentence vectors of the text in photos, inside the app (E4)
- [ ] Indexing in the background while charging
- [ ] Assistant and cost measured on cloud models (E7, E11)
