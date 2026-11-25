#!/bin/bash
# Builds NotchPad.app and wraps it in a drag-to-Applications disk image: build/NotchPad.dmg
set -euo pipefail
cd "$(dirname "$0")"

./build.sh --universal || { echo "Universal build failed, building for this Mac only"; ./build.sh; }

VOL="NotchPad"
STAGE=build/dmg-stage
RW=build/NotchPad-rw.dmg
OUT=build/NotchPad.dmg
rm -rf "$STAGE" "$RW" "$OUT"
mkdir -p "$STAGE/.background"

cp -R build/NotchPad.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if command -v tiffutil >/dev/null; then
  tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png -out "$STAGE/.background/background.tiff" >/dev/null 2>&1 \
    || cp Resources/dmg/background.png "$STAGE/.background/background.tiff"
else
  cp Resources/dmg/background.png "$STAGE/.background/background.tiff"
fi
[[ -f build/NotchPad.app/Contents/Resources/AppIcon.icns ]] && cp build/NotchPad.app/Contents/Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# Eject any old copy that's still mounted.
[[ -d "/Volumes/$VOL" ]] && hdiutil detach "/Volumes/$VOL" -quiet -force || true

hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size 80m "$RW"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
echo "Laying out the installer window (macOS may ask to let Terminal control Finder: click OK)…"

# Custom volume icon (optional tool).
SETFILE=$(xcrun -f SetFile 2>/dev/null || command -v SetFile || true)
[[ -n "$SETFILE" && -f "$MOUNT/.VolumeIcon.icns" ]] && "$SETFILE" -a C "$MOUNT" || true

osascript <<OSA || echo "(Couldn't arrange the window; the disk image still works.)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 562}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "NotchPad.app" of container window to {170, 222}
    set position of item "Applications" of container window to {470, 222}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
hdiutil convert "$RW" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -f "$RW"; rm -rf "$STAGE"
echo "Created $OUT"
