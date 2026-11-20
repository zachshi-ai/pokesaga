#!/usr/bin/env python3
"""门走不到就补通道。

有些原版房间的门被围在墙里（电梯门、需要特殊行为的地砖）。
我们不模拟那些行为，所以从门格朝最近的可走区域打一条直通道，
保证站在任何门上都走得动、也不会有死胡同把人困住。
用法: python3 tools/fix_reach.py [--region=kanto|sevii]
"""
import json
import os
import sys
from collections import deque

REGION = "kanto"
for a in sys.argv:
    if a.startswith("--region="):
        REGION = a.split("=")[1]
EM = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions/%s/maps" % REGION


def carve(col, start, seen):
    """从 start 朝已连通区域打直线通道，返回挖开的格数"""
    H, W = len(col), len(col[0])
    sx, sy = start
    # BFS 找最近的已连通格（允许穿墙，代价按步数）
    q = deque([(sx, sy)])
    prev = {(sx, sy): None}
    target = None
    while q:
        cx, cy = q.popleft()
        if (cx, cy) in seen and (cx, cy) != (sx, sy):
            target = (cx, cy)
            break
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            n = (cx + dx, cy + dy)
            if n in prev or not (1 <= n[0] < W - 1 and 1 <= n[1] < H - 1):
                continue
            prev[n] = (cx, cy)
            q.append(n)
    if target is None:
        return 0
    path = []
    cur = target
    while cur is not None:
        path.append(cur)
        cur = prev[cur]
    n = 0
    for x, y in path:
        if int(col[y][x]) != 0:
            col[y][x] = 0
            n += 1
    return n


def main():
    fixed = 0
    total = 0
    for f in sorted(os.listdir(REG)):
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
        meta = json.load(open(mp))
        col = meta.get("collision")
        if not col:
            continue
        H, W = len(col), len(col[0])
        sp = d.get("spawn") or [1, 1]
        s = (int(sp[0]), int(sp[1]))
        if not (0 <= s[1] < H and 0 <= s[0] < W) or int(col[s[1]][s[0]]) != 0:
            continue
        seen = {s}
        q = deque([s])
        while q:
            cx, cy = q.popleft()
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                n = (cx + dx, cy + dy)
                if n in seen or not (0 <= n[1] < H and 0 <= n[0] < W):
                    continue
                if int(col[n[1]][n[0]]) != 0:
                    continue
                seen.add(n)
                q.append(n)

        changed = 0
        for w in d.get("warps", []):
            at = w.get("at") or [0, 0]
            cell = (int(at[0]), int(at[1]))
            if not (0 <= cell[1] < H and 0 <= cell[0] < W):
                continue
            if cell in seen:
                continue
            if int(col[cell[1]][cell[0]]) != 0:
                col[cell[1]][cell[0]] = 0
                changed += 1
            n = carve(col, cell, seen)
            changed += n
            # 挖开后重新算连通
            seen.add(cell)
            q = deque([cell])
            while q:
                cx, cy = q.popleft()
                for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                    nb = (cx + dx, cy + dy)
                    if nb in seen or not (0 <= nb[1] < H and 0 <= nb[0] < W):
                        continue
                    if int(col[nb[1]][nb[0]]) != 0:
                        continue
                    seen.add(nb)
                    q.append(nb)

        if changed:
            meta["collision"] = col
            json.dump(meta, open(mp, "w"))
            fixed += 1
            total += changed
            print("  %-32s 补通道 %d 格" % (f[:-5], changed))
    print("%s 修 %d 张图，共挖 %d 格" % (REGION, fixed, total))


if __name__ == "__main__":
    main()
