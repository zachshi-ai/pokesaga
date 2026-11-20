#!/usr/bin/env python3
"""检查每个传送的落点：如果落在墙里/水面上，就近挪到一个能站的格子。

自动生成的地图边缘门容易出现"落点在墙里"，玩家一传送就卡住。
"""
import json
import glob
import os

ROOT = "/root/build/pokesaga"
CACHE = {}


def load_em(reg, mid):
    key = "%s/%s" % (reg, mid)
    if key in CACHE:
        return CACHE[key]
    p = os.path.join(ROOT, "content/emerald_maps", mid + ".json")
    em = json.load(open(p)) if os.path.exists(p) else None
    CACHE[key] = em
    return em


NPC_CACHE = {}


def npc_cells(reg, mid):
    key = "%s/%s" % (reg, mid)
    if key in NPC_CACHE:
        return NPC_CACHE[key]
    p = os.path.join(ROOT, "content/regions", reg, "maps", mid + ".json")
    cells = set()
    if os.path.exists(p):
        d = json.load(open(p))
        for n in d.get("npcs", []):
            cells.add((int(n["at"][0]), int(n["at"][1])))
    NPC_CACHE[key] = cells
    return cells


def ok_cell(em, x, y, allow_water=False):
    coll = em.get("collision")
    if not coll or y < 0 or y >= len(coll):
        return False
    row = coll[y]
    if x < 0 or x >= len(row):
        return False
    if int(row[x]) != 0:
        return False
    if not allow_water:
        wg = em.get("water")
        if wg and y < len(wg) and x < len(wg[y]) and int(wg[y][x]) != 0:
            return False
    return True


def nearest(em, x, y, blocked=None):
    h = len(em["collision"])
    w = len(em["collision"][0])
    for r in range(1, 31):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                nx, ny = x + dx, y + dy
                if blocked and (nx, ny) in blocked:
                    continue
                if 0 <= nx < w and 0 <= ny < h and ok_cell(em, nx, ny):
                    return [nx, ny]
    # 实在找不到陆地，才退到水面（海路传送）
    for r in range(1, 4):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                nx, ny = x + dx, y + dy
                if blocked and (nx, ny) in blocked:
                    continue
                if 0 <= nx < w and 0 <= ny < h and ok_cell(em, nx, ny, True):
                    return [nx, ny]
    return None


def main():
    fixed = 0
    for f in glob.glob(os.path.join(ROOT, "content/regions/*/maps/*.json")):
        reg = f.split("/")[-3]
        mid = os.path.basename(f)[:-5]
        data = json.load(open(f))
        changed = False
        for w in data.get("warps", []):
            to = w.get("to", {})
            treg, tmid = String = (to.get("region"), to.get("map"))
            at = to.get("at", [0, 0])
            if not treg or not tmid:
                continue
            em = load_em(treg, tmid)
            if not em or "collision" not in em:
                continue
            blocked = npc_cells(treg, tmid)
            if ok_cell(em, int(at[0]), int(at[1])) and (int(at[0]), int(at[1])) not in blocked:
                continue
            spot = nearest(em, int(at[0]), int(at[1]), blocked)
            if spot:
                to["at"] = spot
                fixed += 1
                changed = True
        if changed:
            json.dump(data, open(f, "w"), ensure_ascii=False, indent=1)
    print("修正落点 %d 个" % fixed)


if __name__ == "__main__":
    main()
