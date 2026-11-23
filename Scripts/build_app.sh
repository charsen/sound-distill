#!/bin/bash
# 构建「音萃 SoundDistill」.app
# 用法：Scripts/build_app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "用法：Scripts/build_app.sh [debug|release]" >&2
    exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> 编译 Swift（${CONFIG}）"
swift build -c "$CONFIG" --product SoundDistill
swift build -c "$CONFIG" --product sounddistill

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
mkdir -p "$ROOT/build"
cp "$BIN_PATH/sounddistill" "$ROOT/build/sounddistill"
APP="$ROOT/build/音萃 SoundDistill.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/SoundDistill" "$APP/Contents/MacOS/SoundDistill"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod 644 "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ "${BUNDLE_FFMPEG:-1}" == "1" ]]; then
    echo "==> 打包内置 ffmpeg"
    "$ROOT/Scripts/bundle_ffmpeg.sh" "$APP"
    if [[ ! -x "$APP/Contents/Resources/ffmpeg/bin/ffmpeg" || ! -x "$APP/Contents/Resources/ffmpeg/bin/ffprobe" ]]; then
        echo "错误：内置 ffmpeg/ffprobe 缺失，打包中止" >&2
        exit 1
    fi

    # Homebrew 的二进制可能按构建机 SDK 生成较高的 minOS；若不声明，旧系统会装上后无法启动。
    if [[ -f "$APP/Contents/Resources/ffmpeg/bin/ffmpeg" ]]; then
        FFMPEG_MINOS="$(otool -l "$APP/Contents/Resources/ffmpeg/bin/ffmpeg" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
        if [[ -n "$FFMPEG_MINOS" ]]; then
            APP_MINOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo 14.0)"
            EFFECTIVE_MINOS="$(awk -v a="$APP_MINOS" -v b="$FFMPEG_MINOS" 'BEGIN { print (a + 0 > b + 0) ? a : b }')"
            plutil -replace LSMinimumSystemVersion -string "$EFFECTIVE_MINOS" "$APP/Contents/Info.plist"
            echo "==> 最低系统版本按内置 ffmpeg 调整为 ${EFFECTIVE_MINOS}（ffmpeg minOS=${FFMPEG_MINOS}）"
        fi
    fi
else
    echo "==> 跳过内置 ffmpeg（使用系统安装）"
fi

echo "==> 签名（ad-hoc）"
if [[ -d "$APP/Contents/Resources/ffmpeg/lib" ]]; then
    find "$APP/Contents/Resources/ffmpeg/lib" -type f -name '*.dylib' -exec codesign --force --sign - {} \; >/dev/null
    codesign --force --sign - "$APP/Contents/Resources/ffmpeg/bin/ffmpeg" >/dev/null
    codesign --force --sign - "$APP/Contents/Resources/ffmpeg/bin/ffprobe" >/dev/null
fi
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "==> 完成：${APP}"
echo "    大小：$(du -sh "$APP" | awk '{print $1}')"
