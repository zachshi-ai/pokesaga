#!/usr/bin/env python3
"""对战开拓区：码头岛 + 对战塔大厅（室内）。挂在丰缘东南，坐船进出。"""
from asset_paths import project_path
from hoenn_ferry import FRONTIER_GUIDE, HOENN_LANDING

import json, os, random

OUT = project_path("content/regions")


def blank(w, h, fill=0):
    return [[fill] * w for _ in range(h)]


def rect(g, x0, y0, x1, y1, t):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = t


def blob(g, cx, cy, r, t, seed=0):
    rnd = random.Random(seed)
    for y in range(cy - r - 2, cy + r + 3):
        for x in range(cx - r - 2, cx + r + 3):
            if not (0 <= y < len(g) and 0 <= x < len(g[0])):
                continue
            wob = 0.75 + rnd.random() * 0.45
            if ((x - cx) ** 2 + ((y - cy) * 1.3) ** 2) ** 0.5 <= r * wob:
                g[y][x] = t


def write(region, map_id, name, g, spawn, warps, npcs):
    d = {
        "name": name,
        "size": [len(g[0]), len(g)],
        "tiles": g,
        "spawn": list(spawn),
        "npcs": npcs,
        "warps": warps,
    }
    p = f"{OUT}/{region}/maps/{map_id}.json"
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)
    print(p, len(g[0]), "x", len(g))


# ---------------- 码头岛 ----------------
W, H = 28, 20
g = blank(W, H, 2)                      # 先整片海
# 岛体：沙滩环 + 草地
for y in range(2, H - 2):
    for x in range(4, W - 4):
        d = max(abs(x - W / 2) / (W / 2 - 6), abs(y - H / 2) / (H / 2 - 4))
        if d <= 0.72:
            g[y][x] = 0
        elif d <= 1.0:
            g[y][x] = 10
blob(g, 9, 12, 3, 1, 311)               # 树丛
blob(g, 19, 8, 2, 1, 312)
blob(g, 8, 6, 2, 11, 313)               # 高草
blob(g, 20, 14, 2, 11, 314)
# 木栈道：南侧码头到北侧塔门
rect(g, 13, 2, 15, 16, 3)
rect(g, 11, 15, 17, 17, 3)
g[1][14] = 8                            # 塔门（室内入口）
g[0][14] = 6
write("frontier", "harbor", "对战开拓区·码头", g, (14, 15),
      [{"at": [14, 1], "to": {"region": "frontier", "map": "tower_lobby", "at": [9, 14]}},
       {"at": [14, 17], "to": {"region": "hoenn", "map": "littleroot_town", "at": HOENN_LANDING}},
       {"at": [14, 4], "to": {"region": "kanto", "map": "kanto_main", "at": [287, 234]}}],
      [{"at": [12, 15], "name": "港口水手", "gfx": "sailor", "lines": FRONTIER_GUIDE},
       {"at": [16, 15], "name": "开拓少女"},
       {"at": [11, 6], "name": "岛上的游客"}])

# ---------------- 对战塔大厅（室内） ----------------
W, H = 18, 16
g = blank(W, H, 13)
rect(g, 0, 0, W - 1, 0, 7)
rect(g, 0, H - 1, W - 1, H - 1, 7)
rect(g, 0, 0, 0, H - 1, 7)
rect(g, W - 1, 0, W - 1, H - 1, 7)
rect(g, 1, 1, W - 2, 1, 6)
rect(g, 6, 1, 11, 4, 14)                # 地毯
rect(g, 8, 4, 9, 13, 13)
rect(g, 2, 2, 5, 3, 6)                  # 左侧柜台
rect(g, 12, 2, 15, 3, 6)                # 右侧柜台
g[15][9] = 13                           # leave the south exit passable
write("frontier", "tower_lobby", "对战塔 · 大厅", g, (9, 13),
      [{"at": [9, 15], "to": {"region": "frontier", "map": "harbor", "at": [14, 2]}}],
      [{"at": [9, 3], "name": "对战塔前台", "facility": True},
       {"at": [13, 3], "name": "登记员"},
       {"at": [3, 3], "name": "登记员"}])
