#!/bin/bash
# 构建并安装到 ~/Applications，然后启动（开发自用）
set -euo pipefail
cd "$(dirname "$0")/.."
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
cp -R build/ClashBar.app "$DEST/"
if [[ -d "$HOME/Applications/ClashBar.app" ]]; then
    rm -rf "$HOME/Applications/ClashBar.app"
fi
rm -rf build/ClashBar.app build/icon
rm -f build/ClashBar-arm64 build/ClashBar-x86_64 build/ClashBar.zip
touch "$DEST/ClashBar.app"
if [[ -f "$LEGACY_AGENT" ]]; then
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $DEST/ClashBar.app/Contents/MacOS/ClashBar" "$LEGACY_AGENT"
    launchctl bootstrap "gui/$(id -u)" "$LEGACY_AGENT"
fi
open "$DEST/ClashBar.app"
echo "✓ 已安装并启动 $DEST/ClashBar.app"
