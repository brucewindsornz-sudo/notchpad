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
With Homebrew:

    brew tap brucewindsornz-sudo/notchpad https://github.com/brucewindsornz-sudo/notchpad
    brew install --cask notchpad

Update with `brew update && brew upgrade --cask notchpad`. Remove with
`brew uninstall --cask notchpad` (add `--zap` to also delete notes and settings).

Without Homebrew, open Terminal and paste:

    curl -fsSL https://raw.githubusercontent.com/brucewindsornz-sudo/notchpad/master/install.sh | bash

It downloads the latest NotchPad, puts it in Applications and opens it. Downloading through
Terminal avoids macOS's "Move to Trash" warning for apps that aren't Apple-notarised.

**Already downloaded the .dmg or zip and got "Move to Trash"?** Click Done (not Move to Trash), then:

    xattr -dr com.apple.quarantine /Applications/NotchPad.app      # after dragging from the .dmg
    xattr -dr com.apple.quarantine ~/Downloads/notchpad            # for the zip folder, then double-click again

Other options in this folder: `Install NotchPad.command` (build on this Mac),
`Make NotchPad.dmg.command` (make a drag-to-Applications disk image),
`Uninstall NotchPad.command`. Needs macOS 13 Ventura or later.
