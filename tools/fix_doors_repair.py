#!/usr/bin/env python3
"""门与落点的修补工，三件事：

1. 楼梯对不上：原版 1F 的楼梯要跳到 2F 的第 N 号门，可 2F 的门数量被裁过，
   N 越界就会被跳过，两层就断了。这里按「目标图里有一扇门反过来指回本图」配对补上。
2. NPC 压在落点上：站在门口正中间，人一出来就跟他重叠，走不动。把人挪到旁边的空地。
3. 门在墙里：有些门在原版美术里就是封死的装饰门，从出生点走不到。把这些门去掉，
   免得检查时报「这扇门走不到」，也不会在城里留一扇看着像门、其实进不去的口子。
用法: python3 tools/fix_doors_repair.py [--dry]
"""
import json
import os
import sys
from collections import deque

_REGION = "kanto"
for _a in sys.argv:
    if _a.startswith("--region="):
        _REGION = _a.split("=")[1]
REG = "/root/build/pokesaga/content/regions/%s/maps" % _REGION
EM = "/root/build/pokesaga/content/emerald_maps"
BIG = "kanto_main" if _REGION == "kanto" else ""


def load_all():
    out = {}
    for f in os.listdir(REG):
        if f.endswith(".json"):
            out[f[:-5]] = json.load(open(os.path.join(REG, f)))
    return out


def grid_of(d):
    p = os.path.join(EM, str(d.get("emerald", "")) + ".json")
    if not d.get("emerald") or not os.path.exists(p):
        return None
    return json.load(open(p))


def walkable(meta, x, y):
    col = meta.get("collision")
    if not col or y < 0 or y >= len(col):
        return False
    row = col[y]
    if x < 0 or x >= len(row):
        return False
    return int(row[x]) == 0


def reach(meta, start, npcs):
    """能走到哪些格：普通四方向 + 土坡跳两格（单向），跟游戏里的判定一致。"""
    seen = {start}
    q = deque([start])
    blocked = {(int(n["at"][0]), int(n["at"][1])) for n in npcs if n.get("at")}
    ledge = meta.get("ledge")
    while q:
        x, y = q.popleft()
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nx, ny = x + dx, y + dy
            if (nx, ny) not in seen and (nx, ny) not in blocked and walkable(meta, nx, ny):
                seen.add((nx, ny))
                q.append((nx, ny))
                continue
            # 土坡：跳两格
            if ledge and 0 <= ny < len(ledge) and 0 <= nx < len(ledge[ny]):
                bits = int(ledge[ny][nx])
                ok = ((dy == -1 and bits & 1) or (dy == 1 and bits & 2)
                      or (dx == 1 and bits & 4) or (dx == -1 and bits & 8))
                if ok:
                    jx, jy = x + dx * 2, y + dy * 2
                    if (jx, jy) not in seen and (jx, jy) not in blocked and walkable(meta, jx, jy):
                        seen.add((jx, jy))
                        q.append((jx, jy))
    return seen


def main():
    dry = "--dry" in sys.argv
    maps = load_all()
    stairs, moved, dropped = [], [], []

    # 1) 楼梯配对
    for k, d in maps.items():
        if k == BIG:
            continue
        for w in d.get("warps", []):
            to = w.get("to") or {}
            t = to.get("map", "")
            if to.get("region") != "kanto" or t == BIG or t == k or t not in maps:
                continue
            tgt = maps[t]
            ok = False
            for w2 in tgt.get("warps", []):
                if (w2.get("to") or {}).get("map") == k and list(w2["at"]) == list(to.get("at", [])):
                    ok = True
                    break
            if ok:
                continue
            # 找目标图里回指本图的门，补成本图的落点
            cands = [w2 for w2 in tgt.get("warps", [])
                     if (w2.get("to") or {}).get("map") == k]
            if not cands:
                continue
            want = [int(w["at"][0]), int(w["at"][1])]
            used = {tuple(x.get("at")) for x in d.get("warps", []) if (x.get("to") or {}).get("map") == t}
            pick = None
            for c in cands:
                if tuple(c["at"]) in used:
                    continue
                if list(c["at"]) == want:
                    pick = c
                    break
                if pick is None:
                    pick = c
            if pick is None:
                pick = cands[0]
            to["at"] = [int(pick["at"][0]), int(pick["at"][1])]
            stairs.append((k, w["at"], t, to["at"]))

    # 2) NPC 压落点
    for k, d in maps.items():
        if k == BIG:
            continue
        meta = grid_of(d)
        if not meta:
            continue
        cells = {(int(w["at"][0]), int(w["at"][1])) for w in d.get("warps", []) if w.get("at")}
        cells.add((int(d.get("spawn", [1, 1])[0]), int(d.get("spawn", [1, 1])[1])))
        for n in d.get("npcs", []) or []:
            if not n.get("at"):
                continue
            pos = (int(n["at"][0]), int(n["at"][1]))
            if pos not in cells:
                continue
            if walkable(meta, pos[0], pos[1]) and pos not in {(int(w["at"][0]), int(w["at"][1])) for w in d.get("warps", [])} \
                    and pos != (int(d.get("spawn", [-1, -1])[0]), int(d.get("spawn", [-1, -1])[1])):
                continue
            spot = None
            for r in range(1, 4):
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        c = (pos[0] + dx, pos[1] + dy)
                        if c in cells:
                            continue
                        if not walkable(meta, c[0], c[1]):
                            continue
                        if any((int(o["at"][0]), int(o["at"][1])) == c for o in d.get("npcs", []) or []):
                            continue
                        spot = c
                        break
                    if spot:
                        break
                if spot:
                    break
            if spot:
                moved.append((k, pos, spot))
                n["at"] = [spot[0], spot[1]]

    # 3) 走不到的门：起点算「出生点 + 所有从别处传进来的落点」，
    # 跟游戏里那套检查一致（森林北口这种门本来就只能从对面走出来）
    incoming = {}
    for k, d in maps.items():
        for w in d.get("warps", []):
            to = w.get("to") or {}
            if to.get("region") != _REGION:
                continue
            t = to.get("map")
            a = to.get("at") or []
            if t and len(a) == 2:
                incoming.setdefault(t, set()).add((int(a[0]), int(a[1])))
    for k, d in maps.items():
        if k == BIG:
            continue
        meta = grid_of(d)
        if not meta:
            continue
        sp = d.get("spawn", [1, 1])
        seeds = {(int(sp[0]), int(sp[1]))} | incoming.get(k, set())
        seen = set()
        for sd in seeds:
            seen |= reach(meta, sd, d.get("npcs") or [])
        keep = []
        for w in d.get("warps", []):
            a = w.get("at") or []
            if len(a) == 2 and (int(a[0]), int(a[1])) not in seen:
                dropped.append((k, list(a), (w.get("to") or {}).get("map")))
                continue
            keep.append(w)
        d["warps"] = keep

    if not dry:
        for k, d in maps.items():
            json.dump(d, open(os.path.join(REG, k + ".json"), "w"), ensure_ascii=False, indent=1)

    print("补楼梯 %d 条" % len(stairs))
    for s in stairs:
        print("   ", s[0], s[1], "->", s[2], s[3])
    print("挪 NPC %d 个" % len(moved))
    for m in moved:
        print("   ", m[0], m[1], "->", m[2])
    print("去掉走不到的门 %d 扇" % len(dropped))
    for x in dropped:
        print("   ", x)


if __name__ == "__main__":
    main()
