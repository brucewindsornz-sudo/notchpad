#!/bin/bash
# End-to-end checks for NotchPad's closing animations on a real Mac.
#   tests/close-effects.sh /path/to/NotchPad.app
# Optional: set CLOSE_FRAMES_OUT=/path/to/dir to copy the rendered frame PNGs out of the sandbox.
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 /path/to/NotchPad.app"
  exit 2
fi

APP_BUNDLE="${1%/}"
APP_BIN="$APP_BUNDLE/Contents/MacOS/NotchPad"
EFFECTS=(lightning matrix teleport stargate blackHole tv dust burn)
FRAMES_PER_EFFECT=12
EXPECTED_FRAMES=$(( ${#EFFECTS[@]} * FRAMES_PER_EFFECT ))

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/notchpad-close-ci.XXXXXX")
APP_PID=""

stop_app() {
  pkill -x NotchPad 2>/dev/null || true
  APP_PID=""
  sleep 1
}

fail() {
  echo "FAILED: $1"
  for f in "$LOG_DIR"/*.log; do
    [ -f "$f" ] || continue
    echo "--- $(basename "$f")"
    cat "$f"
  done
  stop_app
  rm -rf "$LOG_DIR"
  exit 1
}

launch() {   # launch <log> [extra env...]
  local log=$1; shift
  stop_app
  : > "$log"
  env -u NOTCHPAD_NO_EFFECTS NOTCHPAD_DEBUG=1 "$@" "$APP_BIN" 2> "$log" &
  APP_PID=$!
}

wait_for() {   # wait_for <log> <extended-regex> <timeout-seconds>
  local log=$1 pat=$2 limit=$3 elapsed=0
  local steps=$((limit * 4))
  while [ "$elapsed" -lt "$steps" ]; do
    if grep -Eq "$pat" "$log" 2>/dev/null; then
      return 0
    fi
    if [ -n "${APP_PID:-}" ] && ! kill -0 "$APP_PID" 2>/dev/null; then
      sleep 0.2
      grep -Eq "$pat" "$log" 2>/dev/null && return 0
      fail "NotchPad exited before pattern '$pat' appeared in $(basename "$log")"
    fi
    sleep 0.25
    elapsed=$((elapsed + 1))
  done
  fail "Timed out after ${limit}s waiting for '$pat' in $(basename "$log")"
}

[ -x "$APP_BIN" ] || fail "App binary not found or not executable: $APP_BIN"

echo "== a. Render $FRAMES_PER_EFFECT still frames for each of the ${#EFFECTS[@]} closing animations"
LOG_A="$LOG_DIR/a-frames.log"
launch "$LOG_A" NOTCHPAD_DEBUG_CLOSE_FRAMES="$FRAMES_PER_EFFECT"
wait_for "$LOG_A" "^NOTCHPAD_CLOSE_FRAMES dir=.+ count=[0-9]+$" 30
FRAME_LINE=$(grep -E "^NOTCHPAD_CLOSE_FRAMES dir=.+ count=[0-9]+$" "$LOG_A" | tail -1)
FRAME_DIR=$(printf '%s\n' "$FRAME_LINE" | sed 's/^NOTCHPAD_CLOSE_FRAMES dir=\(.*\) count=[0-9][0-9]*$/\1/')
FRAME_COUNT=$(printf '%s\n' "$FRAME_LINE" | sed 's/.* count=\([0-9][0-9]*\)$/\1/')
pgrep -x NotchPad >/dev/null || fail "NotchPad crashed after rendering close frames"
stop_app

[ "$FRAME_COUNT" = "$EXPECTED_FRAMES" ] || fail "Expected count=$EXPECTED_FRAMES, got count=$FRAME_COUNT ($FRAME_LINE)"
[ -d "$FRAME_DIR" ] || fail "Frame directory does not exist: $FRAME_DIR"

ACTUAL_PNGS=$(find "$FRAME_DIR" -type f -name '*.png' | wc -l | tr -d ' ')
[ "$ACTUAL_PNGS" = "$EXPECTED_FRAMES" ] || fail "Expected $EXPECTED_FRAMES PNGs in $FRAME_DIR, found $ACTUAL_PNGS"

EMPTY_PNGS=$(find "$FRAME_DIR" -type f -name '*.png' -size 0 | wc -l | tr -d ' ')
[ "$EMPTY_PNGS" = 0 ] || fail "Found $EMPTY_PNGS empty PNG file(s) in $FRAME_DIR"

for fx in "${EFFECTS[@]}"; do
  FX_PNGS=$(find "$FRAME_DIR" -type f -path "*${fx}*" -name '*.png' | wc -l | tr -d ' ')
  [ "$FX_PNGS" = "$FRAMES_PER_EFFECT" ] || fail "Expected $FRAMES_PER_EFFECT PNGs for effect '$fx', found $FX_PNGS in $FRAME_DIR"
done
echo "OK: rendered $ACTUAL_PNGS non-empty frame PNGs ($FRAMES_PER_EFFECT per effect) in $FRAME_DIR"

if [ -n "${CLOSE_FRAMES_OUT:-}" ]; then
  rm -rf "$CLOSE_FRAMES_OUT"
  mkdir -p "$CLOSE_FRAMES_OUT" || fail "Could not create CLOSE_FRAMES_OUT: $CLOSE_FRAMES_OUT"
  cp -R "$FRAME_DIR"/. "$CLOSE_FRAMES_OUT"/ || fail "Could not copy frames to $CLOSE_FRAMES_OUT"
  echo "OK: copied frame PNGs to $CLOSE_FRAMES_OUT"
fi

echo "== b. Play each closing animation through the real open/close path"
for fx in "${EFFECTS[@]}"; do
  LOG_FX="$LOG_DIR/b-${fx}.log"
  launch "$LOG_FX" \
    NOTCHPAD_DEBUG_OPEN=1 \
    NOTCHPAD_DEBUG_CLOSE="$fx" \
    NOTCHPAD_DEBUG_CLOSE_AFTER=3
  wait_for "$LOG_FX" "^NOTCHPAD_CLOSE effect=${fx}( |$)" 15
  wait_for "$LOG_FX" "^NOTCHPAD_CLOSE_DONE effect=${fx}( |$)" 15
  pgrep -x NotchPad >/dev/null || fail "NotchPad crashed after closing animation '$fx'"
  stop_app
  echo "OK: $fx started and finished cleanly"
done

echo "== c. NOTCHPAD_NO_EFFECTS=1 skips closing animations and uses classic close"
LOG_C="$LOG_DIR/c-no-effects.log"
stop_app
: > "$LOG_C"
env NOTCHPAD_DEBUG=1 NOTCHPAD_NO_EFFECTS=1 \
  NOTCHPAD_DEBUG_OPEN=1 \
  NOTCHPAD_DEBUG_CLOSE=matrix \
  NOTCHPAD_DEBUG_CLOSE_AFTER=3 \
  "$APP_BIN" 2> "$LOG_C" &
APP_PID=$!
wait_for "$LOG_C" "^NOTCHPAD_STATE=collapsed$" 15
sleep 1
pgrep -x NotchPad >/dev/null || fail "NotchPad crashed under NOTCHPAD_NO_EFFECTS=1"
grep -q "^NOTCHPAD_CLOSE effect=" "$LOG_C" && fail "Close animation ran despite NOTCHPAD_NO_EFFECTS=1"
stop_app
echo "OK: NOTCHPAD_NO_EFFECTS=1 skipped close animation"

rm -rf "$LOG_DIR"
echo "All close-effects checks passed"
