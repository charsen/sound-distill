#!/bin/bash
# 把 build/音萃 SoundDistill.app 打成可分发的 DMG。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/音萃 SoundDistill.app"

if [[ ! -d "$APP" ]]; then
    echo "请先运行 Scripts/build_app.sh" >&2
    exit 1
fi

VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo 1.0.0)"
DMG="$ROOT/build/音萃 SoundDistill-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
chmod 755 "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "音萃 SoundDistill" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "已生成：${DMG}（$(du -h "$DMG" | awk '{print $1}')）"
