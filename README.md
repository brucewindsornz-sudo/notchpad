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
Needs macOS 13 Ventura or later. NotchPad is built on your own Mac (it takes about a minute).

**Easiest:** double-click `Install NotchPad.command`. It installs Apple's free Command Line
Tools if needed, builds NotchPad, puts it in Applications and starts it.

**Drag-to-Applications installer:** double-click `Make NotchPad.dmg.command`. It creates
`NotchPad.dmg` in this folder and opens it; drag NotchPad onto Applications. You can keep the
.dmg to reinstall later.

**Remove:** double-click `Uninstall NotchPad.command` (asks before deleting your notes).

If macOS says a .command file "can't be opened", right-click it and choose Open
(on macOS 15: System Settings › Privacy & Security › Open Anyway). Or run it in Terminal:
    bash "Install NotchPad.command"

Terminal equivalents: `./build.sh --install`, `./make-dmg.sh`.
