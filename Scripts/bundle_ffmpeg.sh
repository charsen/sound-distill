#!/bin/bash
# 把 Homebrew 的 ffmpeg/ffprobe 及其非系统动态库打进 app bundle。
# 这样用户机器上即使没有 ffmpeg，也能直接使用。
set -euo pipefail

APP="${1:?用法: bundle_ffmpeg.sh /path/to/App.app}"
DEST="$APP/Contents/Resources/ffmpeg"

if [[ -n "${AUDIOEXTRACT_FFMPEG_DIR:-}" ]]; then
    SRC="$AUDIOEXTRACT_FFMPEG_DIR"
else
    SRC=""
    for dir in "$(dirname "$(command -v ffmpeg 2>/dev/null || echo /nonexistent)")" /opt/homebrew/bin /usr/local/bin; do
        if [[ -x "$dir/ffmpeg" && -x "$dir/ffprobe" ]]; then
            SRC="$dir"
            break
        fi
    done
fi

if [[ -z "$SRC" || ! -x "$SRC/ffmpeg" ]]; then
    echo "错误：BUNDLE_FFMPEG=1 但未找到 ffmpeg；请安装 Homebrew ffmpeg 或显式使用 BUNDLE_FFMPEG=0" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/bin" "$DEST/lib"
cp -L "$SRC/ffmpeg" "$DEST/bin/ffmpeg"
cp -L "$SRC/ffprobe" "$DEST/bin/ffprobe"
chmod u+w "$DEST/bin/ffmpeg" "$DEST/bin/ffprobe"

# 递归复制非系统 dylib，并把依赖改写成 @loader_path / @executable_path。
process_binary() {
    local binary="$1"
    local is_exec="$2"
    local dep name lib

    for dep in $(otool -L "$binary" | tail -n +2 | awk '{print $1}'); do
        case "$dep" in
            /System/*|/usr/lib/*|@*)
                continue
                ;;
            *.dylib)
                name="$(basename "$dep")"
                lib="$DEST/lib/$name"
                if [[ ! -f "$lib" ]]; then
                    if [[ ! -f "$dep" ]]; then
                        echo "错误：依赖不存在 ${dep}（来自 ${binary}）" >&2
                        exit 1
                    fi
                    cp -L "$dep" "$lib"
                    chmod u+w "$lib"
                    process_binary "$lib" 0
                    install_name_tool -id "@loader_path/$name" "$lib"
                fi
                if [[ "$is_exec" == "1" ]]; then
                    install_name_tool -change "$dep" "@executable_path/../lib/$name" "$binary"
                else
                    install_name_tool -change "$dep" "@loader_path/$name" "$binary"
                fi
                ;;
        esac
    done
}

process_binary "$DEST/bin/ffmpeg" 1
process_binary "$DEST/bin/ffprobe" 1

# 剩余 @rpath 依赖会依赖构建机环境，不能随包携带。
if otool -L "$DEST/bin/ffmpeg" "$DEST/bin/ffprobe" | grep -q '@rpath'; then
    echo "错误：仍有未解析的 @rpath 依赖" >&2
    otool -L "$DEST/bin/ffmpeg" "$DEST/bin/ffprobe" | grep '@rpath' >&2
    exit 1
fi

echo "已内置 ffmpeg：$(du -sh "$DEST" | awk '{print $1}')"
