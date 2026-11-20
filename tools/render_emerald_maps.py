#!/usr/bin/env python3
"""直接把 pokeemerald 的原版地图（map.bin + 对应 tileset）渲染成 PNG + 碰撞表。

这样房子、树、水、路全部是原版拼好的样子，我不用拿单个 metatile 去拼，
也就不会出现"房子贴图不对、比例不对"的问题。
"""
import json, os, re, struct
from PIL import Image

ROOT = "/root/build/pokeemerald-expansion-master"
OUT = "/root/build/pokesaga/content/emerald_maps"
TS = os.path.join(ROOT, "data/tilesets")

import sys
sys.path.insert(0, "/root/build/pokesaga/tools")
from emerald_tiles import Tileset


def norm(x):
    return "".join(ch for ch in x.lower() if ch.isalnum())


# tileset 名 -> 目录
PRIMARY = {}
SECONDARY = {}
for kind, table in (("primary", PRIMARY), ("secondary", SECONDARY)):
    d = os.path.join(TS, kind)
    for name in os.listdir(d):
        if os.path.isdir(os.path.join(d, name)) and os.path.exists(os.path.join(d, name, "metatiles.bin")):
            table[norm(name)] = os.path.join(d, name)

_cache = {}


def get_primary(name):
    key = norm(name.replace("gTileset_", ""))
    path = PRIMARY.get(key) or PRIMARY.get(key + "frlg") or PRIMARY.get(norm(name))
    if not path:
        return None
    if path not in _cache:
        _cache[path] = Tileset(path)
    return _cache[path]


def get_secondary(name, fallback=None):
    key = norm(name.replace("gTileset_", ""))
    # 火红的地图 tileset 目录带 _frlg 后缀
    path = SECONDARY.get(key) or SECONDARY.get(key + "frlg") or SECONDARY.get(norm(name))
    if not path:
        return None
    if path not in _cache:
        _cache[path] = Tileset(path, fallback=fallback)
        if fallback is not None:
            _cache[path].base_tiles = fallback.cols * (fallback.h // 8)
    elif fallback is not None and _cache[path].fallback is None:
        _cache[path].fallback = fallback
    return _cache[path]


def render_layout(layout, out_dir):
    w, h = int(layout["width"]), int(layout["height"])
    prim = get_primary(layout["primary_tileset"])
    # secondary 的调色板/贴图缺项要回落到同一张地图的 primary，不能跨世代混用
    sec = get_secondary(layout["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return None
    data = open(os.path.join(ROOT, layout["blockdata_filepath"]), "rb").read()
    if len(data) < w * h * 2:
        return None
    img = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 255))
    collide = []
    for y in range(h):
        row = []
        for x in range(w):
            val = struct.unpack_from("<H", data, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            col = (val >> 10) & 0x3
            row.append(col)
            # 分界是 primary 的 metatile 数量，不是固定 512
            prim_count = prim.count
            ts = prim if mid < prim_count else sec
            local = mid if mid < prim_count else mid - prim_count
            try:
                img.paste(ts.render(local), (x * 16, y * 16))
            except Exception:
                pass
        collide.append(row)

    name = layout["id"].replace("LAYOUT_", "").lower()
    png = os.path.join(out_dir, name + ".png")
    img.save(png)
    meta = {
        "id": layout["id"],
        "size": [w, h],
        "png": os.path.basename(png),
        "collision": collide,
        "primary": layout["primary_tileset"],
        "secondary": layout["secondary_tileset"],
    }
    json.dump(meta, open(os.path.join(out_dir, name + ".json"), "w"), separators=(",", ":"))
    return name, w, h


def main():
    os.makedirs(OUT, exist_ok=True)
    table = json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]
    by_id = {l["id"]: l for l in table}
    want = [
        "LAYOUT_PALLET_TOWN", "LAYOUT_ROUTE1", "LAYOUT_VIRIDIAN_CITY",
        "LAYOUT_ROUTE2", "LAYOUT_VIRIDIAN_FOREST", "LAYOUT_PEWTER_CITY",
        "LAYOUT_PEWTER_CITY_GYM", "LAYOUT_POKEMON_CENTER_1F",
        "LAYOUT_LITTLEROOT_TOWN", "LAYOUT_OLDALE_TOWN", "LAYOUT_ROUTE101",
        "LAYOUT_PETALBURG_CITY", "LAYOUT_PETALBURG_CITY_GYM",
        "LAYOUT_BATTLE_FRONTIER_LOBBY",
    ]
    done = []
    for wid in want:
        lay = by_id.get(wid)
        if not lay:
            print("missing layout", wid)
            continue
        r = render_layout(lay, OUT)
        if r:
            done.append(r)
            print("rendered", r)
    print("total", len(done))


if __name__ == "__main__":
    main()
