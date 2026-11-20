#!/usr/bin/env python3
"""把一组室内地图按原版 warp 关系互连（月见山这类多层洞穴），
并把通往大图的门接到关都大图对应的位置。

用法: python3 tools/link_rooms.py
"""
from asset_paths import project_path, source_path

import json
import os

ROOT = source_path("emerald")
EMAPS = project_path("content/emerald_maps")
REG = project_path("content/regions/kanto/maps")

# 原版地图名 -> 游戏内 id
INDOOR = [
    ("MtMoon_1F_Frlg", "mt_moon_1f", "关都·月见山 1F"),
    ("MtMoon_B1F_Frlg", "mt_moon_b1f", "关都·月见山 B1F"),
    ("MtMoon_B2F_Frlg", "mt_moon_b2f", "关都·月见山 B2F"),
]
# 大图上的落点：这些原版地图名要换回大图坐标
HOST = {"ROUTE4": ("Route4_Frlg", "ROUTE4")}


def norm(x):
    t = x.upper().replace("MAP_", "").replace("_FRLG", "")
    return "".join(ch for ch in t if ch.isalnum())


def main():
    big = json.load(open(os.path.join(EMAPS, "kanto_main.json")))
    offs = big["member_maps"]
    brp = os.path.join(REG, "kanto_main.json")
    big_reg = json.load(open(brp))

    maps = {}
    for src, gid, cn in INDOOR:
        maps[src] = json.load(open(os.path.join(ROOT, "data/maps", src, "map.json")))
    by_norm = {norm(k): k for k in maps}
    host_maps = {}
    for h, (dirname, memb) in HOST.items():
        p = os.path.join(ROOT, "data/maps", dirname, "map.json")
        if os.path.exists(p):
            host_maps[h] = json.load(open(p))

    def dest_point(dest, wid):
        """目标地图 + 目标 warp 序号 -> 目标坐标"""
        d = dest.replace("MAP_", "")
        if d in host_maps:
            we = host_maps[d]["warp_events"]
            if wid < len(we):
                memb = HOST[d][1]
                return ("big", memb, [offs[memb][0] + int(we[wid]["x"]),
                                      offs[memb][1] + int(we[wid]["y"])])
            return None
        k = by_norm.get(norm(d))
        if not k:
            return None
        we = maps[k]["warp_events"]
        if wid >= len(we):
            return None
        return ("room", k, [int(we[wid]["x"]), int(we[wid]["y"])])

    made = 0
    for src, gid, cn in INDOOR:
        d = maps[src]
        meta = json.load(open(os.path.join(EMAPS, gid.replace("mt_moon_", "mt_moon_") + ".json")))
        warps = []
        for i, we in enumerate(d.get("warp_events", [])):
            p = dest_point(str(we.get("dest_map", "")), int(we.get("dest_warp_id", 0) or 0))
            if not p:
                continue
            kind, tgt, at = p
            to = {"region": "kanto", "map": "kanto_main" if kind == "big" else INDOOR_ID[tgt], "at": at}
            warps.append({"at": [int(we["x"]), int(we["y"])], "to": to})
        path = os.path.join(REG, gid + ".json")
        cur = json.load(open(path)) if os.path.exists(path) else {}
        cur.setdefault("name", cn)
        cur["emerald"] = gid
        cur["size"] = meta["size"]
        cur["npcs"] = cur.get("npcs", [])
        cur["warps"] = warps
        entry = [w["at"] for w in warps if w["to"]["map"] == "kanto_main"]
        cur["spawn"] = entry[0] if entry else (warps[0]["at"] if warps else [1, 1])
        if "encounters" not in cur:
            cur["encounters"] = []
            cur["encounter_rate"] = 0.0
        json.dump(cur, open(path, "w"), ensure_ascii=False, indent=1)
        made += 1
        print(gid, "warp", len(warps))

    # 大图：把 Route4 的洞口接进去
    n = 0
    for h, hd in host_maps.items():
        for we in hd.get("warp_events", []):
            p = dest_point(str(we.get("dest_map", "")), int(we.get("dest_warp_id", 0) or 0))
            if not p or p[0] != "room":
                continue
            memb = HOST[h][1]
            door = [offs[memb][0] + int(we["x"]), offs[memb][1] + int(we["y"])]
            tgt = {"region": "kanto", "map": INDOOR_ID[p[1]], "at": p[2]}
            if any(w["at"] == door for w in big_reg["warps"]):
                continue
            big_reg["warps"].append({"at": door, "to": tgt})
            n += 1
    json.dump(big_reg, open(brp, "w"), ensure_ascii=False, indent=1)
    print("大图新增洞口", n, "总门数", len(big_reg["warps"]))


INDOOR_ID = {src: gid for src, gid, _ in INDOOR}

if __name__ == "__main__":
    main()
