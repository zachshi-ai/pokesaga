#!/usr/bin/env python3
"""关都地区补全：常磐市、2 号道路、常磐森林、尼比市、尼比道馆、宝可梦中心室内。
地形编号：0 草 1 树 2 水 3 路 4 花 5 石 6 墙 7 屋顶 8 门 9 栅栏 10 沙 11 高草 12 路牌
          13 室内木地板 14 室内地毯
"""
import json, os, random

OUT = "/root/build/pokesaga/content/regions"


def blank(w, h, fill=0):
    return [[fill] * w for _ in range(h)]


def rect(g, x0, y0, x1, y1, t):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = t


def border(g, w, h, thick=1, t=1):
    rect(g, 0, 0, w - 1, thick - 1, t)
    rect(g, 0, h - thick, w - 1, h - 1, t)
    rect(g, 0, 0, thick - 1, h - 1, t)
    rect(g, w - thick, 0, w - 1, h - 1, t)


def building(g, x, y, w, h, door=True):
    """屋顶两行 + 墙体其余，中间开门"""
    rect(g, x, y, x + w - 1, y + 1, 7)
    rect(g, x, y + 2, x + w - 1, y + h - 1, 6)
    if door:
        g[y + h - 1][x + w // 2] = 8
        g[y + h - 2][x + w // 2] = 8


def blob(g, cx, cy, r, t, seed=0):
    rnd = random.Random(seed)
    for y in range(cy - r - 2, cy + r + 3):
        for x in range(cx - r - 2, cx + r + 3):
            if not (0 <= y < len(g) and 0 <= x < len(g[0])):
                continue
            wob = 0.75 + rnd.random() * 0.45
            if ((x - cx) ** 2 + ((y - cy) * 1.3) ** 2) ** 0.5 <= r * wob:
                g[y][x] = t


def decorate(g, seed, flowers=16, rocks=4):
    rnd = random.Random(seed)
    h, w = len(g), len(g[0])
    spots = [(x, y) for y in range(2, h - 2) for x in range(2, w - 2) if g[y][x] == 0]
    rnd.shuffle(spots)
    for (x, y) in spots[:flowers]:
        g[y][x] = 4
    for (x, y) in spots[flowers:flowers + rocks]:
        g[y][x] = 5


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


# ---------------- 常磐市 ----------------
W, H = 32, 26
g = blank(W, H, 0)
border(g, W, H, 1)
rect(g, 3, 12, W - 4, 13, 3)        # 横向主路
rect(g, 15, 2, 16, 24, 3)           # 纵向主路
building(g, 6, 5, 5, 4)             # 宝可梦中心
building(g, 22, 5, 5, 4)            # 道馆（门锁着）
building(g, 5, 17, 5, 4)            # 民宅
blob(g, 19, 18, 3, 11, 91)
blob(g, 26, 16, 2, 11, 92)
g[2][24] = 12                       # 路牌
decorate(g, 93, flowers=18, rocks=3)
write("kanto", "viridian_city", "关都·常磐市", g, (15, 21),
      [{"at": [15, 1], "to": {"region": "kanto", "map": "route1", "at": [18, 17]}},
       {"at": [15, 24], "to": {"region": "kanto", "map": "route2", "at": [15, 2]}},
       {"at": [8, 8], "to": {"region": "kanto", "map": "pokecenter", "at": [8, 10]}}],
      [{"at": [24, 9], "name": "道馆门卫"},
       {"at": [11, 13], "name": "常磐市老人"},
       {"at": [21, 13], "name": "散步的少年",
        "battle": {"species": 19, "level": 9, "moves": [33, 98]}}])

# ---------------- 2 号道路 ----------------
W, H = 30, 26
g = blank(W, H, 0)
border(g, W, H, 1)
rect(g, 14, 1, 15, 24, 3)
blob(g, 7, 7, 3, 11, 101)
blob(g, 22, 14, 3, 11, 102)
blob(g, 6, 20, 2, 11, 103)
blob(g, 24, 21, 2, 2, 104)
decorate(g, 105, flowers=14, rocks=4)
write("kanto", "route2", "关都·2 号道路", g, (15, 2),
      [{"at": [15, 1], "to": {"region": "kanto", "map": "viridian_city", "at": [15, 23]}},
       {"at": [15, 24], "to": {"region": "kanto", "map": "viridian_forest", "at": [17, 2]}}],
      [{"at": [11, 9], "name": "短裤小子",
        "battle": {"species": 21, "level": 10, "moves": [64, 33]}},
       {"at": [19, 16], "name": "迷路的旅人"}])

# ---------------- 常磐森林（自然蜿蜒通道） ----------------
W, H = 36, 32
g = blank(W, H, 1)
border(g, W, H, 1, 1)
rnd = random.Random(111)


def carve(cx, cy, r=1):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if 1 <= x < W - 1 and 1 <= y < H - 1:
                g[y][x] = 0


def walk(x, y, steps, bias=None):
    """随机游走挖通道：bias=(dx,dy) 让它有大致走向，但不笔直"""
    for _ in range(steps):
        carve(x, y, 1)
        if bias and rnd.random() < 0.62:
            x += bias[0]
            y += bias[1]
        else:
            d = rnd.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
            x += d[0]
            y += d[1]
        x = max(2, min(W - 3, x))
        y = max(2, min(H - 3, y))
    carve(x, y, 1)
    return x, y


# 主路：北入口蜿蜒到南出口
x, y = 17, 2
carve(x, y, 1)
x, y = walk(x, y, 60, bias=(0, 1))
walk(x, y, 60, bias=(0, 1))
carve(17, 29, 1)
carve(17, 30, 1)
# 三条支路，制造岔口与死胡同
walk(11, 8, 26, bias=(1, 0))
walk(24, 14, 26, bias=(-1, 0))
walk(20, 22, 24, bias=(1, 0))
# 通道边缘铺高草：贴着通道两侧，不铺成整块
for yy in range(2, H - 2):
    for xx in range(2, W - 2):
        if g[yy][xx] != 0:
            continue
        near_tree = any(g[yy + dy][xx + dx] == 1 for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if near_tree and rnd.random() < 0.42:
            g[yy][xx] = 11
# 零星石块与花
for yy in range(3, H - 3):
    for xx in range(3, W - 3):
        if g[yy][xx] == 0 and rnd.random() < 0.012:
            g[yy][xx] = 5
        elif g[yy][xx] == 0 and rnd.random() < 0.02:
            g[yy][xx] = 4
g[4][22] = 12
write("kanto", "viridian_forest", "关都·常磐森林", g, (17, 3),
      [{"at": [17, 1], "to": {"region": "kanto", "map": "route2", "at": [15, 23]}},
       {"at": [17, 30], "to": {"region": "kanto", "map": "pewter_city", "at": [16, 2]}}],
      [{"at": [9, 9], "name": "捕虫少年",
        "battle": {"species": 10, "level": 10, "moves": [33, 81]}},
       {"at": [26, 19], "name": "森林里的少女",
        "battle": {"species": 43, "level": 11, "moves": [71, 40]}},
       {"at": [30, 25], "name": "采蘑菇的老人"}])

# ---------------- 尼比市 ----------------
W, H = 32, 26
g = blank(W, H, 0)
border(g, W, H, 1)
rect(g, 3, 13, W - 4, 14, 3)
rect(g, 15, 2, 16, 24, 3)
building(g, 12, 6, 7, 5)            # 尼比道馆
building(g, 4, 18, 5, 4)            # 民宅
building(g, 23, 18, 6, 4)           # 商店
blob(g, 8, 9, 3, 11, 121)
g[2][20] = 12
decorate(g, 123, flowers=16, rocks=3)
write("kanto", "pewter_city", "关都·尼比市", g, (15, 22),
      [{"at": [16, 1], "to": {"region": "kanto", "map": "viridian_forest", "at": [17, 29]}},
       {"at": [15, 10], "to": {"region": "kanto", "map": "pewter_gym", "at": [8, 13]}}],
      [{"at": [15, 12], "name": "尼比市居民"},
       {"at": [25, 17], "name": "商店老板"}])

# ---------------- 尼比道馆（室内） ----------------
W, H = 18, 16
g = blank(W, H, 13)
rect(g, 0, 0, W - 1, 0, 6)
rect(g, 0, H - 1, W - 1, H - 1, 6)
rect(g, 0, 0, 0, H - 1, 6)
rect(g, W - 1, 0, W - 1, H - 1, 6)
rect(g, 7, 1, 10, 4, 14)             # 首领脚下的地毯
rect(g, 8, 4, 9, 13, 13)
write("kanto", "pewter_gym", "尼比道馆", g, (8, 13),
      [{"at": [8, 15], "to": {"region": "kanto", "map": "pewter_city", "at": [15, 11]}}],
      [{"at": [4, 7], "name": "道馆训练家",
        "battle": {"species": 74, "level": 12, "moves": [88, 33]}},
       {"at": [13, 7], "name": "短裤小子",
        "battle": {"species": 95, "level": 12, "moves": [33, 88]}},
       {"at": [8, 3], "name": "馆主 小刚",
        "battle": {"species": 95, "level": 16, "moves": [88, 33]}}])

# ---------------- 宝可梦中心（室内） ----------------
W, H = 16, 12
g = blank(W, H, 13)
rect(g, 0, 0, W - 1, 0, 6)
rect(g, 0, H - 1, W - 1, H - 1, 6)
rect(g, 0, 0, 0, H - 1, 6)
rect(g, W - 1, 0, W - 1, H - 1, 6)
rect(g, 1, 2, 5, 3, 6)               # 柜台
rect(g, 1, 9, W - 2, 9, 14)          # 入口地毯
write("kanto", "pokecenter", "宝可梦中心", g, (8, 10),
      [{"at": [8, 11], "to": {"region": "kanto", "map": "viridian_city", "at": [8, 9]}}],
      [{"at": [3, 4], "name": "护士", "heal": True},
       {"at": [12, 5], "name": "休息的训练家"}])
