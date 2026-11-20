#!/usr/bin/env python3
"""把 pokecrystal 的「地图连接」（attributes.asm 里的 connection）转成我们的门口。

原版里相邻的野外地图是"走到边缘就换图"，没有 warp_event；我们的引擎只有门口，
所以城都 388 张图里绝大多数以前互相走不通。这里按共享边界逐格补出门：
  - 本图边缘格 -> 邻图往里第二行/列（避免一落地就踩在门口的格子上）
  - 邻图边缘格 -> 本图往里第二行/列
只给两边都可走的格子补，墙上的格子跳过。
"""
import json
import os
import re
import sys

ROOT = "/root/build/pokecrystal"
PROJ = "/root/build/pokesaga"
JDIR = os.path.join(PROJ, "content/regions/johto/maps")
EMAPS = os.path.join(PROJ, "content/emerald_maps")


def read(p):
    with open(p, encoding="utf-8", errors="ignore") as f:
        return f.read()


_IDS = {}


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s)


def snake(label):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", label)
    s = re.sub(r"(?<=[A-Za-z])(?=[0-9])", "_", s)
    return s.lower()


def build_ids():
    if not _IDS:
        for f in os.listdir(JDIR):
            if f.endswith(".json"):
                _IDS[norm(f[:-5])] = f[:-5]


def map_id(label):
    build_ids()
    cand = "johto_" + snake(label)
    if os.path.exists(os.path.join(JDIR, cand + ".json")):
        return cand
    return _IDS.get(norm(cand), "")


def emap(mid):
    p = os.path.join(EMAPS, mid + ".json")
    if not os.path.exists(p):
        return None
    return json.load(open(p))


def parse_connections():
    txt = read(os.path.join(ROOT, "data/maps/attributes.asm"))
    out = {}
    cur = None
    seen = set()
    for raw in txt.splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"map_attributes\s+(\w+),", line)
        if m:
            cur = m.group(1)
            seen.add(cur)
            continue
        m = re.match(r"connection\s+(north|south|east|west),\s*(\w+),\s*\w+,\s*(-?\d+)", line)
        if m and cur:
            out.setdefault(cur, []).append(
                {"dir": m.group(1), "to": m.group(2), "offset": int(m.group(3))})
    return out


def walkable(meta, x, y):
    coll = meta["collision"]
    if y < 0 or y >= len(coll):
        return False
    row = coll[y]
    if x < 0 or x >= len(row):
        return False
    return int(row[x]) == 0


def is_water(meta, x, y):
    g = meta.get("water")
    if not g:
        return False
    if y < 0 or y >= len(g):
        return False
    row = g[y]
    if x < 0 or x >= len(row):
        return False
    return int(row[x]) != 0


def passable(meta, x, y):
    """水面也能过（冲浪），所以海路连接要算上水格，否则城都那几个岛永远走不到。"""
    return walkable(meta, x, y) or is_water(meta, x, y)


def size_of(meta):
    g = meta["collision"]
    return len(g[0]), len(g)


def has_warp_at(data, x, y):
    for w in data.get("warps", []):
        at = w.get("at", [-1, -1])
        if int(at[0]) == x and int(at[1]) == y:
            return True
    return False


def true_py():
    return True


def add_warp(data, x, y, region, mid, tx, ty):
    if has_warp_at(data, x, y):
        return False
    data.setdefault("warps", []).append(
        {"at": [x, y], "to": {"region": region, "map": mid, "at": [tx, ty]}, "edge": true_py()})
    return True


def _count(a, b, d, off, aw, ah, bw, bh):
    """offset 的正负在原版里跟方向有关，直接两种都试，取能对上更多的那个。"""
    n = 0
    if d in ("north", "south"):
        for x in range(0, aw):
            for bx in (x - off, x + off):
                if 0 <= bx < bw:
                    ay = 0 if d == "north" else ah - 1
                    by = bh - 1 if d == "north" else 0
                    if passable(a, x, ay) and passable(b, bx, by):
                        n += 1
                        break
    else:
        for y in range(0, ah):
            for by in (y - off, y + off):
                if 0 <= by < bh:
                    ax = aw - 1 if d == "east" else 0
                    bx = 0 if d == "east" else bw - 1
                    if passable(a, ax, y) and passable(b, bx, by):
                        n += 1
                        break
    return n


def link(a_label, b_label, d, off):
    a_id, b_id = map_id(a_label), map_id(b_label)
    if not a_id or not b_id:
        return 0
    am, bm = emap(a_id), emap(b_id)
    if not am or not bm:
        return 0
    aw, ah = size_of(am)
    bw, bh = size_of(bm)
    # 选能对上更多格子的符号
    best_off, best_n = off, -1
    for cand in (off, -off):
        n = _count(am, bm, d, cand, aw, ah, bw, bh)
        if n > best_n:
            best_off, best_n = cand, n
    off = best_off
    da = json.load(open(os.path.join(JDIR, a_id + ".json")))
    db = json.load(open(os.path.join(JDIR, b_id + ".json")))
    n = 0
    if d in ("north", "south"):
        for x in range(0, aw):
            ay = 0 if d == "north" else ah - 1
            by = bh - 1 if d == "north" else 0
            bx = -1
            for cand in (x - off, x + off):
                if 0 <= cand < bw and passable(bm, cand, by):
                    bx = cand
                    break
            if bx < 0 or not passable(am, x, ay):
                continue
            ay2 = 1 if ay == 0 else ah - 2
            by2 = bh - 2 if by == bh - 1 else 1
            n += add_warp(da, x, ay, "johto", b_id, bx, by2)
            n += add_warp(db, bx, by, "johto", a_id, x, ay2)
    else:
        for y in range(0, ah):
            ax = aw - 1 if d == "east" else 0
            bx = 0 if d == "east" else bw - 1
            by = -1
            for cand in (y - off, y + off):
                if 0 <= cand < bh and passable(bm, bx, cand):
                    by = cand
                    break
            if by < 0 or not passable(am, ax, y):
                continue
            ax2 = aw - 2 if ax == aw - 1 else 1
            bx2 = 1 if bx == 0 else bw - 2
            n += add_warp(da, ax, y, "johto", b_id, bx2, by)
            n += add_warp(db, bx, by, "johto", a_id, ax2, y)
    json.dump(da, open(os.path.join(JDIR, a_id + ".json"), "w"), ensure_ascii=False, indent=1)
    json.dump(db, open(os.path.join(JDIR, b_id + ".json"), "w"), ensure_ascii=False, indent=1)
    return n


def main():
    conns = parse_connections()
    pairs = set()
    total = 0
    done = 0
    for a, lst in conns.items():
        for c in lst:
            key = tuple(sorted([a, c["to"]])) + (c["dir"], c["offset"])
            if key in pairs:
                continue
            pairs.add(key)
            n = link(a, c["to"], c["dir"], c["offset"])
            if n:
                done += 1
                total += n
    print("连接 %d 条，补出门 %d 个" % (done, total))


if __name__ == "__main__":
    main()
