"""Loads descriptions written by describe_spike.py into a simulator's index,
so the evaluation can measure what descriptions add to search.

    python3 Eval/load_descriptions.py SIM_DATA_DIR APP_DATA_DIR spike.jsonl DESCRIBER_ID

Quit the app first. Pass an empty jsonl path to clear all descriptions.
"""
import json, sqlite3, sys

sim, app, path, describer = sys.argv[1:5]
photos = sqlite3.connect(f"file:{sim}/Media/PhotoData/Photos.sqlite?mode=ro", uri=True)
ids = {name: f"{uuid}/L0/001" for uuid, name in photos.execute(
    "SELECT a.ZUUID, b.ZORIGINALFILENAME FROM ZASSET a JOIN ZADDITIONALASSETATTRIBUTES b ON b.ZASSET = a.Z_PK")}
index = sqlite3.connect(f"{app}/Library/Application Support/index.sqlite")
index.execute("UPDATE asset SET caption = '', keywords = '', described_by = NULL, doc_version = 0 WHERE described_by IS NOT NULL")
loaded = 0
if path:
    for line in open(path):
        row = json.loads(line)
        parsed = row.get("parsed") or {}
        caption = (parsed.get("caption") or "").strip()
        if not caption or row["file"] not in ids: continue
        words = [parsed.get("scene", ""), parsed.get("activity", "")] + parsed.get("objects", []) + parsed.get("keywords", []) + parsed.get("keywordsChinese", [])
        keywords = ", ".join(w for w in words if isinstance(w, str) and w.strip())
        cur = index.execute("UPDATE asset SET caption = ?, keywords = ?, described_by = ?, doc_version = 0 WHERE local_id = ?",
                            (caption, keywords, describer, ids[row["file"]]))
        loaded += cur.rowcount
index.commit()
print("loaded", loaded)
