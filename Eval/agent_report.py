"""Summarises assistant evaluation runs (E7) and cloud cost logs (E11).

    python3 Eval/agent_report.py Eval/agent-results

Reads every agent-results-*.json (written by the app's -PhophyAgentEval
runner) and every usage-log*.jsonl (one line per cloud request, Debug builds)
in the folder, and prints Markdown tables for the report.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path


def pct(x):
    return f"{100 * x:.0f}%"


def money(x):
    return "—" if x is None else f"${x:.5f}"


def main(folder):
    folder = Path(folder)
    runs = [json.loads(p.read_text()) for p in sorted(folder.glob("agent-results-*.json"))]
    if runs:
        print("## E7: assistant tasks per backend\n")
        print("| Backend | Success | Tool calls / task | Seconds / task | Cost / task |")
        print("|---|---|---|---|---|")
        for r in runs:
            print(f"| {r['backend']} | {r['succeeded']}/{r['tasks']} ({pct(r['success_rate'])}) "
                  f"| {r['mean_tool_calls']:.1f} | {r['mean_seconds']:.1f} | {money(r.get('cost_per_task_usd'))} |")

        print("\n### Success by language and task type\n")
        groups = sorted({(t["lang"], t["kind"]) for r in runs for t in r["results"]})
        print("| Backend | " + " | ".join(f"{l}/{k}" for l, k in groups) + " |")
        print("|---|" + "---|" * len(groups))
        for r in runs:
            cells = []
            for g in groups:
                rows = [t for t in r["results"] if (t["lang"], t["kind"]) == g]
                cells.append(f"{sum(t['ok'] for t in rows)}/{len(rows)}" if rows else "—")
            print(f"| {r['backend']} | " + " | ".join(cells) + " |")

        print("\n### Failures\n")
        for r in runs:
            for t in r["results"]:
                if not t["ok"]:
                    print(f"- **{r['backend']}** `{t['id']}`: {'; '.join(t['failed'])}")

    logs = sorted(folder.glob("usage-log*.jsonl"))
    if logs:
        print("\n## E11: cloud cost\n")
        per_answer = defaultdict(lambda: {"requests": 0, "input": 0, "output": 0, "cost": 0.0, "priced": True, "label": ""})
        for path in logs:
            for line in path.read_text().splitlines():
                if not line.strip():
                    continue
                e = json.loads(line)
                key = (e["model"], e.get("tally") or f"{path.name}:{e['time']}")
                a = per_answer[key]
                a["label"] = e["label"].split(":")[0]
                a["requests"] += 1
                a["input"] += e["input"] + e.get("cache_read", 0) + e.get("cache_write", 0)
                a["output"] += e["output"]
                if "cost_usd" in e:
                    a["cost"] += e["cost_usd"]
                else:
                    a["priced"] = False
        table = defaultdict(list)
        for (model, _), a in per_answer.items():
            table[(a["label"], model)].append(a)
        print("| What | Model | Answers | Requests / answer | Tokens in / answer | Tokens out / answer | Cost / answer | Max cost |")
        print("|---|---|---|---|---|---|---|---|")
        for (label, model), rows in sorted(table.items()):
            n = len(rows)
            priced = all(r["priced"] for r in rows)
            mean_cost = sum(r["cost"] for r in rows) / n if priced else None
            max_cost = max(r["cost"] for r in rows) if priced else None
            print(f"| {label} | {model} | {n} | {sum(r['requests'] for r in rows) / n:.1f} "
                  f"| {sum(r['input'] for r in rows) / n:,.0f} | {sum(r['output'] for r in rows) / n:,.0f} "
                  f"| {money(mean_cost)} | {money(max_cost)} |")
        print("\nTarget from the proposal: under $0.01 per assistant answer or lecture summary.")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Eval/agent-results")
