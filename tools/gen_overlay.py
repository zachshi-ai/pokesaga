#!/usr/bin/env python3
"""给每张原版地图额外生成一张「人物之上」的图层贴图。

原版 GBA 的野外画面是两个背景层，精灵夹在中间：
  NORMAL  —— 底 4 块画在人下面，顶 4 块画在人上面（屋顶、墙头、树冠、招牌）
  COVERED —— 8 块全在人下面
  SPLIT   —— 底 4 块在下，顶 4 块在上

之前把所有 metatile 压成一张平面图，人自然永远压在屋顶上。
这里只抠出「该盖住人」的那部分，单独出 <map>_fg.png，
运行时摆到角色之上，遮挡关系就跟原版一致了。
"""
import json, os, glob, struct, sys
from PIL import Image

ROOT = "/root/build/pokeemerald-expansion-master"
EMAPS = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions"

sys.path.insert(0, "/root/build/pokesaga/tools")
from render_emerald_maps import get_primary, get_secondary

LAYOUTS = {}
for lay in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]:
    LAYOUTS[lay["id"]] = lay


def fg_of_layout(lay):
    w, h = int(lay["width"]), int(lay["height"])
    prim = get_primary(lay["primary_tileset"])
    sec = get_secondary(lay["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return None
    data = open(os.path.join(ROOT, lay["blockdata_filepath"]), "rb").read()
    if len(data) < w * h * 2:
        return None
    img = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 0))
    pc = prim.count
    for y in range(h):
        for x in range(w):
            val = struct.unpack_from("<H", data, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            if ts.layer_type(local) == 1:      # COVERED：全在人下面
                continue
            try:
                _, above = ts.render_split(local)
            except Exception:
                continue
            if above.getbbox() is None:
                continue
            img.paste(above, (x * 16, y * 16), above)
    return img


def main():
    used = {}
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        d = json.load(open(f))
        if d.get("emerald"):
            used[os.path.normcase(d["emerald"])] = f

    made = 0
    for name in used:
        meta_path = os.path.join(EMAPS, name + ".json")
        if not os.path.exists(meta_path):
            continue
        meta = json.load(open(meta_path))

        if meta.get("composed") and meta.get("member_maps"):
            # 拼过的大地图：各成员图按偏移贴进大画布
            sz = meta["size"]
            big = Image.new("RGBA", (sz[0] * 16, sz[1] * 16), (0, 0, 0, 0))
            for key, at in meta["member_maps"].items():
                lay = LAYOUTS.get(key) or LAYOUTS.get("LAYOUT_" + key.upper())
                if not lay:
                    cand = [v for k, v in LAYOUTS.items() if k.upper().endswith("_" + key.upper())]
                    lay = cand[0] if cand else None
                if not lay:
                    print("  ! 找不到布局", key)
                    continue
                piece = fg_of_layout(lay)
                if piece is None:
                    continue
                big.paste(piece, (int(at[0]) * 16, int(at[1]) * 16), piece)
            out = os.path.join(EMAPS, name + "_fg.png")
            big.save(out)
            # 分块版，和底图同一套 chunk 名
            for c in meta.get("chunks", []):
                x0, y0 = c["at"]
                x1 = min(sz[0], x0 + 24)
                y1 = min(sz[1], y0 + 24)
                crop = big.crop((x0 * 16, y0 * 16, x1 * 16, y1 * 16))
                crop.save(os.path.join(EMAPS, c["png"].replace(".png", "_fg.png")))
            print("%-36s composed %dx%d" % (name, sz[0], sz[1]))
            made += 1
        else:
            lay = LAYOUTS.get(meta.get("id", ""))
            if not lay:
                continue
            img = fg_of_layout(lay)
            if img is None:
                continue
            img.save(os.path.join(EMAPS, name + "_fg.png"))
            print("%-36s %dx%d" % (name, img.width // 16, img.height // 16))
            made += 1
    print("fg done", made)


if __name__ == "__main__":
    main()
