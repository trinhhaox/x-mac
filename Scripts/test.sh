#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SWIFTC_PATH="$(xcrun --find swiftc)"
SWIFT_USR_DIR="$(dirname "$(dirname "$SWIFTC_PATH")")"
TESTING_PLUGIN="$SWIFT_USR_DIR/lib/swift/host/plugins/testing/libTestingMacros.dylib"

if [[ -f "$TESTING_PLUGIN" ]]; then
    swift test --package-path "$PROJECT_DIR" \
        -Xswiftc -load-plugin-library \
        -Xswiftc "$TESTING_PLUGIN"
else
    swift test --package-path "$PROJECT_DIR"
fi
