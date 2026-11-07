#!/bin/bash
# 构建 ClashBar.app：先跑核心测试，再编译、组装、签名。
# 用法：Scripts/build.sh            本机架构
#       Scripts/build.sh --universal 同时编译 arm64 + x86_64（发布用）
# 环境变量 SIGN_IDENTITY 可指定 Developer ID；缺省为临时（ad hoc）签名。
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
source Scripts/build-env.sh
BUILD="$CLASHBAR_BUILD_DIR"
if [[ "${CLASHBAR_UPDATE_TEST:-0}" == 1 ]]; then
    BUILD="$CLASHBAR_BUILD_DIR/UpdateSmoke/Build"
fi
APP="$BUILD/ClashBar.app"
MIN_OS="13.0"
UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1

mkdir -p "$BUILD/ModuleCache"
FLAGS=(-swift-version 5 -module-cache-path "$BUILD/ModuleCache")
DISTRIBUTION="${CLASHBAR_DISTRIBUTION:-direct}"
UPDATE_FLAGS=()
if [[ "$DISTRIBUTION" == app-store ]]; then
    UPDATE_FLAGS=(-D APP_STORE)
elif [[ "$DISTRIBUTION" == direct ]]; then
    Scripts/fetch-sparkle.sh
    SPARKLE_DIR="$CLASHBAR_BUILD_DIR/Dependencies/Sparkle-2.10.1"
    UPDATE_FLAGS=(-F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
else
    echo '错误：CLASHBAR_DISTRIBUTION 仅支持 direct 或 app-store。' >&2
    exit 1
fi
if [[ "${CLASHBAR_UPDATE_TEST:-0}" == 1 ]]; then
    [[ "$DISTRIBUTION" == direct ]] || exit 1
    UPDATE_FLAGS+=(-D UPDATE_TESTING)
fi

# 部分 Command Line Tools 版本里 SwiftBridging 模块重复定义，用项目内的 VFS overlay 屏蔽旧 modulemap（不改系统文件）
OLD_MAP="$DEVELOPER_DIR/usr/include/swift/module.modulemap"
NEW_MAP="$DEVELOPER_DIR/usr/include/swift/bridging.modulemap"
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
        "${UPDATE_FLAGS[@]}" "${CORE[@]}" "${APP_SOURCES[@]}" -o "$BUILD/ClashBar-$arch"
    BINARIES+=("$BUILD/ClashBar-$arch")
done

echo "▸ 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ClashBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ "${CLASHBAR_UPDATE_TEST:-0}" == 1 ]]; then
    /usr/libexec/PlistBuddy -c 'Add :ClashBarUpdateTest bool true' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :ClashBarUpdateTestRoot string ${CLASHBAR_UPDATE_TEST_ROOT:?}" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${CLASHBAR_UPDATE_TEST_ID:?}" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 9001' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.2-beta.1' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${CLASHBAR_UPDATE_TEST_FEED:?}" "$APP/Contents/Info.plist"
fi
if [[ "$DISTRIBUTION" == direct ]]; then
    mkdir -p "$APP/Contents/Frameworks"
    ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
    cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"
    if [[ -f Resources/UpdatePublicKey.txt ]]; then
        UPDATE_PUBLIC_KEY="$(tr -d '\r\n' < Resources/UpdatePublicKey.txt)"
        /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $UPDATE_PUBLIC_KEY" "$APP/Contents/Info.plist"
    fi
else
    /usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :SUEnableAutomaticChecks' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :SUAutomaticallyUpdate' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :SUScheduledCheckInterval' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :SUEnableSystemProfiling' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :SUVerifyUpdateBeforeExtraction' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Delete :SURequireSignedFeed' "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"

echo "▸ 签名"
if [[ "$DISTRIBUTION" == direct && -n "${SIGN_IDENTITY:-}" ]]; then
    for component in \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
        "$APP/Contents/Frameworks/Sparkle.framework"; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$component"
    done
fi
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "✓ 已生成 ${APP}（$(lipo -archs "$APP/Contents/MacOS/ClashBar")）"
