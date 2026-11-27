#!/bin/sh
# Run this in Terminal to install or remove NotchPad's optional command runner.
set -e
uid=$(id -u)
if [ "$uid" = 0 ]; then
    printf '%s\n' 'Run this without sudo.' >&2
    exit 1
fi
if [ -z "${HOME-}" ] || [ ! -d "$HOME" ]; then
    printf '%s\n' 'Could not find your home folder.' >&2
    exit 1
fi
destination=${NOTCHPAD_TEST_ADDON_DIR:-"$HOME/Library/Application Scripts/com.newzeebuild.notchpad"}
case $destination in /*) ;; *) destination=./$destination ;; esac

if [ "$#" -eq 1 ] && [ "$1" = --remove ]; then
    rm -f "$destination/notchpad-run"
    rmdir "$destination" 2>/dev/null || :
    printf '%s\n' 'The NotchPad command runner is removed.'
elif [ "$#" -eq 0 ]; then
    case $0 in */*) source_dir=${0%/*} ;; *) source_dir=. ;; esac
    mkdir -p "$destination"
    if [ -d "$destination/notchpad-run" ]; then
        printf '%s\n' 'A folder is in the way of installing the command runner.' >&2
        exit 1
    fi
    temporary=$(mktemp "$destination/.notchpad-run.XXXXXXXX")
    trap 'rm -f "$temporary"' EXIT
    trap 'exit 1' HUP INT TERM
    # Write only the bytes, not the source attributes (such as quarantine).
    cat "$source_dir/notchpad-run" > "$temporary"
    chmod 755 "$temporary"
    mv -f "$temporary" "$destination/notchpad-run"
    xattr -c "$destination/notchpad-run" 2>/dev/null || :
    printf '%s\n' 'The NotchPad command runner is installed.'
else
    printf '%s\n' 'Use install.sh or install.sh --remove.' >&2
    exit 64
fi
printf '%s\n' "Go back to NotchPad's Settings and click Check again."
