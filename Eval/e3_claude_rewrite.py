"""Adds Claude's English rewrite to Eval/e3_queries.json (E3 condition b2).

    pip install anthropic
    ANTHROPIC_API_KEY=... python3 Eval/e3_claude_rewrite.py

Uses the app's default assistant model and the same instruction as the
on-device rewrite in Eval/e3_translate.swift. 74 short requests; with
Claude Haiku 5.5 the whole run costs well under one cent. The key is read
from the environment and never written anywhere.
"""
import json

import anthropic

MODEL = "claude-haiku-5-5"
INSTRUCTIONS = (
    "You turn a photo search typed by the user into what a photo search tool needs: "
    "a short English description of what the photo shows or the words in it. "
    "Keep every detail the user gave and add nothing. Reply with the description only."
)
PATH = "Eval/e3_queries.json"


def main():
    client = anthropic.Anthropic()
    data = json.load(open(PATH))
    tokens_in = tokens_out = 0
    for query_set in data["sets"]:
        for q in query_set["queries"]:
            response = client.messages.create(
                model=MODEL,
                max_tokens=256,
                system=INSTRUCTIONS,
                output_config={"effort": "low"},
                messages=[{"role": "user", "content": f"The user searched: {q['zh']}"}],
            )
            if response.stop_reason == "refusal":
                q["claude_rewrite_error"] = "refusal"
                continue
            text = "".join(b.text for b in response.content if b.type == "text").strip().strip('"“”.')
            q["claude_rewrite"] = text
            tokens_in += response.usage.input_tokens
            tokens_out += response.usage.output_tokens
            print(f"{q['zh']} → {text}")
    data["claude_model"] = MODEL
    json.dump(data, open(PATH, "w"), ensure_ascii=False, indent=1, sort_keys=True)
    cost = tokens_in * 0.10 / 1e6 + tokens_out * 0.50 / 1e6
    print(f"{tokens_in} tokens in, {tokens_out} out, about ${cost:.4f}")


if __name__ == "__main__":
    main()
