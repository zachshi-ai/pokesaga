#!/usr/bin/env python3
"""把「树冠」补进人物遮挡层。

原版 GBA 把树冠画在 BG1（人上面），但也有不少树的整格都在底层，
于是人走到树后面时脑袋会盖住树，看着像踩在树上。
这里按颜色判断：不可走 + 绿色为主的格子视为树冠，把整格贴进 <map>_fg.png。
只处理还没被遮挡层覆盖的格子，不碰别的建筑。
"""
import json
import os

from PIL import Image

EMAPS = "/root/build/pokesaga/content/emerald_maps"


def greenish(px):
    r, g, b = px[0], px[1], px[2]
    if px[3] == 0:
        return False
    return g > 60 and g > r + 12 and g > b + 12


def resolve(name):
    """分块大地图（kanto_main_3_2）没有自己的 json，要用母图的碰撞表 + 偏移。"""
    meta_p = os.path.join(EMAPS, name + ".json")
    off = (0, 0)
    if not os.path.exists(meta_p):
        parts = name.rsplit("_", 2)
        if len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
            parent = parts[0]
            pm = os.path.join(EMAPS, parent + ".json")
            if not os.path.exists(pm):
                return None, (0, 0)
            off = (int(parts[1]) * 24, int(parts[2]) * 24)
            meta_p = pm
        else:
            return None, (0, 0)
    return meta_p, off


def fix_map(name):
    base_p = os.path.join(EMAPS, name + ".png")
    fg_p = os.path.join(EMAPS, name + "_fg.png")
    meta_p, off = resolve(name)
    if not (os.path.exists(base_p) and meta_p):
        return 0
    meta = json.load(open(meta_p))
    coll = meta.get("collision") or []
    if not coll:
        return 0
    base = Image.open(base_p).convert("RGBA")
    fg = Image.open(fg_p).convert("RGBA") if os.path.exists(fg_p) else Image.new("RGBA", base.size, (0, 0, 0, 0))
    if fg.size != base.size:
        fg = Image.new("RGBA", base.size, (0, 0, 0, 0))
    w, h = base.size[0] // 16, base.size[1] // 16
    added = 0
    ox, oy = off
    for y in range(h):
        gy = y + oy
        if gy >= len(coll):
            continue
        row = coll[gy]
        for x in range(w):
            gx = x + ox
            if gx >= len(row):
                continue
            if int(row[gx]) == 0:
                continue
            tile = base.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16))
            px = tile.load()
            greens = 0
            for yy in range(16):
                for xx in range(16):
                    if greenish(px[xx, yy]):
                        greens += 1
            if greens < 120:
                continue
            fg.paste(tile, (x * 16, y * 16))
            added += 1
    if added:
        fg.save(fg_p)
    return added


def main():
    total = 0
    for f in sorted(os.listdir(EMAPS)):
        if not f.endswith(".png") or f.endswith("_fg.png"):
            continue
        name = f[:-4]
        n = fix_map(name)
        if n:
            total += n
    print("补进遮挡层的树格", total)


if __name__ == "__main__":
    main()
