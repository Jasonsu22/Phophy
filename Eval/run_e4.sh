#!/bin/zsh
# Runs experiment E4 (vectors of the text in photos) on a simulator holding
# the Flickr30k 1K test photos plus the E4 text photos
# (Eval/e4_build_text_photos.py). The runner waits for indexing first.
#
# The iOS simulator can't load Apple's contextual embeddings, so the first
# launch exports each photo's text, Eval/e4_embed.swift computes the vector
# rankings on this Mac with the same model and method, and a second launch
# fuses them with the app's own search and scores everything.
#   Eval/run_e4.sh <simulator-udid> [name]
set -e
SIM=$1; NAME=${2:-e4}
cd "$(dirname $0)/.."
EMBED=$(mktemp -d)/e4_embed
swiftc -parse-as-library Eval/e4_embed.swift -o $EMBED
xcrun simctl terminate $SIM app.phophy.Phophy 2>/dev/null || true
xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Phophy.app
DATA=$(xcrun simctl get_app_container $SIM app.phophy.Phophy data)
mkdir -p "$DATA/Documents"; cp Eval/e4_queries.json "$DATA/Documents/"
rm -f "$DATA/Documents/e4_vectors.json" "$DATA/Documents/e4-ocr.json" "$DATA/Documents/e4-results.json"
LOG="$DATA/Documents/$NAME.log"

launch() {
  rm -f "$LOG"
  SIMCTL_CHILD_TZ=Asia/Hong_Kong xcrun simctl launch --terminate-running-process --stderr="$LOG" $SIM app.phophy.Phophy -PhophyE4 -describer off >/dev/null
  for i in $(seq 1 720); do grep -q "E4 done" "$LOG" 2>/dev/null && break; sleep 5; done
  grep -q "E4 done" "$LOG" || { echo "no result after an hour; last lines:"; tail -5 "$LOG"; exit 1; }
}

launch
if [ -f "$DATA/Documents/e4-ocr.json" ] && [ ! -f "$DATA/Documents/e4-results.json" ]; then
  $EMBED "$DATA/Documents/e4-ocr.json" "$DATA/Documents/e4_vectors.json"
  launch
fi
grep "^E4" "$LOG" | grep -v waiting
cp "$DATA/Documents/e4-results.json" "Eval/results-$NAME.json"
