#!/usr/bin/env python3
"""给已渲染的原版地图补一张 counter 网格。

原版柜台是 MB_COUNTER，人走不上去，但可以隔着柜台跟后面的 NPC 说话
（宝可梦中心的乔伊就是这种）。我们的碰撞只记「能不能走」，
所以得过一遍 metatile behavior，把柜台单独标出来。
"""
import json, os, glob, struct, sys

ROOT = "/root/build/pokeemerald-expansion-master"
EMAPS = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions"

sys.path.insert(0, "/root/build/pokesaga/tools")
from render_emerald_maps import get_primary, get_secondary
from annotate_encounters import behaviors, behavior_of

BH = behaviors()
COUNTERS = {BH[k] for k in ("MB_COUNTER",) if k in BH}


def main():
    print("counter behaviors", COUNTERS)
    own = {}
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        d = json.load(open(f))
        if d.get("emerald"):
            own[os.path.normcase(d["emerald"])] = f

    done = 0
    for name in own:
        meta_path = os.path.join(EMAPS, name + ".json")
        if not os.path.exists(meta_path):
            continue
        meta = json.load(open(meta_path))
        lay = meta.get("layout")
        if not lay:
            continue
        prim = get_primary(lay["primary_tileset"])
        sec = get_secondary(lay["secondary_tileset"], fallback=prim)
        if not prim or not sec:
            continue
        block = open(os.path.join(ROOT, lay["blockdata_filepath"]), "rb").read()
        w, h = meta["size"]
        pc = prim.count
        grid = []
        hits = 0
        for y in range(h):
            row = []
            for x in range(w):
                val = struct.unpack_from("<H", block, (y * w + x) * 2)[0]
                mid = val & 0x3FF
                ts = prim if mid < pc else sec
                local = mid if mid < pc else mid - pc
                v = 1 if behavior_of(ts, local) in COUNTERS else 0
                hits += v
                row.append(v)
            grid.append(row)
        meta["counter"] = grid
        json.dump(meta, open(meta_path, "w"), separators=(",", ":"))
        print("%-36s %dx%-3d counter %d" % (name, w, h, hits))
        done += 1
    print("done", done)


if __name__ == "__main__":
    main()
