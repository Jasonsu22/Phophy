# Assistant evaluation (E7) and cloud cost (E11)

Measures whether the assistant finishes real tasks on each backend, how
many tool calls and seconds it takes, and what each answer costs in the
cloud. Search quality alone is measured separately in `README.md` (E1).

## The task set

`agent_tasks.json` has 20 tasks about the demo library built by
`Demo/build_library.py`, whose receipts, documents, slides and screenshots
are drawn by the script. The right answers are therefore known. No one's
real photos are used.

| Type | Tasks | Passes when |
|---|---|---|
| read | 13 (9 English, 4 Chinese): totals on receipts, times on tickets, a Wi-Fi password, rent, deadlines on slides | the reply contains the right value (`answer_any`) and, where given, the right photo is shown (`shows_any`) |
| find | 3: whiteboard, offer letter, database slides (Chinese) | the right photo is among those shown |
| library | 2: where I went skiing, how many screenshots | the reply contains the right value |
| organise | 2: Tokyo trip album (English and Chinese) | the assistant offers an album (`propose_album`) |

Matching ignores case, spaces, commas and `$`, so "HK$702.00" passes for
`702` and "14,500" for `14500`.

## Running it

1. Build the demo library and add it to a simulator (see `Demo/build_library.py`), then let Phophy index it once.
2. For a cloud backend, open Settings in that simulator and save the API key for the provider. Keys stay in the simulator's Keychain and are never written to a file.
3. Build a Debug app into `build/`:
   `xcodebuild -project Phophy.xcodeproj -scheme Phophy -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build`
4. Run one backend at a time:
   - `Eval/run_agent_eval.sh <sim-udid> apple` (Apple Intelligence; needs a Mac with Apple Intelligence on)
   - `Eval/run_agent_eval.sh <sim-udid> anthropic` (default model `claude-haiku-5-5`)
   - `Eval/run_agent_eval.sh <sim-udid> openai` (default model `gpt-5-mini`)

Each run copies `agent-results-<backend>.json` and the request log into
`Eval/agent-results/` and prints the tables with `agent_report.py`.

The launch arguments `-useAppleIntelligence NO -cloudProvider openai`
override the Settings choices for one run only, because launch arguments
take priority over saved settings in `UserDefaults`.

## What is recorded

- **Per task:** pass or fail with the reasons, the reply (first 400 characters), the file names of the photos shown, albums offered, every tool called in order, seconds, tokens, and cost.
- **Per backend:** success rate, mean tool calls, mean seconds, cost per task.
- **E11 cost:** `postJSON` reads the `usage` block of every cloud response: Anthropic's `input_tokens`, `output_tokens` and `cache_*_input_tokens`, or OpenAI's `prompt_tokens`, `completion_tokens` and `cached_tokens`. The tokens from all rounds of one answer are added up and priced with `ModelPrice` in `Phophy/Assistant/UsageMeter.swift`. The app shows the total as the last step under each cloud answer. Debug builds also write one line per request to `Documents/usage-log.jsonl`. It holds token counts only, never the text.

Prices used, in US dollars per million tokens of input and output (check them before quoting):

| Model | Input | Output |
|---|---|---|
| claude-haiku-5-5 | 0.10 | 0.50 |
| gpt-5-mini | 0.25 | 2.00 |

Models without a price (for example a custom DeepSeek endpoint) still show
token counts, with the cost left blank.
