#!/usr/bin/env python3
"""Regenerate Haven favicon / PWA / Apple / OG assets from brand/nori.png."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
NORI = ROOT / "brand" / "nori.png"
PUBLIC = ROOT / "public"


def fit_square(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.Resampling.LANCZOS)


def load_font(size: int) -> ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def write_icons(nori: Image.Image) -> None:
    for name, size in (
        ("favicon-16x16.png", 16),
        ("favicon-32x32.png", 32),
        ("apple-touch-icon.png", 180),
        ("icon-192.png", 192),
        ("icon-512.png", 512),
    ):
        fit_square(nori, size).save(PUBLIC / name, optimize=True)

    maskable = Image.new("RGBA", (512, 512), (0, 0, 0, 255))
    inner = fit_square(nori, 410)
    maskable.paste(inner, ((512 - 410) // 2, (512 - 410) // 2), inner)
    maskable.save(PUBLIC / "icon-maskable-512.png", optimize=True)

    sizes = [(16, 16), (32, 32), (48, 48)]
    ico_images = [fit_square(nori, w) for w, _ in sizes]
    ico_images[-1].save(PUBLIC / "favicon.ico", format="ICO", sizes=sizes)


def write_og(nori: Image.Image) -> None:
    # Match design/og-card.html: black DriftSky field + Haven wordmark.
    width, height = 1200, 630
    og = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(og)
    rng = random.Random(0x5EED11)
    count = min(300, (width * height) // 3600)
    for _ in range(count):
        depth = rng.random()
        x = rng.random() * width
        y = rng.random() * height
        size = 0.5 + depth * 1.6
        base = 0.1 + depth * 0.45
        hot = rng.random() < 0.04
        tw = 0.7 + 0.3 * abs(math.sin(rng.random() * 6.28))
        radius = max(1, int(round(size)))
        if hot:
            color = (10, 132, 255, int(min(255, (base + 0.2) * 255)))
        else:
            color = (255, 255, 255, int(min(255, base * tw * 255)))
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=color,
        )

    nori_og = fit_square(nori, 420)
    mx = width - 80 - 420
    my = (height - 420) // 2 + 10
    og.paste(nori_og, (mx, my), nori_og)

    pad_l = 80
    draw.text((pad_l, 360), "Haven", font=load_font(96), fill=(245, 245, 247, 255))
    draw.text(
        (pad_l, 470),
        "A personal memory layer over the people of your life.",
        font=load_font(30),
        fill=(184, 184, 189, 255),
    )
    draw.text(
        (pad_l, 530),
        "INHAVENS.COM",
        font=load_font(18),
        fill=(152, 152, 157, 255),
    )
    og.convert("RGB").save(PUBLIC / "og.png", optimize=True, quality=92)


def main() -> None:
    if not NORI.is_file():
        raise SystemExit(f"Missing Nori source: {NORI}")
    PUBLIC.mkdir(exist_ok=True)
    nori = Image.open(NORI).convert("RGBA")
    write_icons(nori)
    write_og(nori)
    print(f"Regenerated Haven brand assets from {NORI.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
