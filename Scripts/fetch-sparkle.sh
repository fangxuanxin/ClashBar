#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR="$CLASHBAR_BUILD_DIR/Dependencies/Sparkle-$SPARKLE_VERSION"
if [[ ! -f "$SPARKLE_DIR/.verified-$SPARKLE_SHA256" ]]; then
    mkdir -p "$SPARKLE_DIR"
    ARCHIVE="$SPARKLE_DIR/distribution.tar.xz"
    for attempt in 1 2 3 4 5 6; do
        if printf '%s  %s\n' "$SPARKLE_SHA256" "$ARCHIVE" | shasum -a 256 --check >/dev/null 2>&1; then break; fi
        curl --fail --location --connect-timeout 20 --continue-at - --output "$ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" || true
    done
    printf '%s  %s\n' "$SPARKLE_SHA256" "$ARCHIVE" | shasum -a 256 --check
    tar -xf "$ARCHIVE" -C "$SPARKLE_DIR"
    test -d "$SPARKLE_DIR/Sparkle.framework"
    touch "$SPARKLE_DIR/.verified-$SPARKLE_SHA256"
fi
echo "✓ Sparkle ${SPARKLE_VERSION}：$SPARKLE_DIR"
