#!/usr/bin/env python3
"""把预渲染的原版地图接成游戏地图：自动找边缘开口当 warp，写 region map json。"""
import json, os

MAPS = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions"

SPEC = [
    # 游戏内 map id, region, 显示名, emerald 图, 北出口(游戏内目标), 南出口(游戏内目标)
    ("pallet_town", "kanto", "关都·真新镇", "pallet_town", None, ("kanto", "route1")),
    ("route1", "kanto", "关都·1 号道路", "route1", ("kanto", "pallet_town"), ("kanto", "viridian_city")),
    ("viridian_city", "kanto", "关都·常磐市", "viridian_city", ("kanto", "route1"), ("kanto", "route2")),
    ("route2", "kanto", "关都·2 号道路", "route2", ("kanto", "viridian_city"), ("kanto", "viridian_forest")),
    ("viridian_forest", "kanto", "关都·常磐森林", "viridian_forest", ("kanto", "route2"), ("kanto", "pewter_city")),
    ("pewter_city", "kanto", "关都·尼比市", "pewter_city", ("kanto", "viridian_forest"), None),
    ("littleroot_town", "hoenn", "丰缘·未白镇", "littleroot_town", ("hoenn", "route101"), None),
    ("route101", "hoenn", "丰缘·101 号道路", "route101", None, ("hoenn", "littleroot_town")),
]


def load(name):
    return json.load(open(os.path.join(MAPS, name + ".json")))


def walkable(col, x, y):
    if y < 0 or y >= len(col):
        return False
    row = col[y]
    return 0 <= x < len(row) and int(row[x]) == 0


def openings(col, w, h, edge):
    """在指定边上找连续可走的格，返回中间那一格"""
    hits = []
    if edge == "north":
        for x in range(w):
            if walkable(col, x, 1):
                hits.append((x, 1))
    elif edge == "south":
        for x in range(w):
            if walkable(col, x, h - 2):
                hits.append((x, h - 2))
    elif edge == "west":
        for y in range(h):
            if walkable(col, 1, y):
                hits.append((1, y))
    else:
        for y in range(h):
            if walkable(col, w - 2, y):
                hits.append((w - 2, y))
    if not hits:
        return None
    mid = hits[len(hits) // 2]
    return [mid[0], mid[1]]


def spawn_point(col, w, h):
    """出生点：优先地图底部中央的可走格"""
    for y in range(h - 3, 1, -1):
        for dx in range(0, w // 2):
            for x in (w // 2 + dx, w // 2 - dx):
                if 0 <= x < w and walkable(col, x, y):
                    return [x, y]
    return [w // 2, h // 2]


def main():
    for mid, rid, disp, em, north, south in SPEC:
        meta = load(em)
        w, h = meta["size"]
        col = meta["collision"]
        warps = []
        sp_n = openings(col, w, h, "north")
        sp_s = openings(col, w, h, "south")
        if north and sp_n:
            warps.append({"at": sp_n, "to": {"region": north[0], "map": north[1], "at": None}})
        if south and sp_s:
            warps.append({"at": sp_s, "to": {"region": south[0], "map": south[1], "at": None}})
        data = {
            "name": disp,
            "emerald": em,
            "size": [w, h],
            "spawn": spawn_point(col, w, h),
            "npcs": [],
            "warps": warps,
        }
        out = os.path.join(REG, rid, "maps", mid + ".json")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        json.dump(data, open(out, "w"), ensure_ascii=False, indent=1)
        print(rid, mid, w, h, "warps", [(w2["at"], w2["to"]["map"]) for w2 in warps])


if __name__ == "__main__":
    main()
