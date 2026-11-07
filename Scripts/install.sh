#!/bin/bash
# 构建并安装到 ~/Applications，然后启动（开发自用）
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
Scripts/make-icon.sh
Scripts/build.sh
DEST="/Applications"
mkdir -p "$DEST"
LEGACY_AGENT="$HOME/Library/LaunchAgents/local.clashbar.plist"
if [[ -f "$LEGACY_AGENT" ]]; then
    launchctl bootout "gui/$(id -u)" "$LEGACY_AGENT" 2>/dev/null || true
fi
osascript -e 'quit app "ClashBar"' 2>/dev/null || true
pkill -x ClashBar 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/ClashBar.app"
cp -R "$CLASHBAR_BUILD_DIR/ClashBar.app" "$DEST/"
if [[ -d "$HOME/Applications/ClashBar.app" ]]; then
    rm -rf "$HOME/Applications/ClashBar.app"
fi
rm -rf "$CLASHBAR_BUILD_DIR/ClashBar.app" "$CLASHBAR_BUILD_DIR/icon"
rm -f "$CLASHBAR_BUILD_DIR/ClashBar-arm64" "$CLASHBAR_BUILD_DIR/ClashBar-x86_64" "$CLASHBAR_BUILD_DIR/ClashBar.zip"
touch "$DEST/ClashBar.app"
if [[ -f "$LEGACY_AGENT" ]]; then
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $DEST/ClashBar.app/Contents/MacOS/ClashBar" "$LEGACY_AGENT"
    launchctl bootstrap "gui/$(id -u)" "$LEGACY_AGENT"
fi
open "$DEST/ClashBar.app"
echo "✓ 已安装并启动 $DEST/ClashBar.app"
