# Progress log: Qin Mengmeng (Track B: search and assistant)

Owner: Qin Mengmeng (GitHub `MJoy519`) · Team 26, COMP7607 · Last updated: **27 Nov 2026**

Track B covers search quality, the search evaluation set, Chinese queries,
the assistant's tools and backends, and cloud cost. Its experiments in the
proposal are **E1, E3, E4, E7, E11**. Code owned: `Phophy/Assistant/`,
`Phophy/Index/SearchEngine.swift`, `Eval/`.

## Deadlines

| Date (HKT) | What | Track B input |
|---|---|---|
| 28 Nov | Results handed to whoever edits the video | E7 and E11 numbers, one search before/after slide |
| **29 Nov 23:59** | `Team26.zip`: 5-minute pre-recorded video (we present **online**) | Scenes 9–11 (assistant) and 14 (search results) |
| **15 Dec 23:59** | Final report | Methods and results sections for E1, E3, E4, E7, E11 |

## Status

| Item | Status | Where |
|---|---|---|
| E1 hybrid vs keyword vs CLIP search | ✅ Done by the lead on Flickr30k (1K test split) | `Eval/README.md`, `Eval/results-*.json` |
| E11 cloud cost logging | 🟡 Code builds; price maths checked on macOS; not yet run in the app | `Phophy/Assistant/UsageMeter.swift`, `postJSON` in `CloudAssistant.swift` |
| E7 assistant tasks per backend | 🟡 Task set, runner and report written; app builds; not yet run | `Eval/agent_tasks.json`, `Phophy/Debug/AgentEvaluation.swift`, `Eval/run_agent_eval.sh`, `Eval/agent_report.py`, `Eval/AGENT_EVAL.md` |
| E3 Chinese queries | ⏳ Next. Short Chinese words work (P@10 0.51), Chinese full captions do not (R@5 0.60 against 0.94 in English) | Plan below |
| E4 OCR text embeddings | ⏳ After E3; needs an index column, to be agreed with the lead and Track A | `IndexStore.swift` (lead-owned) |
| Bugs #7, #8, #9, #13 (TEAM_PLAN.md) | ⏳ Not started | |

## Environment

- [x] Repository cloned to `~/NLP/Phophy`; commits use the GitHub noreply address
- [x] Write access to `Jasonsu22/Phophy` confirmed
- [x] MobileCLIP S0 image and text models downloaded into `Phophy/CLIP/Models/` (ignored by git)
- [x] Xcode 27.2 installed
- [x] Xcode licence accepted
- [x] Xcode first-launch components (`sudo xcodebuild -runFirstLaunch`)
- [x] Metal Toolchain downloaded; Swift packages resolved
- [ ] iOS 27.2 simulator runtime for iPhone 18 Pro Max (the lead's demo device). The general runtime (24B8117) got mounted twice when two downloads ran at once and shows as malformed; a restart of the Mac should clear the stale mount. Only the iPhone Duo runtime (24B91016s) works for now.
- [x] First Debug build for the iOS Simulator: **BUILD SUCCEEDED**, no errors and no warnings in the new code (27 Nov)
- [x] Flickr30k 1K test photos downloaded to `~/NLP/data/flickr1k` (outside git)
- [x] Demo library built with `Demo/build_library.py` into `~/NLP/data/demo-library` (158 files: 124 photos, the rest drawn)
- [x] Demo library indexed on a test simulator (iPhone Duo): 162 photos with OCR and embeddings; receipt text reads correctly
- [ ] Same on an iPhone 18 Pro Max simulator
- [ ] Apple Intelligence in the simulator: **blocked on this Mac.** Apple Intelligence is on, but every request fails with `Model Catalog error (UnifiedAssetFramework 5000, no underlying assets)`. Likely cause: the Mac runs macOS 26.6, while the iOS 27.2 simulator's Foundation Models need the macOS 27 model assets (the lead's Mac and CI run macOS 27). Plan: the lead runs the Apple Intelligence group; this Mac runs the cloud groups.
- [ ] API keys for Claude and OpenAI saved in the simulator's Settings (never in git)

## Work log

### 27 Nov 2026

- Checked the state of the repository. Every commit so far is by the lead.
  The newest work is on `photo-descriptions` (11 commits ahead of `main`,
  including the search changes), so Track B branches from there.
- Branch `b-e11-e7-assistant-eval` (from `origin/photo-descriptions`).
- **E11:**
  - `TokenUsage` reads the `usage` block of Anthropic and OpenAI-compatible responses.
  - `UsageTally` adds up all the rounds of one answer.
  - `ModelPrice` prices them: Claude Haiku 5.5 at $0.10/$0.50 and GPT-5 mini at $0.25/$2.00 per million input/output tokens.
  - Each cloud answer now shows a last step such as "Cloud: 3,120 tokens in, 85 out · about $0.0004".
  - Debug builds log token counts per request to `usage-log.jsonl`.
  - Lecture digests go through the same `postJSON`, so their cost is logged too.
- **E7:**
  - 20 tasks on the demo library: 14 English, 6 Chinese; read, find, library and organise types.
  - A `-PhophyAgentEval` runner asks each task in a fresh conversation on the selected backend and checks the reply, the photos shown and any album offered. It records the tool calls, time and cost.
  - `PhotoToolbox` now keeps a log of the tools called in each turn.
  - `agent_report.py` prints the E7 and E11 tables in Markdown.
- Checked `UsageMeter.swift` with a small macOS test program: Anthropic and OpenAI usage blocks parse correctly, and a Haiku plus GPT-5 mini mix prices to $0.000695 as worked out by hand.
- Touched one lead-owned file: `RootView.swift`, one Debug-only line to start the runner. This needs a heads-up in the team chat and the PR.

### 27 Nov 2026 (evening)

- First E7 run on Apple Intelligence: 0/20, all with `Model Catalog error ... com.apple.modelcatalog`. The simulator could not load Apple's on-device model, so the run says nothing about the assistant and was discarded. The same cause explains why no photo descriptions were written during indexing.
- Added Hong Kong time and a 30-minute timeout to `Eval/run_agent_eval.sh`.
- The simulator was in Chinese, so Apple Maps returned Chinese place names (香港大學) and "Where did I go skiing?" could never match "Zermatt". Switched the test simulator to English with the Hong Kong region, as on the lead's, and rebuilt the index: place names are now English (The University of Hong Kong, Central, Mong Kok). **Run E7 with an English simulator.**
- Second Apple Intelligence run after the language change: same model error, 0/20, discarded. See Environment.

- Opened [Jasonsu22/Phophy#2](https://github.com/Jasonsu22/Phophy/pull/2) (E11 + E7 + this log) into `photo-descriptions`, as three commits.

## Next steps

1. Finish the iOS simulator download; build the demo library (`Demo/build_library.py`) and add it to a simulator.
2. Run E7 and E11 on Claude Haiku 5.5 and GPT-5 mini (and Apple Intelligence if the Mac supports it); put the tables below.
3. ~~Open a PR for review.~~ Done: [Jasonsu22/Phophy#2](https://github.com/Jasonsu22/Phophy/pull/2) into `photo-descriptions`. Waiting for the lead's review, and asking the lead to run the Apple Intelligence group on macOS 27.
4. E3: compare (a) no handling, (b) the assistant rewrites the query in English, (c) on-device translation (Apple's Translation framework) before the CLIP text encoder, on the two Chinese query sets in `Eval/eval.json`.

## Results

*Filled in after the first runs.*

### E7: assistant tasks

| Backend | Success | Tool calls / task | Seconds / task | Cost / task |
|---|---|---|---|---|
| Apple Intelligence | | | | free |
| Claude Haiku 5.5 | | | | |
| GPT-5 mini | | | | |

### E11: cloud cost

| What | Model | Cost / answer | Target |
|---|---|---|---|
| Assistant answer | Claude Haiku 5.5 | | < $0.01 |
| Assistant answer | GPT-5 mini | | < $0.01 |
| Lecture summary | | | < $0.01 |
