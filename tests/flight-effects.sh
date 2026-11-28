#!/bin/bash
# End-to-end boomerang animation checks on a Mac:
#   tests/flight-effects.sh /path/to/NotchPad.app
# Optional: FLIGHT_FRAMES_OUT=/path/to/dir copies the rendered PNGs out of the sandbox.
set -uo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/NotchPad.app"
  exit 2
fi

APP="${1%/}/Contents/MacOS/NotchPad"
P="$HOME/Library/Containers/com.newzeebuild.notchpad/Data/Library/Preferences/com.newzeebuild.notchpad"
mkdir -p "$(dirname "$P")" || exit 1

EFFECTS=(boomerang gate beam codestream warp swarm bolt comet)
PER_EFFECT=12
EXPECTED=$(( ${#EFFECTS[@]} * PER_EFFECT ))
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/notchpad-flight-ci.XXXXXX") || exit 1
PID=""
keys=(rememberLayout detached offsetX offsetY closeOnClickOutside)
types=(bool bool float float bool)
saved=()
for key in "${keys[@]}"; do saved+=("$(defaults read "$P" "$key" 2>/dev/null || true)"); done

stop() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    PID=""
  fi
}

cleanup() {
  stop
  local i
  for ((i=0; i<${#keys[@]}; i++)); do
    if [ -n "${saved[$i]}" ]; then
      defaults write "$P" "${keys[$i]}" "-${types[$i]}" "${saved[$i]}" 2>/dev/null || true
    else
      defaults delete "$P" "${keys[$i]}" 2>/dev/null || true
    fi
  done
  rm -rf "$LOG_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAILED: $1"
  for f in "$LOG_DIR"/*.log; do
    [ -f "$f" ] || continue
    echo "--- $(basename "$f")"
    cat "$f"
  done
  exit 1
}

launch() {
  local log=$1; shift
  stop
  env -u NOTCHPAD_NO_EFFECTS NOTCHPAD_DEBUG=1 NOTCHPAD_DEBUG_FORCE_MOTION=1 "$@" "$APP" 2>"$log" &
  PID=$!
}

wait_for() {
  local log=$1 pattern=$2 limit=$3 i
  for ((i=0; i<limit*4; i++)); do
    grep -Eq "$pattern" "$log" 2>/dev/null && return 0
    kill -0 "$PID" 2>/dev/null || fail "App exited while waiting for '$pattern' in $(basename "$log")"
    sleep 0.25
  done
  fail "Timed out waiting for '$pattern' in $(basename "$log")"
}

start_floating() {
  local log=$1 fx=$2; shift 2
  stop
  defaults write "$P" rememberLayout -bool true &&
    defaults write "$P" detached -bool true &&
    defaults write "$P" offsetX -float 180 &&
    defaults write "$P" offsetY -float 255 &&
    defaults write "$P" closeOnClickOutside -bool false || fail "Could not write floating position"
  launch "$log" NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_BOOMERANG_AFTER=2.4 NOTCHPAD_DEBUG_FLIGHT="$fx" "$@"
  wait_for "$log" '^NOTCHPAD_OPEN floating=true ' 15
}

check_docked() {
  local log=$1 mode=$2
  wait_for "$log" "^NOTCHPAD_FLIGHT_LANDED mode=$mode docked=true visible=true$" 15
  kill -0 "$PID" 2>/dev/null || fail "NotchPad crashed after landing"
  local detached i
  for ((i=0; i<12; i++)); do
    detached=$(defaults read "$P" detached 2>/dev/null || echo invalid)
    if [ "$detached" = 0 ] || [ "$detached" = false ]; then return 0; fi
    sleep 0.25
  done
  fail "Pad position was not saved as docked (detached=$detached)"
}

[ -x "$APP" ] || fail "App binary not found or not executable: $APP"

echo "== Render $PER_EFFECT frames for each of the eight boomerang animations"
LOG="$LOG_DIR/frames.log"
launch "$LOG" NOTCHPAD_DEBUG_FLIGHT_FRAMES="$PER_EFFECT"
wait_for "$LOG" '^NOTCHPAD_FLIGHT_FRAMES dir=.+ count=[0-9]+$' 180
LINE=$(grep '^NOTCHPAD_FLIGHT_FRAMES ' "$LOG" | tail -1)
DIR=$(printf '%s\n' "$LINE" | sed 's/^NOTCHPAD_FLIGHT_FRAMES dir=\(.*\) count=[0-9][0-9]*$/\1/')
COUNT=${LINE##* count=}
stop
[ "$COUNT" = "$EXPECTED" ] || fail "Expected $EXPECTED frame PNGs, got $COUNT"
for fx in "${EFFECTS[@]}"; do
  for ((i=0; i<PER_EFFECT; i++)); do
    NAME=$(printf 'flight-%s-%03d.png' "$fx" "$i")
    [ -s "$DIR/$NAME" ] || fail "Missing or empty frame: $NAME"
  done
done
if [ -n "${FLIGHT_FRAMES_OUT:-}" ]; then
  mkdir -p "$FLIGHT_FRAMES_OUT" && cp "$DIR"/flight-*.png "$FLIGHT_FRAMES_OUT"/ || fail "Could not copy frame PNGs"
fi

echo "== Play each animation live, then verify the pad is docked, visible and interactive"
for fx in "${EFFECTS[@]}"; do
  LOG="$LOG_DIR/live-$fx.log"
  start_floating "$LOG" "$fx"
  wait_for "$LOG" "^NOTCHPAD_FLIGHT effect=$fx distance=[1-9][0-9]*$" 15
  wait_for "$LOG" "^NOTCHPAD_FLIGHT_DONE effect=$fx frames=[1-9][0-9]* seconds=" 15
  check_docked "$LOG" effect
  stop
  echo "OK: $fx started, played and landed"
done

echo "== Close the pad mid-flight and check the overlay does not leave it hidden"
LOG="$LOG_DIR/interrupted.log"
start_floating "$LOG" gate NOTCHPAD_DEBUG_FLIGHT_FREEZE=0.5 NOTCHPAD_DEBUG_CLOSE_AFTER=3.5
wait_for "$LOG" '^NOTCHPAD_FLIGHT effect=gate ' 15
check_docked "$LOG" effect
wait_for "$LOG" '^NOTCHPAD_STATE=collapsed$' 15
stop

echo "== NOTCHPAD_NO_EFFECTS=1 must use the classic physical flight"
LOG="$LOG_DIR/no-effects.log"
start_floating "$LOG" gate NOTCHPAD_NO_EFFECTS=1
check_docked "$LOG" classic
grep -q '^NOTCHPAD_BOOMERANG distance=' "$LOG" || fail "Did not see the classic spring flight"
if grep -q '^NOTCHPAD_FLIGHT effect=' "$LOG"; then
  fail "A flight effect ran despite NOTCHPAD_NO_EFFECTS=1"
fi
echo "All flight-effects checks passed"
