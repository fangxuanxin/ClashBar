#!/bin/bash
# 构建并安装到 ~/Applications，然后启动（开发自用）
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build.sh
DEST="$HOME/Applications"
mkdir -p "$DEST"
osascript -e 'quit app "ClashBar"' 2>/dev/null || true
pkill -x ClashBar 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/ClashBar.app"
cp -R build/ClashBar.app "$DEST/"
open "$DEST/ClashBar.app"
echo "✓ 已安装并启动 $DEST/ClashBar.app"
