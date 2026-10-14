#!/bin/bash
# Builds a release binary and wraps it in an ad-hoc-signed MemoryMonitor.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MemoryMonitor"
APP="MemoryMonitor.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MemoryMonitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $(pwd)/$APP"
