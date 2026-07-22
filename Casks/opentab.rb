# Casks/opentab.rb
# Homebrew cask. Run `make release` to build the zip and print the version +
# sha256 to paste below, then attach the zip to a matching GitHub Release.
cask "opentab" do
  version "0.3.0"
  sha256 "cecb9a1925b27067590a03cd973674074673a153009287ed85d6833d8c641718"

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
