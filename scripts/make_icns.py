#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def centered_square_crop_bounds(width: int, height: int, side: int) -> tuple[int, int, int, int]:
    left = (width - side) // 2
    top = (height - side) // 2
    return (left, top, left + side, top + side)


def build_prepared_icon(image: Image.Image, fill_ratio: float = 0.64) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    min_dim = min(width, height)

    alpha = rgba.getchannel("A")
    bbox = alpha.getbbox()

    if bbox is None:
        crop_side = int(min_dim * fill_ratio)
        crop_box = centered_square_crop_bounds(width, height, max(1, crop_side))
    else:
        left, top, right, bottom = bbox
        content_w = max(1, right - left)
        content_h = max(1, bottom - top)
        content_side = max(content_w, content_h)

        if bbox == (0, 0, width, height):
            # Fully opaque image: use a fixed center crop so the icon appears less zoomed out.
            crop_side = int(min_dim * fill_ratio)
            crop_box = centered_square_crop_bounds(width, height, max(1, crop_side))
        else:
            target_side = int(content_side / fill_ratio)
            crop_side = max(content_side, min(min_dim, target_side))
            center_x = (left + right) / 2
            center_y = (top + bottom) / 2
            crop_left = int(round(center_x - crop_side / 2))
            crop_top = int(round(center_y - crop_side / 2))
            crop_left = max(0, min(width - crop_side, crop_left))
            crop_top = max(0, min(height - crop_side, crop_top))
            crop_box = (crop_left, crop_top, crop_left + crop_side, crop_top + crop_side)

    prepared = rgba.crop(crop_box).resize((1024, 1024), Image.Resampling.LANCZOS)
    return prepared


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("Usage: make_icns.py <input_png> <output_icns> [fill_ratio]", file=sys.stderr)
        return 1

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    fill_ratio = float(sys.argv[3]) if len(sys.argv) == 4 else 0.64

    if not input_path.exists():
        print(f"Icon source not found: {input_path}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(input_path) as source:
        prepared = build_prepared_icon(source, fill_ratio=fill_ratio)
        # Pillow's ICNS writer will generate required representations from this source.
        prepared.save(
            output_path,
            format="ICNS",
            sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)],
        )

    print(f"Wrote icon: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
