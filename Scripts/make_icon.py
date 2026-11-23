#!/usr/bin/env python3
"""生成「音萃 SoundDistill」的 AppIcon.icns。

品牌母版是 Resources/AppIcon-1024.png（V3 深色底品牌图标，已按 macOS 规范做圆角）。
更换品牌图标时：先替换该母版，再运行本脚本生成各尺寸与 .icns。
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "Resources" / "AppIcon-1024.png"
ICONSET = ROOT / "build" / "AppIcon.iconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"

SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"缺少品牌图标母版：{MASTER}")

    icon = Image.open(MASTER).convert("RGBA")
    if icon.size != (1024, 1024):
        icon = icon.resize((1024, 1024), Image.LANCZOS)
        icon.save(MASTER)

    ICONSET.mkdir(parents=True, exist_ok=True)
    for name, pixel_size in SIZES.items():
        icon.resize((pixel_size, pixel_size), Image.LANCZOS).save(ICONSET / name)

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"generated {ICNS}")


if __name__ == "__main__":
    main()
