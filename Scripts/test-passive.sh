#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
export CLASHBAR_PASSIVE_TEST_ROOT="$(mktemp -d "$CLASHBAR_BUILD_DIR/PassiveTests.XXXXXX")"
uv run --no-project Tests/Integration/passive-latency-server.py > "$CLASHBAR_PASSIVE_TEST_ROOT/server.log" 2>&1 &
task_server=$!
trap 'kill "$task_server" 2>/dev/null || true' EXIT
for attempt in {1..100}; do
    [[ -f "$CLASHBAR_PASSIVE_TEST_ROOT/port" ]] && break
    sleep 0.1
done
[[ -f "$CLASHBAR_PASSIVE_TEST_ROOT/port" ]]
xcrun swiftc -swift-version 5 -D APP_STORE -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$CLASHBAR_BUILD_DIR/ModuleCache" Sources/Core/*.swift \
    Sources/App/AppModel.swift Sources/App/Preferences.swift Sources/App/HistoryModel.swift \
    Tests/Integration/PassiveAppTests.swift -o "$CLASHBAR_PASSIVE_TEST_ROOT/passive-app-tests"
"$CLASHBAR_PASSIVE_TEST_ROOT/passive-app-tests"
