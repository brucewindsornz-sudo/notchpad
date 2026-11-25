# NotchPad

A private scratchpad that lives in your MacBook's camera notch.

- Hover over the notch: it nudges out a little.
- Click: it expands into a scratchpad. Esc or the arrow closes it.
- Pin it (or turn on "Keep the scratchpad open") to leave it open.
- Control + Option + N opens/closes it from anywhere.
- Drag the top bar to move it anywhere; drag the bottom-right corner to resize.
  Drop it near the notch to tuck it back in. Size and position are remembered
  after a restart, and if it was pinned open it reopens on launch.

## Privacy
- App Sandbox with no network entitlement: macOS blocks all internet access.
- Notes are encrypted (AES-256-GCM) on disk; the key lives in your login Keychain.
- Hidden from screenshots and screen sharing by default.
- Optional Touch ID lock, blur-when-away and auto-erase.

## Install
Prebuilt: unzip NotchPad.zip, move NotchPad.app to Applications, then run once:
    xattr -dr com.apple.quarantine /Applications/NotchPad.app
From source (needs `xcode-select --install`):
    ./build.sh --install

Requires macOS 13 Ventura or later. Works on Macs without a notch too (sits at the top centre).
