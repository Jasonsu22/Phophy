"""Adds one more lecture to the demo library, photographed today, so the
video can show "the slides from today's lecture".

    python3 Demo/add_todays_lecture.py OUT_DIR
    xcrun simctl addmedia <sim> OUT_DIR/*

Reuses the drawing code of build_library.py (its helpers and slide sections).
"""
import sys
from datetime import datetime, timedelta
from pathlib import Path

source = (Path(__file__).parent / "build_library.py").read_text().splitlines()
start = next(i for i, l in enumerate(source) if l.startswith("# MARK: Everyday photos"))
slides_at = next(i for i, l in enumerate(source) if l.startswith("# MARK: Lecture slides"))
lectures_at = next(i for i, l in enumerate(source) if l.startswith("LECTURES = ["))
out = sys.argv[1]
sys.argv = [sys.argv[0], "-", "-", out]
scope = {}
exec("\n".join(source[:start] + source[slides_at:lectures_at]), scope)

COURSE = "COMP3270 Artificial Intelligence · Lecture 9"
SLIDES = [
    ("Search Problems", ["States, actions and a goal test", "A solution is a path to a goal", "Cost: the sum of step costs"]),
    ("Uninformed Search", ["BFS: shallowest node first, complete", "DFS: deepest node first, little memory", "Uniform-cost: cheapest path first"]),
    ("Heuristics", ["h(n) estimates the cost from n to a goal", "Admissible: never overestimates", "Consistent: h(n) ≤ c(n, n') + h(n')"]),
    ("A* Search", ["Expand the node with the lowest f(n) = g(n) + h(n)", "Optimal if h is admissible", "  Fewer nodes expanded with a better h"]),
    ("Minimax", ["Two players: MAX and MIN take turns", "Value of a state = best outcome for MAX", "Search the game tree to a depth limit"]),
    ("Alpha-Beta Pruning", ["Skip branches that cannot change the result", "Same answer as minimax", "  Best case: twice the depth in the same time"]),
    ("Summary", ["A* = uniform-cost + a heuristic", "Alpha-beta prunes the minimax tree", "Quiz 3: Tuesday 1 December, Lecture 8–9"]),
]
today = datetime.now().replace(hour=10, minute=35, second=0, microsecond=0)
for i, (title, lines) in enumerate(SLIDES, 1):
    img = scope["slide"](title, lines, COURSE, i)
    when = today + timedelta(minutes=6 * i + i % 3)
    scope["save"](scope["photograph"](img, 4100 + i), f"today_slide_{i:02d}.jpg", when, scope["HKU"])
print(len(SLIDES), "slides written to", out)
