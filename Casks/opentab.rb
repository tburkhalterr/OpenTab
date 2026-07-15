# Casks/opentab.rb
# Homebrew cask. Run `make release` to build the zip and print the version +
# sha256 to paste below, then attach the zip to a matching GitHub Release.
cask "opentab" do
  version "0.2.0"
  sha256 "07d49f0df9bebc165ed6036fb76a2af06e390c70dc35191d1d116fa774ed3b67"

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
