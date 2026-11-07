#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/build-env.sh
[[ "${CLASHBAR_DISTRIBUTION:-direct}" == direct && "${CLASHBAR_UPDATE_TEST:-0}" == 0 ]] || { echo '错误：正式更新只能使用 direct 正式构建。' >&2; exit 1; }
: "${SIGN_IDENTITY:?需要 Developer ID Application 签名身份}"
: "${APPLE_NOTARY_PROFILE:?需要 notarytool 钥匙串凭证名称}"
security find-identity -v -p codesigning | /usr/bin/grep -F -- "$SIGN_IDENTITY" >/dev/null
[[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]] || { echo '错误：必须使用 Developer ID Application。' >&2; exit 1; }
export CLASHBAR_SIGNING_KEY_FILE="${CLASHBAR_SIGNING_KEY_FILE:-$HOME/Library/Application Support/ClashBar/UpdateSigning/ed25519.privatekey}"
PUBLIC_KEY="$(xcrun swift Scripts/update-key.swift)"
[[ "$PUBLIC_KEY" == "$(tr -d '\r\n' < Resources/UpdatePublicKey.txt)" ]] || { echo '错误：更新私钥与应用公钥不匹配。' >&2; exit 1; }
Scripts/build.sh --universal
APP="$CLASHBAR_BUILD_DIR/ClashBar.app"
codesign --verify --deep --strict "$APP"
codesign --verify -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
export CLASHBAR_RELEASE_DIR="$CLASHBAR_BUILD_DIR/releases/$VERSION-$BUILD_NUMBER"
[[ ! -e "$CLASHBAR_RELEASE_DIR" ]] || { echo '错误：该版本产物已存在；请检查后再处理，避免覆盖。' >&2; exit 1; }
mkdir -p "$CLASHBAR_RELEASE_DIR"
ditto -c -k --keepParent "$APP" "$CLASHBAR_RELEASE_DIR/notarization.zip"
xcrun notarytool submit "$CLASHBAR_RELEASE_DIR/notarization.zip" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$CLASHBAR_RELEASE_DIR/ClashBar.zip"
export CLASHBAR_RELEASE_APP="$APP"
uv run Scripts/release-feed.py
rm "$CLASHBAR_RELEASE_DIR/notarization.zip"
echo "✓ 已生成签名、公证和验签通过的发布候选：$CLASHBAR_RELEASE_DIR"
echo '尚未上传 GitHub，也未更新公开 appcast 或 Homebrew。发布步骤见 docs/updates.md。'
