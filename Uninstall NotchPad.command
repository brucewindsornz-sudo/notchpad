#!/bin/bash
# Double-click to remove NotchPad. Asks before deleting your notes.
clear
echo "== Uninstall NotchPad =="
pkill -x NotchPad 2>/dev/null || true
rm -rf /Applications/NotchPad.app && echo "Removed NotchPad from Applications."
if [[ -e ~/Library/Application\ Scripts/com.newzeebuild.notchpad ]]; then
  rm -rf ~/Library/Application\ Scripts/com.newzeebuild.notchpad && echo "Removed the terminal add-on."
fi
read -r -p "Also delete your notes and settings? This can't be undone. (y/N) " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  rm -rf ~/Library/Containers/com.newzeebuild.notchpad
  rm -rf ~/Library/Application\ Support/NotchPad
  defaults delete com.newzeebuild.notchpad 2>/dev/null || true
  security delete-generic-password -s com.newzeebuild.notchpad >/dev/null 2>&1 || true
  echo "Notes, settings and the encryption key have been deleted."
else
  echo "Your notes were kept. Reinstalling NotchPad will bring them back."
fi
echo
read -n 1 -s -r -p "Press any key to close this window."
