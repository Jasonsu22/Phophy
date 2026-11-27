# Demo video plan

About 7 minutes, recorded in the iOS simulator ("Phophy Demo", iPhone 18 Pro Max, iOS 27.2) on the demo library from `Demo/build_library.py`: 153 photos, slides, receipts, screenshots and videos, all dated and placed as if taken in Hong Kong, Tokyo and Zermatt. Nobody's real photos appear.

## How it's made

1. **Screen footage.** Each scene is recorded on its own with `xcrun simctl io <sim> recordVideo`, while the app is driven step by step. The app runs in Hong Kong time (`SIMCTL_CHILD_TZ=Asia/Hong_Kong`). Chinese queries are filled in with `-PhophySearchQuery`, because the simulator can't type them.
2. **Title and diagram cards.** Five still cards (1920×1080): title, the problem, how it works (from `docs/architecture.svg`), results, team.
3. **Voice-over.** Read from the script below, one clip per scene, so a scene can be re-recorded alone. Each member can voice their own part.
4. **Edit.** Phone footage sits centred on a dark background next to a caption, cards in between, then voice and quiet music. Assembled with `ffmpeg` into one 1080p MP4, or in iMovie if you'd rather edit by hand.

## Script

| # | Time | On screen | Voice-over |
|---|---|---|---|
| 1 | 0:00 | Title card: "Phophy: find anything in your photos, on your iPhone" | "This is Phophy, an iPhone app that understands your photo library, " |
| 2 | 0:10 | Problem card: thousands of photos, receipts, slides, screenshots | "A phone holds thousands of photos. Finding the receipt from last week or the slide about TCP means minutes of scrolling, and sending everything to a cloud AI costs money and gives your photos away." |
| 3 | 0:30 | How it works card (architecture) | "Phophy reads every photo once, on the phone: the text in it, what it shows, and an embedding. A small AI model writes a short description. Search combines all of that. Nothing leaves the phone unless you choose a cloud model." |
| 4 | 0:55 | App: Library, scroll Recents, open a receipt, info sheet (where, description, text) | "Here's the library. Open a photo and Phophy shows what it knows: where it was taken, a description written on the phone, and every word on the receipt." |
| 5 | 1:20 | Search: "dog on the beach" → "Tokyo" → "bicyle" (typo) → "狗" | "Search understands what you mean. A scene, a place, even a typo or a Chinese word. Each answer takes about 20 milliseconds." |
| 6 | 1:55 | Search: "G1234", "receipt from Muji", "whiteboard with the network diagram" | "It also finds words written in photos, and photos described in a sentence, like the whiteboard from our group project." |
| 7 | 2:20 | Collections: categories, then Similar photos | "Collections sorts the library for you: slides, receipts, documents, pets, screenshots. And it finds bursts of near-identical shots, suggesting which one to keep." |
| 8 | 2:50 | Study: three lectures → open TCP lecture → Make notes → summary, key points, flashcards | "Students photograph lecture slides and never look at them again. Phophy groups them by lecture, and in a few seconds turns them into a summary, key points and flashcards, using only the text on the slides." |
| 9 | 3:40 | Assistant: "How much did I spend at Muji?" → HK$702 | "You can also just ask. The assistant searches your photos with tools and reads the answer from the receipt." |
| 10 | 4:05 | Assistant: "When does my train to Shanghai leave?" → 08:15 | "When does my train leave? It finds the booking screenshot and reads the time." |
| 11 | 4:25 | Assistant: "Put my photos from the Tokyo trip in an album" → Save album | "And it can organise: here it gathers the Tokyo trip into an album, which you confirm with one tap." |
| 12 | 4:50 | Editor: open a beach photo, type "warmer and brighter", Done | "Edits work the same way: describe the change, and it runs on the phone for free." |
| 13 | 5:10 | Settings: who describes photos, the cloud warning alert | "Everything runs on the phone by default, with Apple Intelligence or a small open model for older iPhones. If you choose a cloud model, Phophy warns you first that your photos leave the device." |
| 14 | 5:35 | Results card: search before and after | "We measured search on a standard benchmark, Flickr30k. Compared with our first version, Chinese searches went from 2% to 51% correct in the top ten, misspelled searches from 13% to 59%, and objects found in the top 50 from 51% to 89%, while long descriptions stayed as accurate as before." |
| 15 | 6:10 | Results card: speed on an iPhone 13 Pro Max | "On a real iPhone 13 Pro Max, without Apple Intelligence, search takes under 25 milliseconds and the on-device model describes a photo in about one and a half seconds." |
| 16 | 6:35 | Closing card | "Thank you for watching." |

## Before recording

- Rebuild the demo library (one slide symbol fixed), erase the demo simulator, add the library, then let Phophy index and describe it (about 20 minutes).
- Make notes for two lectures ahead of time; leave the TCP lecture without notes, so scene 8 shows them being made live.
- Leave Favorites empty and no albums, so scene 11 creates the first one.
- Simulator limits to avoid on camera: background removal and blur need a real iPhone (subject detection), so the editor scene shows colour and light only.

## Draft (22 Nov)

`Demo/video/out/phophy-demo.mp4`, 5:06, with a synthetic voice (macOS "Samantha"). To rebuild:

1. `python3 Demo/video/make_cards.py Demo/video/out/cards Demo/video/out/cards/architecture.svg.png` draws the cards.
2. Screen clips are in `Demo/video/out/raw/NN.mov`, recorded with `Demo/video/record.sh start NN` / `stop`. `NN-end.png` is a screenshot of the scene's final screen, added as a still because the recorder drops the last frames.
3. `python3 Demo/video/assemble.py` builds the video, plus a reference copy with each line on screen (`phophy-demo-reference.mp4`), subtitles (`phophy-demo.srt`) and a recording sheet (`RECORDING_SHEET.md`) in the same folder.

**To use your own voices:** record each scene's line from `Demo/video/script.json` as `Demo/video/out/voice/NN.m4a` (any of m4a, wav, mp3), delete the matching `NN.aiff`, and run step 3 again. Scene lengths follow the new recordings.

## Decisions for you

- **Voice:** the draft uses a synthetic voice; replace any scene with your own recording as above.
- **Language:** English throughout, with Chinese searches shown on screen.
