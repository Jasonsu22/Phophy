# Search evaluation

Measures how well search finds photos, so every change to the index or the
ranking is checked with numbers (experiment E1 in the proposal).

## The test set

`eval.json` is built from the **Flickr30k 1K test split**: 1,000 everyday
photos, each with five human-written captions. It's a standard benchmark for
finding images from text, so the numbers can be compared with published
work. (The photos aren't in git; they come from Hugging Face,
`nlphuji/flickr_1k_test_image_text_retrieval`, about 141 MB.)

| Set | Queries | Ground truth | Measures |
|---|---|---|---|
| Objects and scenes | 44 short searches ("dog", "wedding", "rock climbing") | every photo whose captions mention it (2 of 5 or more) | P@10, R@50, MRR |
| … in Chinese | the same 44 in Chinese ("狗", "婚礼") | same | same |
| … with typos | the same 44 misspelled ("bicyle", "resturant") | same | same |
| Detailed descriptions | 200 full captions ("A man in an orange hat starring at something") | the one photo it describes | R@1, R@5, R@10, MRR |
| … in Chinese | 30 captions translated by hand | the one photo | same |

- **P@10:** share of the top 10 that are right.
- **R@k:** share of the right photos found in the top k (single-photo sets: how often the photo is in the top k).
- **MRR:** 1 / rank of the first right photo, averaged.

Rebuild it with `python3 Eval/build_eval.py path/to/test_1k_flickr.csv`.

## Running it

1. Add the photos to a simulator: `xcrun simctl addmedia <sim> *.jpg`.
2. Install a Debug build, then copy `eval.json` into the app's Documents
   folder (`xcrun simctl get_app_container <sim> app.phophy.Phophy data`).
3. Launch with `-PhophyEval -describer off`. The app waits for indexing,
   runs every query through each setup (each layer added in turn, then a few weight choices), prints
   lines starting with `EVAL`, and writes `eval-results.json`.

## Descriptions

`describe_spike.py` writes descriptions for the test photos with a small
MLX vision model on a Mac (same request as the app), and
`load_descriptions.py` puts them into the simulator's index, so the effect
of descriptions can be measured without describing on a phone.
