#!/usr/bin/env python3
"""收尾修补：1) 大图补齐所有「从室内/洞窟通回大图」的反向门
2) 室内地图出生点若在墙里，挪到最近可走格
用法: python3 tools/fix_links.py
"""
from asset_paths import project_path

import glob
import json
import os

PJ = project_path()
EM = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"


def walk(col, x, y):
    return 0 <= y < len(col) and 0 <= x < len(col[0]) and col[y][x] == 0


def nearest(col, x, y):
    for r in range(1, 6):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if walk(col, x + dx, y + dy):
                    return [x + dx, y + dy]
    return None


def main():
    bigp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bigp))
    bmeta = json.load(open(os.path.join(EM, BIG + ".json")))
    bcol = bmeta["collision"]

    # 1) 反向门
    exist = {(tuple(w["at"]), w["to"]["map"]) for w in big["warps"]}
    added = 0
    for f in glob.glob(os.path.join(REG, "*.json")):
        mid = os.path.basename(f)[:-5]
        if mid == BIG:
            continue
        d = json.load(open(f))
        for w in d.get("warps", []):
            to = w.get("to") or {}
            if to.get("region") != "kanto" or to.get("map") != BIG:
                continue
            at = [int(to["at"][0]), int(to["at"][1])]
            key = (tuple(at), mid)
            if key in exist:
                continue
            self_at = [int(w["at"][0]), int(w["at"][1])]
            big["warps"].append({"at": at, "to": {"region": "kanto", "map": mid, "at": self_at}})
            exist.add(key)
            added += 1
    print("补反向门", added)

    # 2) 大图门所在格打通
    carved = 0
    for w in big["warps"]:
        x, y = int(w["at"][0]), int(w["at"][1])
        for yy in (y, y + 1):
            if 0 <= yy < len(bcol) and 0 <= x < len(bcol[0]) and bcol[yy][x] != 0:
                bcol[yy][x] = 0
                carved += 1
    if carved:
        json.dump(bmeta, open(os.path.join(EM, BIG + ".json"), "w"), separators=(",", ":"))
    print("大图打通格", carved)

    # 3) 室内出生点
    fixed = 0
    for f in glob.glob(os.path.join(REG, "*.json")):
        mid = os.path.basename(f)[:-5]
        if mid == BIG:
            continue
        d = json.load(open(f))
        em = d.get("emerald", "")
        mp = os.path.join(EM, em + ".json")
        if not os.path.exists(mp):
            continue
        col = json.load(open(mp))["collision"]
        sp = d.get("spawn") or [1, 1]
        if walk(col, int(sp[0]), int(sp[1])):
            continue
        n = nearest(col, int(sp[0]), int(sp[1]))
        if n:
            d["spawn"] = n
            json.dump(d, open(f, "w"), ensure_ascii=False, indent=1)
            fixed += 1
            print("  %s 出生点 %s -> %s" % (mid, sp, n))
    print("修出生点", fixed)
    json.dump(big, open(bigp, "w"), ensure_ascii=False, indent=1)
    print("大图门总数", len(big["warps"]))


if __name__ == "__main__":
    main()
