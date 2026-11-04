#!/bin/bash
# 重新生成 Resources/AppIcon.icns（改了 make-icon.swift 后运行）
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="build/icon"
rm -rf "$WORK" && mkdir -p "$WORK/AppIcon.iconset" build/ModuleCache
FLAGS=(-module-cache-path build/ModuleCache)
OLD_MAP=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [[ -f "$OLD_MAP" && -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]]; then
    : > build/empty.modulemap
    printf '{"version":0,"roots":[{"type":"file","name":"%s","external-contents":"%s"}]}' "$OLD_MAP" "$PWD/build/empty.modulemap" > build/overlay.json
    FLAGS+=(-vfsoverlay build/overlay.json -Xcc -ivfsoverlay -Xcc build/overlay.json)
fi
xcrun swiftc "${FLAGS[@]}" Scripts/make-icon.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/icon_1024.png"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 256:icon_128x128@2x \
            256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
    sips -z "${spec%%:*}" "${spec%%:*}" "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/${spec##*:}.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/icon_1024.png" Resources/AppIcon-1024.png
echo "✓ Resources/AppIcon.icns"
