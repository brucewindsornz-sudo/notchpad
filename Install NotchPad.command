#!/bin/bash
# Double-click to build NotchPad on this Mac and install it in Applications.
cd "$(dirname "$0")"
clear
echo "== NotchPad installer =="
echo
if ! xcode-select -p >/dev/null 2>&1; then
  echo "NotchPad is built on your Mac with Apple's free Command Line Tools."
  echo "A window will pop up: click Install and wait for it to finish (a few minutes)."
  xcode-select --install 2>/dev/null || true
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  echo "Command Line Tools installed."
fi
echo "Building NotchPad…"
if ./build.sh --install; then
  echo
  echo "Done. NotchPad is in Applications and running. Look at the notch at the top of your screen."
  echo "Tip: turn on 'Start when I log in' in NotchPad's settings (gear button)."
else
  echo
  echo "The build didn't finish. Copy the messages above and send them over so they can be fixed."
fi
echo
read -n 1 -s -r -p "Press any key to close this window."
