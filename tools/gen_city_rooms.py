#!/usr/bin/env python3
"""批量生成城市室内（宝可梦中心 / 商店 / 道馆）并接进关都大图。
用法: python3 tools/gen_city_rooms.py [城市名...]   不带参数就处理全部
"""
import json
import os
import sys

ROOT = "/root/build/pokeemerald-expansion-master"
PJ = "/root/build/pokesaga"
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")

CITIES = {
    "VermilionCity": "枯叶市", "CeladonCity": "玉虹市", "SaffronCity": "金黄市",
    "LavenderTown": "紫苑镇", "FuchsiaCity": "浅红市", "CinnabarIsland": "红莲岛",
    "PewterCity": "尼比市", "ViridianCity": "常磐市", "CeruleanCity": "华蓝市",
}
KINDS = [("_PokemonCenter_1F", "pokemon_center_1f_frlg", "宝可梦中心"),
         ("_Mart", "mart_frlg", "友好商店"),
         ("_Gym", None, "道馆")]

GFX = {
    "NURSE": ("nurse", "护士"), "MART_EMPLOYEE": ("clerk", "店员"), "CLERK": ("clerk", "店员"),
    "SCIENTIST": ("scientist", "研究员"), "EXPERT_M": ("expert_m", "专家"),
    "WOMAN": ("lass", "大姐"), "GIRL": ("lass", "小女孩"), "LITTLE_GIRL": ("lass", "小女孩"),
    "LITTLE_BOY": ("youngster", "小男孩"), "BOY": ("youngster", "小男孩"), "MAN": ("man", "大叔"),
    "FAT_MAN": ("man", "胖大叔"), "OLD_MAN": ("old_man", "老爷爷"), "OLD_WOMAN": ("old_man", "老奶奶"),
    "COOLTRAINER_M": ("cooltrainer_m", "训练家"), "COOLTRAINER_F": ("teala", "训练家"),
    "LASS": ("lass", "少女"), "YOUNGSTER": ("youngster", "短裤小子"),
    "BUG_CATCHER": ("bug_catcher", "捕虫少年"), "HIKER": ("hiker", "登山男"),
    "CAMPER": ("camper", "露营少年"), "SAILOR": ("sailor", "水手"),
    "BROCK": ("brock", "馆主 小刚"), "MISTY": ("misty", "馆主 小霞"),
    "LT_SURGE": ("cooltrainer_m", "馆主 马志士"), "ERIKA": ("lass", "馆主 莉佳"),
    "KOGA": ("cooltrainer_m", "馆主 阿桔"), "SABRINA": ("lass", "馆主 娜姿"),
    "BLAINE": ("old_man", "馆主 夏伯"), "GIOVANNI": ("cooltrainer_m", "馆主 坂木"),
}
LEADERS = {
    "VermilionCity": ("馆主 马志士", 25, 24, [85, 84, 98, 33]),
    "CeladonCity": ("馆主 莉佳", 29, 71, [79, 78, 51, 80]),
    "SaffronCity": ("馆主 娜姿", 34, 65, [94, 115, 105, 60]),
    "FuchsiaCity": ("馆主 阿桔", 39, 110, [40, 92, 188, 48]),
    "CinnabarIsland": ("馆主 夏伯", 42, 59, [53, 36, 109, 46]),
    "PewterCity": ("馆主 小刚", 14, 95, [88, 106, 111, 33]),
    "CeruleanCity": ("馆主 小霞", 21, 121, [55, 105, 33, 110]),
}
SKIP = ["CUTTABLE_TREE", "ROCK_SMASH", "BOULDER", "SIGNPOST", "CUT_TREE", "BREAKABLE_ROCK",
        "FOSSIL", "ITEM", "BALL", "CLIPBOARD"]
LINES = {
    "路人": ["这条路我走了十几年。", "前面就是下一座城。"],
    "大姐": ["最近野生的宝可梦很活跃。", "多带几个精灵球。"],
    "少女": ["听说馆主很强。", "记得先把队伍练起来。"],
    "短裤小子": ["我将来要当训练家！", "现在先练级。"],
    "登山男": ["山路不好走。", "洞里更黑。"],
    "训练家": ["想比一场吗？", "我可不手下留情。"],
    "研究员": ["形态道具我这儿都有。", "带上就能变样子。"],
    "专家": ["别急着赶路。", "看清属性再出招。"],
    "老爷爷": ["年纪大了，走两步就累。", "你们年轻人真好啊。"],
    "老奶奶": ["记得给宝可梦回血。", "别硬撑。"],
}


def gfx_of(gid):
    g = gid.replace("OBJ_EVENT_GFX_", "").replace("_FRLG", "")
    if g in GFX:
        return GFX[g]
    for k, v in GFX.items():
        if g.startswith(k):
            return v
    return ("man", "路人")


def main():
    want = sys.argv[1:]
    big_meta = json.load(open(os.path.join(EMAPS, "kanto_main.json")))
    offs = big_meta["member_maps"]
    brp = os.path.join(REG, "kanto_main.json")
    big = json.load(open(brp))
    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    total = 0
    for city, cn in CITIES.items():
        if want and city not in want:
            continue
        big_key = "".join(ch for ch in city.upper() if ch.isalnum())
        cand = [k for k in offs if "".join(ch for ch in k if ch.isalnum()) == big_key]
        if not cand:
            print("大图里没有", city)
            continue
        city_off = offs[cand[0]]
        city_json_path = os.path.join(ROOT, "data/maps", city + "_Frlg/map.json")
        if not os.path.exists(city_json_path):
            continue
        city_maps = json.load(open(city_json_path))
        for suffix, emerald, label in KINDS:
            src = city + suffix
            p = os.path.join(ROOT, "data/maps", src + "_Frlg/map.json")
            if not os.path.exists(p):
                continue
            d = json.load(open(p))
            lay_id = d["layout"]
            em = emerald or lay_id.replace("LAYOUT_", "").lower()
            if not os.path.exists(os.path.join(EMAPS, em + ".json")):
                lay = layouts.get(lay_id)
                if not lay:
                    print("缺 layout", lay_id)
                    continue
                sys.path.insert(0, os.path.join(PJ, "tools"))
                from render_emerald_maps import render_layout
                r = render_layout(lay, EMAPS)
                if not r:
                    continue
            meta = json.load(open(os.path.join(EMAPS, em + ".json")))
            base = city.replace("City", "").replace("Town", "").replace("Island", "")
            snake = ""
            for i, c in enumerate(base):
                snake += ("_" + c.lower()) if (c.isupper() and i) else c.lower()
            snake = snake.strip("_")
            if city.endswith("City"):
                snake += "_city"
            elif city.endswith("Town"):
                snake += "_town"
            elif city.endswith("Island"):
                snake += "_island"
            gid = snake + {"_PokemonCenter_1F": "_pokemon_center_1f", "_Mart": "_mart", "_Gym": "_gym"}[suffix]
            # 出口：指向本城的门
            exits = [(int(w["x"]), int(w["y"]), int(w.get("dest_warp_id", 0) or 0))
                     for w in d.get("warp_events", []) if city.upper() in str(w.get("dest_map", "")).upper()
                     .replace("_", "")]
            if not exits:
                print("无出口", src)
                continue
            warps = []
            for x, y, did in exits:
                cw = city_maps.get("warp_events", [])
                if did >= len(cw):
                    continue
                at = [city_off[0] + int(cw[did]["x"]), city_off[1] + int(cw[did]["y"])]
                warps.append({"at": [x, y], "to": {"region": "kanto", "map": "kanto_main", "at": at}})
            npcs = []
            for oe in d.get("object_events", []):
                g = str(oe.get("graphics_id", ""))
                if any(s in g for s in SKIP):
                    continue
                tex, name = gfx_of(g)
                npc = {"at": [int(oe["x"]), int(oe["y"])], "name": name, "gfx": tex,
                       "script": str(oe.get("script", ""))}
                if "NURSE" in g:
                    npc["name"] = "护士"
                    npc["heal"] = True
                elif "MART_EMPLOYEE" in g:
                    npc["name"] = "店员"
                    npc["shop"] = True
                elif city in LEADERS and (name.startswith("馆主") or "LEADER" in g or "MISTY" in g or "BROCK" in g):
                    ln, lv, sid, moves = LEADERS[city]
                    npc["name"] = ln
                    npc["battle"] = {"species": sid, "level": lv, "moves": moves}
                else:
                    key = next((k for k in LINES if k in name), "路人")
                    npc["lines"] = list(LINES[key]) + ["——%s" % cn]
                npcs.append(npc)
            out = {"name": "关都·%s·%s" % (cn, label), "emerald": em, "size": meta["size"],
                   "spawn": warps[0]["at"] if warps else [1, 1], "npcs": npcs, "warps": warps,
                   "encounters": [], "encounter_rate": 0.0}
            json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
            # 大图加门
            for x, y, _ in exits:
                for cw in city_maps.get("warp_events", []):
                    if "".join(ch for ch in str(cw.get("dest_map", "")).upper() if ch.isalnum()) != \
                            "".join(ch for ch in ("MAP_" + src.upper()) if ch.isalnum()):
                        continue
                    door = [city_off[0] + int(cw["x"]), city_off[1] + int(cw["y"])]
                    if any(w["at"] == door for w in big["warps"]):
                        break
                    big["warps"].append({"at": door, "to": {"region": "kanto", "map": gid,
                                                            "at": [x, y]}})
                    total += 1
                    break
            print("房间", gid, "出口", len(warps), "npc", len(npcs))
    json.dump(big, open(brp, "w"), ensure_ascii=False, indent=1)
    print("新增大图门", total, "总门数", len(big["warps"]))


if __name__ == "__main__":
    main()
