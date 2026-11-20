#!/usr/bin/env python3
"""启动图标 + 应用标题字标。"""
from asset_paths import project_path

from PIL import Image, ImageDraw
import os

OUT = project_path("assets/icons")
os.makedirs(OUT, exist_ok=True)

# 圆形宝球徽标，配色取自数据表里的地形色
BACK = (30, 42, 54)
RED = (208, 78, 66)
RED_D = (172, 58, 50)
WHITE = (238, 240, 236)
WHITE_D = (196, 200, 196)
LINE = (28, 32, 36)


def ball(size, transparent=False):
    S = 8
    n = size * S
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = n // 12
    box = [m, m, n - m, n - m]
    d.ellipse(box, fill=WHITE_D)
    d.ellipse([m + S, m + S, n - m - S, n - m - S], fill=WHITE)
    # 上半红
    d.pieslice(box, 180, 360, fill=RED_D)
    d.pieslice([m + S, m + S, n - m - S, n - m - S], 180, 360, fill=RED)
    # 中带
    cy = n // 2
    d.rectangle([m, cy - 2 * S, n - m, cy + 2 * S], fill=LINE)
    d.rectangle([m, cy - S, n - m, cy + S], fill=WHITE)
    # 中心按钮
    r = n // 9
    d.ellipse([n // 2 - r, cy - r, n // 2 + r, cy + r], fill=LINE)
    d.ellipse([n // 2 - r + S, cy - r + S, n // 2 + r - S, cy + r - S], fill=WHITE)
    d.ellipse([n // 2 - r + 3 * S, cy - r + 3 * S, n // 2 + r - 3 * S, cy + r - 3 * S], fill=(190, 196, 200))
    # 高光
    d.arc([m + 3 * S, m + 3 * S, n - m - 3 * S, cy - 3 * S], 200, 260, fill=(255, 210, 200), width=3 * S)
    return im.resize((size, size), Image.LANCZOS)


def with_bg(size):
    im = Image.new("RGBA", (size, size), BACK + (255,))
    d = ImageDraw.Draw(im)
    # 柔和径向底
    for i in range(14, 0, -1):
        r = int(size * 0.5 * i / 14)
        shade = tuple(min(255, c + int(26 * (14 - i) / 14)) for c in BACK)
        d.ellipse([size // 2 - r, size // 2 - r, size // 2 + r, size // 2 + r], fill=shade + (255,))
    b = ball(int(size * 0.72))
    off = (size - b.width) // 2
    im.alpha_composite(b, (off, off))
    return im


for s in (48, 72, 96, 144, 192, 512):
    with_bg(s).save(f"{OUT}/icon_{s}.png")

# 自适应前景：只有球，四周留 25% 安全边距
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
b = ball(260)
fg.alpha_composite(b, ((432 - 260) // 2, (432 - 260) // 2))
fg.save(f"{OUT}/icon_foreground.png")

print("icons done", sorted(os.listdir(OUT)))
