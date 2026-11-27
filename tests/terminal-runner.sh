#!/bin/bash
# Direct runner checks, without the app. Bash is available on macOS and Linux.
set -m
here=$(cd -P "$(dirname "$0")" && pwd -P) || exit 1
runner=${1:-"$here/../terminal-addon/notchpad-run"}
case $runner in /*) ;; *) runner=$PWD/$runner ;; esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/notchpad-runner.XXXXXXXX") || exit 1
active=
child_pids=
check=

cleanup() {
    exec 8>&-
    for pid in $child_pids; do kill -KILL "$pid" 2>/dev/null || :; done
    if [ -n "$active" ]; then
        # Closing its input starts the runner's own cleanup, even on failure.
        for attempt in {1..50}; do
            kill -0 "$active" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$active" 2>/dev/null; then
            for pid in $(pgrep -P "$active" || :); do
                kill -s KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || :
            done
            kill -KILL "$active" 2>/dev/null || :
            for attempt in {1..10}; do
                kill -0 "$active" 2>/dev/null || break
                sleep 0.1
            done
        fi
        if ! kill -0 "$active" 2>/dev/null; then wait "$active" 2>/dev/null || :; fi
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
    {
        printf 'FAILED: %s: %s\n' "$check" "$*"
        printf '%s\n' '--- control channel (stderr) ---'
        [ ! -f "$tmp/control" ] || cat "$tmp/control"
        printf '\n%s\n' '--- command output (stdout) ---'
        [ ! -f "$tmp/output" ] || cat "$tmp/output"
        printf '\n%s\n' '--- end captured streams ---'
    } >&2
    exit 1
}
ok() { printf 'OK: %s\n' "$check"; }
[ -x "$runner" ] || fail "runner is not executable: $runner"
original_path=$PATH
mkdir -p "$tmp/bin" "$tmp/home with spaces" "$tmp/cwd with 'quotes'" "$tmp/shell with spaces" || exit 1
foreign_shell="$tmp/shell with spaces/foreign-shell"
test_home=$(cd -P "$tmp/home with spaces" && pwd -P) || exit 1
test_cwd=$(cd -P "$tmp/cwd with 'quotes'" && pwd -P) || exit 1
tmp_cwd=$(cd -P /tmp && pwd -P) || exit 1
export NOTCHPAD_TEST_HOME=$test_home
export NOTCHPAD_TEST_KERNEL=$(uname -s)
export BASH_SILENCE_DEPRECATION_WARNING=1
unset BASH_ENV ENV ZDOTDIR NOTCHPAD_TEST_NOISY_ZSH
printf '%s\n' '[ "${NOTCHPAD_TEST_NOISY_ZSH-}" != 1 ] || printf "noisy zshrc startup\n" >&2' > "$test_home/.zshrc"
printf '%s\n' '. "$HOME/.bashrc"' > "$test_home/.bash_profile"
printf '%s\n' 'case $- in *i*) printf "interactive bash startup\n" >&2 ;; esac' > "$test_home/.bashrc"

# Replace only the account lookup so every user shell can be checked without
# editing the host's login account or reading the host user's startup files.
cat > "$tmp/bin/getent" <<'EOF'
#!/bin/sh
[ "$1" = passwd ] && [ "$2" = "$(id -u)" ] || exit 1
printf '%s:x:%s:%s::%s:%s\n' "$(id -un)" "$2" "$(id -g)" "$NOTCHPAD_TEST_HOME" "$SHELL"
EOF
cat > "$tmp/bin/dscacheutil" <<'EOF'
#!/bin/sh
[ "$1" = -q ] && [ "$2" = user ] && [ "$3" = -a ] && [ "$4" = name ] &&
    [ "$5" = "$(id -un)" ] || exit 1
printf 'name: %s\nuid: %s\ndir: %s\nshell: %s\n' "$5" "$(id -u)" "$NOTCHPAD_TEST_HOME" "$SHELL"
EOF
cat > "$tmp/bin/uname" <<'EOF'
#!/bin/sh
[ "$1" = -s ] || exit 1
printf '%s\n' "$NOTCHPAD_TEST_KERNEL"
EOF
cat > "$foreign_shell" <<'EOF'
#!/bin/sh
[ "$1" = -l ] || exit 98
shift
if [ "$1" = -i ]; then
    printf 'noisy shell startup\n' >&2
    shift
fi
[ "$#" = 2 ] && [ "$1" = -c ] || exit 98
if [ "${NOTCHPAD_TEST_ECHO-}" = 1 ]; then
    printf '%s' "$2"
    exit
fi
exec /bin/sh -c "$2"
EOF
chmod 755 "$tmp/bin/getent" "$tmp/bin/dscacheutil" "$tmp/bin/uname" "$foreign_shell" || exit 1
mkfifo "$tmp/input" || exit 1

start() {
    # Keep a FIFO writer open just like the app. Do not pass it to the runner.
    # Clear old output before the fork so ready() cannot see the last run.
    : > "$tmp/output"
    : > "$tmp/control"
    exec 8<> "$tmp/input"
    HOME=/nonexistent-container SHELL=$selected_shell PATH="$tmp/bin:$original_path" \
        "$interpreter" "$runner" "$@" < "$tmp/input" 8>&- > "$tmp/output" 2> "$tmp/control" &
    active=$!
}
stop_input() { exec 8>&-; }

finish() {
    local budget=$1 attempts=0
    while kill -0 "$active" 2>/dev/null; do
        [ "$attempts" -lt "$((budget * 10))" ] || fail "runner did not exit within $budget seconds"
        sleep 0.1
        attempts=$((attempts + 1))
    done
    wait "$active" 2>/dev/null
    runner_status=$?
    active=
}

valid() {
    [ "$runner_status" = 0 ] || fail "runner exit was $runner_status rather than 0"
    [ "$(tail -n 1 "$tmp/control")" = "status=$1" ] || fail "expected status=$1 as the final control line"
    awk '
        /^cwd=\/.+$|^cwd=\/$/ && !cwd && !status { cwd++; next }
        /^status=[0-9]+$/ && !status { status++; next }
        { exit 1 }
        END { if (status != 1) exit 1 }
    ' "$tmp/control" || fail 'invalid control channel'
}

run() {
    local expected=$1
    shift
    start 1 "$@"
    finish 3
    stop_input
    valid "$expected"
}

output_is() {
    printf '%s' "$1" > "$tmp/expected"
    cmp -s "$tmp/output" "$tmp/expected" || fail 'stdout bytes were not as expected'
}
cwd_is() { grep -Fqx "cwd=$1" "$tmp/control" || fail "expected cwd=$1"; }
no_cwd() { [ "$(wc -l < "$tmp/control")" -eq 1 ] || fail 'unexpected cwd report'; }

valid_interrupted() {
    case $(tail -n 1 "$tmp/control") in
        status=130) valid 130 ;;
        status=143) valid 143 ;;
        status=137) valid 137 ;;
        *) fail 'suspended command did not finish with an interrupt or termination status' ;;
    esac
}

no_live_marker() {
    local marker=$1 pid state
    for pid in $(pgrep -f "$marker" || :); do
        state=$(ps -p "$pid" -o stat= 2>/dev/null) || continue
        case $state in Z*|'') ;; *) fail "process $pid is still running ($marker)" ;; esac
    done
}

no_live_children() {
    local pid state
    for pid in $child_pids; do
        state=$(ps -p "$pid" -o stat= 2>/dev/null) || continue
        case $state in Z*|'') ;; *) fail "process $pid is still running";; esac
    done
    child_pids=
}

ready() {
    local attempts=0
    until grep -q '^ready: [0-9]' "$tmp/output"; do
        [ "$attempts" -lt 30 ] || fail 'command never started'
        sleep 0.1
        attempts=$((attempts + 1))
    done
    child_pids=$(sed -n 's/^ready: //p' "$tmp/output")
}

for interpreter in sh dash bash; do
    command -v "$interpreter" >/dev/null || continue
    for user_shell in zsh bash sh dash "$foreign_shell"; do
        selected_shell=$(command -v "$user_shell") || continue
        check="$interpreter runner with ${user_shell##*/} login shell: merged output, status and cwd"
        run 0 login "$test_cwd" 'printf first; printf second >&2; printf third; cd /tmp'
        output_is firstsecondthird
        if [ "$selected_shell" = "$foreign_shell" ]; then no_cwd; else cwd_is "$tmp_cwd"; fi
        ok
        check="$interpreter runner with ${user_shell##*/} login shell: full mode loads setup and keeps noise off control"
        NOTCHPAD_TEST_NOISY_ZSH=1 run 0 full "$test_cwd" 'printf full-mode-marker'
        grep -q 'full-mode-marker' "$tmp/output" || fail 'missing command output'
        case $user_shell in
            "$foreign_shell") no_cwd; output_is $'noisy shell startup\nfull-mode-marker' ;;
            zsh) cwd_is "$test_cwd"; output_is $'noisy zshrc startup\nfull-mode-marker' ;;
            bash)
                cwd_is "$test_cwd"
                # Bash without a tty may print job-control notices, but
                # still loads the truly interactive branch of .bashrc.
                sed '/bash: cannot set terminal process group/d; /bash: no job control in this shell/d' \
                    "$tmp/output" > "$tmp/bash-output"
                [ "$(cat "$tmp/bash-output")" = $'interactive bash startup\nfull-mode-marker' ] ||
                    fail 'unexpected Bash startup output'
                ;;
            *) cwd_is "$test_cwd" ;;
        esac
        ok
        if [ "$user_shell" = zsh ]; then
            check="$interpreter runner with zsh: quiet full mode output is exactly the command output"
            run 0 full "$test_cwd" 'printf full-mode-marker'
            cwd_is "$test_cwd"
            output_is full-mode-marker
            ok
        fi
    done

    check="$interpreter runner: macOS account record preserves spaces in the home and shell paths"
    selected_shell="$foreign_shell"
    NOTCHPAD_TEST_KERNEL=Darwin run 0 login '' 'printf "%s\n%s\n" "$HOME" "$SHELL"'
    output_is "$test_home"$'\n'"$foreign_shell"$'\n'
    no_cwd
    ok

    selected_shell=$(command -v bash)
    check="$interpreter runner: exit 3, command not found, signal status"
    run 3 login "$test_cwd" 'exit 3'
    run 127 login "$test_cwd" 'notchpad-command-that-does-not-exist'
    run 143 login "$test_cwd" 'kill -TERM $$'
    ok

    check="$interpreter runner: initial directory and home fallback"
    run 0 login "$test_cwd" 'pwd -P'
    output_is "$test_cwd"$'\n'
    cwd_is "$test_cwd"
    run 0 login '' 'pwd -P'
    output_is "$test_home"$'\n'
    cwd_is "$test_home"
    run 0 login "$tmp/missing" 'pwd -P'
    cwd_is "$test_home"
    newline_dir="$test_cwd"$'\n''second line'
    mkdir -p "$newline_dir" || fail 'could not create multiline directory'
    run 0 login "$newline_dir" 'pwd -P'
    output_is "$newline_dir"$'\n'
    no_cwd
    ok

    check="$interpreter runner: quotes, expansion, backslashes, newline, semicolon, pipe and Unicode"
    input=$'key=ready\nprintf "%s\\n" \'"single" $ stays \\\\ and café\' "$key"; printf pipe | cat'
    run 0 login "$test_cwd" "$input"
    output_is $'"single" $ stays \\\\ and café\nready\npipe'
    run 127 login "$test_cwd" '-notchpad-unknown'
    grep -q -- '-notchpad-unknown' "$tmp/output" || fail 'shell did not receive leading dash'
    malformed=$':\n)'
    # Bash 3.2 counts -c syntax errors from zero. Compare against this
    # shell's direct output rather than expecting all versions to say 2.
    native_error=$("$selected_shell" --noprofile --norc -c "$malformed" 2>&1)
    native_line=$(printf '%s\n' "$native_error" | sed -n 's/.*: line \([0-9][0-9]*\): syntax error.*/\1/p')
    run 2 login "$test_cwd" "$malformed"
    [ -n "$native_line" ] && grep -Fq "line $native_line:" "$tmp/output" || fail 'wrapper shifted the syntax error line'
    selected_shell="$foreign_shell"
    export NOTCHPAD_TEST_ECHO=1
    input="-$input"
    run 0 login "$test_cwd" "$input"
    output_is "$input"
    unset NOTCHPAD_TEST_ECHO
    selected_shell=$(command -v bash)
    ok

    check="$interpreter runner: raw bytes, no final newline and complete 4 MiB output"
    run 0 login "$test_cwd" 'printf "abc\000\377end"'
    printf 'abc\000\377end' > "$tmp/expected"
    cmp -s "$tmp/output" "$tmp/expected" || fail 'raw output changed'
    run 0 login "$test_cwd" 'dd if=/dev/zero bs=1048576 count=4 2>/dev/null'
    [ "$(wc -c < "$tmp/output")" -eq 4194304 ] || fail 'large output was truncated'
    ok

    check="$interpreter runner: command input is /dev/null"
    run 0 login "$test_cwd" 'cat; if read -r x; then exit 42; fi; printf finished'
    output_is finished
    ok

    check="$interpreter runner: environment defaults and HOME correction"
    unset LANG LC_ALL PAGER USER LOGNAME
    export TERM=bad NOTCHPAD_TERMINAL=0
    # Use the foreign shell so a real shell's startup files cannot replace the
    # very values this check observes.
    selected_shell="$foreign_shell"
    run 0 login "$test_cwd" 'printf "%s\n" "$HOME" "$USER" "$LOGNAME" "$LANG" "$TERM" "$PAGER" "$NOTCHPAD_TERMINAL"'
    username=$(id -un)
    output_is "$(printf '%s\n' "$test_home" "$username" "$username" en_US.UTF-8 dumb cat 1)"$'\n'
    export LANG=C PAGER=more
    run 0 login "$test_cwd" 'printf "%s %s" "$LANG" "$PAGER"'
    output_is 'C more'
    selected_shell=$(command -v bash)
    ok

    check="$interpreter runner: invalid version, missing arguments and invalid mode"
    start 2 login "$test_cwd" ':'
    finish 3; stop_input
    [ "$runner_status" = 64 ] && [ "$(cat "$tmp/control")" = 'error=unsupported protocol' ] || fail 'wrong version error'
    start 1 login
    finish 3; stop_input
    [ "$runner_status" = 64 ] && [ "$(cat "$tmp/control")" = 'error=expected four arguments' ] || fail 'wrong argument error'
    start 1 other "$test_cwd" ':'
    finish 3; stop_input
    [ "$runner_status" = 64 ] && [ "$(cat "$tmp/control")" = 'error=unsupported shell mode' ] || fail 'wrong mode error'
    ok

    check="$interpreter runner: EOF stops a foreground command with INT"
    marker="notchpad-test-$$-$interpreter-int"
    start 1 login "$test_cwd" ": $marker; printf 'ready: %s\n' \"\$\$\"; exec sleep 300"
    ready; stop_input; finish 1; valid 130
    no_live_children; no_live_marker "$marker"
    ok

    check="$interpreter runner: EOF still stops descendants after the command shell exits"
    marker="notchpad-test-$$-$interpreter-tree"
    start 1 login "$test_cwd" "trap 'exit 130' INT; sh -c 'sleep 300 & child=\$!; printf \"ready: %s %s\n\" \"\$\$\" \"\$child\"; wait' $marker & wait"
    ready; stop_input; finish 6; valid 130
    no_live_children; no_live_marker "$marker"
    ok

    check="$interpreter runner: EOF stops a command repeatedly suspending itself"
    marker="notchpad-test-$$-$interpreter-stopped"
    start 1 login "$test_cwd" ": $marker; printf 'ready: %s\n' \"\$\$\"; while :; do kill -STOP \$\$; done"
    ready; stop_input; finish 6; valid_interrupted
    no_live_children; no_live_marker "$marker"
    ok

    check="$interpreter runner: a self-suspended command stays suspended without reporting status until EOF"
    marker="notchpad-test-$$-$interpreter-held-stop"
    start 1 login "$test_cwd" ": $marker; printf 'ready: %s\n' \"\$\$\"; kill -STOP \$\$; exec sleep 300"
    ready; sleep 1
    kill -0 "$active" 2>/dev/null || fail 'runner exited while its command was suspended'
    if grep -q '^status=' "$tmp/control"; then fail 'runner reported status while its command was suspended'; fi
    state=$(ps -p "$child_pids" -o stat= 2>/dev/null) || fail 'suspended command disappeared'
    case $state in T*) ;; *) fail "command was not suspended (state: $state)" ;; esac
    stop_input; finish 6; valid_interrupted
    no_live_children; no_live_marker "$marker"
    ok

    check="$interpreter runner: TERM can clear a suspended child without escalating to KILL"
    marker="notchpad-test-$$-$interpreter-stopped-child"
    start 1 login "$test_cwd" "trap '' INT; sh -c 'printf \"ready: %s\n\" \"\$\$\"; kill -STOP \$\$; exec sleep 300' $marker"
    ready; stop_input; finish 3; valid 143
    no_live_children; no_live_marker "$marker"
    ok

    check="$interpreter runner: KILL stops a command and descendants ignoring INT and TERM"
    marker="notchpad-test-$$-$interpreter-kill"
    start 1 login "$test_cwd" "trap '' INT TERM; sh -c 'sleep 300 & child=\$!; printf \"ready: %s %s\n\" \"\$\$\" \"\$child\"; wait' $marker"
    ready; stop_input; finish 6; valid 137
    no_live_children; no_live_marker "$marker"
    ok

    check="$interpreter runner: runner returns normally with stdin still open and no watcher left"
    marker="notchpad-test-$$-$interpreter-watcher"
    run 0 login "$test_cwd" ": $marker; printf done"
    output_is done
    no_live_marker "$marker"
    ok

    check="$interpreter runner: stdin already at EOF"
    marker="notchpad-test-$$-$interpreter-early"
    SHELL=$selected_shell PATH="$tmp/bin:$original_path" \
        "$interpreter" "$runner" 1 login "$test_cwd" ": $marker; sh -c 'sleep 300; :' $marker" \
        </dev/null > "$tmp/output" 2> "$tmp/control" &
    active=$!
    finish 6; valid 130
    no_live_marker "$marker"
    ok

    check="$interpreter runner: a deliberate background job does not delay normal completion"
    marker="notchpad-test-$$-$interpreter-background"
    start 1 login "$test_cwd" ": $marker; sleep 300 & printf 'ready: %s\n' \"\$!\""
    ready; finish 3; valid 0; stop_input
    kill -0 "$child_pids" 2>/dev/null || fail 'the deliberate background child was not left running'
    kill -KILL "$child_pids" || fail 'could not clean up deliberate background child'
    child_pids=
    no_live_marker "$marker"
    ok
done

for user_shell in zsh bash; do
    selected_shell=$(command -v "$user_shell") || continue
    interpreter=sh
    check="sh runner with $user_shell: EOF stops a foreground child in full mode"
    marker="notchpad-test-$$-$user_shell-full-stop"
    start 1 full "$test_cwd" "sh -c 'printf \"ready: %s\n\" \"\$\$\"; exec sleep 300' $marker; :"
    ready; stop_input; finish 1
    # Interactive Bash can catch INT and exit 1 instead of dying by signal.
    if [ "$user_shell" = bash ] && [ "$(tail -n 1 "$tmp/control")" = status=1 ]; then
        valid 1
    else
        valid 130
    fi
    no_live_children; no_live_marker "$marker"
    ok
done

check='installer: stage add-on in a path with spaces'
bundle="$tmp/NotchPad App.app/Contents/Resources/TerminalAddOn"
destination="$tmp/Application Scripts/com.newzeebuild.notchpad"
mkdir -p "$bundle" || fail 'could not create staging folder'
cp "$here/../terminal-addon/install.sh" "$bundle/install.sh" || fail 'could not stage installer'
cp "$runner" "$bundle/notchpad-run" || fail 'could not stage runner'
if [ "$(uname -s)" = Darwin ]; then
    xattr -w com.apple.quarantine '0081;00000000;NotchPad-Test;' "$bundle/notchpad-run" || fail 'could not add test quarantine'
fi
export NOTCHPAD_TEST_ADDON_DIR=$destination
check='installer: rejects root, empty HOME and non-directory HOME before touching the destination'
mkdir "$tmp/root-bin" || fail 'could not create fake root account tool'
printf '%s\n' '#!/bin/sh' 'printf "0\n"' > "$tmp/root-bin/id"
chmod 755 "$tmp/root-bin/id" || fail 'could not make fake id executable'
expect_install_refusal() {
    local message=$1
    shift
    if "$@" > "$tmp/output" 2> "$tmp/control"; then fail 'unsafe installer invocation succeeded'; fi
    grep -Fqx "$message" "$tmp/control" || fail 'incorrect refusal message'
    [ ! -e "${destination%/*}" ] || fail 'installer touched destination despite refusal'
}
expect_install_refusal 'Run this without sudo.' env PATH="$tmp/root-bin:$PATH" HOME="$test_home" \
    /bin/sh "$bundle/install.sh"
expect_install_refusal 'Could not find your home folder.' env HOME= /bin/sh "$bundle/install.sh"
expect_install_refusal 'Could not find your home folder.' env HOME="$bundle/notchpad-run" /bin/sh "$bundle/install.sh"
ok

check='installer: byte-identical, executable, idempotent and removable through paths with spaces'
/bin/sh "$bundle/install.sh" > "$tmp/output" 2> "$tmp/control" || fail 'install failed'
grep -Fq 'click Check again' "$tmp/output" || fail 'missing install instructions'
installed="$destination/notchpad-run"
cmp -s "$installed" "$runner" && [ -x "$installed" ] || fail 'installed runner differs or is not executable'
if [ "$(uname -s)" = Darwin ]; then
    [ -z "$(xattr "$installed")" ] || fail 'installed runner has extended attributes'
fi
/bin/sh "$bundle/install.sh" > "$tmp/output" 2> "$tmp/control" || fail 're-install failed'
cmp -s "$installed" "$runner" || fail 're-install changed file contents'
/bin/sh "$bundle/install.sh" --remove > "$tmp/output" 2> "$tmp/control" || fail 'remove failed'
[ ! -e "$destination" ] || fail 'remove left the runner or its empty folder'
/bin/sh "$bundle/install.sh" --remove > "$tmp/output" 2> "$tmp/control" || fail 'remove was not harmless when already absent'
ok
