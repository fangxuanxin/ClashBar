#!/bin/bash
# 生成发布用的通用二进制压缩包：build/ClashBar.zip，并打印 sha256（填 Homebrew cask 用）
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build.sh --universal
rm -f build/ClashBar.zip
ditto -c -k --sequesterRsrc --keepParent build/ClashBar.app build/ClashBar.zip
echo "✓ build/ClashBar.zip"
shasum -a 256 build/ClashBar.zip
