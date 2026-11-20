#!/usr/bin/env python3
"""按原版 data/maps/<Map>.json 生成指定室内地图并接进关都大图。
用法: python3 tools/gen_room.py <原版地图名> [<原版地图名>...]
例:  python3 tools/gen_room.py PalletTown_PlayersHouse_1F_Frlg ViridianCity_School_Frlg
"""
import json
import os
import sys

ROOT = "/root/build/pokeemerald-expansion-master"
PJ = "/root/build/pokesaga"
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"

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
    "MOM": ("mom", "妈妈"), "PROF_OAK": ("oak", "大木博士"),
    "BLUE": ("cooltrainer_m", "小茂"), "BROCK": ("brock", "馆主 小刚"),
}
SKIP = ["CUTTABLE_TREE", "ROCK_SMASH", "BOULDER", "SIGNPOST", "CUT_TREE", "BREAKABLE_ROCK",
        "FOSSIL", "ITEM", "BALL", "CLIPBOARD"]
LINES = {
    "路人": ["……", "路上小心。"],
    "妈妈": ["别把宝可梦累坏了。", "记得常回来。"],
    "大木博士": ["图鉴还差得远呢。", "外面的世界很大。"],
    "研究员": ["形态道具我这儿都有。", "带上就能变样子。"],
    "专家": ["看清属性再出招。", "别小看相性。"],
    "老爷爷": ["年纪大了，走两步就累。", "你们年轻人真好啊。"],
    "老奶奶": ["记得给宝可梦回血。", "别硬撑。"],
    "少女": ["听说馆主很强。", "记得先把队伍练起来。"],
    "短裤小子": ["我将来要当训练家！", "现在先练级。"],
    "训练家": ["想比一场吗？", "我可不手下留情。"],
}


def snake(name):
    out = ""
    for i, ch in enumerate(name):
        out += ("_" + ch.lower()) if ch.isupper() and i else ch.lower()
    return out.replace("_f_r_l_g", "").replace("_frlg", "").strip("_")


def gfx_of(gid):
    g = gid.replace("OBJ_EVENT_GFX_", "").replace("_FRLG", "")
    if g in GFX:
        return GFX[g]
    for k, v in GFX.items():
        if g.startswith(k):
            return v
    return ("man", "路人")


def main():
    names = sys.argv[1:]
    big_meta = json.load(open(os.path.join(EMAPS, BIG + ".json")))
    offs = big_meta["member_maps"]
    bigp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bigp))
    all_maps = {}
    for city in os.listdir(os.path.join(ROOT, "data/maps")):
        if not city.endswith("_Frlg"):
            continue
        try:
            d = json.load(open(os.path.join(ROOT, "data/maps", city, "map.json")))
            d["_dir"] = city
            all_maps[city] = d
        except Exception:
            pass
    added = 0
    for src in names:
        d = all_maps.get(src)
        if not d:
            print("找不到原版地图", src)
            continue
        em = d["layout"].replace("LAYOUT_", "").lower()
        mp = os.path.join(EMAPS, em + ".json")
        if not os.path.exists(mp):
            print("缺渲染", em)
            continue
        meta = json.load(open(mp))
        gid = snake(src)
        parent = src.split("_")[0].upper()
        cand = [k for k in offs if "".join(c for c in k if c.isalnum()) == "".join(c for c in parent if c.isalnum())]
        if not cand:
            print("大图里没有所属城市", parent)
            continue
        off = offs[cand[0]]
        pcand = [k for k in all_maps if k.upper().replace("_", "") == parent.replace("_", "") + "FRLG"]
        pm = all_maps[pcand[0]] if pcand else {}
        pw = pm.get("warp_events", [])
        warps = []
        for we in d.get("warp_events", []):
            dest = str(we.get("dest_map", ""))
            if "".join(c for c in dest.upper() if c.isalnum()) != "".join(c for c in ("MAP_" + parent) if c.isalnum()):
                continue
            did = int(we.get("dest_warp_id", 0) or 0)
            if did >= len(pw):
                continue
            at = [off[0] + int(pw[did]["x"]), off[1] + int(pw[did]["y"])]
            warps.append({"at": [int(we["x"]), int(we["y"])],
                          "to": {"region": "kanto", "map": BIG, "at": at}})
            if not any(w["at"] == at for w in big["warps"]):
                big["warps"].append({"at": at, "to": {"region": "kanto", "map": gid,
                                                      "at": [int(we["x"]), int(we["y"])]}})
                added += 1
        if not warps:
            print("无同类出口", src)
            continue
        npcs = []
        for oe in d.get("object_events", []):
            g = str(oe.get("graphics_id", ""))
            if any(s in g for s in SKIP):
                continue
            tex, name = gfx_of(g)
            npc = {"at": [int(oe["x"]), int(oe["y"])], "name": name, "gfx": tex}
            if "NURSE" in g:
                npc["name"], npc["heal"] = "护士", True
            elif "MART_EMPLOYEE" in g:
                npc["name"], npc["shop"] = "店员", True
            else:
                key = next((k for k in LINES if k in name), "路人")
                npc["lines"] = list(LINES[key])
            npcs.append(npc)
        out = {"name": "关都·" + gid.replace("_", "·"), "emerald": em, "size": meta["size"],
               "spawn": warps[0]["at"], "npcs": npcs, "warps": warps,
               "encounters": [], "encounter_rate": 0.0}
        json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
        print("房间", gid, "出口", len(warps), "npc", len(npcs))
    json.dump(big, open(bigp, "w"), ensure_ascii=False, indent=1)
    print("新增大图门", added, "总门数", len(big["warps"]))


if __name__ == "__main__":
    main()
