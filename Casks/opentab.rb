# Casks/opentab.rb
# Homebrew cask. Publish a zipped OpenTab.app as a GitHub Release asset,
# then fill in `version` and `sha256` (shasum -a 256 OpenTab.zip).
cask "opentab" do
  version "0.1.0"
  sha256 :no_check # replace with the real checksum once a release is published

  url "https://github.com/socraft/opentab/releases/download/v#{version}/OpenTab.zip"
  name "OpenTab"
  desc "Free, open-source AltTab-style window switcher for macOS"
  homepage "https://github.com/socraft/opentab"

  depends_on macos: ">= :ventura"

  app "OpenTab.app"

  caveats <<~EOS
    OpenTab needs Accessibility permission to switch windows.
    On first launch, grant it in:
      System Settings → Privacy & Security → Accessibility
    then relaunch OpenTab.
  EOS
end
