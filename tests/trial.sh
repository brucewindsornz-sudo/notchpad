#!/bin/bash
# Development trial run on a GitHub Mac (see .github/workflows/trial.yml). Reads one "fx:" line from the
# commit message in $TRIAL_MSG and writes everything into ./out:
#
#   close=a,b      closing animations to render as still frames ("all", or "none"; default all)
#   flight=a,b     boomerang animations to render as still frames ("all", or "none"; default none)
#   frames=N       still frames per animation (default 12, at most 120)
#   themes=a,b     theme ids to render the frames in (default notch)
#   floating       also render the closing animations for a floating pad
#   shots=a,b      screenshots of the real pad, open, with a sample note, in these themes
#   float-shots    take those screenshots with the pad floating as well
#   settings=a,b   screenshots of Settings scrolled to these sections (theme, closeAnimation, flightAnimation ...)
#   live           play each listed closing/boomerang animation for real, and report how many frames it drew
#   close-checks   also run the full closing animation and interruption checks
#
# Frames land in out/frames/<theme>[-floating]/<animation>-NNN.png, screenshots in out/shots/.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/NotchPad.app/Contents/MacOS/NotchPad"
C=~/Library/Containers/com.newzeebuild.notchpad/Data
P="$C/Library/Preferences/com.newzeebuild.notchpad"
mkdir -p out/frames out/shots out/logs

LINE=$(printf '%s\n' "${TRIAL_MSG:-}" | grep -E '^[[:space:]]*fx:' | head -1 | sed 's/^[[:space:]]*fx://')
CLOSE=all; FLIGHT=none; FRAMES=12; THEMES=notch; FLOATING=0; SHOTS=""; FLOATSHOTS=0; SETTINGS=""; LIVE=0; CLOSE_CHECKS=0
for word in $LINE; do
  case "$word" in
    close=*) CLOSE=${word#close=} ;;
    flight=*) FLIGHT=${word#flight=} ;;
    frames=*) FRAMES=${word#frames=} ;;
    themes=*) THEMES=${word#themes=} ;;
    floating) FLOATING=1 ;;
    shots=*) SHOTS=${word#shots=} ;;
    float-shots) FLOATSHOTS=1 ;;
    settings=*) SETTINGS=${word#settings=} ;;
    live) LIVE=1 ;;
    close-checks) CLOSE_CHECKS=1 ;;
  esac
done
echo "Trial: close=$CLOSE flight=$FLIGHT frames=$FRAMES themes=$THEMES floating=$FLOATING shots=$SHOTS settings=$SETTINGS live=$LIVE"

ALL_CLOSE="lightning matrix teleport stargate blackHole tv dust burn glitch shatter hyperspace melt"
list() { [ "$1" = all ] && echo "$2" || { [ "$1" = none ] && echo "" || echo "$1" | tr ',' ' '; }; }

run() {   # run <log name> [env...]   starts the app in the background
  local name=$1; shift
  env NOTCHPAD_DEBUG=1 NOTCHPAD_ALLOW_CAPTURE=1 NOTCHPAD_DEBUG_FORCE_MOTION=1 "$@" "$APP" 2> "out/logs/$name.log" &
}
stop() { pkill -x NotchPad 2>/dev/null; sleep 1; }
wait_log() {   # wait_log <log name> <pattern> <seconds>
  local i=0
  while [ $i -lt $(( $3 * 4 )) ]; do
    grep -Eq "$2" "out/logs/$1.log" 2>/dev/null && return 0
    pgrep -x NotchPad >/dev/null || { echo "!! NotchPad exited while waiting for '$2' ($1)"; return 1; }
    sleep 0.25; i=$((i + 1))
  done
  echo "!! timed out waiting for '$2' ($1)"; return 1
}
FAILED=0

# 1. Still frames from the app's own renderer.
for theme in $(echo "$THEMES" | tr ',' ' '); do
  for mode in docked floating; do
    [ "$mode" = floating ] && [ "$FLOATING" = 0 ] && continue
    name="frames-$theme-$mode"
    dest="out/frames/$theme"; [ "$mode" = floating ] && dest="out/frames/$theme-floating"
    mkdir -p "$dest"
    extra=(); [ "$mode" = floating ] && extra=(NOTCHPAD_DEBUG_CLOSE_FLOATING=1)
    flight_env=(); [ "$FLIGHT" != none ] && [ "$mode" = docked ] && flight_env=(NOTCHPAD_DEBUG_FLIGHT_FRAMES="$FRAMES" NOTCHPAD_DEBUG_FLIGHT_ONLY="$FLIGHT")
    [ "$FLIGHT" = all ] && [ "$mode" = docked ] && flight_env=(NOTCHPAD_DEBUG_FLIGHT_FRAMES="$FRAMES")
    close_env=(NOTCHPAD_DEBUG_CLOSE_FRAMES="$FRAMES"); [ "$CLOSE" != all ] && close_env+=(NOTCHPAD_DEBUG_CLOSE_ONLY="$CLOSE")
    run "$name" NOTCHPAD_DEBUG_THEME="$theme" "${close_env[@]}" ${extra[@]+"${extra[@]}"} ${flight_env[@]+"${flight_env[@]}"}
    wait_log "$name" "^NOTCHPAD_CLOSE_FRAMES dir=" 240 || FAILED=1
    D=$(grep NOTCHPAD_CLOSE_FRAMES "out/logs/$name.log" | sed 's/.*dir=\(.*\) count=.*/\1/')
    [ -n "$D" ] && cp "$D"/*.png "$dest"/ 2>/dev/null
    if [ ${#flight_env[@]} -gt 0 ]; then
      wait_log "$name" "^NOTCHPAD_FLIGHT_FRAMES dir=" 240 || FAILED=1
      D=$(grep NOTCHPAD_FLIGHT_FRAMES "out/logs/$name.log" | sed 's/.*dir=\(.*\) count=.*/\1/')
      [ -n "$D" ] && cp "$D"/*.png "$dest"/ 2>/dev/null
    fi
    stop
    echo "frames: $dest -> $(ls "$dest" | wc -l | tr -d ' ') files"
  done
done

# 2. Screenshots of the real pad with a sample note.
if [ -n "$SHOTS" ] || [ "$LIVE" = 1 ]; then
  brew install cliclick >/dev/null 2>&1
  mkdir -p "$C/Library/Application Support/NotchPad/Themes"
  cp tests/themes/* "$C/Library/Application Support/NotchPad/Themes/" 2>/dev/null
  run type NOTCHPAD_DEBUG_OPEN=1
  sleep 3
  args=(-w 15)
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && args+=("t:$line")
    args+=(kp:return)
  done < tests/trial-note.txt
  cliclick "${args[@]}"
  sleep 1
  stop
fi
for theme in $(echo "$SHOTS" | tr ',' ' '); do
  run "open-$theme" NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_THEME="$theme"
  sleep 4
  screencapture -x "out/shots/open-$theme.png"
  pgrep -x NotchPad >/dev/null || { echo "!! crashed: open-$theme"; FAILED=1; }
  stop
  if [ "$FLOATSHOTS" = 1 ]; then
    defaults write "$P" detached -bool true; defaults write "$P" offsetX -float 180; defaults write "$P" offsetY -float 220
    run "float-$theme" NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_THEME="$theme"
    sleep 4
    screencapture -x "out/shots/float-$theme.png"
    pgrep -x NotchPad >/dev/null || { echo "!! crashed: float-$theme"; FAILED=1; }
    stop
    defaults write "$P" detached -bool false; defaults write "$P" offsetX -float 0; defaults write "$P" offsetY -float 0
  fi
done

# 3. Settings sections.
first_theme=$(echo "$THEMES" | cut -d, -f1)
for section in $(echo "$SETTINGS" | tr ',' ' '); do
  run "settings-$section" NOTCHPAD_DEBUG_SETTINGS="$section" NOTCHPAD_DEBUG_THEME="$first_theme"
  sleep 6
  screencapture -x "out/shots/settings-$section.png"
  pgrep -x NotchPad >/dev/null || { echo "!! crashed: settings-$section"; FAILED=1; }
  stop
done

# 4. The real thing: a close with each listed animation, frozen half-way for a screenshot, then live.
if [ "$LIVE" = 1 ]; then
  for fx in $(list "$CLOSE" "$ALL_CLOSE"); do
    run "freeze-$fx" NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_THEME="$first_theme" NOTCHPAD_DEBUG_CLOSE="$fx" NOTCHPAD_DEBUG_CLOSE_FREEZE=0.45 NOTCHPAD_DEBUG_CLOSE_AFTER=3
    wait_log "freeze-$fx" "^NOTCHPAD_CLOSE effect=$fx" 15 || FAILED=1
    sleep 1
    screencapture -x "out/shots/close-$fx-midway.png"
    stop
    run "live-$fx" NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_THEME="$first_theme" NOTCHPAD_DEBUG_CLOSE="$fx" NOTCHPAD_DEBUG_CLOSE_AFTER=3
    wait_log "live-$fx" "^NOTCHPAD_CLOSE_DONE effect=$fx" 20 || FAILED=1
    sleep 0.5
    screencapture -x "out/shots/close-$fx-after.png"
    stop
  done
  # Boomerang animations for real: tests/trial-flight.sh, if the branch has one.
  if [ "$FLIGHT" != none ] && [ -x tests/trial-flight.sh ]; then
    FLIGHT="$FLIGHT" THEME="$first_theme" tests/trial-flight.sh || FAILED=1
  fi
fi

if [ "$CLOSE_CHECKS" = 1 ]; then
  tests/close-effects.sh "$PWD/build/NotchPad.app" >out/logs/close-release-check.log 2>&1 || FAILED=1
  cat out/logs/close-release-check.log
fi

echo "== what the app said"
grep -hE '^NOTCHPAD_(CLOSE|FLIGHT)_DONE ' out/logs/*.log 2>/dev/null | sort
grep -h "NOTCHPAD_CLOSE\|NOTCHPAD_FLIGHT\|NOTCHPAD_THEME\|NOTCHPAD_BOOMERANG" out/logs/*.log 2>/dev/null |
  grep -vE '^NOTCHPAD_(CLOSE|FLIGHT)_DONE ' | sort | uniq -c | head -80
ls ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i notchpad | head && FAILED=1
cp ~/Library/Logs/DiagnosticReports/NotchPad* out/logs/ 2>/dev/null
[ "$FAILED" = 0 ] && echo "Trial finished" || { echo "Trial finished WITH PROBLEMS (see above)"; exit 1; }
