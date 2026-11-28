#!/bin/bash
# Called by trial.sh on a Mac. FLIGHT=all or a comma-separated list; THEME=theme id.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/NotchPad.app/Contents/MacOS/NotchPad"
P="$HOME/Library/Containers/com.newzeebuild.notchpad/Data/Library/Preferences/com.newzeebuild.notchpad"
mkdir -p "$(dirname "$P")" out/logs out/shots

effects=(boomerang gate beam codestream warp swarm bolt comet)
if [ "${FLIGHT:-all}" != all ]; then
  IFS=, read -r -a effects <<< "$FLIGHT"
fi
theme="${THEME:-notch}"
keys=(rememberLayout detached offsetX offsetY closeOnClickOutside)
types=(bool bool float float bool)
saved=()
for key in "${keys[@]}"; do saved+=("$(defaults read "$P" "$key" 2>/dev/null || true)"); done

PID=""
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
}
trap cleanup EXIT

launch() {
  local name=$1 fx=$2; shift 2
  stop
  defaults write "$P" rememberLayout -bool true &&
    defaults write "$P" detached -bool true &&
    defaults write "$P" offsetX -float 180 &&
    defaults write "$P" offsetY -float 255 &&
    defaults write "$P" closeOnClickOutside -bool false || return 1
  env -u NOTCHPAD_NO_EFFECTS NOTCHPAD_DEBUG=1 NOTCHPAD_DEBUG_FORCE_MOTION=1 NOTCHPAD_ALLOW_CAPTURE=1 \
    NOTCHPAD_DEBUG_OPEN=1 NOTCHPAD_DEBUG_THEME="$theme" NOTCHPAD_DEBUG_FLIGHT="$fx" \
    NOTCHPAD_DEBUG_BOOMERANG_AFTER=2.4 "$@" "$APP" 2>"out/logs/$name.log" &
  PID=$!
}

wait_log() {
  local name=$1 pattern=$2 i
  for ((i=0; i<80; i++)); do
    grep -Eq "$pattern" "out/logs/$name.log" 2>/dev/null && return 0
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.25
  done
  echo "NotchPad did not log '$pattern' during $name."
  cat "out/logs/$name.log"
  return 1
}

FAILED=0
for fx in "${effects[@]}"; do
  [ "$fx" = none ] && continue
  for pose in start midway end; do
    case "$pose" in start) t=0 ;; midway) t=0.5 ;; end) t=1 ;; esac
    name="flight-$fx-$pose"
    if launch "$name" "$fx" NOTCHPAD_DEBUG_FLIGHT_FREEZE="$t" &&
       wait_log "$name" "^NOTCHPAD_OPEN floating=true " &&
       wait_log "$name" "^NOTCHPAD_FLIGHT effect=$fx "; then
      sleep 0.4
      screencapture -x "out/shots/$name.png" || FAILED=1
    else
      FAILED=1
    fi
    stop
  done

  name="flight-$fx-live"
  if launch "$name" "$fx" && wait_log "$name" "^NOTCHPAD_OPEN floating=true " &&
     wait_log "$name" "^NOTCHPAD_FLIGHT_DONE effect=$fx frames=[1-9][0-9]* " &&
     wait_log "$name" '^NOTCHPAD_FLIGHT_LANDED mode=effect docked=true visible=true$'; then
    sleep 0.25
    screencapture -x "out/shots/flight-$fx-after.png" || FAILED=1
  else
    FAILED=1
  fi
  stop
done

# A full live trial also exercises cancellation, the classic fallback and the complete release check.
if [ "${FLIGHT:-all}" = all ] && [ "$FAILED" = 0 ]; then
  tests/flight-effects.sh "$PWD/build/NotchPad.app" >out/logs/flight-release-check.log 2>&1 || FAILED=1
  cat out/logs/flight-release-check.log
fi
exit "$FAILED"
