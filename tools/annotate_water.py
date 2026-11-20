#!/usr/bin/env python3
"""给地图导出「水面」网格，供冲浪判定。

FRLG 的水面 metatile behavior 在这套数据里统一是 MB_NORMAL（拿不到），
所以改按渲染出来的颜色判断：水体是明显的蓝色，且比同图其它色更蓝。
逐格取中心 4x4 像素投票，超过一半偏蓝就算水。
输出 emerald_maps/<map>.json 的 water 字段（1 = 水面）。
"""
import glob
import json
import os
from collections import Counter

from PIL import Image

EMAPS = "/root/build/pokesaga/content/emerald_maps"


def is_blue(r, g, b):
    return b > 110 and b > g + 35 and b > r + 55


def grid_from_png(png, w, h):
    im = Image.open(png).convert("RGB")
    px = im.load()
    iw, ih = im.size
    if iw < w * 16 or ih < h * 16:
        return None
    grid = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            votes = 0
            tot = 0
            for dy in (6, 8, 10):
                for dx in (6, 8, 10):
                    r, g, b = px[x * 16 + dx, y * 16 + dy]
                    tot += 1
                    if is_blue(r, g, b):
                        votes += 1
            if votes * 2 > tot:
                grid[y][x] = 1
    return grid


INDOOR = ("gym", "mart", "pokemon_center", "pokemoncenter", "house", "school", "museum",
          "bike", "department", "tower", "lab", "playershouse", "professor")


def main():
    total_maps = 0
    for mp in sorted(glob.glob(os.path.join(EMAPS, "*.json"))):
        meta = json.load(open(mp))
        name = os.path.basename(mp)[:-5]
        size = meta.get("size") or [0, 0]
        w, h = int(size[0]), int(size[1])
        if w <= 0 or h <= 0:
            continue
        png = os.path.join(EMAPS, name + "_full.png")
        if not os.path.exists(png):
            png = os.path.join(EMAPS, str(meta.get("png", name + ".png")))
        if not os.path.exists(png):
            continue
        meta.pop("water", None)
        if any(k in name for k in INDOOR):
            json.dump(meta, open(mp, "w"), separators=(",", ":"))
            continue
        grid = grid_from_png(png, w, h)
        if grid is None:
            continue
        meta["water"] = grid
        json.dump(meta, open(mp, "w"), separators=(",", ":"))
        n = sum(sum(r) for r in grid)
        if n:
            print("%-26s %dx%d 水面格 %d" % (name, w, h, n))
            total_maps += 1
    print("有水面的地图", total_maps)


if __name__ == "__main__":
    main()
