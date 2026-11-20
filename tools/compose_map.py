#!/usr/bin/env python3
"""用建筑预制件拼地图。

底图可以是一张原版地图，也可以是一片草地；然后把 prefab 贴到指定格子，
PNG 与碰撞表一起更新，输出成一张新的 emerald 地图。这样房子、道馆、宝可梦中心
都能反复用在任何城镇里，不用每次重画。
"""
import json, os, shutil
from PIL import Image

EMAPS = "/root/build/pokesaga/content/emerald_maps"
PREFABS = "/root/build/pokesaga/content/prefabs"


def load_base(name):
    meta = json.load(open(os.path.join(EMAPS, name + ".json")))
    png = Image.open(os.path.join(EMAPS, name + ".png")).convert("RGBA")
    return meta, png


def stamp(png, col, prefab_id, at, clear=True):
    """把 prefab 贴到 (ax, ay)，返回更新后的 png 与碰撞表（原地修改）"""
    p = json.load(open(os.path.join(PREFABS, prefab_id + ".json")))
    tile = Image.open(os.path.join(PREFABS, prefab_id + ".png")).convert("RGBA")
    pw, ph = p["size"]
    ax, ay = int(at[0]), int(at[1])
    png.paste(tile, (ax * 16, ay * 16), tile)
    for y in range(ph):
        for x in range(pw):
            yy, xx = ay + y, ax + x
            if 0 <= yy < len(col) and 0 <= xx < len(col[0]):
                col[yy][xx] = p["collision"][y][x]
    return {"door": [ax + p["door"][0], ay + p["door"][1]], "size": [pw, ph]}


def build(name, base, stamps, out_png_name=None):
    meta, png = load_base(base)
    col = [row[:] for row in meta["collision"]]
    doors = []
    for s in stamps:
        d = stamp(png, col, s["prefab"], s["at"])
        doors.append(d)
    out = out_png_name or ("composed_" + base)
    png.save(os.path.join(EMAPS, out + ".png"))
    newmeta = {"id": "LAYOUT_" + out.upper(), "size": meta["size"],
               "png": out + ".png", "collision": col, "composed": True,
               "tileset_src": base}
    json.dump(newmeta, open(os.path.join(EMAPS, out + ".json"), "w"), separators=(",", ":"))
    print("built", out, meta["size"], "doors", doors)
    return out, doors


if __name__ == "__main__":
    # 演示：在未白镇的空地上摆一排房子，验证 prefab 真的可复用
    build("littleroot_town", "littleroot_town", [
        {"prefab": "petalburg_city_0", "at": [2, 12]},
        {"prefab": "oldale_town_0", "at": [8, 12]},
        {"prefab": "pallet_town_0", "at": [13, 11]},
    ], out_png_name="demo_town")
