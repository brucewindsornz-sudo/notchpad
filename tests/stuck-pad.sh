#!/bin/bash
# Checks that the pad can never be left where its buttons can't be clicked.
#   tests/stuck-pad.sh /path/to/NotchPad.app/Contents/MacOS/NotchPad
# Needs cliclick. Extra environment (e.g. NOTCHPAD_NO_EFFECTS=1) is passed through to the app.
# FOR BUILD MACHINES ONLY: it quits NotchPad and wipes its settings. Set STUCK_PAD_CI=1 to confirm.
set -uo pipefail
[ "${STUCK_PAD_CI:-}" = 1 ] || { echo "Refusing to run: this wipes NotchPad's settings. Build machines only (STUCK_PAD_CI=1)."; exit 2; }
APP="$1"
C=~/Library/Containers/com.newzeebuild.notchpad/Data
P="$C/Library/Preferences/com.newzeebuild.notchpad"
fail() {
  echo "FAILED: $1"
  for f in stuck*.log; do echo "--- $f"; cat "$f"; done
  screencapture -x stuck-failed.png 2>/dev/null
  pkill -x NotchPad; defaults delete "$P" 2>/dev/null
  exit 1
}
launch() {   # launch <log> [extra env...]
  local log=$1; shift
  pkill -x NotchPad 2>/dev/null; sleep 1
  killall cfprefsd 2>/dev/null; sleep 1
  env NOTCHPAD_DEBUG=1 NOTCHPAD_ALLOW_CAPTURE=1 "$@" "$APP" 2> "$log" &
  sleep 6
  pgrep -x NotchPad >/dev/null || fail "NotchPad is not running ($log)"
}
field() { echo "$1" | sed "s/.* $2=\([0-9-]*\).*/\1/"; }   # field <line> <name>
below_menu_bar() {   # below_menu_bar <log>: the last time the pad was laid out open, was it floating with its top under the limit?
  local line; line=$(grep NOTCHPAD_OPEN "$1" | tail -1)
  [ -n "$line" ] || fail "the pad never opened ($1)"
  echo "$line"
  echo "$line" | grep -q "floating=true" || fail "expected a floating pad ($1)"
  local top limit; top=$(field "$line" top); limit=$(field "$line" limit)
  [ "$top" -le "$limit" ] || fail "pad top $top is above the menu bar limit $limit: its buttons can't be clicked"
}
click_close() {   # click_close <log> <dx> <dy>: click the Close button, offset from where it was first drawn
  local X Y
  read X Y < <(grep NOTCHPAD_CLOSE_AT "$1" | tail -1 | sed 's/.*x=\([0-9-]*\) y=\([0-9-]*\).*/\1 \2/')
  [ -n "${X:-}" ] && [ -n "${Y:-}" ] || fail "no NOTCHPAD_CLOSE_AT in $1"
  local bar; bar=$(field "$(grep NOTCHPAD_CLOSE_AT "$1" | tail -1)" menubar)
  X=$((X+$2)); Y=$((Y+$3))
  [ "$Y" -gt "$bar" ] || fail "Close button centre (y=$Y) is inside the menu bar strip ($bar tall)"
  echo "Clicking Close at $X,$Y (menu bar is $bar tall)"
  cliclick m:$X,$Y w:400 c:$X,$Y
  sleep 1.5
  grep -q "NOTCHPAD_STATE=collapsed" "$1" || fail "clicking Close did not close the pad ($1)"
}

mkdir -p "$C/Library/Preferences"
defaults delete "$P" 2>/dev/null

echo "== 1. A pad that 1.1.3 left under the menu bar, pinned open, reopens where its buttons work"
defaults write "$P" detached -bool true
defaults write "$P" offsetX -float 140
defaults write "$P" offsetY -float 0
defaults write "$P" keepOpen -bool true      # pinned: only the Close button can close it
defaults write "$P" wasOpen -bool true
launch stuck1.log
below_menu_bar stuck1.log
click_close stuck1.log 0 0
echo "OK: it opens below the menu bar and Close works"

echo "== 2. Dragging straight sideways out of the notch can't park it under the menu bar"
pkill -x NotchPad; sleep 1
defaults delete "$P" 2>/dev/null
defaults write "$P" keepOpen -bool true      # pinned: a click that misses the button can't close it
launch stuck2.log NOTCHPAD_DEBUG_OPEN=1
read X Y < <(grep NOTCHPAD_MOVE_AT stuck2.log | tail -1 | sed 's/.*x=\([0-9-]*\) y=\([0-9-]*\)/\1 \2/')
[ -n "${X:-}" ] && [ -n "${Y:-}" ] || fail "no NOTCHPAD_MOVE_AT in stuck2.log"
LEFT0=$(field "$(grep NOTCHPAD_OPEN stuck2.log | tail -1)" left)
echo "Move button at $X,$Y; pad's left edge at $LEFT0"
cliclick m:$X,$Y w:300 dd:$X,$Y w:100 dm:$((X+60)),$Y w:100 dm:$((X+140)),$Y w:100 dm:$((X+220)),$Y w:100 du:$((X+220)),$Y
sleep 2
grep NOTCHPAD_DROP stuck2.log | tail -1 | grep -q "docked=false" || fail "the sideways drag did not leave it floating"
below_menu_bar stuck2.log
LEFT1=$(field "$(grep NOTCHPAD_OPEN stuck2.log | tail -1)" left)
echo "Pad moved $((LEFT1-LEFT0)) points right"
[ $((LEFT1-LEFT0)) -gt 150 ] || fail "the pad did not follow the pointer"
# Floating, the buttons sit 2 points lower on screen than when docked.
click_close stuck2.log $((LEFT1-LEFT0)) 2
echo "OK: after a sideways drag it floats below the menu bar and Close works"

echo "== 3. ...and it comes back in a usable spot after a restart"
launch stuck3.log NOTCHPAD_DEBUG_OPEN=1
below_menu_bar stuck3.log
click_close stuck3.log 0 0
echo "OK: it restarts below the menu bar and Close works"

pkill -x NotchPad; sleep 1
defaults delete "$P" 2>/dev/null
killall cfprefsd 2>/dev/null
echo "All stuck-pad checks passed"
