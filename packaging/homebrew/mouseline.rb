# Homebrew cask for MouseLine. Lives in the tap repository opendino/homebrew-tap as
# Casks/mouseline.rb; scripts/update-cask.sh fills in version and sha256 for a release.
cask "mouseline" do
  version "0.1.0"
  sha256 "REPLACED_BY_UPDATE_CASK_SH"

  url "https://github.com/opendino/mouseline/releases/download/v#{version}/MouseLine-#{version}.dmg"
  name "MouseLine"
  desc "Mouse gestures: draw shapes to control windows, media and apps"
  homepage "https://github.com/opendino/mouseline"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "MouseLine.app"

  uninstall quit: "app.mouseline"

  zap trash: [
    "~/Library/Application Support/MouseLine",
    "~/Library/Preferences/app.mouseline.plist",
  ]

  caveats <<~EOS
    MouseLine needs Accessibility access: the welcome guide opens the right place, or go to
    System Settings → Privacy & Security → Accessibility and switch MouseLine on.

    Until MouseLine is notarized by Apple, macOS may block the first launch. Then open
    System Settings → Privacy & Security and click "Open Anyway" next to MouseLine.
  EOS
end
