# Casks/opentab.rb
# Homebrew cask. Run `make release` to build the zip and print the version +
# sha256 to paste below, then attach the zip to a matching GitHub Release.
cask "opentab" do
  version "0.1.0"
  sha256 "cc9ff9ff10bcf6b6dbea1b4e05a47edc903992745b75506e0fbfca9883582ca9"

  url "https://github.com/tburkhalterr/OpenTab/releases/download/v#{version}/OpenTab-#{version}.zip"
  name "OpenTab"
  desc "Free, open-source AltTab-style window switcher for macOS"
  homepage "https://github.com/tburkhalterr/OpenTab"

  depends_on macos: :ventura

  app "OpenTab.app"

  caveats <<~EOS
    OpenTab needs Accessibility permission to switch windows.
    On first launch, grant it in:
      System Settings → Privacy & Security → Accessibility
    then relaunch OpenTab.
  EOS
end
