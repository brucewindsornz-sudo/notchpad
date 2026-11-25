#!/bin/bash
# Double-click to create NotchPad.dmg (a drag-to-Applications installer) in this folder.
cd "$(dirname "$0")"
clear
echo "== Making NotchPad.dmg =="
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are needed. Click Install in the window that pops up."
  xcode-select --install 2>/dev/null || true
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
fi
if ./make-dmg.sh; then
  cp build/NotchPad.dmg ./NotchPad.dmg
  echo
  echo "Created NotchPad.dmg in this folder. Opening it now: drag NotchPad onto Applications."
  open ./NotchPad.dmg
else
  echo "Something went wrong. Copy the messages above and send them over."
fi
echo
read -n 1 -s -r -p "Press any key to close this window."
