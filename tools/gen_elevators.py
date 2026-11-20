#!/usr/bin/env python3
"""电梯：西尔佛公司、火箭队秘密基地、训练家塔各做一间电梯厅，
里面按楼层排好，一格电梯门对一层，双向可走。
用法: python3 tools/gen_elevators.py
"""
from asset_paths import project_path, source_path

import json
import os
import re
import sys

ROOT = source_path("emerald")
PJ = project_path()
EMAPS = os.path.join(PJ, "content/emerald_maps")
KANTO = os.path.join(PJ, "content/regions/kanto/maps")
SEVII = os.path.join(PJ, "content/regions/sevii/maps")

GROUPS = [
    # 地区, 电梯原版地图, 电梯房 id, 楼层前缀, 楼层 id 规则
    ("kanto", "SilphCo_Elevator_Frlg", "silph_co_elevator", "silph_co_", range(1, 12)),
    ("kanto", "RocketHideout_Elevator_Frlg", "rocket_hideout_elevator", "rocket_hideout_b", range(1, 5)),
    ("sevii", "TrainerTower_Elevator_Frlg", "trainer_tower_elevator", "trainer_tower_", range(1, 9)),
]


def snake(name):
    out = ""
    for i, ch in enumerate(name):
        out += ("_" + ch.lower()) if ch.isupper() and i else ch.lower()
    out = re.sub(r"__+", "_", out.replace("_frlg", "").strip("_"))
    return re.sub(r"(\d)_f$", r"\1f", out)


def free_cells(col, count, avoid):
    out = []
    H, W = len(col), len(col[0])
    # 从中间往外找，排成一行行，离得开一点
    for y in range(H):
        for x in range(W):
            if len(out) >= count:
                return out
            if int(col[y][x]) != 0:
                continue
            if any(abs(x - a) + abs(y - b) < 1 for a, b in out):
                continue
            if (x, y) in avoid:
                continue
            out.append((x, y))
    return out


def main():
    sys.path.insert(0, os.path.join(PJ, "tools"))
    from render_emerald_maps import render_layout

    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    md = os.path.join(ROOT, "data/maps")

    for region, srcname, eid, prefix, rng in GROUPS:
        regdir = KANTO if region == "kanto" else SEVII
        src = json.load(open(os.path.join(md, srcname, "map.json")))
        lay = layouts[src["layout"]]
        em = str(src["layout"]).replace("LAYOUT_", "").lower()
        if not os.path.exists(os.path.join(EMAPS, em + ".json")):
            render_layout(lay, EMAPS)
        meta = json.load(open(os.path.join(EMAPS, em + ".json")))

        # 楼层 id
        floors = []
        for n in rng:
            for cand in ("%s%d_f" % (prefix, n) if not prefix.endswith("b") else "%s%df" % (prefix, n),
                         "%s%df" % (prefix, n)):
                pass
            gid = "%s%df" % (prefix, n) if prefix.endswith("b") else "%s_%df" % (prefix.rstrip("_"), n)
            gid = re.sub(r"(\d)_f$", r"\1f", gid)
            if os.path.exists(os.path.join(regdir, gid + ".json")):
                floors.append(gid)
        if not floors:
            print("电梯 %s：没有楼层" % eid)
            continue

        cells = free_cells(meta["collision"], len(floors), set())
        if len(cells) < len(floors):
            print("电梯 %s：格子不够（%d/%d）" % (eid, len(cells), len(floors)))
            continue

        warps = []
        for gid, cell in zip(floors, cells):
            fp = os.path.join(regdir, gid + ".json")
            f = json.load(open(fp))
            # 楼层里原有的电梯门（之前被丢掉的那扇）
            src_map = None
            for d in os.listdir(md):
                if d.endswith("_Frlg") and snake(d[:-5]) == gid:
                    src_map = json.load(open(os.path.join(md, d, "map.json")))
                    break
            door = None
            if src_map:
                for we in src_map.get("warp_events", []):
                    if "ELEVATOR" in str(we.get("dest_map", "")).upper():
                        door = [int(we["x"]), int(we["y"])]
                        break
            if door is None:
                # 找不到原版门就放在本层出生点旁边
                door = list(f["spawn"])
            warps.append({"at": [cell[0], cell[1]],
                          "to": {"region": region, "map": gid, "at": door}})
            f["warps"] = [w for w in f["warps"] if w["at"] != door]
            f["warps"].append({"at": door, "to": {"region": region, "map": eid,
                                                  "at": [cell[0], cell[1]]}})
            json.dump(f, open(fp, "w"), ensure_ascii=False, indent=1)

        out = {"name": "关都·电梯" if region == "kanto" else "七之岛·电梯",
               "emerald": em, "size": meta["size"], "spawn": list(cells[0]),
               "npcs": [], "warps": warps, "encounters": [], "encounter_rate": 0.0}
        json.dump(out, open(os.path.join(regdir, eid + ".json"), "w"), ensure_ascii=False, indent=1)
        print("电梯 %-22s 接 %d 层：%s" % (eid, len(floors), ", ".join(floors)))

        # 地区清单补上电梯房
        rp = os.path.join(PJ, "content/regions/%s/region.json" % region)
        rd = json.load(open(rp))
        if eid not in rd["maps"]:
            rd["maps"].append(eid)
            json.dump(rd, open(rp, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
