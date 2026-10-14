#!/bin/bash
# Builds a notarized, stapled Fresh-<version>.dmg in dist/, ready to publish.
#
# One-time setup (see README): a "Developer ID Application" certificate in the keychain,
# and notarization credentials stored under the profile name below:
#   xcrun notarytool store-credentials fresh-notary \
#     --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-fresh-notary}"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || { echo "error: no Developer ID Application certificate in the keychain" >&2; exit 1; }

scripts/test.sh
scripts/bundle.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Fresh.app/Contents/Info.plist)
IDENTITY=$(codesign -dvv Fresh.app 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)/\1/p')
mkdir -p dist
DMG="dist/Fresh-$VERSION.dmg"

# 1. Notarize the app itself and staple the ticket, so it verifies offline once copied out.
ditto -c -k --keepParent Fresh.app dist/Fresh-notarize.zip
xcrun notarytool submit dist/Fresh-notarize.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple Fresh.app
rm dist/Fresh-notarize.zip

# 2. Disk image with an Applications shortcut for drag-to-install; sign, notarize, staple.
STAGE=$(mktemp -d)
cp -R Fresh.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Fresh $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Release ready: $(pwd)/$DMG"
