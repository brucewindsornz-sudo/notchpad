# NotchPad

A private scratchpad that lives in your MacBook's camera notch.

- Hover over the notch: it nudges out a little.
- Click: it expands into a scratchpad. Esc or the arrow closes it.
- Pin it (or turn on "Keep the scratchpad open") to leave it open.
- Control + Option + N opens/closes it from anywhere.

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
