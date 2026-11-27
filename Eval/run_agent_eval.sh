#!/bin/zsh
# Installs the current Debug build on a simulator and runs the assistant
# evaluation (E7) on one backend. The demo library must already be in the
# simulator (Demo/build_library.py), and for cloud backends the API key
# must be saved in Settings on that simulator.
#   Eval/run_agent_eval.sh <simulator-udid> apple
#   Eval/run_agent_eval.sh <simulator-udid> anthropic
#   Eval/run_agent_eval.sh <simulator-udid> openai
set -e
SIM=$1; BACKEND=${2:-apple}
cd "$(dirname $0)/.."
case $BACKEND in
  apple) ARGS=(-useAppleIntelligence YES) ;;
  anthropic|openai|custom) ARGS=(-useAppleIntelligence NO -allowCloudAI YES -cloudProvider $BACKEND) ;;
  *) echo "backend must be apple, anthropic, openai or custom"; exit 1 ;;
esac
xcrun simctl terminate $SIM app.phophy.Phophy 2>/dev/null || true
xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Phophy.app
DATA=$(xcrun simctl get_app_container $SIM app.phophy.Phophy data)
mkdir -p "$DATA/Documents"; cp Eval/agent_tasks.json "$DATA/Documents/"
LOG="$DATA/Documents/agent-$BACKEND.log"
rm -f "$LOG"
# Hong Kong time, as in the demo video, so "last week" means the same thing every run.
SIMCTL_CHILD_TZ=Asia/Hong_Kong xcrun simctl launch --terminate-running-process --stderr="$LOG" $SIM app.phophy.Phophy -PhophyAgentEval "${ARGS[@]}" >/dev/null
for i in $(seq 1 360); do grep -q "AGENT done" "$LOG" 2>/dev/null && break; sleep 5; done
grep -q "AGENT done" "$LOG" || { echo "no result after 30 minutes; last lines:"; tail -5 "$LOG"; exit 1; }
grep AGENT "$LOG" | grep -v waiting
mkdir -p Eval/agent-results
cp "$DATA"/Documents/agent-results-*.json Eval/agent-results/ 2>/dev/null || true
cp "$DATA/Documents/usage-log.jsonl" "Eval/agent-results/usage-log-$BACKEND.jsonl" 2>/dev/null || true
python3 Eval/agent_report.py Eval/agent-results
