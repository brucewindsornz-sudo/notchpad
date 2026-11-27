#!/bin/bash
# End-to-end checks for NotchPad's optional terminal mode on a real Mac.
#   TERMINAL_APP_CI=1 tests/terminal-app.sh /path/to/NotchPad.app
# Extra environment (e.g. NOTCHPAD_NO_EFFECTS=1) is passed through to the app.
# FOR BUILD MACHINES ONLY: quits NotchPad, installs/removes the add-on and wipes settings.
set -uo pipefail

[ "${TERMINAL_APP_CI:-}" = 1 ] || {
  echo "Refusing to run: this installs/removes the add-on and wipes NotchPad's settings. Build machines only (TERMINAL_APP_CI=1)."
  exit 2
}

if [ $# -lt 1 ]; then
  echo "Usage: TERMINAL_APP_CI=1 $0 /path/to/NotchPad.app"
  exit 2
fi

APP_BUNDLE="${1%/}"
APP_BIN="$APP_BUNDLE/Contents/MacOS/NotchPad"
BUNDLED_DIR="$APP_BUNDLE/Contents/Resources/TerminalAddOn"
BUNDLED_RUNNER="$BUNDLED_DIR/notchpad-run"
BUNDLED_INSTALL="$BUNDLED_DIR/install.sh"

SCRIPT_DIR="$HOME/Library/Application Scripts/com.newzeebuild.notchpad"
INSTALLED_RUNNER="$SCRIPT_DIR/notchpad-run"

C="$HOME/Library/Containers/com.newzeebuild.notchpad/Data"
P="$C/Library/Preferences/com.newzeebuild.notchpad"

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/notchpad-term-ci.XXXXXX")
MARKER="$HOME/.notchpad-terminal-ci-$$.tmp"
STOP_TAG="np-stop-marker-$$"
QUIT_TAG="np-quit-marker-$$"
STOP_SLEEP="301.$$"
QUIT_SLEEP="302.$$"
APP_PID=""

cleanup_state() {
  pkill -x NotchPad 2>/dev/null || true
  pkill -9 -f "[n]p-stop-marker-$$" 2>/dev/null || true
  pkill -9 -f "[s]leep 301\.$$" 2>/dev/null || true
  pkill -9 -f "[n]p-quit-marker-$$" 2>/dev/null || true
  pkill -9 -f "[s]leep 302\.$$" 2>/dev/null || true
  rm -f "$MARKER"
  rm -rf "$SCRIPT_DIR"
  defaults delete "$P" 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true
}

fail() {
  echo "FAILED: $1"
  for f in "$LOG_DIR"/*.log; do
    [ -f "$f" ] || continue
    echo "--- $(basename "$f")"
    cat "$f"
  done
  cleanup_state
  rm -rf "$LOG_DIR"
  exit 1
}

stop_app() {
  pkill -x NotchPad 2>/dev/null || true
  APP_PID=""
  sleep 1
}

launch() {   # launch <log> [extra env...]
  local log=$1; shift
  stop_app
  : > "$log"
  env NOTCHPAD_DEBUG=1 "$@" "$APP_BIN" 2> "$log" &
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

wait_gone() {   # wait_gone <pgrep-pattern> <timeout-seconds>
  local pat=$1 limit=$2 elapsed=0
  local steps=$((limit * 4))
  while [ "$elapsed" -lt "$steps" ]; do
    if ! pgrep -f "$pat" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
    elapsed=$((elapsed + 1))
  done
  return 1
}

[ -x "$APP_BIN" ] || fail "App binary not found or not executable: $APP_BIN"
[ -x "$BUNDLED_RUNNER" ] || fail "Bundled runner missing or not executable: $BUNDLED_RUNNER"
[ -x "$BUNDLED_INSTALL" ] || fail "Bundled install.sh missing or not executable: $BUNDLED_INSTALL"

mkdir -p "$C/Library/Preferences"
cleanup_state
sleep 1

echo "== a. Sandbox lock-down is unchanged"
ENT_XML=$(codesign -d --entitlements - --xml "$APP_BUNDLE" 2>/dev/null) || fail "codesign -d --entitlements failed"
python3 - "$ENT_XML" <<'PY' || fail "Entitlements check failed"
import plistlib, sys
data = plistlib.loads(sys.argv[1].encode("utf-8"))
expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-only": True,
}
for forbidden in ("com.apple.security.network.client", "com.apple.security.network.server"):
    if forbidden in data:
        print(f"Forbidden network entitlement present: {forbidden}", file=sys.stderr)
        sys.exit(1)
if data != expected:
    print(f"Unexpected entitlements: {data!r} (expected {expected!r})", file=sys.stderr)
    sys.exit(1)
print("OK: entitlements match app-sandbox + files.user-selected.read-only only")
PY

echo "== b. Without the add-on installed, commands do not run"
rm -rf "$SCRIPT_DIR"
LOG_B="$LOG_DIR/b-not-installed.log"
launch "$LOG_B" NOTCHPAD_DEBUG_TERMINAL="echo should-not-run"
wait_for "$LOG_B" "^NOTCHPAD_TERM_ADDON=notInstalled$" 15
sleep 2
grep -q "NOTCHPAD_TERM_LINE should-not-run" "$LOG_B" && fail "Command ran even though add-on is not installed"
pgrep -x NotchPad >/dev/null || fail "NotchPad crashed when add-on was not installed"
stop_app
echo "OK: notInstalled reported and command did not run"

echo "== c. Bundled install.sh installs the add-on cleanly"
"$BUNDLED_INSTALL" || fail "Bundled install.sh failed"
[ -x "$INSTALLED_RUNNER" ] || fail "Installed runner is missing or not executable: $INSTALLED_RUNNER"
cmp -s "$BUNDLED_RUNNER" "$INSTALLED_RUNNER" || fail "Installed runner differs from bundled copy"
echo "OK: add-on installed, executable and byte-identical"

echo "== d. Commands run outside the sandbox through NotchPad"
rm -f "$MARKER"
NET_CMD='code=$(curl -sS --max-time 10 -o /dev/null -w "%{http_code}" https://example.com || echo 000); echo "NET_CODE:$code"'
CMDS_D=$(cat <<EOF
echo "HOME_IS:\$HOME"
printf "marker-ok\n" > "$MARKER"
cd /tmp
pwd
sh -c 'exit 3'
echo "stderr-check-line" >&2
$NET_CMD
EOF
)
LOG_D="$LOG_DIR/d-run.log"
launch "$LOG_D" NOTCHPAD_DEBUG_TERMINAL="$CMDS_D"
wait_for "$LOG_D" "^NOTCHPAD_TERM_FINISHED$" 30
grep -qx "NOTCHPAD_TERM_ADDON=ready" "$LOG_D" || fail "Expected NOTCHPAD_TERM_ADDON=ready"

REPORTED_HOME=$(grep "^NOTCHPAD_TERM_LINE HOME_IS:" "$LOG_D" | head -1 | sed 's/^NOTCHPAD_TERM_LINE HOME_IS://')
[ -n "$REPORTED_HOME" ] || fail "Did not see HOME_IS output"
case "$REPORTED_HOME" in
  *Library/Containers*) fail "Command HOME is inside sandbox container: $REPORTED_HOME" ;;
esac
[ "$REPORTED_HOME" = "$HOME" ] || fail "Command HOME ($REPORTED_HOME) does not match real HOME ($HOME)"
echo "OK: HOME is real home ($REPORTED_HOME)"

[ -f "$MARKER" ] || fail "Marker file was not created in real home ($MARKER)"
grep -q "marker-ok" "$MARKER" || fail "Marker file had unexpected contents"
rm -f "$MARKER"
echo "OK: command wrote to real home folder"

grep -qx "NOTCHPAD_TERM_LINE /private/tmp" "$LOG_D" || fail "cd /tmp did not carry over to pwd"
echo "OK: cd carried over (/private/tmp)"

grep -q "NOTCHPAD_TERM_DONE status=3 stopped=false" "$LOG_D" || fail "Non-zero exit status=3 not reported"
echo "OK: non-zero exit status (3) reported"

grep -qx "NOTCHPAD_TERM_LINE stderr-check-line" "$LOG_D" || fail "stderr text did not appear in output"
echo "OK: stderr appeared in output"

if grep -qx "NOTCHPAD_TERM_LINE NET_CODE:200" "$LOG_D"; then
  echo "OK: command reached the internet (HTTP 200)"
else
  echo "Retrying network fetch once..."
  LOG_NET="$LOG_DIR/d-net-retry.log"
  launch "$LOG_NET" NOTCHPAD_DEBUG_TERMINAL="$NET_CMD"
  wait_for "$LOG_NET" "^NOTCHPAD_TERM_FINISHED$" 25
  if grep -qx "NOTCHPAD_TERM_LINE NET_CODE:200" "$LOG_NET"; then
    echo "OK: command reached the internet on retry (HTTP 200)"
  else
    echo "WARNING: network fetch from command did not return HTTP 200 (possible build-machine network outage)"
  fi
fi
stop_app

echo "== e. Stop ends a running command and leaves no orphan"
LOG_E="$LOG_DIR/e-stop.log"
launch "$LOG_E" \
  NOTCHPAD_DEBUG_TERMINAL="sh -c 'sleep $STOP_SLEEP; true' $STOP_TAG" \
  NOTCHPAD_DEBUG_TERMINAL_STOP=2
wait_for "$LOG_E" "^NOTCHPAD_TERM_DONE .*stopped=true" 15
wait_gone "[n]p-stop-marker-$$" 5 || fail "Process $STOP_TAG still running after Stop"
wait_gone "[s]leep 301\.$$" 5 || fail "Grandchild sleep $STOP_SLEEP still running after Stop"
stop_app
echo "OK: Stop ended the command and grandchild cleanly"

echo "== f. Quitting NotchPad stops a running command"
LOG_F="$LOG_DIR/f-quit.log"
launch "$LOG_F" NOTCHPAD_DEBUG_TERMINAL="sh -c 'sleep $QUIT_SLEEP; true' $QUIT_TAG"
wait_for "$LOG_F" "^NOTCHPAD_TERM_RUN " 15
# Confirm both the shell and its grandchild sleep actually started before quitting NotchPad.
started=0
for _ in $(seq 1 20); do
  if pgrep -f "[n]p-quit-marker-$$" >/dev/null 2>&1 && pgrep -f "[s]leep 302\.$$" >/dev/null 2>&1; then
    started=1
    break
  fi
  sleep 0.25
done
[ "$started" -eq 1 ] || fail "Quit test command (and grandchild sleep $QUIT_SLEEP) did not appear in process list"
pkill -x NotchPad || true
APP_PID=""
wait_gone "[n]p-quit-marker-$$" 10 || fail "Process $QUIT_TAG still running 10s after NotchPad quit"
wait_gone "[s]leep 302\.$$" 10 || fail "Grandchild sleep $QUIT_SLEEP still running 10s after NotchPad quit"
echo "OK: quitting NotchPad stopped the running command and grandchild"

echo "== g. Out-of-date add-on is refused until updated"
printf '\n# modified-for-ci-test\n' >> "$INSTALLED_RUNNER"
LOG_G1="$LOG_DIR/g1-outdated.log"
launch "$LOG_G1" NOTCHPAD_DEBUG_TERMINAL="echo should-not-run-outdated"
wait_for "$LOG_G1" "^NOTCHPAD_TERM_ADDON=needsUpdate$" 15
sleep 2
grep -q "NOTCHPAD_TERM_LINE should-not-run-outdated" "$LOG_G1" && fail "Command ran despite needsUpdate"
pgrep -x NotchPad >/dev/null || fail "NotchPad crashed when add-on needed update"
stop_app

"$BUNDLED_INSTALL" || fail "Re-running install.sh failed"
cmp -s "$BUNDLED_RUNNER" "$INSTALLED_RUNNER" || fail "Re-installed runner differs from bundled copy"
LOG_G2="$LOG_DIR/g2-updated.log"
launch "$LOG_G2" NOTCHPAD_DEBUG_TERMINAL="echo back-to-ready"
wait_for "$LOG_G2" "^NOTCHPAD_TERM_FINISHED$" 15
grep -qx "NOTCHPAD_TERM_ADDON=ready" "$LOG_G2" || fail "Expected ready after re-installing add-on"
grep -qx "NOTCHPAD_TERM_LINE back-to-ready" "$LOG_G2" || fail "Expected command output after re-installing add-on"
stop_app
echo "OK: out-of-date add-on refused, and re-installing restored ready"

echo "== h. install.sh --remove removes the add-on"
"$BUNDLED_INSTALL" --remove || fail "install.sh --remove failed"
[ ! -e "$INSTALLED_RUNNER" ] || fail "Installed runner still exists after --remove"
LOG_H="$LOG_DIR/h-removed.log"
launch "$LOG_H" NOTCHPAD_DEBUG_TERMINAL="echo should-not-run-removed"
wait_for "$LOG_H" "^NOTCHPAD_TERM_ADDON=notInstalled$" 15
sleep 2
grep -q "NOTCHPAD_TERM_LINE should-not-run-removed" "$LOG_H" && fail "Command ran after --remove"
stop_app
echo "OK: --remove removed the add-on and app reports notInstalled"

cleanup_state
rm -rf "$LOG_DIR"
echo "All terminal-app checks passed"
