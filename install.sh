#!/bin/bash
# One-line installer:  curl -fsSL https://raw.githubusercontent.com/brucewindsornz-sudo/notchpad/master/install.sh | bash
# Downloads with curl (so macOS doesn't attach the "downloaded from internet" block), installs to /Applications, opens it.
set -euo pipefail
REPO=brucewindsornz-sudo/notchpad
APP=/Applications/NotchPad.app
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "== Installing NotchPad =="

URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | grep -o '"browser_download_url": *"[^"]*NotchPad\.dmg"' | sed 's/.*"\(https[^"]*\)"$/\1/' || true)

pkill -x NotchPad 2>/dev/null || true
if [[ -n "$URL" ]]; then
  echo "Downloading the latest NotchPad…"
  curl -fL --progress-bar "$URL" -o "$TMP/NotchPad.dmg"
  MNT=$(hdiutil attach -nobrowse -readonly -noverify "$TMP/NotchPad.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')
  rm -rf "$APP"
  ditto "$MNT/NotchPad.app" "$APP"
  hdiutil detach "$MNT" -quiet || true
else
  echo "No ready-made download yet, so NotchPad will be built on this Mac (about a minute)."
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Apple's free Command Line Tools are needed. Click Install in the window that pops up."
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/master.tar.gz" | tar xz -C "$TMP"
  "$TMP/notchpad-master/build.sh"
  rm -rf "$APP"
  ditto "$TMP/notchpad-master/build/NotchPad.app" "$APP"
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
echo "Done. NotchPad is in Applications and running. Look at the notch at the top of your screen."
