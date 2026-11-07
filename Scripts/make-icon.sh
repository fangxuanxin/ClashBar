#!/bin/bash
# 重新生成 Resources/AppIcon.icns（改了 make-icon.swift 后运行）
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
WORK="$CLASHBAR_BUILD_DIR/icon"
rm -rf "$WORK" && mkdir -p "$WORK/AppIcon.iconset" "$CLASHBAR_BUILD_DIR/ModuleCache"
FLAGS=(-module-cache-path "$CLASHBAR_BUILD_DIR/ModuleCache")
OLD_MAP="$DEVELOPER_DIR/usr/include/swift/module.modulemap"
if [[ -f "$OLD_MAP" && -f "$DEVELOPER_DIR/usr/include/swift/bridging.modulemap" ]]; then
    : > "$CLASHBAR_BUILD_DIR/empty.modulemap"
    printf '{"version":0,"roots":[{"type":"file","name":"%s","external-contents":"%s"}]}' "$OLD_MAP" "$CLASHBAR_BUILD_DIR/empty.modulemap" > "$CLASHBAR_BUILD_DIR/overlay.json"
    FLAGS+=(-vfsoverlay "$CLASHBAR_BUILD_DIR/overlay.json" -Xcc -ivfsoverlay -Xcc "$CLASHBAR_BUILD_DIR/overlay.json")
fi
xcrun swiftc "${FLAGS[@]}" -parse-as-library Scripts/make-icon.swift Sources/App/CatGlyph.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/icon_1024.png"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 256:icon_128x128@2x \
            256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
    sips -z "${spec%%:*}" "${spec%%:*}" "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/${spec##*:}.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/icon_1024.png" Resources/AppIcon-1024.png
echo "✓ Resources/AppIcon.icns"
