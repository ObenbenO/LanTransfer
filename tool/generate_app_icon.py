#!/usr/bin/env python3
"""生成与 Material Icons.sync_alt_rounded 相近的双箭头应用图标（白/透明，供 launcher 与各平台合成）。"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
# 描边粗细（与 1024 画布比例接近 24dp 图标里的线宽）
STROKE = 72
HEAD = STROKE * 2.2
WHITE = (255, 255, 255, 255)


def _arrow_line_right(
    draw: ImageDraw.ImageDraw,
    x0: float,
    y: float,
    x1: float,
    color: tuple[int, int, int, int],
    width: float,
) -> None:
    """水平线段，箭头在右侧 (x1)。"""

    hx = HEAD * 0.9
    shaft_end = x1 - hx
    draw.line([(x0, y), (shaft_end, y)], fill=color, width=int(width), joint="curve")
    # 箭头三角（指向右）
    tip = (x1, y)
    p1 = (x1 - hx, y - hx * 0.55)
    p2 = (x1 - hx, y + hx * 0.55)
    draw.polygon([tip, p1, p2], fill=color)


def _arrow_line_left(
    draw: ImageDraw.ImageDraw,
    x0: float,
    y: float,
    x1: float,
    color: tuple[int, int, int, int],
    width: float,
) -> None:
    """水平线段，箭头在左侧 (x0)。"""

    hx = HEAD * 0.9
    shaft_start = x0 + hx
    draw.line([(shaft_start, y), (x1, y)], fill=color, width=int(width), joint="curve")
    tip = (x0, y)
    p1 = (x0 + hx, y - hx * 0.55)
    p2 = (x0 + hx, y + hx * 0.55)
    draw.polygon([tip, p1, p2], fill=color)


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    out = root / "assets" / "app_icon.png"
    out.parent.mkdir(parents=True, exist_ok=True)

    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    pad = SIZE * 0.18
    x0, x1 = pad, SIZE - pad
    # 上：向右；下：向左（与 sync_alt 视觉一致）
    y_top = SIZE * 0.38
    y_bot = SIZE * 0.62

    _arrow_line_right(draw, x0, y_top, x1, WHITE, STROKE)
    _arrow_line_left(draw, x0, y_bot, x1, WHITE, STROKE)

    im.save(out, "PNG")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
