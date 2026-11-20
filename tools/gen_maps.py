#!/usr/bin/env python3
"""生成两个地区的测试地图（手工布局，不用随机）。
地形编号：0 草 1 树 2 水 3 路 4 花 5 石 6 墙 7 屋顶 8 门 9 栅栏 10 沙
"""
from asset_paths import project_path

import json, os

OUT = project_path("content/regions")


def blank(w, h, fill=0):
    return [[fill] * w for _ in range(h)]


def rect(g, x0, y0, x1, y1, t):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = t


def house(g, x, y, w=5):
    """在 (x,y) 画一栋房子：屋顶两行 + 墙体两行 + 中间门"""
    rect(g, x, y, x + w - 1, y + 1, 7)          # 屋顶
    rect(g, x, y + 2, x + w - 1, y + 3, 6)      # 墙体
    g[y + 3][x + w // 2] = 8                    # 门
    g[y + 2][x + w // 2] = 8


def pond(g, x0, y0, x1, y1):
    rect(g, x0, y0, x1, y1, 2)


def border(g, w, h, thick=2):
    rect(g, 0, 0, w - 1, thick - 1, 1)
    rect(g, 0, h - thick, w - 1, h - 1, 1)
    rect(g, 0, 0, thick - 1, h - 1, 1)
    rect(g, w - thick, 0, w - 1, h - 1, 1)


def tree_patch(g, x0, y0, x1, y1):
    rect(g, x0, y0, x1, y1, 1)


def fence_line(g, x0, x1, y):
    for x in range(x0, x1 + 1):
        g[y][x] = 9


def blob(g, cx, cy, r, t, seed=0):
    """不规则水池/高草团"""
    import random, math
    rnd = random.Random(seed)
    for y in range(cy - r - 2, cy + r + 3):
        for x in range(cx - r - 2, cx + r + 3):
            if not (0 <= y < len(g) and 0 <= x < len(g[0])):
                continue
            wob = 0.75 + rnd.random() * 0.5
            d = math.hypot(x - cx, (y - cy) * 1.25)
            if d <= r * wob:
                g[y][x] = t


def make_town(w=32, h=24, style="hoenn"):
    g = blank(w, h, 0)
    border(g, w, h, 2)

    # 主路：横贯 + 两条竖街（错位，不做十字对称）
    rect(g, 2, 12, 29, 13, 3)
    rect(g, 15, 5, 16, 20, 3)
    rect(g, 6, 12, 7, 19, 3)
    rect(g, 23, 6, 24, 12, 3)

    if style == "hoenn":
        blob(g, 26, 9, 3, 2, 3)
        blob(g, 11, 8, 2, 2, 5)
        blob(g, 6, 6, 3, 11, 7)
        blob(g, 28, 19, 3, 11, 9)
        blob(g, 12, 14, 2, 11, 11)
        # 再铺路，保证路面完整
        rect(g, 2, 12, 29, 14, 3)
        rect(g, 15, 5, 16, 21, 3)
        rect(g, 6, 12, 7, 19, 3)
        rect(g, 23, 6, 24, 13, 3)
        house(g, 4, 4)
        house(g, 19, 3)
        house(g, 10, 18)
        house(g, 25, 16)
        fence_line(g, 4, 9, 9)
        fence_line(g, 19, 23, 8)
        for (x, y) in [(3, 15), (4, 15), (8, 15), (17, 15), (21, 15), (27, 15)]:
            g[y][x] = 4
        g[5][7] = 5
        g[20][17] = 5
        g[11][2] = 12
        tree_patch(g, 8, 22, 12, 23)
        tree_patch(g, 27, 1, 29, 2)

    else:
        # 关都：中央砂石广场，规整街区
        blob(g, 27, 11, 3, 11, 13)
        blob(g, 8, 11, 2, 11, 15)
        rect(g, 2, 12, 29, 14, 3)
        rect(g, 15, 5, 16, 21, 3)
        rect(g, 6, 12, 7, 17, 3)
        rect(g, 23, 8, 24, 13, 3)
        rect(g, 12, 9, 19, 16, 10)
        house(g, 3, 3)
        house(g, 21, 3)
        house(g, 4, 17)
        house(g, 22, 18)
        house(g, 12, 3, 6)
        fence_line(g, 3, 8, 8)
        fence_line(g, 21, 26, 8)
        for (x, y) in [(9, 6), (10, 6), (20, 15), (21, 15), (9, 18), (17, 18)]:
            g[y][x] = 4
        g[5][9] = 5
        g[5][20] = 5
        g[13][11] = 12
        tree_patch(g, 2, 20, 4, 22)

    return g


def decorate(g, seed, density=12, rocks=3):
    """确定性撒花与石块：花可踩，石头挡路"""
    import random
    rnd = random.Random(seed)
    h, w = len(g), len(g[0])
    spots = [(x, y) for y in range(2, h - 2) for x in range(2, w - 2) if g[y][x] == 0]
    rnd.shuffle(spots)
    for (x, y) in spots[:density]:
        g[y][x] = 4
    for (x, y) in spots[density:density + rocks]:
        g[y][x] = 5


def route(w=36, h=20, style="hoenn", seed=1):
    """纵向道路：中间主道，两侧灌木与水池"""
    g = blank(w, h, 0)
    border(g, w, h, 1)
    rect(g, w // 2 - 2, 1, w // 2 + 1, h - 2, 3)
    if style == "hoenn":
        blob(g, 8, 6, 3, 11, seed)
        blob(g, w - 9, 13, 3, 11, seed + 1)
        blob(g, 6, 15, 2, 2, seed + 2)
        blob(g, w - 7, 5, 2, 2, seed + 3)
    else:
        blob(g, 7, 5, 2, 11, seed)
        blob(g, w - 8, 14, 2, 11, seed + 1)
        rect(g, 4, 9, w - 5, 10, 10)
    decorate(g, seed + 7, density=14, rocks=3)
    for y in range(1, h - 1):
        for x in (w // 2 - 2, w // 2 + 1):
            if g[y][x] != 2:
                g[y][x] = 3
    return g


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


# ---- 丰缘 ----
write("hoenn", "test_town", "丰缘·未白镇", make_town(style="hoenn"), (15, 13),
      [{"at": [29, 12], "to": {"region": "hoenn", "map": "route101", "at": [18, 2]}}],
      [{"at": [9, 13], "name": "训练家 小遥", "battle": {"species": 25, "level": 12, "moves": [84, 33, 98]}},
       {"at": [16, 8], "name": "钓鱼老伯"},
       {"at": [14, 13], "name": "路牌"}])

write("hoenn", "route101", "丰缘·101 号道路", route(style="hoenn", seed=41), (18, 2),
      [{"at": [18, 1], "to": {"region": "hoenn", "map": "test_town", "at": [29, 11]}},
       {"at": [18, 18], "to": {"region": "road", "map": "link_road", "at": [14, 2]}}],
      [{"at": [14, 8], "name": "短裤小子", "battle": {"species": 74, "level": 10, "moves": [88, 33]}},
       {"at": [22, 13], "name": "采花少女"}])

# ---- 连接道路（第三块地盘，独立 region 目录用来验证"加地区=加目录"）----
g = blank(30, 26, 0)
border(g, 30, 26, 1)
rect(g, 13, 1, 16, 24, 3)
blob(g, 8, 8, 3, 11, 21)
blob(g, 22, 18, 3, 11, 22)
blob(g, 7, 19, 2, 2, 23)
for y in range(1, 25):
    for x in (13, 16):
        if g[y][x] != 2:
            g[y][x] = 3
decorate(g, 33, density=12, rocks=2)
write("road", "link_road", "连接道路", g, (14, 2),
      [{"at": [14, 1], "to": {"region": "hoenn", "map": "route101", "at": [18, 17]}},
       {"at": [14, 24], "to": {"region": "kanto", "map": "pallet_town", "at": [15, 3]}}],
      [{"at": [12, 12], "name": "旅行商人"}])

# ---- 关都 ----
write("kanto", "pallet_town", "关都·真新镇", make_town(style="kanto"), (10, 12),
      [{"at": [15, 2], "to": {"region": "road", "map": "link_road", "at": [14, 23]}},
       {"at": [29, 12], "to": {"region": "kanto", "map": "route1", "at": [18, 2]}}],
      [{"at": [16, 12], "name": "大木博士"},
       {"at": [17, 11], "name": "少女"}])

write("kanto", "route1", "关都·1 号道路", route(style="kanto", seed=61), (18, 2),
      [{"at": [18, 1], "to": {"region": "kanto", "map": "pallet_town", "at": [29, 11]}}],
      [{"at": [21, 9], "name": "捕虫少年", "battle": {"species": 10, "level": 8, "moves": [33]}},
       {"at": [12, 14], "name": "登山男"}])
