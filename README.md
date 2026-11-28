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
- Optional terminal mode (Settings › Terminal mode): run shell commands right in the pad
  and copy the output or add it to your note, via a small script you install yourself.
- 33 built-in themes, including 12 special themes with their own font, text style and
  matching closing animation, plus Ghostty theme file import.
- Eight closing animations (Lightning, Matrix, Teleport, Stargate, Black hole, Old TV, Dust
  and Burn) with adjustable speed, plus Classic, Match theme and Surprise me.

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

- 33 built-in themes: 21 classic colour palettes (Catppuccin, Dracula, Nord, Tokyo Night,
  Gruvbox, Solarized, Rosé Pine, One Dark, Monokai, Kanagawa, Everforest, GitHub and NotchPad's
  own) plus 12 special themes (under the Special filter) with their own font, text style, glow
  and paired closing animation: Matrix, Stargate, Storm, Transporter, Singularity, Phosphor,
  Chalkboard, Ember Typewriter, Field Notes, Blueprint, Neon District and Morning Edition.
- **Theme's own font:** the Font setting defaults to "Theme's own font", so each special
  theme brings its own look automatically. Pick a different font in Settings to override the
  font family while keeping the theme's colours, spacing and glow.
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
font-family = Menlo
font-style = Bold
notchpad-font-size-scale = 1.0
notchpad-line-spacing = 2
notchpad-letter-spacing = 0.5
notchpad-glow = #ffcc66
notchpad-close = teleport
```

`background` and `foreground` are required. `cursor-color` sets the cursor and highlights
(if it's missing, `palette = 4=` is used), and `selection-background` sets the text selection.

All style keys are optional (unknown or invalid values are ignored):

- `font-family`: any installed font family or PostScript name, or `mono`, `serif`, `rounded`,
  `system` (falls back to the system font if unavailable).
- `font-style`: `Regular`, `Light`, `Medium`, `Semibold`, `Bold`, `Italic` or `Bold Italic`.
- `notchpad-font-size-scale`: text size ratio from `0.75` to `1.5`.
- `notchpad-line-spacing`: extra line spacing from `0` to `12` pt.
- `notchpad-letter-spacing`: letter spacing from `-1` to `4` pt.
- `notchpad-glow`: text glow colour (`#RGB` or `#RRGGBB`).
- `notchpad-close`: paired closing animation (`lightning`, `matrix`, `teleport`, `stargate`,
  `blackHole`, `tv`, `dust` or `burn`).

## Closing animations
Choose how the pad shuts in Settings › Closing animation:

- **Eight animations:** Lightning, Matrix, Teleport, Stargate, Black hole, Old TV, Dust and Burn.
- **Match theme** (default) plays the active theme's paired animation, or the classic close if
  it has none. You can also pick **Classic**, **Surprise me** (a different animation each time),
  or any single animation.
- **Speed:** Quick, Normal or Slow, with live previews in Settings.
- **Reduce motion:** if macOS Reduce motion is turned on in System Settings, NotchPad skips
  custom closing animations and uses the classic close.

## Terminal mode (optional add-on)
Click the terminal icon in the pad's top bar and it turns the theme's accent colour, switching
the pad from your note to a command line. Type a command, press Return, and the output appears
right in the pad.

It is a command runner, not a full terminal:

- One command runs at a time, with output kept up to about 200 000 characters per command.
  There is no support for `sudo`, password prompts, or full-screen programs such as `vim` or
  `htop` (use Terminal for those).
- Click Stop or press Control + C to stop a running command. Press Control + L or type `clear`
  to clear the transcript, and type `exit` to return to your note.
- Changing directory with `cd` carries over to the next command in `zsh`, `bash`, `sh`, `dash`
  and `ksh` (other shells such as `fish` still run commands, but `cd` does not carry over).
- Press Up and Down to step through your command history (kept in memory only, not across
  restarts).
- Use the small buttons beside the input row to copy the last command's output, add the last
  command and its output to your note, or clear the transcript.

**How to switch it on:** open Settings › Terminal mode, turn it on, copy the install command,
and paste it into Terminal once. If a future NotchPad update changes the add-on script, Settings
will let you know so you can paste the install command again.

**How to remove it:** click Copy remove command in Settings › Terminal mode and paste it into
Terminal, or run:

```sh
rm -rf ~/Library/Application\ Scripts/com.newzeebuild.notchpad
```

**Shell setup and permissions:** commands run in your login shell, so `PATH` changes from your
login profile (such as Homebrew in `~/.zprofile`) work out of the box. Turn on "Load my full
shell setup" in Settings › Terminal mode if you also want your interactive shell setup
(`~/.zshrc` for zsh, `~/.bashrc` for bash) for aliases and functions. macOS may ask once for
permission before commands can read protected folders such as Desktop, Documents or Downloads.

## Privacy
- App Sandbox with no network entitlement: macOS blocks all internet access from NotchPad itself,
  and nothing changes unless you install the optional terminal add-on.
- With the terminal add-on installed, commands you run from the pad run outside NotchPad as you,
  much as they would in Terminal, so those commands can use the internet and your files. Commands,
  history and output are held in memory only and are never saved unless you add them to your note.
  macOS only lets you (never NotchPad) put the add-on script in place.
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
