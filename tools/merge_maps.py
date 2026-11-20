#!/usr/bin/env python3
"""把有 connections 的地图按原版接壤关系拼成一张大地图。

原版走路是滚动的，一张图走到边就无缝进下一张。我之前每张图各自渲染、
靠 warp 硬跳，看着就是"地图不连贯"。这里按 connections 的 direction + offset
把地图摆到同一坐标系里拼起来，玩家在一张连续的图上走。

输出 meta 里用 chunks 记录分块贴图（单张不要超过 4096px，手机纹理上限），
game 侧按块摆放即可。
"""
from asset_paths import project_path, source_path

import json, os, glob, struct
from PIL import Image

ROOT = source_path("emerald")
EMAPS = project_path("content/emerald_maps")
OUT = project_path("content/emerald_maps")
CHUNK = 24          # 每块 24x24 格 = 384x384 px

import sys
sys.path.insert(0, project_path("tools"))
from render_emerald_maps import get_primary, get_secondary

# 只拼室外、能走通的几组；室内保持单张
GROUPS = {
    "kanto_main": [
        "PalletTown", "Route1", "ViridianCity", "Route2", "ViridianForest", "PewterCity",
        "Route3", "Route4", "CeruleanCity", "Route24", "Route25",
        "Route5", "Route6", "VermilionCity", "Route7", "Route8", "Route9", "Route10",
        "LavenderTown", "Route11", "Route12", "Route13",
        "Route14", "Route15", "FuchsiaCity", "Route16", "Route17", "Route18",
        "Route19", "Route20", "CinnabarIsland",
        "Route21North", "Route21South", "Route22", "Route23", "IndigoPlateauExterior",
        "CeladonCity", "SaffronCityConnection", "SaffronCity",
    ],
    "hoenn_main": ["LittlerootTown", "Route101"],
}


def norm(x):
    return "".join(ch for ch in x.lower() if ch.isalnum())


def load_maps():
    out = {}
    for p in glob.glob(os.path.join(ROOT, "data/maps/*/map.json")):
        d = json.load(open(p))
        out[d["id"].replace("MAP_", "")] = d
    return out


def main():
    maps = load_maps()
    by_norm = {norm(k): k for k in maps}

    for gname, members in GROUPS.items():
        keys = []
        for m in members:
            k = m if m in maps else by_norm.get(norm(m.replace("_Frlg", "")))
            if k:
                keys.append(k)
        if not keys:
            print("skip group", gname)
            continue

        # 以第一张为基准做 BFS，按 connections 摆位
        base = keys[0]
        pos = {base: (0, 0)}
        queue = [base]
        while queue:
            cur = queue.pop(0)
            cd = maps[cur]
            lay = json.load(open(os.path.join(EMAPS, cd["layout"].replace("LAYOUT_", "").lower() + ".json")))
            cw, ch = lay["size"]
            cx, cy = pos[cur]
            for c in cd.get("connections", []) or []:
                nb = c.get("map", "").replace("MAP_", "")
                if nb not in maps or nb not in keys or nb in pos:
                    continue
                nd = maps[nb]
                nlay_path = os.path.join(EMAPS, nd["layout"].replace("LAYOUT_", "").lower() + ".json")
                if not os.path.exists(nlay_path):
                    continue
                nlay = json.load(open(nlay_path))
                nw, nh = nlay["size"]
                off = int(c.get("offset", 0) or 0)
                direction = c.get("direction", "up")
                if direction == "up":
                    nx, ny = cx + off, cy - nh
                elif direction == "down":
                    nx, ny = cx + off, cy + ch
                elif direction == "left":
                    nx, ny = cx - nw, cy + off
                else:
                    nx, ny = cx + cw, cy + off
                pos[nb] = (nx, ny)
                queue.append(nb)

        # 城名 + Connection 的地图共用一块地（原版里 SaffronCity 是城主体，
        # Connection 只是四条路的过渡带，两者地理重合）
        for k in keys:
            if k in pos:
                continue
            for ck in list(pos.keys()):
                if norm(ck) == norm(k + "Connection") or norm(ck) == norm(k.replace("Connection", "")):
                    pos[k] = pos[ck]
                    queue.append(k)
                    break

        # 求包围盒
        minx = min(p[0] for p in pos.values())
        miny = min(p[1] for p in pos.values())
        maxx = max(pos[k][0] + json.load(open(os.path.join(EMAPS, maps[k]["layout"].replace("LAYOUT_", "").lower() + ".json")))["size"][0] for k in pos)
        maxy = max(pos[k][1] + json.load(open(os.path.join(EMAPS, maps[k]["layout"].replace("LAYOUT_", "").lower() + ".json")))["size"][1] for k in pos)
        W, H = maxx - minx, maxy - miny
        print(gname, "canvas", W, "x", H, "tiles", "maps", len(pos))

        big = Image.new("RGBA", (W * 16, H * 16), (0, 0, 0, 255))
        col = [[1] * W for _ in range(H)]
        grass = [[0] * W for _ in range(H)]
        for k, (px, py) in pos.items():
            lp = os.path.join(EMAPS, maps[k]["layout"].replace("LAYOUT_", "").lower() + ".json")
            meta = json.load(open(lp))
            png = Image.open(os.path.join(EMAPS, meta["png"])).convert("RGBA")
            ox, oy = (px - minx) * 16, (py - miny) * 16
            big.paste(png, (ox, oy))
            mw, mh = meta["size"]
            for y in range(mh):
                for x in range(mw):
                    gx, gy = px - minx + x, py - miny + y
                    col[gy][gx] = meta["collision"][y][x]
                    if meta.get("grass"):
                        grass[gy][gx] = meta["grass"][y][x]

        # 分块导出
        chunks = []
        cx_n = (W + CHUNK - 1) // CHUNK
        cy_n = (H + CHUNK - 1) // CHUNK
        for j in range(cy_n):
            for i in range(cx_n):
                x0, y0 = i * CHUNK, j * CHUNK
                x1, y1 = min(W, x0 + CHUNK), min(H, y0 + CHUNK)
                if x1 <= x0 or y1 <= y0:
                    continue
                piece = big.crop((x0 * 16, y0 * 16, x1 * 16, y1 * 16))
                pn = "%s_%d_%d.png" % (gname, i, j)
                piece.save(os.path.join(OUT, pn))
                chunks.append({"png": pn, "at": [x0, y0]})

        meta = {
            "id": gname,
            "size": [W, H],
            "chunks": chunks,
            "collision": col,
            "grass": grass,
            "composed": True,
            "member_maps": {k: [pos[k][0] - minx, pos[k][1] - miny] for k in pos},
        }
        json.dump(meta, open(os.path.join(OUT, gname + ".json"), "w"), separators=(",", ":"))
        big.save(os.path.join(OUT, gname + "_full.png"))
        print("  chunks", len(chunks), "members", meta["member_maps"])


if __name__ == "__main__":
    main()
