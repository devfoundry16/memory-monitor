#!/bin/bash
# Builds a universal (Apple Silicon + Intel) release binary and wraps it in Fresh.app.
# Signs with a "Developer ID Application" certificate from the keychain when one is
# installed (hardened runtime + secure timestamp, as notarization requires);
# otherwise signs ad hoc, which runs only on this Mac.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  pick a specific certificate
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Fresh"
APP="Fresh.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Fresh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "No Developer ID certificate found: signed ad hoc (runs on this Mac only)"
fi
codesign --verify --strict "$APP"
echo "Built $(pwd)/$APP"
