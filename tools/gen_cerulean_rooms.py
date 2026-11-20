#!/usr/bin/env python3
"""生成华蓝市室内地图（宝可梦中心 / 商店 / 道馆 / 民居 / 自行车店 / 月见山 1F），
并把它们的门接进关都大图。

坐标规则：大图坐标 = 该城市在大图里的偏移 + 原版房间内的本地坐标。
"""
from asset_paths import project_path, source_path

import json
import os

ROOT = source_path("emerald")
PJ = project_path()
EMAPS = os.path.join(PJ, "content/emerald_maps")
REGMAPS = os.path.join(PJ, "content/regions/kanto/maps")

# (原版地图名, 游戏内 id, 显示名, emerald 图名)
ROOMS = [
    ("CeruleanCity_PokemonCenter_1F_Frlg", "cerulean_city_pokemon_center_1f",
     "关都·华蓝市·宝可梦中心", "pokemon_center_1f_frlg"),
    ("CeruleanCity_Mart_Frlg", "cerulean_city_mart", "关都·华蓝市·友好商店", "mart_frlg"),
    ("CeruleanCity_Gym_Frlg", "cerulean_city_gym", "关都·华蓝市·华蓝道馆", "cerulean_city_gym"),
    ("CeruleanCity_House1_Frlg", "cerulean_city_house1", "关都·华蓝市·民居", "cerulean_city_house1"),
    ("CeruleanCity_House2_Frlg", "cerulean_city_house2", "关都·华蓝市·民居", "cerulean_city_house2"),
    ("CeruleanCity_BikeShop_Frlg", "cerulean_city_bike_shop", "关都·华蓝市·自行车店", "cerulean_city_bike_shop"),
    ("MtMoon_1F_Frlg", "mt_moon_1f", "关都·月见山 1F", "mt_moon_1f"),
]

GFX = {
    "NURSE": ("nurse", "护士"), "MART_EMPLOYEE": ("clerk", "店员"), "CLERK": ("clerk", "店员"),
    "SCIENTIST": ("scientist", "研究员"), "EXPERT_M": ("expert_m", "专家"),
    "WOMAN": ("lass", "大姐"), "WOMAN_2": ("lass", "女士"), "WOMAN_3": ("lass", "女士"),
    "GIRL": ("lass", "小女孩"), "LITTLE_GIRL": ("lass", "小女孩"), "LITTLE_BOY": ("youngster", "小男孩"),
    "BOY": ("youngster", "小男孩"), "MAN": ("man", "大叔"), "FAT_MAN": ("man", "胖大叔"),
    "OLD_MAN": ("old_man", "老爷爷"), "OLD_WOMAN": ("old_man", "老奶奶"),
    "COOLTRAINER_M": ("cooltrainer_m", "训练家"), "COOLTRAINER_F": ("teala", "训练家"),
    "LASS": ("lass", "少女"), "YOUNGSTER": ("youngster", "短裤小子"),
    "BUG_CATCHER": ("bug_catcher", "捕虫少年"), "HIKER": ("hiker", "登山男"),
    "CAMPER": ("camper", "露营少年"), "SAILOR": ("sailor", "水手"),
    "MISTY": ("misty", "馆主 小霞"), "BLUE": ("cooltrainer_m", "小茂"),
}
SKIP = ["CUTTABLE_TREE", "ROCK_SMASH", "BOULDER", "SIGNPOST", "CUT_TREE", "BREAKABLE_ROCK",
        "FOSSIL", "ITEM", "BALL", "CLIPBOARD"]


def gfx_of(gid):
    g = gid.replace("OBJ_EVENT_GFX_", "").replace("_FRLG", "")
    if g in GFX:
        return GFX[g]
    for k, v in GFX.items():
        if g.startswith(k):
            return v
    return ("man", "路人")


def main():
    big_meta = json.load(open(os.path.join(EMAPS, "kanto_main.json")))
    members = big_meta["member_maps"]
    city_off = members["CERULEAN_CITY"]
    big_reg_path = os.path.join(REGMAPS, "kanto_main.json")
    big_reg = json.load(open(big_reg_path))
    city_json = json.load(open(os.path.join(ROOT, "data/maps/CeruleanCity_Frlg/map.json")))
    city_warps = city_json.get("warp_events", [])

    added_doors = 0
    for src, gid, cn, emerald in ROOMS:
        p = os.path.join(ROOT, "data/maps", src, "map.json")
        if not os.path.exists(p):
            print("缺地图", src)
            continue
        d = json.load(open(p))
        meta = json.load(open(os.path.join(EMAPS, emerald + ".json")))
        w, h = meta["size"]
        col = meta["collision"]

        # 出口坐标：本房间 warps 里指向城市的那几个
        exits = []
        for we in d.get("warp_events", []):
            if "CERULEAN_CITY" not in str(we.get("dest_map", "")):
                continue
            exits.append((int(we["x"]), int(we["y"]), int(we.get("dest_warp_id", 0) or 0)))
        if not exits:
            print("没有出口", src)
            continue
        spawn = [exits[0][0], exits[0][1]]

        warps = []
        for x, y, dest_id in exits:
            if dest_id >= len(city_warps):
                continue
            cw = city_warps[dest_id]
            at = [city_off[0] + int(cw["x"]), city_off[1] + int(cw["y"])]
            warps.append({"at": [x, y], "to": {"region": "kanto", "map": "kanto_main", "at": at}})

        npcs = []
        for oe in d.get("object_events", []):
            gid_raw = str(oe.get("graphics_id", ""))
            if any(s in gid_raw for s in SKIP):
                continue
            tex, label = gfx_of(gid_raw)
            npc = {"at": [int(oe["x"]), int(oe["y"])], "name": label, "gfx": tex,
                   "script": str(oe.get("script", ""))}
            if "NURSE" in gid_raw:
                npc["name"] = "护士"
                npc["heal"] = True
            elif "MART_EMPLOYEE" in gid_raw:
                npc["name"] = "店员"
                npc["shop"] = True
            if "Mist" in label or "小霞" in label:
                npc["name"] = "馆主 小霞"
                npc["lines"] = ["我是小霞，华蓝道馆的馆主。", "水系宝可梦可不是好惹的——来试试？"]
                npc["battle"] = {"species": 121, "level": 21, "moves": [55, 105, 33, 110]}
            npcs.append(npc)

        out = {"name": cn, "emerald": emerald, "size": [w, h], "spawn": spawn,
               "npcs": npcs, "warps": warps, "encounters": [], "encounter_rate": 0.0}
        if gid == "mt_moon_1f":
            out["encounters"] = [
                {"species": 41, "min": 7, "max": 10, "weight": 20},
                {"species": 74, "min": 8, "max": 10, "weight": 20},
                {"species": 41, "min": 8, "max": 9, "weight": 10},
                {"species": 74, "min": 9, "max": 11, "weight": 10},
                {"species": 46, "min": 8, "max": 10, "weight": 10},
                {"species": 35, "min": 8, "max": 11, "weight": 10},
                {"species": 27, "min": 9, "max": 11, "weight": 5},
                {"species": 74, "min": 10, "max": 12, "weight": 5},
            ]
            out["encounter_rate"] = 0.14
        json.dump(out, open(os.path.join(REGMAPS, gid + ".json"), "w"), ensure_ascii=False, indent=1)
        print("房间", gid, "warp", len(warps), "npc", len(npcs))

        # 城市这边加门
        for x, y, _ in exits:
            at = [x, y]
            # 反向找城市里指向这个房间的门
            for cw in city_warps:
                a = str(cw.get("dest_map", "")).upper().replace("MAP_", "").replace("_", "")
                b = src.upper().replace("_FRLG", "").replace("_", "")
                if a != b:
                    continue
                door = [city_off[0] + int(cw["x"]), city_off[1] + int(cw["y"])]
                target = {"region": "kanto", "map": gid, "at": at}
                if not any(w["at"] == door and w["to"]["map"] == gid for w in big_reg["warps"]):
                    big_reg["warps"].append({"at": door, "to": target})
                    added_doors += 1
                break

    json.dump(big_reg, open(big_reg_path, "w"), ensure_ascii=False, indent=1)
    print("大图新增门", added_doors, "总计", len(big_reg["warps"]))


if __name__ == "__main__":
    main()
