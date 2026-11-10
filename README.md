# Phophy

An iOS app that puts an AI agent on top of your photo library: find any photo by describing it, organize automatically, turn lecture-slide photos into study notes, and edit photos with AI.

Analysis runs on the device wherever possible, so indexing thousands of photos costs nothing and your library is never uploaded in bulk.

## Status

| Phase | What | State |
|---|---|---|
| 0 | Xcode project, Liquid Glass shell | Done |
| 1 | Photo library access, grids, photo view | Done |
| 2 | On-device index (text recognition, MobileCLIP) and search | Done |
| 3 | Auto categories, similar-photo cleanup, save as album | Done |
| 4 | Agent chat over the index | Planned |
| 5 | Lecture digest: slides to notes and flashcards | Planned |
| 6 | AI photo editing | Planned |

The full plan, tech stack and cost strategy are in [PLAN.md](PLAN.md).

## Requirements

- Xcode 27 or later
- iOS 26 or later (simulator or device)

## Run

1. Open `Phophy.xcodeproj` in Xcode.
2. Pick an iPhone simulator, or your own iPhone, as the run destination.
3. Press Run (⌘R).

To run on a physical iPhone, select your Apple ID team under the target's Signing & Capabilities tab first. A free Apple ID is enough.

The simulator ships with only a few photos. Add your own with:

```bash
xcrun simctl addmedia booted ~/Pictures/test/*.jpg
```

## Project layout

| Path | Contents |
|---|---|
| `Phophy/PhophyApp.swift`, `RootView.swift` | App entry, tab bar, ask bar |
| `Phophy/LibraryView.swift` | Home screen |
| `Phophy/PhotoLibrary.swift` | PhotoKit access, permission, filters |
| `Phophy/PhotoGridView.swift`, `PhotoDetailView.swift`, `AssetThumbnail.swift` | Browsing |
| `Phophy/Index/` | On-device index, indexer and search engine |
| `Phophy/CLIP/` | MobileCLIP encoder and tokenizer (models downloaded separately, see PLAN.md) |
| `Phophy/SearchView.swift` | Search tab |
| `Phophy/Collections/` | Automatic categories, similar photos, Collections tab |
| `Phophy/Settings/` | Settings screen and AI backend choice |
| `Phophy/Theme.swift` | Background and colour helpers |

## Privacy

Phophy reads the photo library through Apple's PhotoKit after you grant access. Indexing happens on the device. Cloud models are used only for features you invoke, and only with the photos or text that request needs.
