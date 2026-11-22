#!/bin/zsh
# Records the demo simulator's screen, one scene at a time.
#   Demo/video/record.sh start 05     starts Demo/video/out/raw/05.mov
#   Demo/video/record.sh stop         stops the recording
SIM=${PHOPHY_SIM:-4EF13E27-49C0-47D2-8539-D71C07ED45F5}
DIR="$(dirname $0)/out/raw"; mkdir -p "$DIR"
PIDFILE="$DIR/.recording"
case $1 in
  start)
    xcrun simctl io $SIM recordVideo --codec=h264 --force "$DIR/$2.mov" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"; sleep 1.5 ;;
  stop)
    [ -f "$PIDFILE" ] && kill -INT $(cat "$PIDFILE") && rm "$PIDFILE"; sleep 2 ;;
esac
