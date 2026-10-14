#!/bin/bash
# Runs the unit tests. With Command Line Tools only (no Xcode), SwiftPM does not find
# the Swift Testing macro plugin on its own, so point the compiler at it.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
