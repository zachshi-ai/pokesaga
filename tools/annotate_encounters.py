#!/usr/bin/env python3
"""给已渲染的原版地图补两样数据：

1. grass 网格 —— 哪些格子是高草（按 metatile behavior 判断），
   我这边没有 tiles 数组，遇敌判定必须靠它。
2. encounters —— 直接抄原版 wild_encounters.json 里这张图的陆地分布
   （species / 等级区间 / 权重），连触发率一起带过来。
"""
from asset_paths import project_path, source_path

import json, os, glob, struct

ROOT = source_path("emerald")
EMAPS = project_path("content/emerald_maps")
REG = project_path("content/regions")

import sys
sys.path.insert(0, project_path("tools"))
from render_emerald_maps import get_primary, get_secondary


def behaviors():
    vals = {}
    n = 0
    for line in open(os.path.join(ROOT, "include/constants/metatile_behaviors.h"), errors="ignore"):
        ln = line.split("//")[0].strip()
        if ln.startswith("MB_"):
            vals[ln.rstrip(",")] = n
            n += 1
    return vals


# 只有这两种才会遇敌；城镇里的短草、灰草不算
GRASS_BEHAVIORS = ["MB_TALL_GRASS", "MB_LONG_GRASS"]


def attr_step(ts):
    """metatile 属性每条多少字节：绿宝石 2 字节，火红叶绿 4 字节。
    之前一律按 2 字节读，火红那批地图的 behavior 全是错的
    （所以栅栏被当成土坡、真土坡反而当成普通墙）。"""
    p = os.path.join(ts.path, "metatile_attributes.bin")
    if not os.path.exists(p):
        return 2
    size = os.path.getsize(p)
    n = getattr(ts, "count", 0) or 0
    if n <= 0:
        return 2
    return max(2, size // n)


def behavior_of(ts, local):
    p = os.path.join(ts.path, "metatile_attributes.bin")
    if not os.path.exists(p):
        return -1
    d = open(p, "rb").read()
    step = attr_step(ts)
    if (local + 1) * step > len(d):
        return -1
    if step >= 4:
        v = struct.unpack_from("<I", d, local * step)[0]
    else:
        v = struct.unpack_from("<H", d, local * step)[0]
    return v & 0xFF


def species_to_dex():
    """SPECIES_X -> 全国图鉴号（来自 species_info 里的 natDexNum）"""
    dex_order = {}
    pdex = os.path.join(ROOT, "include/constants/pokedex.h")
    n = 0
    started = False
    for line in open(pdex, errors="ignore"):
        ln = line.split("//")[0]
        if "enum NationalDexOrder" in ln:
            started = True
            continue
        if not started:
            continue
        import re
        m = re.match(r"\s*NATIONAL_DEX_(\w+)\s*,?\s*$", ln)
        if m:
            dex_order[m.group(1)] = n
            n += 1
    out = {}
    import re
    for path in glob.glob(os.path.join(ROOT, "src/data/pokemon/species_info/gen_*_families.h")):
        text = open(path, errors="ignore").read()
        heads = [(m.start(), m.group(1)) for m in re.finditer(r"\n\s*\[SPECIES_(\w+)\]\s*=", text)]
        for i, (pos, key) in enumerate(heads):
            end = heads[i + 1][0] if i + 1 < len(heads) else len(text)
            body = text[pos:end]
            m = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", body)
            if not m:
                continue
            dex = dex_order.get(m.group(1))
            if dex and key not in out:
                out[key] = dex
    return out


def load_wild():
    d = json.load(open(os.path.join(ROOT, "src/data/wild_encounters.json")))
    table = {}
    for e in d["wild_encounter_groups"][0]["encounters"]:
        table[e["map"].replace("MAP_", "")] = e
    return table


def main():
    bh = behaviors()
    grass_ids = {bh[k] for k in GRASS_BEHAVIORS if k in bh}
    s2d = species_to_dex()
    wild = load_wild()
    print("grass behaviors", grass_ids, "species map", len(s2d))

    # 原版 map 名（去 _Frlg）-> 我的地图 json
    own = {}
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        d = json.load(open(f))
        if d.get("emerald"):
            own[os.path.normcase(d["emerald"])] = (f, d)

    for name, (f, d) in own.items():
        meta_path = os.path.join(EMAPS, d["emerald"] + ".json")
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
        for y in range(h):
            row = []
            for x in range(w):
                val = struct.unpack_from("<H", block, (y * w + x) * 2)[0]
                mid = val & 0x3FF
                ts = prim if mid < pc else sec
                local = mid if mid < pc else mid - pc
                row.append(1 if behavior_of(ts, local) in grass_ids else 0)
            grid.append(row)
        meta["grass"] = grid

        # 原版分布：map 名大小写/下划线都不一致，统一归一化后比
        def nk(x):
            return "".join(ch for ch in x.lower() if ch.isalnum())
        key = None
        target = nk(d["emerald"])
        for k in wild:
            if nk(k) == target:
                key = k
                break
        enc = []
        rate = 0.0
        if key:
            wd = wild[key].get("land_mons")
            if wd:
                rate = float(wd.get("encounter_rate", 0)) / 100.0
                rate = min(0.45, max(0.02, rate))
                rates = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
                for i, mon in enumerate(wd.get("mons", [])):
                    sp = mon.get("species", "").replace("SPECIES_", "")
                    dex = s2d.get(sp)
                    if not dex:
                        continue
                    enc.append({"species": dex,
                                "min": int(mon.get("min_level", 2)),
                                "max": int(mon.get("max_level", 2)),
                                "weight": rates[i] if i < len(rates) else 1})
        meta["encounters"] = enc
        meta["encounter_rate"] = rate
        json.dump(meta, open(meta_path, "w"), separators=(",", ":"))
        d["encounters"] = enc
        d["encounter_rate"] = rate
        json.dump(d, open(f, "w"), ensure_ascii=False, indent=1)
        print("%-32s grass %4d  encounters %2d  rate %.2f" % (d["emerald"], sum(sum(r) for r in grid), len(enc), rate))


if __name__ == "__main__":
    main()
