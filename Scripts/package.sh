#!/bin/bash
# 生成发布用的通用二进制压缩包：build/ClashBar.zip，并打印 sha256（填 Homebrew cask 用）
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
Scripts/build.sh --universal
rm -f "$CLASHBAR_BUILD_DIR/ClashBar.zip"
ditto -c -k --sequesterRsrc --keepParent "$CLASHBAR_BUILD_DIR/ClashBar.app" "$CLASHBAR_BUILD_DIR/ClashBar.zip"
echo "✓ $CLASHBAR_BUILD_DIR/ClashBar.zip"
shasum -a 256 "$CLASHBAR_BUILD_DIR/ClashBar.zip"
