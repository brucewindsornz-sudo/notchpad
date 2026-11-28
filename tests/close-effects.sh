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
EFFECTS=(lightning matrix teleport stargate blackHole tv dust burn glitch shatter hyperspace melt)
FRAMES_PER_EFFECT=12
EXPECTED_FRAMES=$(( ${#EFFECTS[@]} * FRAMES_PER_EFFECT ))

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/notchpad-close-ci.XXXXXX")
APP_PID=""
P="$HOME/Library/Containers/com.newzeebuild.notchpad/Data/Library/Preferences/com.newzeebuild.notchpad"
keys=(rememberLayout detached offsetX offsetY closeOnClickOutside openOnHover keepOpen wasOpen hideFromCapture lockEnabled)
types=(bool bool float float bool bool bool bool bool bool)
saved=()
configured=0

restore_preferences() {
  [ "$configured" = 1 ] || return 0
  local i value
  for ((i=0; i<${#keys[@]}; i++)); do
    value=${saved[$i]}
    if [ -n "$value" ]; then
      if [ "${types[$i]}" = bool ]; then
        case "$value" in 0) value=false ;; 1) value=true ;; esac
      fi
      defaults write "$P" "${keys[$i]}" "-${types[$i]}" "$value" >/dev/null 2>&1 ||
        echo "Could not restore the NotchPad preference '${keys[$i]}'." >&2
    else
      defaults delete "$P" "${keys[$i]}" >/dev/null 2>&1 || true
    fi
  done
}
trap restore_preferences EXIT

stop_app() {
  if [ -n "$APP_PID" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
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
  env -u NOTCHPAD_NO_EFFECTS -u NOTCHPAD_ALLOW_CAPTURE NOTCHPAD_DEBUG=1 NOTCHPAD_DEBUG_FORCE_MOTION=1 "$@" "$APP_BIN" 2> "$log" &
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
mkdir -p "$(dirname "$P")" || fail "Could not open the NotchPad preferences folder"
for key in "${keys[@]}"; do saved+=("$(defaults read "$P" "$key" 2>/dev/null || true)"); done
configured=1
for key in detached closeOnClickOutside openOnHover keepOpen wasOpen lockEnabled; do
  defaults write "$P" "$key" -bool false || fail "Could not set $key for test"
done
for key in rememberLayout hideFromCapture; do
  defaults write "$P" "$key" -bool true || fail "Could not set $key for test"
done

echo "== a. Render $FRAMES_PER_EFFECT still frames for each of the ${#EFFECTS[@]} closing animations"
LOG_A="$LOG_DIR/a-frames.log"
launch "$LOG_A" NOTCHPAD_DEBUG_CLOSE_FRAMES="$FRAMES_PER_EFFECT"
wait_for "$LOG_A" "^NOTCHPAD_CLOSE_FRAMES dir=.+ count=[0-9]+$" 180
FRAME_LINE=$(grep -E "^NOTCHPAD_CLOSE_FRAMES dir=.+ count=[0-9]+$" "$LOG_A" | tail -1)
FRAME_DIR=$(printf '%s\n' "$FRAME_LINE" | sed 's/^NOTCHPAD_CLOSE_FRAMES dir=\(.*\) count=[0-9][0-9]*$/\1/')
FRAME_COUNT=$(printf '%s\n' "$FRAME_LINE" | sed 's/.* count=\([0-9][0-9]*\)$/\1/')
kill -0 "$APP_PID" 2>/dev/null || fail "NotchPad crashed after rendering close frames"
stop_app

[ "$FRAME_COUNT" = "$EXPECTED_FRAMES" ] || fail "Expected count=$EXPECTED_FRAMES, got count=$FRAME_COUNT ($FRAME_LINE)"
[ -d "$FRAME_DIR" ] || fail "Frame directory does not exist: $FRAME_DIR"

ACTUAL_PNGS=$(find "$FRAME_DIR" -type f -name '*.png' | wc -l | tr -d ' ')
[ "$ACTUAL_PNGS" = "$EXPECTED_FRAMES" ] || fail "Expected $EXPECTED_FRAMES PNGs in $FRAME_DIR, found $ACTUAL_PNGS"

EMPTY_PNGS=$(find "$FRAME_DIR" -type f -name '*.png' -size 0 | wc -l | tr -d ' ')
[ "$EMPTY_PNGS" = 0 ] || fail "Found $EMPTY_PNGS empty PNG file(s) in $FRAME_DIR"

for fx in "${EFFECTS[@]}"; do
  FX_PNGS=$(find "$FRAME_DIR" -type f -name "${fx}-*.png" | wc -l | tr -d ' ')
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
  wait_for "$LOG_FX" "^NOTCHPAD_CLOSE_DONE effect=${fx} frames=[1-9][0-9]* seconds=[0-9.]+ worst_ms=[0-9.]+ avg_ms=[0-9.]+$" 15
  kill -0 "$APP_PID" 2>/dev/null || fail "NotchPad crashed after closing animation '$fx'"
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
kill -0 "$APP_PID" 2>/dev/null || fail "NotchPad crashed under NOTCHPAD_NO_EFFECTS=1"
grep -q "^NOTCHPAD_CLOSE effect=" "$LOG_C" && fail "Close animation ran despite NOTCHPAD_NO_EFFECTS=1"
stop_app
echo "OK: NOTCHPAD_NO_EFFECTS=1 skipped close animation"

start_sequence() {
  local log=$1 sequence=$2; shift 2
  launch "$log" NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_CLOSE=matrix NOTCHPAD_DEBUG_CLOSE_FREEZE=0.5 \
    NOTCHPAD_DEBUG_CLOSE_SEQUENCE="$sequence" "$@"
}

probe() {
  local log=$1 stage=$2 state=$3 details=$4
  wait_for "$log" "^NOTCHPAD_CLOSE_PROBE stage=$stage state=$state visible=true overlay=false $details$" 12
}

echo "== d. Rapid toggles, hover-open and pinned close/reopen"
LOG="$LOG_DIR/d-reopen.log"
start_sequence "$LOG" '2:toggle,2.07:toggle,2.18:toggle,2.25:toggle,2.5:probe-fast,2.65:toggle,2.78:hover,3.2:probe-hover,3.25:pin,3.4:toggle,3.55:screen,3.7:probe-pinnedclosed,3.85:toggle,4:probe-pinnedopen'
wait_for "$LOG" '^NOTCHPAD_CLOSE_CANCEL reason=open overlay=false$' 12
wait_for "$LOG" '^NOTCHPAD_CLOSE_CANCEL reason=hover overlay=false$' 12
probe "$LOG" fast expanded 'floating=false home=true pinned=false wasOpen=false private=true interactive=true'
probe "$LOG" hover expanded 'floating=false home=true pinned=false wasOpen=false private=true interactive=true'
probe "$LOG" pinnedclosed collapsed 'floating=false home=true pinned=true wasOpen=false private=true interactive=false'
probe "$LOG" pinnedopen expanded 'floating=false home=true pinned=true wasOpen=true private=true interactive=true'
stop_app
defaults write "$P" keepOpen -bool false && defaults write "$P" wasOpen -bool false &&
  defaults write "$P" openOnHover -bool false || fail "Could not clear pinned/hover test settings"

echo "== e. Display change, capture privacy changes and screen lock"
LOG="$LOG_DIR/e-surfaces.log"
start_sequence "$LOG" '2:toggle,2.15:screen,2.3:probe-screen,2.45:toggle,2.6:toggle,2.75:public,2.9:probe-public,3.05:toggle,3.2:toggle,3.35:private,3.5:probe-private,3.65:toggle,3.8:toggle,3.95:lock,4.1:probe-lock,4.25:toggle,4.4:lock,4.55:probe-lockopen'
wait_for "$LOG" '^NOTCHPAD_CLOSE effect=matrix .* private=true$' 12
wait_for "$LOG" '^NOTCHPAD_CLOSE effect=matrix .* private=false$' 12
for reason in screen privacy lock; do
  wait_for "$LOG" "^NOTCHPAD_CLOSE_CANCEL reason=$reason overlay=false$" 12
done
for stage in screen private lock lockopen; do
  probe "$LOG" "$stage" collapsed 'floating=false home=true pinned=false wasOpen=false private=true interactive=false'
done
probe "$LOG" public collapsed 'floating=false home=true pinned=false wasOpen=false private=false interactive=false'
[ "$(grep -c '^NOTCHPAD_CLOSE effect=matrix ' "$LOG")" = 4 ] || fail "Lock should not start a new close animation"
stop_app

float_pad() {
  defaults write "$P" detached -bool true &&
    defaults write "$P" offsetX -float 180 &&
    defaults write "$P" offsetY -float 255 || fail "Could not set a floating position"
}

echo "== f. Reopen a floating pad, then close while a boomerang is still playing"
LOG="$LOG_DIR/f-floating.log"
float_pad
start_sequence "$LOG" '2:toggle,2.15:toggle,2.35:probe-float,2.55:flight,2.85:toggle,3:screen,3.15:probe-flew,3.3:toggle,3.45:probe-home' \
  NOTCHPAD_DEBUG_FLIGHT=boomerang NOTCHPAD_DEBUG_FLIGHT_FREEZE=0.5
wait_for "$LOG" '^NOTCHPAD_CLOSE effect=matrix .* floating=true ' 12
wait_for "$LOG" '^NOTCHPAD_FLIGHT effect=boomerang ' 12
wait_for "$LOG" '^NOTCHPAD_FLIGHT_LANDED mode=effect docked=true visible=true$' 12
wait_for "$LOG" '^NOTCHPAD_CLOSE effect=matrix snapshot=none floating=false ' 12
probe "$LOG" float expanded 'floating=true home=false pinned=false wasOpen=false private=true interactive=true'
probe "$LOG" flew collapsed 'floating=false home=true pinned=false wasOpen=false private=true interactive=false'
probe "$LOG" home expanded 'floating=false home=true pinned=false wasOpen=false private=true interactive=true'
stop_app

echo "== g. Reopen during a Classic floating fade, then let a later fade finish"
LOG="$LOG_DIR/g-classic-fade.log"
float_pad
start_sequence "$LOG" '2:toggle,2.06:toggle,2.4:probe-fadeopen,2.6:toggle,2.95:probe-fadedone,3.1:toggle,3.35:probe-fadereopen' \
  NOTCHPAD_NO_EFFECTS=1
probe "$LOG" fadeopen expanded 'floating=true home=false pinned=false wasOpen=false private=true interactive=true'
probe "$LOG" fadedone collapsed 'floating=false home=true pinned=false wasOpen=false private=true interactive=false'
probe "$LOG" fadereopen expanded 'floating=true home=false pinned=false wasOpen=false private=true interactive=true'
stop_app

echo "== h. Quit while the closing overlay is still showing"
LOG="$LOG_DIR/h-quit.log"
start_sequence "$LOG" '2:toggle,2.2:quit'
wait_for "$LOG" '^NOTCHPAD_CLOSE_CANCEL reason=quit overlay=false$' 12
probe "$LOG" quit collapsed 'floating=false home=true pinned=false wasOpen=false private=true interactive=false'
wait "$APP_PID" || fail "NotchPad did not quit normally"
APP_PID=""

rm -rf "$LOG_DIR"
echo "All close-effects checks passed"
