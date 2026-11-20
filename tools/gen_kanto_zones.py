#!/usr/bin/env python3
"""按 FRLG 原版野生分布给关都大图分区写遇敌，并重写地名分区（areas）。

大图是拼出来的，一张图里横跨好几段路，遇敌必须按矩形分区，
不然在真新镇草地上也可能蹦出 25 号路的东西。
用法: python3 tools/gen_kanto_zones.py
"""
from asset_paths import project_path, source_path

import json
import os

ROOT = project_path()
EMAPS = os.path.join(ROOT, "content/emerald_maps")
REG = os.path.join(ROOT, "content/regions/kanto/maps", "kanto_main.json")
FRLG = source_path("firered", "src/data/wild_encounters.json")

# 大图成员 -> 显示用中文名（None 表示城里，没有陆地遇敌）
AREA_CN = {
    "PALLET_TOWN": "真新镇",
    "ROUTE1": "1 号道路",
    "VIRIDIAN_CITY": "常磐市",
    "ROUTE2": "2 号道路",
    "VIRIDIAN_FOREST": "常磐森林",
    "PEWTER_CITY": "尼比市",
    "ROUTE3": "3 号道路",
    "ROUTE4": "4 号道路",
    "CERULEAN_CITY": "华蓝市",
    "ROUTE24": "24 号道路",
    "ROUTE25": "25 号道路",
}


def main():
    meta = json.load(open(os.path.join(EMAPS, "kanto_main.json")))
    members = meta["member_maps"]
    frlg = json.load(open(FRLG))["wild_encounter_groups"][0]["encounters"]
    by_map = {}
    for e in frlg:
        old = by_map.get(e["map"])
        if old is None or (not old.get("land_mons", {}).get("encounter_rate") and e.get("land_mons", {}).get("encounter_rate")):
            by_map[e["map"]] = e
    species = {s["key"]: int(s["id"]) for s in json.load(open(os.path.join(ROOT, "content/species.json")))}

    zones = []
    areas = []
    for name, (ox, oy) in members.items():
        lay = json.load(open(os.path.join(EMAPS, name.lower() + ".json")))
        w, h = lay["size"]
        areas.append({"x0": ox, "x1": ox + w, "y0": oy, "y1": oy + h,
                      "name": AREA_CN.get(name, name)})
        entry = by_map.get("MAP_" + name)
        land = ((entry or {}).get("land_mons") or {})
        mons = land.get("mons") or []
        if not mons:
            continue
        weights = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
        enc = []
        for i, m in enumerate(mons[:12]):
            skey = String = str(m.get("species", "")).replace("SPECIES_", "")
            sid = species.get(skey)
            if not sid:
                continue
            enc.append({"species": sid, "min": int(m.get("min_level", 2)),
                        "max": int(m.get("max_level", 3)), "weight": weights[i]})
        if not enc:
            continue
        rate = float(land.get("encounter_rate", 21)) / 100.0
        zone = {"rect": [ox, oy, w, h], "rate": rate, "name": name, "encounters": enc}
        # 水面（冲浪）分布：原版 water_mons
        water = (entry or {}).get("water_mons") or {}
        wmons = water.get("mons") or []
        if wmons:
            wenc = []
            for i, m in enumerate(wmons[:5]):
                sid2 = species.get(str(m.get("species", "")).replace("SPECIES_", ""))
                if not sid2:
                    continue
                wenc.append({"species": sid2, "min": int(m.get("min_level", 5)),
                             "max": int(m.get("max_level", 10)),
                             "weight": [60, 30, 5, 4, 1][i]})
            if wenc:
                zone["water"] = wenc
                zone["water_rate"] = float(water.get("encounter_rate", 10)) / 100.0
        zones.append(zone)

    d = json.load(open(REG))
    d["zones"] = zones
    d["areas"] = areas
    json.dump(d, open(REG, "w"), ensure_ascii=False, indent=1)
    print("zones", len(zones), "areas", len(areas))
    for z in zones:
        print("  %-16s rect=%s rate=%.2f 种类 %d" % (z["name"], z["rect"], z["rate"], len(z["encounters"])))


if __name__ == "__main__":
    main()
