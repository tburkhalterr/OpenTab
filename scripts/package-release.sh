#!/usr/bin/env bash
# scripts/package-release.sh
# Builds OpenTab.app, zips it for distribution, and prints the version + sha256
# to drop into Casks/opentab.rb (or to attach to a GitHub Release).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
ZIP="OpenTab-${VERSION}.zip"

make app
rm -f "$ZIP"
# ditto makes a macOS-correct archive that preserves the .app bundle.
ditto -c -k --keepParent OpenTab.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat <<EOF

Packaged $ZIP
  version: $VERSION
  sha256:  $SHA

Release checklist:
  1. gh release create "v${VERSION}" "$ZIP" --title "v${VERSION}" --generate-notes
  2. Set   version "${VERSION}"   and   sha256 "${SHA}"   in Casks/opentab.rb
  3. Push Casks/opentab.rb to a "tburkhalterr/homebrew-tap" repo
  4. brew install --cask tburkhalterr/tap/opentab

NOTE: this build is signed with the self-signed "OpenTab Dev" cert. For a public
release that passes Gatekeeper on other Macs, sign with a Developer ID identity
and notarize (xcrun notarytool) before zipping.
EOF
