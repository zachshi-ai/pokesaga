#!/usr/bin/env python3
"""生成洞窟/迷宫类室内地图（岩山隧道、冠军之路、狩猎区、宝可梦塔、双子岛、无人发电所、
华蓝洞窟、地鼠洞），彼此按原版 warp 互连，通往室外的门接进关都大图。
用法: python3 tools/gen_dungeons.py [组名...]
"""
import json
import os
import sys

ROOT = "/root/build/pokeemerald-expansion-master"
PJ = "/root/build/pokesaga"
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"
FRLG = "/tmp/frlg/pokefirered-master/src/data/wild_encounters.json"

# 组名 -> [(原版地图目录, 游戏内 id, 中文名)]
GROUPS = {
    "rocktunnel": [("RockTunnel_1F_Frlg", "rocktunnel_1f", "岩山隧道 1F"),
                   ("RockTunnel_B1F_Frlg", "rocktunnel_b1f", "岩山隧道 B1F")],
    "victoryroad": [("VictoryRoad_1F_Frlg", "victoryroad_1f", "冠军之路 1F"),
                    ("VictoryRoad_2F_Frlg", "victoryroad_2f", "冠军之路 2F"),
                    ("VictoryRoad_3F_Frlg", "victoryroad_3f", "冠军之路 3F")],
    "safari": [("FuchsiaCity_SafariZone_Entrance_Frlg", "safarizone_entrance", "狩猎区·入口"),
               ("SafariZone_Center_Frlg", "safarizone_center", "狩猎区·中央"),
               ("SafariZone_East_Frlg", "safarizone_east", "狩猎区·东"),
               ("SafariZone_North_Frlg", "safarizone_north", "狩猎区·北"),
               ("SafariZone_West_Frlg", "safarizone_west", "狩猎区·西")],
    "tower": [("PokemonTower_1F_Frlg", "pokemontower_1f", "宝可梦塔 1F"),
              ("PokemonTower_2F_Frlg", "pokemontower_2f", "宝可梦塔 2F"),
              ("PokemonTower_3F_Frlg", "pokemontower_3f", "宝可梦塔 3F"),
              ("PokemonTower_4F_Frlg", "pokemontower_4f", "宝可梦塔 4F"),
              ("PokemonTower_5F_Frlg", "pokemontower_5f", "宝可梦塔 5F"),
              ("PokemonTower_6F_Frlg", "pokemontower_6f", "宝可梦塔 6F"),
              ("PokemonTower_7F_Frlg", "pokemontower_7f", "宝可梦塔 7F")],
    "seafoam": [("SeafoamIslands_1F_Frlg", "seafoam_1f", "双子岛 1F"),
                ("SeafoamIslands_B1F_Frlg", "seafoam_b1f", "双子岛 B1F")],
    "powerplant": [("PowerPlant_Frlg", "powerplant", "无人发电所")],
    "ceruleancave": [("CeruleanCave_1F_Frlg", "ceruleancave_1f", "华蓝洞窟 1F"),
                     ("CeruleanCave_2F_Frlg", "ceruleancave_2f", "华蓝洞窟 2F"),
                     ("CeruleanCave_B1F_Frlg", "ceruleancave_b1f", "华蓝洞窟 B1F")],
}

# 室外落点：原版地图名（去 _Frlg）-> 大图成员 key
HOSTS = {
    "ROUTE10": "ROUTE10", "ROUTE9": "ROUTE9", "ROUTE23": "ROUTE23",
    "INDIGO_PLATEAU_EXTERIOR": "INDIGO_PLATEAU_EXTERIOR", "FUCHSIA_CITY": "FUCHSIA_CITY",
    "LAVENDER_TOWN": "LAVENDER_TOWN", "CERULEAN_CITY": "CERULEAN_CITY", "ROUTE4": "ROUTE4",
    "ROUTE19": "ROUTE19", "ROUTE20": "ROUTE20", "ROUTE11": "ROUTE11", "ROUTE12": "ROUTE12",
    "ROUTE2": "ROUTE2", "VIRIDIAN_CITY": "VIRIDIAN_CITY", "ROUTE26": "ROUTE26",
    "ROUTE22": "ROUTE22", "ROUTE13": "ROUTE13", "ROUTE14": "ROUTE14", "ROUTE15": "ROUTE15",
}


LINES_A = ["洞里比外面冷。", "回音很大，小声点。", "前面塌了一段。", "火把快烧完了。",
           "这层我来过三回。", "脚下滑，慢点走。", "你听见水滴声了吗。", "别往深处乱走。",
           "我把备用绳放这儿了。", "这石头有股硫磺味。", "一个人进来太危险。", "洞口的风是往外吹的。",
           "我在这儿歇一会儿。", "墙上有旧的刻痕。", "这层的路是个圈。"]
LINES_B = ["小心脚下的碎石。", "贴着墙走能省力。", "常有小拳石滚下来。", "我把灯留给你。",
           "出去记得晒太阳。", "水源在第三层。", "别惊动洞穴里的东西。", "地图我画了一半。",
           "有些岔路是死路。", "呼吸放慢点。", "这里曾经是矿道。", "我数过台阶，四十七级。",
           "带上解毒药再来。", "拐角处很窄。", "天黑前必须出去。"]
_npc_i = 0


def norm(x):
    t = str(x).upper().replace("MAP_", "").replace("_FRLG", "")
    return "".join(ch for ch in t if ch.isalnum())


def main():
    want = sys.argv[1:]
    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    sys.path.insert(0, os.path.join(PJ, "tools"))
    from render_emerald_maps import render_layout

    wild = {}
    if os.path.exists(FRLG):
        for e in json.load(open(FRLG))["wild_encounter_groups"][0]["encounters"]:
            old = wild.get(e["map"])
            if old is None or (not old.get("land_mons", {}).get("encounter_rate")
                               and e.get("land_mons", {}).get("encounter_rate")):
                wild[e["map"]] = e
    species = {s["key"]: s["id"] for s in json.load(open(os.path.join(PJ, "content/species.json")))}
    bigp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bigp))
    offs = json.load(open(os.path.join(EMAPS, BIG + ".json")))["member_maps"]

    # 凡是大图成员都能当落点（不再手写白名单，漏一个就断一片）
    HOSTS.update({norm(k): k for k in offs})

    for gname, rooms in GROUPS.items():
        if want and gname not in want:
            continue
        by_norm = {norm(src): (src, gid, cn) for src, gid, cn in rooms}
        data = {}
        for src, gid, cn in rooms:
            p = os.path.join(ROOT, "data/maps", src, "map.json")
            if not os.path.exists(p):
                print("缺地图", src)
                continue
            data[src] = json.load(open(p))
        # 1) 渲染
        for src, d in data.items():
            lay = layouts.get(d["layout"])
            if not lay:
                print("缺 layout", d["layout"])
                continue
            em = d["layout"].replace("LAYOUT_", "").lower()
            if not os.path.exists(os.path.join(EMAPS, em + ".json")):
                render_layout(lay, EMAPS)

        # 2) 逐间生成
        for src, gid, cn in rooms:
            d = data.get(src)
            if not d:
                continue
            em = d["layout"].replace("LAYOUT_", "").lower()
            mp = os.path.join(EMAPS, em + ".json")
            if not os.path.exists(mp):
                continue
            meta = json.load(open(mp))
            warps = []
            for we in d.get("warp_events", []):
                dest = norm(we.get("dest_map", ""))
                did = int(we.get("dest_warp_id", 0) or 0)
                cell = [int(we["x"]), int(we["y"])]
                if dest in by_norm:
                    tsrc, tgid, _ = by_norm[dest]
                    twe = data.get(tsrc, {}).get("warp_events", [])
                    if did >= len(twe):
                        continue
                    warps.append({"at": cell, "to": {"region": "kanto", "map": tgid,
                                                     "at": [int(twe[did]["x"]), int(twe[did]["y"])]}})
                elif dest in HOSTS:
                    host = HOSTS[dest]
                    hp = os.path.join(ROOT, "data/maps", host + "_Frlg/map.json")
                    if not os.path.exists(hp):
                        for dn in os.listdir(os.path.join(ROOT, "data/maps")):
                            fp = os.path.join(ROOT, "data/maps", dn, "map.json")
                            if not os.path.exists(fp):
                                continue
                            try:
                                if json.load(open(fp)).get("id", "") == "MAP_" + host:
                                    hp = fp
                                    break
                            except Exception:
                                pass
                    if host not in offs or not os.path.exists(hp):
                        continue
                    hw = json.load(open(hp)).get("warp_events", [])
                    if did >= len(hw):
                        continue
                    at = [offs[host][0] + int(hw[did]["x"]), offs[host][1] + int(hw[did]["y"])]
                    warps.append({"at": cell, "to": {"region": "kanto", "map": BIG, "at": at}})
                    if not any(w["at"] == at for w in big["warps"]):
                        big["warps"].append({"at": at, "to": {"region": "kanto", "map": gid, "at": cell}})
            if not warps:
                print("  无出口", gid)
                continue
            npcs = []
            global _npc_i
            for oe in d.get("object_events", []):
                g = str(oe.get("graphics_id", ""))
                if any(x in g for x in ("ITEM", "BALL", "SIGNPOST", "BOULDER", "FOSSIL", "CUT")):
                    continue
                npcs.append({"at": [int(oe["x"]), int(oe["y"])], "name": "训练家", "gfx": "cooltrainer_m",
                             "lines": [LINES_A[_npc_i % 15], LINES_B[(_npc_i // 15) % 15]]})
                _npc_i += 1
            enc, rate = [], 0.0
            mid = str(d.get("id", "")).replace("MAP_", "")
            w = wild.get("MAP_" + mid) or wild.get("MAP_" + src.replace("_Frlg", "").upper())
            if w:
                land = w.get("land_mons") or {}
                weights = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
                for i, m in enumerate((land.get("mons") or [])[:12]):
                    sid = species.get(m["species"].replace("SPECIES_", ""))
                    if not sid:
                        continue
                    enc.append({"species": sid, "min": int(m["min_level"]), "max": int(m["max_level"]),
                                "weight": weights[i]})
                rate = float(land.get("encounter_rate", 0)) / 100.0
            entry = [w2["at"] for w2 in warps if w2["to"]["map"] == BIG]
            out = {"name": "关都·" + cn, "emerald": em, "size": meta["size"],
                   "spawn": entry[0] if entry else warps[0]["at"], "npcs": npcs, "warps": warps,
                   "encounters": enc, "encounter_rate": rate}
            json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
            print("  %s warp%d npc%d 遇敌%d" % (gid, len(warps), len(npcs), len(enc)))
    json.dump(big, open(bigp, "w"), ensure_ascii=False, indent=1)
    print("大图门", len(big["warps"]))


if __name__ == "__main__":
    main()
