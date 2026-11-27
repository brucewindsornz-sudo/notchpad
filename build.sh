#!/bin/bash
# Builds NotchPad.app. Needs Apple's Command Line Tools (run: xcode-select --install).
#   ./build.sh            build into ./build/NotchPad.app
#   ./build.sh --install  build, copy to /Applications and open it
#   ./build.sh --universal  build for both Apple Silicon and Intel
set -euo pipefail
cd "$(dirname "$0")"
APP=build/NotchPad.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() { swiftc -O -target "$1-apple-macos13.0" -o "$2" Sources/*.swift; }

if [[ " $* " == *" --universal "* ]]; then
  compile arm64 build/NotchPad-arm64
  compile x86_64 build/NotchPad-x86_64
  lipo -create build/NotchPad-arm64 build/NotchPad-x86_64 -output "$APP/Contents/MacOS/NotchPad"
  rm build/NotchPad-arm64 build/NotchPad-x86_64
else
  compile "$(uname -m)" "$APP/Contents/MacOS/NotchPad"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.png ]] && command -v iconutil >/dev/null; then
  ICONSET=build/AppIcon.iconset; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf "$ICONSET"
fi
mkdir -p "$APP/Contents/Resources/TerminalAddOn"
cp terminal-addon/notchpad-run terminal-addon/install.sh "$APP/Contents/Resources/TerminalAddOn/"
chmod 755 "$APP/Contents/Resources/TerminalAddOn/notchpad-run" "$APP/Contents/Resources/TerminalAddOn/install.sh"
codesign --force --sign - --options runtime --entitlements Resources/NotchPad.entitlements "$APP"
echo "Built $APP"

if [[ " $* " == *" --install "* ]]; then
  pkill -x NotchPad 2>/dev/null || true
  rm -rf /Applications/NotchPad.app
  cp -R "$APP" /Applications/
  xattr -dr com.apple.quarantine /Applications/NotchPad.app 2>/dev/null || true
  open /Applications/NotchPad.app
  echo "Installed to /Applications and opened. Look at your notch."
fi
