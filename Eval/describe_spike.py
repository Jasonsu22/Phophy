"""Day-2 spike: describe the Flickr test photos with a small MLX vision model
on a Mac, with the same instructions the app uses, and record speed.

    python Eval/describe_spike.py MODEL_ID IMAGE_DIR OUT.jsonl [LIMIT]

The output can be loaded into the simulator's index to measure what
descriptions add to search (Eval/load_descriptions.py).
"""
import json, os, re, sys, time
from mlx_vlm import load, generate
from mlx_vlm.prompt_utils import apply_chat_template
from mlx_vlm.utils import load_config
from PIL import Image

INSTRUCTIONS = ("You describe photos for a photo search index. Be literal and specific: name "
    "objects, colours, clothing, animals, food, signs, landmarks and activities you can actually see. "
    "Never guess names of people. Keep every field short.")
PROMPT = ('Describe this photo for a search index. Reply with JSON only, no other text, in exactly this shape: '
    '{"caption": "one sentence, at most 20 words", "objects": ["up to 10 short nouns"], "scene": "2-3 words", '
    '"activity": "a few words or empty", "keywords": ["up to 10 English search words"], '
    '"keywordsChinese": ["the same search words in Simplified Chinese"]}')

# Small models can't follow a JSON template; they get a plain request.
PLAIN = ("Describe this photo in two short sentences. Name the main objects, their colours, "
    "the place, and what any people or animals are doing.")
MODE = os.environ.get("MODE", "plain")
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "80"))

model_id, image_dir, out_path = sys.argv[1:4]
limit = int(sys.argv[4]) if len(sys.argv) > 4 else 10**9
model, processor = load(model_id)
config = load_config(model_id)
done = set()
if os.path.exists(out_path):
    done = {json.loads(l)["file"] for l in open(out_path)}
files = sorted(f for f in os.listdir(image_dir) if f.endswith(".jpg"))[:limit]
out = open(out_path, "a")
for name in files:
    if name in done: continue
    img = Image.open(os.path.join(image_dir, name)).convert("RGB")
    img.thumbnail((448, 448))
    request = PLAIN if MODE == "plain" else INSTRUCTIONS + "\n\n" + PROMPT
    prompt = apply_chat_template(processor, config, request, num_images=1)
    t = time.time()
    result = generate(model, processor, prompt, [img], max_tokens=MAX_TOKENS, temperature=0.0, verbose=False)
    text = result.text if hasattr(result, "text") else str(result)
    ms = (time.time() - t) * 1000
    m = re.search(r"\{.*\}", text, re.S) if MODE != "plain" else None
    parsed = {"caption": text.strip()} if MODE == "plain" else None
    if m:
        try: parsed = json.loads(m.group(0))
        except Exception: parsed = None
    out.write(json.dumps({"file": name, "ms": round(ms), "raw": text, "parsed": parsed}, ensure_ascii=False) + "\n")
    out.flush()
    print(name, round(ms), (parsed or {}).get("caption", text[:80]), flush=True)
