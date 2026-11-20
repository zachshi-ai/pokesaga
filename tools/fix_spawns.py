#!/usr/bin/env python3
"""出生点体检：出生格在碰撞里是墙（或者地图边界外）就挪到最近的可走格。
用法: python3 tools/fix_spawns.py [--region=sevii]
"""
import json
import os
import sys
from collections import deque

REGION = "kanto"
for a in sys.argv:
    if a.startswith("--region="):
        REGION = a.split("=")[1]
REG = "/root/build/pokesaga/content/regions/%s/maps" % REGION
EM = "/root/build/pokesaga/content/emerald_maps"


def main():
    fixed = 0
    for f in os.listdir(REG):
        if not f.endswith(".json"):
            continue
        p = os.path.join(REG, f)
        d = json.load(open(p))
        em = d.get("emerald")
        if not em:
            continue
        mp = os.path.join(EM, em + ".json")
        if not os.path.exists(mp):
            continue
        col = json.load(open(mp)).get("collision")
        if not col:
            continue
        sp = d.get("spawn") or [1, 1]
        x, y = int(sp[0]), int(sp[1])
        H, W = len(col), len(col[0])

        def ok(cx, cy):
            return 0 <= cy < H and 0 <= cx < W and int(col[cy][cx]) == 0

        # NPC 压住出生点/门格就挪开
        occ = {(int(w["at"][0]), int(w["at"][1])) for w in d.get("warps", [])}
        occ.add((x, y))
        for npc in d.get("npcs", []):
            nx, ny = int(npc["at"][0]), int(npc["at"][1])
            if (nx, ny) not in occ:
                continue
            spot2 = None
            for r in range(1, 5):
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        c = (nx + dx, ny + dy)
                        if c in occ or not ok(*c):
                            continue
                        spot2 = c
                        break
                    if spot2:
                        break
                if spot2:
                    break
            if spot2:
                npc["at"] = [spot2[0], spot2[1]]
                occ.add(spot2)
                print("  挪开 NPC", f[:-5], [nx, ny], "->", list(spot2))
        json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)

        if ok(x, y):
            continue
        spot = None
        q = deque([(x, y)])
        seen = {(x, y)}
        while q and spot is None:
            cx, cy = q.popleft()
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                n = (cx + dx, cy + dy)
                if n in seen:
                    continue
                seen.add(n)
                if ok(*n):
                    spot = n
                    break
                if abs(n[0] - x) <= 6 and abs(n[1] - y) <= 6:
                    q.append(n)
        if spot is None:
            print("  挪不动", f[:-5], sp)
            continue
        d["spawn"] = [spot[0], spot[1]]
        json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)
        fixed += 1
        print("  出生点", f[:-5], [x, y], "->", list(spot))
    print("%s 修出生点 %d 张" % (REGION, fixed))


if __name__ == "__main__":
    main()
