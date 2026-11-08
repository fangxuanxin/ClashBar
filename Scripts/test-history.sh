#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
export CLASHBAR_HISTORY_TEST_ROOT="$CLASHBAR_BUILD_DIR/HistoryTests/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CLASHBAR_HISTORY_TEST_ROOT"
xcrun swiftc -swift-version 5 -D APP_STORE -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$CLASHBAR_BUILD_DIR/ModuleCache" \
    Sources/Core/*.swift Sources/App/AppModel.swift Sources/App/Preferences.swift \
    Sources/App/HistoryModel.swift Sources/App/HistoryView.swift \
    Tests/Integration/HistoryAppTests.swift -o "$CLASHBAR_HISTORY_TEST_ROOT/history-app-tests"
"$CLASHBAR_HISTORY_TEST_ROOT/history-app-tests"
echo "✓ 历史窗口预览：$CLASHBAR_HISTORY_TEST_ROOT"
