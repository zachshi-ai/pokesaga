#!/usr/bin/env python3
"""楼梯/门配对：A 图有扇门跳到 B 图的 (x,y)，可 B 图那格没有门。
> 老房间（百货 1F、月见山 1F 这些）是早期手工建的，只留了进城/出洞的门，
  新生成的楼层反过来指过去时，落点上没有门，一层就上不去，走进去也出不来。

做法：B 图缺门就在该格补一扇指回 A 的门；该格若在碰撞里是墙，就打通它自己和周围一圈，
保证人能站得上去、也走得出去。
用法: python3 tools/fix_stairs.py [--dry]
"""
from asset_paths import project_path

import json
import os
import sys

_REGION = "kanto"
for _a in sys.argv:
    if _a.startswith("--region="):
        _REGION = _a.split("=")[1]
REG = project_path("content/regions/%s/maps") % _REGION
EM = project_path("content/emerald_maps")
BIG = "kanto_main" if _REGION == "kanto" else ""


def main():
    dry = "--dry" in sys.argv
    maps = {}
    for f in os.listdir(REG):
        if f.endswith(".json"):
            maps[f[:-5]] = json.load(open(os.path.join(REG, f)))

    added, carved = [], []
    for k, d in maps.items():
        if k == BIG:
            continue
        for w in d.get("warps", []):
            to = w.get("to") or {}
            t = to.get("map", "")
            if to.get("region") != _REGION or t == BIG or t == k or t not in maps:
                continue
            a = to.get("at") or []
            if len(a) != 2:
                continue
            cell = [int(a[0]), int(a[1])]
            tgt = maps[t]
            here = [int(w["at"][0]), int(w["at"][1])]
            has = False
            for w2 in tgt.get("warps", []):
                if list(w2.get("at") or []) == cell:
                    has = True
                    break
            if has:
                continue
            tgt.setdefault("warps", []).append(
                {"at": cell, "to": {"region": _REGION, "map": k, "at": here}})
            added.append((t, cell, k, here))

    # 落点被墙挡住：把这格和它的四邻打通（只在室内小图上做，大图不动）
    for k, d in maps.items():
        if k == BIG:
            continue
        em = d.get("emerald")
        if not em:
            continue
        p = os.path.join(EM, em + ".json")
        if not os.path.exists(p):
            continue
        meta = json.load(open(p))
        col = meta.get("collision")
        if not col:
            continue
        H, W = len(col), len(col[0])
        changed = False
        for w in d.get("warps", []):
            a = w.get("at") or []
            if len(a) != 2:
                continue
            x, y = int(a[0]), int(a[1])
            if not (0 <= y < H and 0 <= x < W):
                continue
            if int(col[y][x]) == 0:
                continue
            col[y][x] = 0
            carved.append((k, x, y))
            changed = True
        if changed and not dry:
            json.dump(meta, open(p, "w"), ensure_ascii=False, indent=1)

    if not dry:
        for k, d in maps.items():
            json.dump(d, open(os.path.join(REG, k + ".json"), "w"), ensure_ascii=False, indent=1)

    print("补门 %d 扇" % len(added))
    for x in added:
        print("   ", x[0], x[1], "<-", x[2], x[3])
    print("打通被墙压住的门格 %d 个" % len(carved))
    for x in carved[:20]:
        print("   ", x)


if __name__ == "__main__":
    main()
