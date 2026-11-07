#!/bin/bash

if [[ "${CLASHBAR_ENV_READY:-}" != 1 ]]; then
    CLASHBAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    CLASHBAR_SSD_ROOT=""
    CLASHBAR_SSD_UUID=""
    if [[ -f "$CLASHBAR_ROOT/Scripts/build-storage.local.sh" ]]; then
        source "$CLASHBAR_ROOT/Scripts/build-storage.local.sh"
    fi
    CLASHBAR_BUILD_DIR="$CLASHBAR_ROOT/build"
    if [[ "${CLASHBAR_STORAGE:-auto}" != auto && "${CLASHBAR_STORAGE:-auto}" != local ]]; then
        echo "错误：CLASHBAR_STORAGE 仅支持 auto 或 local。" >&2
        return 1
    fi
    if [[ "${CLASHBAR_STORAGE:-auto}" == auto && -n "$CLASHBAR_SSD_ROOT" && -n "$CLASHBAR_SSD_UUID" && -d "$CLASHBAR_SSD_ROOT" ]]; then
        CLASHBAR_VOLUME_DEVICE="$(df -P "$CLASHBAR_SSD_ROOT" | awk 'NR == 2 { print $1 }')"
        CLASHBAR_VOLUME_UUID="$(diskutil info -plist "$CLASHBAR_VOLUME_DEVICE" 2>/dev/null | plutil -extract VolumeUUID raw -o - - 2>/dev/null || true)"
        if [[ "$CLASHBAR_VOLUME_UUID" == "$CLASHBAR_SSD_UUID" && -w "$CLASHBAR_SSD_ROOT" ]]; then
            CLASHBAR_BUILD_DIR="$CLASHBAR_SSD_ROOT/ClashBar/build"
        fi
    fi
    if [[ -z "${DEVELOPER_DIR:-}" ]]; then
        if [[ "$CLASHBAR_BUILD_DIR" != "$CLASHBAR_ROOT/build" && -x "$CLASHBAR_SSD_ROOT/Xcode.app/Contents/Developer/usr/bin/xcodebuild" ]]; then
            DEVELOPER_DIR="$CLASHBAR_SSD_ROOT/Xcode.app/Contents/Developer"
        else
            DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
            if [[ ! -d "$DEVELOPER_DIR" ]]; then
                DEVELOPER_DIR="/Library/Developer/CommandLineTools"
            fi
        fi
    fi
    export DEVELOPER_DIR
    xcrun --find swiftc >/dev/null
    mkdir -p "$CLASHBAR_BUILD_DIR/ModuleCache" "$CLASHBAR_BUILD_DIR/tmp"
    export TMPDIR="$CLASHBAR_BUILD_DIR/tmp/"
    export CLANG_MODULE_CACHE_PATH="$CLASHBAR_BUILD_DIR/ModuleCache"
    export SWIFT_MODULECACHE_PATH="$CLASHBAR_BUILD_DIR/ModuleCache"
    export CLASHBAR_BUILD_DIR
    export CLASHBAR_ENV_READY=1
    echo "▸ 构建目录：$CLASHBAR_BUILD_DIR"
    echo "▸ 开发工具：$DEVELOPER_DIR"
fi
