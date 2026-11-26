"""Builds Eval/e3_queries.json, the Chinese-query test set for experiment E3.

    python3 Eval/e3_prepare.py path/to/test_1k_flickr.csv

Takes the two Chinese sets from Eval/eval.json (44 short concepts, 30
full sentences) and adds the human English for each query: the concept's
English name, or the Flickr30k caption the sentence was translated from.
The human English is the upper bound (a perfect translation). Machine
English versions are added by Eval/e3_translate.swift.
"""
import csv
import json
import sys

# CSV rows of the 30 hand-translated sentences, in eval.json order
# (CHINESE_SENTENCES in Eval/build_eval.py).
CHINESE_SENTENCE_INDEXES = [
    331, 970, 154, 404, 666, 49, 74, 840, 548, 96, 374, 596, 59, 931, 519,
    219, 38, 88, 444, 428, 71, 246, 92, 564, 434, 60, 846, 579, 126, 228,
]


def main(csv_path):
    rows = list(csv.DictReader(open(csv_path)))
    caps = {r["filename"]: json.loads(r["raw"]) for r in rows}
    files = [r["filename"] for r in rows]
    eval_set = json.load(open("Eval/eval.json"))
    by_name = {s["name"]: s for s in eval_set["sets"]}

    english = by_name["Objects and scenes"]["queries"]
    chinese = by_name["Objects and scenes, Chinese"]["queries"]
    assert len(english) == len(chinese)
    concepts = [
        {"zh": zh["q"], "human_en": en["q"], "relevant": zh["relevant"]}
        for en, zh in zip(english, chinese)
    ]

    sentences = []
    for query, index in zip(by_name["Detailed descriptions, Chinese"]["queries"], CHINESE_SENTENCE_INDEXES):
        file = files[index]
        assert query["relevant"] == [file], (query, file)
        sentences.append({"zh": query["q"], "human_en": caps[file][0].rstrip("."), "relevant": [file]})

    out = {
        "library": eval_set["library"],
        "sets": [
            {"name": "Objects and scenes, Chinese", "kind": "multi", "queries": concepts},
            {"name": "Detailed descriptions, Chinese", "kind": "single", "queries": sentences},
        ],
    }
    json.dump(out, open("Eval/e3_queries.json", "w"), ensure_ascii=False, indent=1)
    print(len(concepts), "concepts,", len(sentences), "sentences")


if __name__ == "__main__":
    main(sys.argv[1])
