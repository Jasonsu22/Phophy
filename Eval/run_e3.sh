#!/bin/zsh
# Installs the current Debug build on a simulator holding the Flickr30k 1K
# test photos and runs experiment E3 (Chinese queries). The runner waits for
# indexing to finish first.
#   Eval/run_e3.sh <simulator-udid> [name]
set -e
SIM=$1; NAME=${2:-e3}
cd "$(dirname $0)/.."
xcrun simctl terminate $SIM app.phophy.Phophy 2>/dev/null || true
xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Phophy.app
DATA=$(xcrun simctl get_app_container $SIM app.phophy.Phophy data)
mkdir -p "$DATA/Documents"; cp Eval/e3_queries.json "$DATA/Documents/"
LOG="$DATA/Documents/$NAME.log"
rm -f "$LOG"
SIMCTL_CHILD_TZ=Asia/Hong_Kong xcrun simctl launch --terminate-running-process --stderr="$LOG" $SIM app.phophy.Phophy -PhophyE3 -describer off >/dev/null
for i in $(seq 1 720); do grep -q "E3 done" "$LOG" 2>/dev/null && break; sleep 5; done
grep -q "E3 done" "$LOG" || { echo "no result after an hour; last lines:"; tail -5 "$LOG"; exit 1; }
grep "^E3" "$LOG" | grep -v waiting
cp "$DATA/Documents/e3-results.json" "Eval/results-$NAME.json"
