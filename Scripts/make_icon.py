#!/usr/bin/env python3
"""生成「音萃 SoundDistill」的应用图标（可重复执行）。"""
from __future__ import annotations

import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Resources"
ICONSET = ROOT / "build" / "AppIcon.iconset"
ICNS = OUT_DIR / "AppIcon.icns"


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


def make_background(size: int) -> Image.Image:
    # 对角渐变：深夜蓝 -> 青绿
    start = (12, 24, 52)
    end = (9, 126, 120)
    gradient = Image.new("RGB", (size, size))
    pixels = gradient.load()
    for y in range(size):
        for x in range(size):
            t = (x * 0.42 + y * 0.58) / size
            # 轻微 S 曲线让中间更亮
            t = t ** 0.9
            pixels[x, y] = lerp(start, end, min(t, 1.0))

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.225), fill=255)
    canvas.paste(gradient, (0, 0), mask)

    # 左上柔光
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-size * 0.25, -size * 0.35, size * 0.62, size * 0.5], fill=(120, 255, 235, 26))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.08))
    canvas.alpha_composite(glow)

    # 背景细波纹
    wave = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wave)
    for i in range(5):
        y = size * (0.16 + i * 0.16)
        points = []
        for x in range(0, size + 20, 20):
            yy = y + math.sin(x / size * math.pi * 2 + i) * size * 0.018
            points.append((x, yy))
        wd.line(points, fill=(255, 255, 255, 12), width=int(size * 0.006))

    wave_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(wave_mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.225), fill=255)
    wave.putalpha(Image.composite(wave.getchannel("A"), Image.new("L", (size, size), 0), wave_mask))
    canvas.alpha_composite(wave)
    return canvas


def draw_symbol(canvas: Image.Image) -> None:
    size = canvas.size[0]
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    # 左侧：视频画框
    frame = [size * 0.145, size * 0.325, size * 0.435, size * 0.675]
    stroke = int(size * 0.034)
    draw.rounded_rectangle(frame, radius=int(size * 0.055), outline=(235, 252, 250, 242), width=stroke)

    # 画框中的播放三角
    triangle = [
        (size * 0.232, size * 0.405),
        (size * 0.358, size * 0.5),
        (size * 0.232, size * 0.595),
    ]
    draw.polygon(triangle, fill=(255, 255, 255, 248))

    # 右侧：音频波形条
    bar_specs = [
        (0.505, 0.18, 0.72),
        (0.575, 0.30, 0.86),
        (0.645, 0.46, 1.0),
        (0.715, 0.34, 0.92),
        (0.785, 0.22, 0.76),
    ]
    bar_width = size * 0.048
    for x_ratio, height_ratio, alpha in bar_specs:
        h = size * height_ratio
        x = size * x_ratio
        y0 = (size - h) / 2
        color = (255, 255, 255, int(255 * alpha))
        if abs(x_ratio - 0.645) < 0.001:
            color = (137, 255, 215, 255)  # 中间一根薄荷绿，呼应音质
        draw.rounded_rectangle(
            [x, y0, x + bar_width, y0 + h],
            radius=bar_width / 2,
            fill=color,
        )

    # 底部小横线，像一段音轨
    draw.rounded_rectangle(
        [size * 0.505, size * 0.735, size * 0.833, size * 0.752],
        radius=size * 0.009,
        fill=(255, 255, 255, 70),
    )

    # 轻投影，让小图标也有层次
    shadow = layer.filter(ImageFilter.GaussianBlur(size * 0.012))
    shadow.putalpha(shadow.getchannel("A").point(lambda v: int(v * 0.45)))
    canvas.alpha_composite(shadow, (0, int(size * 0.008)))
    canvas.alpha_composite(layer)


def main() -> None:
    size = 1024
    icon = make_background(size)
    draw_symbol(icon)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)

    # 带圆角与透明外边的 1024 母图
    master = OUT_DIR / "AppIcon-1024.png"
    icon.save(master)

    mappings = {
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
    for name, pixel_size in mappings.items():
        resized = icon.resize((pixel_size, pixel_size), Image.LANCZOS)
        resized.save(ICONSET / name)

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"generated {ICNS}")


if __name__ == "__main__":
    main()
