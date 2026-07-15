#!/usr/bin/env bash
# scripts/notarize-release.sh
# Signs OpenTab.app with a Developer ID identity + hardened runtime, notarizes
# it with Apple, staples the ticket, and produces a distributable zip that
# passes Gatekeeper on any Mac.
#
# One-time setup (creates the keychain profile referenced below):
#   xcrun notarytool store-credentials OpenTab-Notary \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Then:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="OpenTab-Notary" ./scripts/notarize-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEV_ID:?Set DEV_ID to your 'Developer ID Application: … (TEAMID)' identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile name}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
ZIP="OpenTab-${VERSION}.zip"
SUBMIT_ZIP="OpenTab-notarize.zip"

echo "==> Building"
make build
rm -rf OpenTab.app
mkdir -p OpenTab.app/Contents/MacOS OpenTab.app/Contents/Resources
cp .build/release/OpenTab OpenTab.app/Contents/MacOS/OpenTab
cp Info.plist OpenTab.app/Contents/Info.plist
iconutil -c icns Resources/AppIcon.iconset -o OpenTab.app/Contents/Resources/AppIcon.icns
cp Resources/menubar/MenubarIcon.png OpenTab.app/Contents/Resources/MenubarIcon.png
cp Resources/menubar/MenubarIcon@2x.png OpenTab.app/Contents/Resources/MenubarIcon@2x.png

echo "==> Signing (Developer ID + hardened runtime)"
codesign --force --options runtime --timestamp --sign "$DEV_ID" OpenTab.app
codesign --verify --deep --strict --verbose=2 OpenTab.app

echo "==> Submitting to Apple notary service"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent OpenTab.app "$SUBMIT_ZIP"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$SUBMIT_ZIP"

echo "==> Stapling ticket"
xcrun stapler staple OpenTab.app
spctl --assess --type execute --verbose=2 OpenTab.app

echo "==> Packaging distributable zip"
rm -f "$ZIP"
ditto -c -k --keepParent OpenTab.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat <<EOF

Notarized & stapled $ZIP
  version: $VERSION
  sha256:  $SHA

This build passes Gatekeeper on any Mac. Attach it to the GitHub release and set
version/sha256 in Casks/opentab.rb.
EOF
