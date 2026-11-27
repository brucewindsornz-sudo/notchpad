# NotchPad

A private scratchpad that lives in your MacBook's camera notch.

## Install with Homebrew

```sh
brew tap brucewindsornz-sudo/notchpad https://github.com/brucewindsornz-sudo/notchpad
brew trust brucewindsornz-sudo/notchpad
brew install --cask notchpad
```

The `brew trust` line is a one-time step: recent Homebrew versions ask you to approve
taps from outside Homebrew before installing from them. The cask also clears macOS's
download quarantine, so there's no "Move to Trash" warning on first launch.

| To | Run |
| --- | --- |
| Update | `brew update && brew upgrade --cask notchpad` |
| Uninstall | `brew uninstall --cask notchpad` |
| Uninstall and delete notes and settings | `brew uninstall --cask --zap notchpad` |

Needs macOS 13 Ventura or later. Built for Apple Silicon and Intel.

## Features

- Hover over the notch: it nudges out a little.
- Click: it expands into a scratchpad. Esc or the arrow closes it.
- Pin it (or turn on "Keep the scratchpad open") to leave it open.
- Control + Option + N opens/closes it from anywhere.
- Settings › Pad buttons explains every button along the top of the pad and lets you hide
  the ones you don't use (Settings and Close always stay).
- Moved it somewhere? Click the boomerang button on its top bar and it flies back into the notch.
- Drag the move button (next to the bin) or the top bar to move it anywhere; drag the
  bottom-right corner to resize. Bring it back near the notch and it's pulled in and
  snaps to the centre, like a magnet. Size and position are remembered
  after a restart, and if it was pinned open it reopens on launch.

## If the pad ever gets stuck

A moved pad always stays below the menu bar and on screen, so its buttons can be reached. If it
still ends up somewhere awkward, any of these gets you out:

- Esc closes it, and Control + Option + N opens/closes it from any app.
- Right-click the pad's top bar: Close, Put Back in Notch, Reset Position and Size, Quit.
- Menu bar icon › Reset Position and Size.
- Command + Q quits NotchPad while the pad is in use.
- Hold Option while NotchPad starts: it goes back into the notch at its normal size, closed.
- From Terminal: `pkill -x NotchPad` quits it.

## Themes
Like Ghostty, NotchPad has a theme gallery (Settings › Theme, or the menu bar icon › Theme):

- 21 built-in themes, including Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, Solarized,
  Rosé Pine, One Dark, Monokai, Kanagawa, Everforest and GitHub, plus NotchPad's own.
- **Match light and dark mode:** pick one theme for Light mode and one for Dark mode.
- **Bring your own:** NotchPad reads Ghostty's theme file format, so any Ghostty theme works
  as it is. Use Import theme files… (it opens Ghostty's themes folder if Ghostty is installed),
  or drop files into the Themes folder and click Reload.

A theme file is plain text:

```
background = #1f2430
foreground = #cbccc6
cursor-color = #ffcc66
selection-background = #33415e
```

`background` and `foreground` are required. `cursor-color` sets the cursor and highlights
(if it's missing, `palette = 4=` is used), and `selection-background` sets the text selection.

## Privacy
- App Sandbox with no network entitlement: macOS blocks all internet access.
- Notes are encrypted (AES-256-GCM) on disk; the key lives in your login Keychain.
- Hidden from screenshots and screen sharing by default.
- Optional Touch ID lock, blur-when-away and auto-erase.
- Clipboard: copies clear themselves after 1 minute by default (30 s to 5 min, or never),
  and when your Mac locks or sleeps. Only NotchPad's own copy is ever wiped automatically.
  Copies stay off Universal Clipboard and are marked so clipboard history apps skip them.
  The clear-clipboard button in the pad (next to Copy; click twice, like the bin), the menu bar icon and Settings wipe the clipboard on demand.

## Other ways to install
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
