#!/bin/bash
# 构建 ClashBar.app：先跑核心测试，再编译、组装、签名。
# 用法：Scripts/build.sh            本机架构
#       Scripts/build.sh --universal 同时编译 arm64 + x86_64（发布用）
# 环境变量 SIGN_IDENTITY 可指定 Developer ID；缺省为临时（ad hoc）签名。
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/ClashBar.app"
MIN_OS="13.0"
UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1

mkdir -p "$BUILD/ModuleCache"
FLAGS=(-swift-version 5 -module-cache-path "$BUILD/ModuleCache")

# 部分 Command Line Tools 版本里 SwiftBridging 模块重复定义，用项目内的 VFS overlay 屏蔽旧 modulemap（不改系统文件）
OLD_MAP=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
NEW_MAP=/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap
if [[ -f "$OLD_MAP" && -f "$NEW_MAP" ]]; then
    : > "$BUILD/empty.modulemap"
    printf '{"version":0,"roots":[{"type":"file","name":"%s","external-contents":"%s"}]}' "$OLD_MAP" "$BUILD/empty.modulemap" > "$BUILD/overlay.json"
    FLAGS+=(-vfsoverlay "$BUILD/overlay.json" -Xcc -ivfsoverlay -Xcc "$BUILD/overlay.json")
fi

CORE=(Sources/Core/*.swift)
APP_SOURCES=(Sources/App/*.swift)

echo "▸ 运行核心测试"
xcrun swiftc "${FLAGS[@]}" -parse-as-library -target "$(uname -m)-apple-macosx$MIN_OS" \
    "${CORE[@]}" Tests/*.swift -o "$BUILD/core-tests"
"$BUILD/core-tests"

echo "▸ 编译应用"
if [[ $UNIVERSAL == 1 ]]; then ARCHS=(arm64 x86_64); else ARCHS=("$(uname -m)"); fi
BINARIES=()
for arch in "${ARCHS[@]}"; do
    xcrun swiftc "${FLAGS[@]}" -O -parse-as-library -target "$arch-apple-macosx$MIN_OS" \
        "${CORE[@]}" "${APP_SOURCES[@]}" -o "$BUILD/ClashBar-$arch"
    BINARIES+=("$BUILD/ClashBar-$arch")
done

echo "▸ 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ClashBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"

echo "▸ 签名"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ 已生成 ${APP}（$(lipo -archs "$APP/Contents/MacOS/ClashBar")）"
