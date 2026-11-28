cask "notchpad" do
  version "1.2.0"
  sha256 "c848260889ea08fa43127a7d7c5d60ae773a6abacc20c6c9d056b58f006b0f3e"

  url "https://github.com/brucewindsornz-sudo/notchpad/releases/download/v#{version}/NotchPad.dmg"
  name "NotchPad"
  desc "Private scratchpad that lives in the MacBook camera notch"
  homepage "https://github.com/brucewindsornz-sudo/notchpad"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "NotchPad.app"

  # NotchPad is ad-hoc signed, not Apple-notarised: clear the download quarantine so macOS
  # doesn't show the "Move to Trash" warning on first launch.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/NotchPad.app"]
  end

  uninstall quit: "com.newzeebuild.notchpad"

  # brew uninstall --zap notchpad also deletes notes, settings and the terminal add-on.
  zap trash: [
    "~/Library/Containers/com.newzeebuild.notchpad",
    "~/Library/Application Support/NotchPad",
    "~/Library/Preferences/com.newzeebuild.notchpad.plist",
    "~/Library/Application Scripts/com.newzeebuild.notchpad",
  ]

  caveats <<~EOS
    Optional terminal mode is off by default. To enable it, open NotchPad
    Settings › Terminal mode and run the install command shown there.
  EOS
end
