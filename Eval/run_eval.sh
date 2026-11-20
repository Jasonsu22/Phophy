#!/bin/zsh
# Installs the current Debug build on a simulator and runs the search evaluation.
#   Eval/run_eval.sh <simulator-udid> [log-name]
set -e
SIM=$1; NAME=${2:-eval}
cd "$(dirname $0)/.."
xcrun simctl terminate $SIM app.phophy.Phophy 2>/dev/null || true
xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Phophy.app
DATA=$(xcrun simctl get_app_container $SIM app.phophy.Phophy data)
mkdir -p "$DATA/Documents"; cp Eval/eval.json "$DATA/Documents/"
rm -f "$DATA/Documents/$NAME.log"
xcrun simctl launch --terminate-running-process --stderr="$DATA/Documents/$NAME.log" $SIM app.phophy.Phophy -PhophyEval -describer off >/dev/null
until grep -q "EVAL done" "$DATA/Documents/$NAME.log" 2>/dev/null; do sleep 5; done
grep EVAL "$DATA/Documents/$NAME.log" | grep -v waiting
cp "$DATA/Documents/eval-results.json" "Eval/results-$NAME.json"
