cask "notchpad" do
  version "1.1.1"
  sha256 "1f7bfe259d2fcfd0d329e79bda5b60b93247a166d51f40fb86b46cca01d10037"

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

  # brew uninstall --zap notchpad also deletes notes and settings.
  zap trash: [
    "~/Library/Containers/com.newzeebuild.notchpad",
    "~/Library/Application Support/NotchPad",
    "~/Library/Preferences/com.newzeebuild.notchpad.plist",
  ]
end
