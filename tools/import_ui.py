#!/usr/bin/env python3
"""导出原版窗口边框（文字窗口 9 宫格）与光标，供 UI 直接使用。"""
from asset_paths import project_path, source_path

import os
from PIL import Image

SRC = source_path("emerald", "graphics")
OUT = project_path("assets/ui")


def pal(path):
    cols = []
    for ln in open(path, errors="ignore").read().replace("\r", "").split("\n")[3:]:
        p = ln.strip().split()
        if len(p) >= 3:
            cols.append((int(p[0]), int(p[1]), int(p[2])))
    while len(cols) < 16:
        cols.append((0, 0, 0))
    return cols


def rgba(path, pal_path, transparent_zero=True):
    im = Image.open(path).convert("P")
    p = pal(pal_path)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            v = src[x, y]
            if transparent_zero and v == 0:
                continue
            r, g, b = p[v & 0xF]
            dst[x, y] = (r, g, b, 255)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    pl = os.path.join(SRC, "text_window", "text_pal1.pal")
    for i in (1, 2, 3, 6):
        src = os.path.join(SRC, "text_window", "%d.png" % i)
        if os.path.exists(src):
            rgba(src, pl).save(os.path.join(OUT, "window_%d.png" % i))
            print("window_%d.png" % i)
    cur = os.path.join(SRC, "text_window", "arrow_cursor.png")
    if os.path.exists(cur):
        rgba(cur, pl, False).save(os.path.join(OUT, "cursor.png"))
        print("cursor.png")


if __name__ == "__main__":
    main()
