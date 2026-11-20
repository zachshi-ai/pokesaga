#!/usr/bin/env python3
"""修正通行判定：原版的"走不过去"不只看 map.bin 的 collision 位，
metatile behavior 里的 impassable / jump 系列也会挡人。

之前只用 collision 位，导致房子的屋檐、花坛边缘、部分墙体在 collision
位上是 0，人就走进房子里去了 —— 这就是"碰撞体积不对"。

这里把 behavior 也算进去，重算每张图（以及拼好的大地图）的 collision。
"""
import json, os, glob, struct

ROOT = "/root/build/pokeemerald-expansion-master"
EMAPS = "/root/build/pokesaga/content/emerald_maps"

import sys
sys.path.insert(0, "/root/build/pokesaga/tools")
from render_emerald_maps import get_primary, get_secondary
from annotate_encounters import behaviors

BH = behaviors()
BLOCK_BEHAVIORS = {BH[k] for k in BH
                   if ("IMPASSABLE" in k or k.startswith("MB_JUMP_")
                       or k == "MB_SECRET_BASE_BREAKABLE_DOOR")}


def behavior_of(ts, local):
    p = os.path.join(ts.path, "metatile_attributes.bin")
    if not os.path.exists(p):
        return -1
    d = open(p, "rb").read()
    if (local + 1) * 2 > len(d):
        return -1
    return struct.unpack_from("<H", d, local * 2)[0] & 0xFF


def rebuild(meta_path):
    meta = json.load(open(meta_path))
    lay = meta.get("layout")
    if not lay:
        return False
    prim = get_primary(lay["primary_tileset"])
    sec = get_secondary(lay["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return False
    block = open(os.path.join(ROOT, lay["blockdata_filepath"]), "rb").read()
    w, h = meta["size"]
    pc = prim.count
    old = meta.get("collision", [])
    col = []
    changed = 0
    for y in range(h):
        row = []
        for x in range(w):
            val = struct.unpack_from("<H", block, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            collision = (val >> 10) & 3
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            b = behavior_of(ts, local)
            blocked = 1 if (collision != 0 or b in BLOCK_BEHAVIORS) else 0
            if y < len(old) and x < len(old[y]) and old[y][x] != blocked:
                changed += 1
            row.append(blocked)
        col.append(row)
    meta["collision"] = col
    json.dump(meta, open(meta_path, "w"), separators=(",", ":"))
    return changed


def main():
    total = 0
    for p in sorted(glob.glob(os.path.join(EMAPS, "*.json"))):
        name = os.path.basename(p)
        if name in ("kanto_main.json", "hoenn_main.json"):
            continue
        c = rebuild(p)
        if c:
            print("%-40s +%d 格改为阻挡" % (name, c))
            total += c
    print("per-map changed", total)

    # 拼好的大地图：按成员偏移重新贴 collision
    for gname in ("kanto_main", "hoenn_main"):
        p = os.path.join(EMAPS, gname + ".json")
        if not os.path.exists(p):
            continue
        g = json.load(open(p))
        members = g.get("member_maps", {})
        if not members:
            continue
        W, H = g["size"]
        col = [[0] * W for _ in range(H)]
        alias = {"PALLET_TOWN": "pallet_town", "ROUTE1": "route1", "VIRIDIAN_CITY": "viridian_city",
                 "ROUTE2": "route2", "PEWTER_CITY": "pewter_city",
                 "LITTLEROOT_TOWN": "littleroot_town", "ROUTE101": "route101"}
        for orig, off in members.items():
            mp = os.path.join(EMAPS, alias.get(orig, orig.lower()) + ".json")
            if not os.path.exists(mp):
                continue
            m = json.load(open(mp))
            mw, mh = m["size"]
            for y in range(mh):
                for x in range(mw):
                    gy, gx = off[1] + y, off[0] + x
                    if 0 <= gy < H and 0 <= gx < W:
                        col[gy][gx] = m["collision"][y][x]
        # 门口必须可走，否则落点会卡住
        for w in g.get("warps", []):
            x, y = w["at"]
            if 0 <= y < H and 0 <= x < W:
                col[y][x] = 0
        g["collision"] = col
        json.dump(g, open(p, "w"), separators=(",", ":"))
        blocked = sum(sum(r) for r in col)
        print("%s: %d 格阻挡 (%.1f%%)" % (gname, blocked, 100.0 * blocked / (W * H)))


if __name__ == "__main__":
    main()
