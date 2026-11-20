#!/usr/bin/env python3
"""把关都 / 七岛原版里的三样挡路物摆进游戏：居合斩小树、可碎岩石、可推岩块。

只认 object_events 里的原始图形名，坐标和原版一致；已经存在的同格同类型物件
不会重复添加，所以这个脚本可以反复跑。
"""
from asset_paths import project_path, source_path

import json
import os
import re

PJ = project_path()
ROOT = source_path("emerald")
MD = os.path.join(ROOT, "data/maps")
EM = os.path.join(PJ, "content/emerald_maps")

KINDS = [
    ("OBJ_EVENT_GFX_CUTTABLE_TREE", "cut", "cut"),
    ("OBJ_EVENT_GFX_BREAKABLE_ROCK", "rock", "rock"),
    ("OBJ_EVENT_GFX_PUSHABLE_BOULDER", "boulder", "boulder"),
]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def main():
    rooms = {}
    for rid in ("kanto", "sevii"):
        d = os.path.join(PJ, "content/regions", rid, "maps")
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if f.endswith(".json"):
                rooms[(rid, f[:-5])] = json.load(open(os.path.join(d, f)))
    by_norm = {}
    for (rid, gid) in rooms:
        if gid == "kanto_main":
            continue
        by_norm[norm(gid)] = (rid, gid)
        by_norm["map" + norm(gid)] = (rid, gid)
    hosts = {norm(k): (k, v) for k, v in
             json.load(open(os.path.join(EM, "kanto_main.json")))["member_maps"].items()}

    stat = {"cut": 0, "rock": 0, "boulder": 0}
    for d in sorted(os.listdir(MD)):
        if not d.endswith("_Frlg"):
            continue
        mp = os.path.join(MD, d, "map.json")
        if not os.path.exists(mp):
            continue
        key = norm(d[:-5])
        hit = by_norm.get(key)
        off = None
        if hit:
            rid, gid = hit
        elif key in hosts:
            rid, gid = "kanto", "kanto_main"
            off = hosts[key][1]
        else:
            continue
        room = rooms[(rid, gid)]
        objs = room.setdefault("objects", [])
        have = {(int(o["at"][0]), int(o["at"][1]), str(o.get("kind", "")))
                for o in objs if "at" in o}
        added = False
        for oe in json.load(open(mp)).get("object_events", []):
            gfx = str(oe.get("graphics_id", ""))
            kind = sprite = None
            for prefix, k, sp in KINDS:
                if gfx.startswith(prefix):
                    kind, sprite = k, sp
                    break
            if kind is None:
                continue
            at = [int(oe["x"]), int(oe["y"])]
            if off:
                at = [at[0] + int(off[0]), at[1] + int(off[1])]
            key3 = (at[0], at[1], kind)
            if key3 in have:
                continue
            objs.append({"at": at, "kind": kind, "sprite": sprite})
            have.add(key3)
            stat[kind] += 1
            added = True
        if added:
            p = os.path.join(PJ, "content/regions", rid, "maps", gid + ".json")
            json.dump(room, open(p, "w"), ensure_ascii=False, indent=1)

    print("新增 小树 %d，岩石 %d，岩块 %d" % (stat["cut"], stat["rock"], stat["boulder"]))
    total = {}
    for (rid, gid), room in rooms.items():
        for o in room.get("objects", []):
            k = str(o.get("kind", ""))
            total[k] = total.get(k, 0) + 1
    print("全库物件：", total)


if __name__ == "__main__":
    main()
