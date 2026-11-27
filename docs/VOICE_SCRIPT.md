# Voice-over transcript

For the coded demo video (`Demo/video/remotion`, 2:57).

**How to record:**
- **One file per scene:** save each as `NN.m4a`, for example `05.m4a`, in `Demo/video/remotion/public/voice/`, replacing the AI file with the same number.
- **Each file:** leave about half a second of silence at the start and end.
- **"Phophy":** say it like "FOH-fee".
- **"Fits in":** the longest the scene allows. If a take runs over, the scene can be lengthened in `src/Video.tsx`.
- **When all files are in:** run this in `Demo/video/remotion`:

```bash
npx remotion render PhophyDemo ../out/phophy-coded.mp4
```

| # | Scene | Starts | Fits in | Line |
|---|---|---|---|---|
| 01 | Title | 0:00 | 6 s | This is Phophy, an iPhone app that understands your photo library. |
| 02 | The problem | 0:07 | 12 s | A phone holds thousands of photos. Finding the receipt from last week or the slide about TCP means minutes of scrolling, and sending everything to a cloud AI costs money and gives your photos away. |
| 03 | How it works | 0:19 | 14 s | Phophy reads every photo once, on the phone: the text in it, what it shows, and an embedding. A small AI model writes a short description. Search combines all of that. Nothing leaves the phone unless you choose a cloud model. |
| 04 | Library | 0:33 | 10 s | Here's the library. Open a photo and Phophy shows what it knows: where it was taken, a description written on the phone, and every word on the receipt. |
| 05 | Search by meaning | 0:44 | 13 s | Search understands what you mean. A scene, a place, even a typo or a Chinese word. Each answer takes about 20 milliseconds. |
| 06 | Words in photos | 0:57 | 11 s | It also finds words written in photos, and photos described in a sentence, like the whiteboard from our group project. |
| 07 | Collections | 1:08 | 12 s | Collections sorts the library for you: slides, receipts, documents, pets, screenshots. And it finds bursts of near-identical shots, suggesting which one to keep. |
| 08 | Study | 1:20 | 14 s | Students photograph lecture slides and never look at them again. Phophy groups them by lecture, and in a few seconds turns them into a summary, key points and flashcards, using only the text on the slides. |
| 09 | Ask: Muji | 1:34 | 7 s | You can also just ask. The assistant searches your photos with tools and reads the answer from the receipt. |
| 10 | Ask: train | 1:41 | 6 s | When does my train leave? It finds the booking screenshot and reads the time. |
| 11 | Ask: album | 1:48 | 8 s | And it can organise: here it gathers the Tokyo trip into an album, which you confirm with one tap. |
| 12 | Edit | 1:56 | 6 s | Edits work the same way: describe the change, and it runs on the phone for free. |
| 13 | Privacy | 2:03 | 12 s | Everything runs on the phone by default, with Apple Intelligence or a small open model for older iPhones. If you choose a cloud model, Phophy warns you first that your photos leave the device. |
| 14 | Results | 2:15 | 22 s | We measured search on a standard benchmark, Flickr30k. Compared with our first version, Chinese searches went from 2% to 51% correct in the top ten, misspelled searches from 13% to 59%, and objects found in the top 50 from 51% to 89%, while long descriptions stayed as accurate as before. |
| 15 | On a real iPhone | 2:38 | 11 s | On a real iPhone 13 Pro Max, without Apple Intelligence, search takes under 25 milliseconds and the on-device model describes a photo in about one and a half seconds. |
| 16 | Thank you | 2:49 | 8 s | Thank you for watching. |

Scenes 01, 10 and 12 are the tightest, at about 6 seconds each, so read those at a natural but brisk pace.
