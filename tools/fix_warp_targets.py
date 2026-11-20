#!/usr/bin/env python3
"""修补 warp 目标：新生成的房间可能把老房间写成另一种命名（safari_zone_center vs
safarizone_center、celadon_city_pokemon_center_1f vs celadoncity_pokemoncenter_1f）。
先按归一化名字重新指向已有地图；真的没有对应地图的（贴图缺失没生成的，如西尔佛、
火箭队基地、百货电梯），就把那扇门去掉，避免自检里出现"传送目标不存在"。
用法: python3 tools/fix_warp_targets.py [--dry]
"""
from asset_paths import project_path

import json
import os
import re

_REGION = "kanto"
import sys as _sys
for _a in _sys.argv:
    if _a.startswith("--region="):
        _REGION = _a.split("=")[1]
REG = project_path("content/regions/%s/maps") % _REGION
BIG = "kanto_main" if _REGION == "kanto" else ""


def norm(s):
    s = str(s).lower()
    s = s.replace("frlg", "")
    return re.sub(r"[^a-z0-9]", "", s)


def main():
    dry = "--dry" in os_sys()
    files = {f[:-5]: os.path.join(REG, f) for f in os.listdir(REG) if f.endswith(".json")}
    idx = {}
    for k in files:
        idx.setdefault(norm(k), []).append(k)

    remap, dropped = 0, []
    for k, p in files.items():
        d = json.load(open(p))
        changed = False
        keep = []
        for w in d.get("warps", []):
            to = w.get("to") or {}
            if to.get("region") != _REGION:
                keep.append(w)
                continue
            m = str(to.get("map", ""))
            if m == "" or m in files:
                keep.append(w)
                continue
            cand = [c for c in idx.get(norm(m), []) if c != k]
            if cand:
                to["map"] = cand[0]
                changed = True
                remap += 1
                keep.append(w)
                continue
            dropped.append((k, w.get("at"), m))
            changed = True
        if changed:
            d["warps"] = keep
            if not dry:
                json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)

    # 大图里指向不存在房间的门一并清掉
    if BIG == "":
        print("改写目标 %d 条，删除无主门 %d 条" % (remap, len(dropped)))
        for row in dropped:
            print("   去掉 ->", row[2])
        return
    bp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bp))
    keep = []
    for w in big.get("warps", []):
        to = w.get("to") or {}
        m = str(to.get("map", ""))
        if to.get("region") == "kanto" and m != BIG and m not in files:
            dropped.append((BIG, w.get("at"), m))
            continue
        keep.append(w)
    if not dry:
        big["warps"] = keep
        json.dump(big, open(bp, "w"), ensure_ascii=False, indent=1)
    print("改写目标 %d 条，删除无主门 %d 条" % (remap, len(dropped)))
    seen = set()
    for row in dropped:
        key = row[2]
        if key in seen:
            continue
        seen.add(key)
        print("   去掉 ->", key)


def os_sys():
    import sys
    return sys.argv


if __name__ == "__main__":
    main()
