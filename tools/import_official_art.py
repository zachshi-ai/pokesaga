#!/usr/bin/env python3
"""从 pokeemerald-expansion 的原始素材里导出官方立绘。

anim_front.png 是 64x128 的两帧动画，取上半帧做静态立绘；
像素值是调色板索引，颜色来自 normal.pal（JASC-PAL）。
索引 0 视为透明。
"""
import csv, json, os
from PIL import Image

ART = "/root/build/pokeemerald-expansion-master/graphics/pokemon"
POKEAPI = "/root/build/pokeapi/pokemon_species.csv"
OUT = "/root/build/pokesaga/assets/mon"


def load_pal(path):
    cols = []
    for ln in open(path, errors="ignore").read().replace("\r", "").split("\n")[3:]:
        p = ln.strip().split()
        if len(p) >= 3:
            cols.append((int(p[0]), int(p[1]), int(p[2])))
    while len(cols) < 16:
        cols.append((0, 0, 0))
    return cols


def convert(src_dir):
    anim = os.path.join(src_dir, "anim_front.png")
    plain = os.path.join(src_dir, "front.png")
    if os.path.exists(anim):
        frame = Image.open(anim).convert("P")
    else:
        # 八、九世代没有两帧动画图，只有单张 front.png
        im = Image.open(plain).convert("RGBA")
        if im.size[0] != 64:
            k = 64.0 / im.size[0]
            im = im.resize((64, max(1, int(im.size[1] * k))), Image.NEAREST)
        canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        canvas.paste(im.crop((0, 0, 64, min(64, im.size[1]))), (0, 0))
        return canvas
    px = frame.load()
    pal = load_pal(os.path.join(src_dir, "normal.pal"))
    out = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    op = out.load()
    for y in range(64):
        for x in range(64):
            v = px[x, y] & 0xF
            if v == 0:
                continue
            r, g, b = pal[v]
            op[x, y] = (r, g, b, 255)
    return out


def norm(x):
    return "".join(ch for ch in x.lower() if ch.isalnum())


def main():
    # 目录名和 pokeapi 的 identifier 有一堆差异（nidoran-f / mr-mime / ho-oh…），
    # 用"去掉非字母数字后比较"的方式匹配，避免维护一堆别名表
    dirs = {}
    for d in os.listdir(ART):
        full = os.path.join(ART, d)
        if os.path.isdir(full) and (os.path.exists(os.path.join(full, "anim_front.png"))
                or os.path.exists(os.path.join(full, "front.png"))):
            dirs[norm(d)] = d

    names = {}
    for r in csv.DictReader(open(POKEAPI)):
        names[int(r["id"])] = r["identifier"]
    os.makedirs(OUT, exist_ok=True)
    species = json.load(open("/root/build/pokesaga/content/species.json"))
    ok, miss = 0, []
    for row in species:
        sid = int(row["id"])
        ident = names.get(sid, "")
        real = dirs.get(norm(ident)) if ident else None
        if not real:
            miss.append(sid)
            continue
        d = os.path.join(ART, real)
        convert(d).save(os.path.join(OUT, "%d.png" % sid))
        ok += 1
    print("exported", ok, "missing", len(miss), miss[:10])


if __name__ == "__main__":
    main()
