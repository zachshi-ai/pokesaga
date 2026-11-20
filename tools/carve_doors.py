#!/usr/bin/env python3
"""把每扇门所在格与其正下方一格打通。
门格原本算建筑碰撞，玩家走不到；但门必须能站上去才能触发传送。
用法: python3 tools/carve_doors.py
"""
from asset_paths import project_path

import glob
import json
import os

PJ = project_path()
EM = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions")


def main():
    # 每张大图：所有指向它的门点位 + 它自己的门点位
    targets = {}
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        rid = os.path.basename(os.path.dirname(os.path.dirname(f)))
        d = json.load(open(f))
        mid = os.path.basename(f)[:-5]
        targets.setdefault((rid, mid), set())
        for w in d.get("warps", []):
            to = w.get("to") or {}
            key = (String(to.get("region")), String(to.get("map")))
            at = to.get("at") or [0, 0]
            targets.setdefault(key, set()).add((int(at[0]), int(at[1])))
            a = w.get("at") or [0, 0]
            targets.setdefault((rid, mid), set()).add((int(a[0]), int(a[1])))
    total = 0
    for (rid, mid), cells in targets.items():
        p = os.path.join(EM, mid + ".json")
        if not os.path.exists(p):
            continue
        m = json.load(open(p))
        col = m["collision"]
        w, h = m["size"]
        touched = 0
        for x, y in cells:
            for yy in (y, y + 1):
                if 0 <= x < w and 0 <= yy < h and col[yy][x] != 0:
                    col[yy][x] = 0
                    touched += 1
        if touched:
            json.dump(m, open(p, "w"), separators=(",", ":"))
            total += touched
            print(mid, "打通", touched)
    # 室内图自己的门口也要能站人（门画在墙上）
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        d = json.load(open(f))
        em = d.get("emerald", "")
        if not em:
            continue
        mp = os.path.join(EM, em + ".json")
        if not os.path.exists(mp):
            continue
        m = json.load(open(mp))
        col = m["collision"]
        w, h = m["size"]
        touched = 0
        for wr in d.get("warps", []):
            x, y = int(wr["at"][0]), int(wr["at"][1])
            for yy in (y, y - 1 if y > 0 else 0, y + 1):
                if 0 <= x < w and 0 <= yy < h and col[yy][x] != 0:
                    col[yy][x] = 0
                    touched += 1
        if touched:
            json.dump(m, open(mp, "w"), separators=(",", ":"))
            total += touched
            print(os.path.basename(f), "打通", touched)
    print("合计打通格", total)


def String(v):
    return "" if v is None else str(v)


if __name__ == "__main__":
    main()
