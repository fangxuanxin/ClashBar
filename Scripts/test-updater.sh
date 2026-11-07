#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
Scripts/fetch-sparkle.sh
SPARKLE_DIR="$CLASHBAR_BUILD_DIR/Dependencies/Sparkle-2.10.1"
xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$CLASHBAR_BUILD_DIR/ModuleCache" \
    -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_DIR" \
    Sources/Core/L10n.swift Sources/Core/Updates.swift Sources/App/UpdateController.swift \
    Tests/Integration/UpdateControllerTests.swift -o "$CLASHBAR_BUILD_DIR/update-controller-tests"
"$CLASHBAR_BUILD_DIR/update-controller-tests"
uv run Tests/Integration/release-feed-tests.py
