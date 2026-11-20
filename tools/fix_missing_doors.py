#!/usr/bin/env python3
"""补大图上漏接的门。

早期手工建城里那几间房时，只挂了「那扇门」而漏了同一栋楼的其他门格
（宝可梦中心三格门、公寓两扇门、道路关卡东西两扇门…），结果楼在、门不通。
做法：拿原版室外图的 warp_events（含 dest_map / dest_warp_id）逐个对，
大图上缺哪一格就补哪一格，并保证房间那一侧也有对得上的门。
用法: python3 tools/fix_missing_doors.py [--dry]
"""
from asset_paths import project_path, source_path

import json
import os
import re
import sys

ROOT = source_path("emerald")
PJ = project_path()
EM = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"


def norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("frlg", ""))


def snake(n):
    o = ""
    for i, c in enumerate(n):
        o += ("_" + c.lower()) if c.isupper() and i else c.lower()
    o = re.sub(r"__+", "_", o.replace("_frlg", "").strip("_"))
    return re.sub(r"(\d)_f$", r"\1f", o)


def main():
    dry = "--dry" in sys.argv
    md = os.path.join(ROOT, "data/maps")
    offs = json.load(open(os.path.join(EM, BIG + ".json")))["member_maps"]
    bp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bp))
    have = {(int(w["at"][0]), int(w["at"][1])) for w in big["warps"]}

    # 已有房间：原版地图 id -> 本地房间 id（按 layout 与尺寸对）
    rooms = {}
    for f in os.listdir(REG):
        if not f.endswith(".json") or f == BIG + ".json":
            continue
        d = json.load(open(os.path.join(REG, f)))
        rooms[f[:-5]] = d
    by_em = {}
    for gid, d in rooms.items():
        by_em.setdefault(d.get("emerald", ""), []).append(gid)

    # 原版地图 id -> (目录, map.json)
    srcmaps = {}
    for d in os.listdir(md):
        if d.endswith("_Frlg"):
            try:
                mm = json.load(open(os.path.join(md, d, "map.json")))
            except Exception:
                continue
            srcmaps[norm(str(mm.get("id", "")))] = (d, mm)
            srcmaps[norm(d)] = (d, mm)

    added, skipped = 0, []
    for d in sorted(os.listdir(md)):
        if not d.endswith("_Frlg"):
            continue
        key = norm(d[:-5])
        host = next((k for k in offs if norm(k) == key), None)
        if host is None:
            continue
        m = json.load(open(os.path.join(md, d, "map.json")))
        ox, oy = offs[host]
        for we in m.get("warp_events", []):
            g = (ox + int(we["x"]), oy + int(we["y"]))
            if g in have:
                continue
            dest = str(we.get("dest_map", ""))
            try:
                did = int(we.get("dest_warp_id", 0) or 0)
            except (TypeError, ValueError):
                skipped.append((g, dest, "dynamic"))
                continue
            src = srcmaps.get(norm(dest))
            if not src:
                skipped.append((g, dest, "no-map"))
                continue
            sdir, sm = src
            gid = next((k for k, v in rooms.items() if norm(k) == norm(snake(sdir[:-5]))), None)
            if gid is None:
                # 没做这张图：跳过
                skipped.append((g, dest, "no-room"))
                continue
            twe = sm.get("warp_events", [])
            if did >= len(twe):
                skipped.append((g, dest, "no-dest-warp"))
                continue
            cell = [int(twe[did]["x"]), int(twe[did]["y"])]
            if not any(list(w["at"]) == cell for w in rooms[gid].get("warps", [])):
                rooms[gid].setdefault("warps", []).append(
                    {"at": cell, "to": {"region": "kanto", "map": BIG, "at": [g[0], g[1]]}})
            big["warps"].append({"at": [g[0], g[1]],
                                 "to": {"region": "kanto", "map": gid, "at": cell}})
            have.add(g)
            added += 1
            print("  补门 %s -> %s %s" % (list(g), gid, cell))

    if not dry:
        json.dump(big, open(bp, "w"), ensure_ascii=False, indent=1)
        for gid, d in rooms.items():
            json.dump(d, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
    print("补 %d 扇，跳过 %d 扇" % (added, len(skipped)))
    for s in skipped:
        print("   跳过", s)


if __name__ == "__main__":
    main()
