#!/usr/bin/env python3
"""统一生成关都各城市的室内地图（宝可梦中心 / 商店 / 道馆 / 特色房间），并接进大图。

命名统一为「城市名去下划线 + _后缀」，例：pewtercity_gym、viridiancity_pokemoncenter_1f。
用法: python3 tools/gen_all_rooms.py
"""
import json
import os
import sys

ROOT = "/root/build/pokeemerald-expansion-master"
PJ = "/root/build/pokesaga"
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"

# 城市 -> (原版目录前缀, 中文名, 大图成员名)
CITIES = [
    ("PalletTown", "pallettown", "真新镇", "PALLET_TOWN"),
    ("ViridianCity", "viridiancity", "常磐市", "VIRIDIAN_CITY"),
    ("PewterCity", "pewtercity", "尼比市", "PEWTER_CITY"),
    ("CeruleanCity", "ceruleancity", "华蓝市", "CERULEAN_CITY"),
    ("VermilionCity", "vermilioncity", "枯叶市", "VERMILION_CITY"),
    ("CeladonCity", "celadoncity", "玉虹市", "CELADON_CITY"),
    ("SaffronCity", "saffroncity", "金黄市", "SAFFRON_CITY"),
    ("LavenderTown", "lavendertown", "紫苑镇", "LAVENDER_TOWN"),
    ("FuchsiaCity", "fuchsiacity", "浅红市", "FUCHSIA_CITY"),
    ("CinnabarIsland", "cinnabarisland", "红莲岛", "CINNABAR_ISLAND"),
]

# 特色房间（仅这些城市有）
EXTRA = {
    "PalletTown": [("_PlayersHouse_1F", "playershouse_1f", "自己的家"),
                   ("_RivalsHouse", "rivalshouse", "小茂的家"),
                   ("_ProfessorOaksLab", "professoroakslab", "大木研究所")],
    "ViridianCity": [("_School", "school", "训练家学校"), ("_House", "house", "民宅")],
    "PewterCity": [("_Museum_1F", "museum1f", "科学博物馆"), ("_House1", "house1", "民宅")],
    "CeruleanCity": [("_BikeShop", "bikeshop", "自行车店"), ("_House1", "house1", "民宅"),
                     ("_House2", "house2", "民宅")],
    "CeladonCity": [("_DepartmentStore_1F", "departmentstore_1f", "百货大楼 1F")],
    "LavenderTown": [("_PokemonTower_1F", "pokemontower_1f", "宝可梦塔")],
}

BASE_KINDS = [("_PokemonCenter_1F", "pokemoncenter_1f", "宝可梦中心"),
              ("_Mart", "mart", "友好商店"),
              ("_Gym", "gym", "道馆")]

# 馆主：中文名、徽章、队伍（物种ID, 等级, 招式名列表）
LEADERS = {
    "PewterCity": ("馆主 小刚", "灰色徽章", [(74, 12, ["撞击", "变硬"]), (95, 14, ["撞击", "落石"])]),
    "CeruleanCity": ("馆主 小霞", "蓝色徽章", [(120, 18, ["撞击", "水枪"]), (121, 21, ["水枪", "高速星星"])]),
    "VermilionCity": ("馆主 马志士", "橙色徽章", [(100, 21, ["电击", "音爆"]), (25, 18, ["电击", "电光一闪"]),
                                                (26, 24, ["十万伏特", "电光一闪"])]),
    "CeladonCity": ("馆主 莉佳", "彩虹徽章", [(71, 24, ["藤鞭", "溶解液"]), (102, 24, ["念力", "催眠粉"]),
                                            (45, 29, ["花瓣舞", "催眠粉"])]),
    "SaffronCity": ("馆主 娜姿", "金色徽章", [(64, 38, ["念力", "幻象光线"]), (122, 37, ["幻象光线", "光墙"]),
                                            (49, 43, ["精神强念", "催眠粉"])]),
    "FuchsiaCity": ("馆主 阿桔", "粉红徽章", [(109, 37, ["污泥攻击", "烟雾"]), (89, 39, ["污泥攻击", "变小"]),
                                             (110, 43, ["污泥攻击", "自爆"])]),
    "ViridianCity": ("馆主 坂木", "绿色徽章", [(111, 45, ["角撞", "踩踏"]), (51, 42, ["挖洞", "掷泥"]),
                                             (31, 44, ["泰山压顶", "二连踢"]), (112, 50, ["地震", "角撞"])]),
    "CinnabarIsland": ("馆主 夏伯", "深红徽章", [(58, 42, ["火花", "咬住"]), (77, 40, ["火花", "踩踏"]),
                                               (78, 47, ["大字爆炎", "突进"])]),
}

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
    "BLUE": ("cooltrainer_m", "小茂"),
    "GIOVANNI": ("cooltrainer_m", "馆主 坂木"),
}
SKIP = ["CUTTABLE_TREE", "ROCK_SMASH", "BOULDER", "SIGNPOST", "CUT_TREE", "BREAKABLE_ROCK",
        "FOSSIL", "ITEM", "BALL", "CLIPBOARD", "TV", "CUSHION"]

# 台词池：每对都不同，保证同一张图里不会撞车
POOL = [
    ["这条街我闭着眼都能走。", "不过夜里还是别乱逛。"],
    ["宝可梦的体力要靠平时的照顾。", "别只顾着打。"],
    ["我刚从北边过来，风挺大。", "帽子差点被吹跑。"],
    ["你队伍里有几只？", "我这只跟了我三年。"],
    ["听说馆主今天心情不错。", "挑这时候挑战正合适。"],
    ["这附近的水很干净。", "能看到鱼在游。"],
    ["我小时候在这里迷过路。", "后来是只波波带我出去的。"],
    ["训练家最重要的是判断。", "不是谁先出手。"],
    ["你在收集徽章吗？", "八枚就能去石英高原。"],
    ["商店今天补货了。", "精灵球管够。"],
    ["别小看短裤小子。", "他们跑得比谁都快。"],
    ["我在等一个朋友。", "他说带了好东西来。"],
    ["天气一热，宝可梦就懒。", "我也是。"],
    ["南边的路正在修。", "绕一圈也不远。"],
    ["你见过会变形的宝可梦吗？", "我见过一次，吓一跳。"],
    ["背包里常备解毒药。", "省得半路手忙脚乱。"],
    ["这条路上训练家不少。", "走两步就有人拦你。"],
    ["我打算攒钱买个新鱼竿。", "旧的线断了。"],
    ["宝可梦中心在城中心。", "认那个红色屋顶。"],
    ["别把 PP 用完才想起来回去。", "很麻烦的。"],
    ["这座城的石头有年头了。", "摸上去还是凉的。"],
    ["我每天早上都在这儿散步。", "空气好。"],
    ["对面那家店的饭团不错。", "就是有点咸。"],
    ["我女儿刚拿到第一只宝可梦。", "高兴得睡不着。"],
    ["你走路的声音太响了。", "会惊到野生宝可梦。"],
    ["这里的道馆地板是木头的。", "踩上去会响。"],
    ["我年轻时也想当训练家。", "后来改行修自行车了。"],
    ["听说有人在洞里挖到化石。", "值不少钱。"],
    ["别在草丛边发呆。", "容易被打个措手不及。"],
    ["我养了只卡蒂狗。", "看家很靠得住。"],
    ["海风带咸味。", "衣服晾不干。"],
    ["城东的桥上风景最好。", "傍晚去看。"],
    ["我最近在练钓鱼。", "一条都没钓上来。"],
    ["挑战道馆前先回血。", "别嫌麻烦。"],
    ["你能帮我看下地图吗？", "我好像走反了。"],
    ["这条路通向下一个城镇。", "走过去大概半天。"],
    ["宝可梦也会累。", "记得让它歇歇。"],
    ["我把精灵球都放第二格。", "找起来快。"],
    ["听说这附近有稀有的宝可梦。", "但我没遇到。"],
    ["雨后的空气最好闻。", "泥土味。"],
    ["我在这儿等巴士。", "已经等了半小时。"],
]


POOL_A = [
    "这条街我闭着眼都能走。", "宝可梦的体力靠平时的照顾。", "我刚从北边过来，风挺大。",
    "你队伍里有几只？", "听说馆主今天心情不错。", "这附近的水很干净。",
    "我小时候在这里迷过路。", "训练家最重要的是判断。", "你在收集徽章吗？",
    "商店今天补货了。", "别小看短裤小子。", "我在等一个朋友。",
    "天气一热，宝可梦就懒。", "南边的路正在修。", "你见过会变形的宝可梦吗？",
]
POOL_B = [
    "不过夜里还是别乱逛。", "别只顾着打。", "帽子差点被吹跑。",
    "我这只跟了我三年。", "挑这时候挑战正合适。", "能看到鱼在游。",
    "后来是只波波带我出去的。", "不是谁先出手。", "八枚就能去石英高原。",
    "精灵球管够。", "他们跑得比谁都快。", "他说带了好东西来。",
    "我也是。", "绕一圈也不远。", "我见过一次，吓一跳。",
]
POOL_C = [
    "背包里常备解毒药。", "这条路上训练家不少。", "我打算攒钱买个新鱼竿。",
    "宝可梦中心在城中心。", "别把 PP 用完才想起来回去。", "这座城的石头有年头了。",
    "我每天早上都在这儿散步。", "对面那家店的饭团不错。", "我女儿刚拿到第一只宝可梦。",
    "你走路的声音太响了。", "这里的道馆地板是木头的。", "我年轻时也想当训练家。",
    "听说有人在洞里挖到化石。", "别在草丛边发呆。", "海风带咸味。",
]


def norm_id(name):
    return "".join(c for c in name if c.isalnum()).lower()


def snake(src):
    out = ""
    for i, ch in enumerate(src):
        out += ("_" + ch.lower()) if ch.isupper() and i else ch.lower()
    return out.replace("_f_r_l_g", "").replace("__", "_").strip("_")


def load_maps():
    out = {}
    for d in os.listdir(os.path.join(ROOT, "data/maps")):
        p = os.path.join(ROOT, "data/maps", d, "map.json")
        if os.path.exists(p):
            try:
                out[d] = json.load(open(p))
            except Exception:
                pass
    return out


def gfx_of(gid):
    g = gid.replace("OBJ_EVENT_GFX_", "").replace("_FRLG", "")
    if g in GFX:
        return GFX[g]
    for k, v in GFX.items():
        if g.startswith(k):
            return v
    return ("man", "路人")


def main():
    moves = {m["name"]: m["id"] for m in json.load(open(os.path.join(PJ, "content/moves.json")))}
    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    sys.path.insert(0, os.path.join(PJ, "tools"))
    from render_emerald_maps import render_layout

    all_maps = load_maps()
    big_meta = json.load(open(os.path.join(EMAPS, BIG + ".json")))
    offs = big_meta["member_maps"]
    bigp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bigp))
    import re as _re
    _room_re = _re.compile(r"^[a-z]+(city|town|island)_")
    _keep = [w for w in big["warps"] if not _room_re.match(str(w["to"]["map"]))]
    print("保留非室内门", len(_keep), "丢弃旧室内门", len(big["warps"]) - len(_keep))
    big["warps"] = _keep     # 室内门按地图重建，其它（洞口、森林入口）保留

    made = 0
    used = 0   # 全局 NPC 计数，跨图不重复
    for src_city, pid, cn, bigkey in CITIES:
        city_map = all_maps.get(src_city + "_Frlg")
        if not city_map or bigkey not in offs:
            print("跳过", cn)
            continue
        off = offs[bigkey]
        pw = city_map.get("warp_events", [])
        kinds = list(BASE_KINDS) + EXTRA.get(src_city, [])
        for suffix, sname, label in kinds:
            src = src_city + suffix + "_Frlg"
            d = all_maps.get(src)
            if not d:
                print("  缺原版", src)
                continue
            lay = layouts.get(d["layout"])
            if not lay:
                print("  缺 layout", d["layout"])
                continue
            em = d["layout"].replace("LAYOUT_", "").lower()
            if not os.path.exists(os.path.join(EMAPS, em + ".json")):
                if not render_layout(lay, EMAPS):
                    print("  渲染失败", em)
                    continue
            meta = json.load(open(os.path.join(EMAPS, em + ".json")))
            gid = pid + "_" + sname
            # 出口：本图所有指向本城大图的门
            warps = []
            for we in d.get("warp_events", []):
                if norm_id(str(we.get("dest_map", ""))) != norm_id("MAP_" + src_city.upper()):
                    continue
                did = int(we.get("dest_warp_id", 0) or 0)
                if did >= len(pw):
                    continue
                at = [off[0] + int(pw[did]["x"]), off[1] + int(pw[did]["y"])]
                cell = [int(we["x"]), int(we["y"])]
                warps.append({"at": cell, "to": {"region": "kanto", "map": BIG, "at": at}})
                big["warps"].append({"at": at, "to": {"region": "kanto", "map": gid, "at": cell}})
            if not warps:
                print("  无出口", gid)
                continue
            # NPC
            npcs = []
            leader = LEADERS.get(src_city) if sname == "gym" else None
            for oe in d.get("object_events", []):
                g = str(oe.get("graphics_id", ""))
                if any(s in g for s in SKIP):
                    continue
                tex, name = gfx_of(g)
                npc = {"at": [int(oe["x"]), int(oe["y"])], "gfx": tex, "name": name}
                if "NURSE" in g:
                    npc["name"], npc["heal"] = "护士", True
                elif "MART_EMPLOYEE" in g:
                    npc["name"], npc["shop"] = "店员", True
                elif leader and ("LEADER" in g or name.startswith("馆主") or g.endswith("_MISTY")
                                 or g.endswith("_BROCK") or g.endswith("_LT_SURGE") or g.endswith("_ERIKA")
                                 or g.endswith("_KOGA") or g.endswith("_SABRINA") or g.endswith("_BLAINE") or g.endswith("_GIOVANNI")):
                    lname, badge, team = leader
                    npc["name"] = lname
                    npc["badge"] = badge
                    npc["battle"] = {"team": [{"species": s, "level": lv,
                                               "moves": [moves[m] for m in mvs if m in moves]}
                                              for s, lv, mvs in team]}
                    npc["lines"] = ["%s：能走到这里，说明你有点本事。" % lname,
                                    "%s 就交给你了。" % badge]
                    leader = None
                else:
                    a = used % 15
                    b = (used // 15) % 15
                    c = (used // 225) % 15
                    npc["lines"] = [POOL_A[a], POOL_B[b], POOL_C[c]]
                    used += 1
                npcs.append(npc)
            out = {"name": "关都·%s·%s" % (cn, label), "emerald": em, "size": meta["size"],
                   "spawn": warps[0]["at"], "npcs": npcs, "warps": warps,
                   "encounters": [], "encounter_rate": 0.0}
            json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
            made += 1
            print("  %s 出口%d npc%d" % (gid, len(warps), len(npcs)))
    json.dump(big, open(bigp, "w"), ensure_ascii=False, indent=1)
    print("共生成", made, "间，大图门", len(big["warps"]))


if __name__ == "__main__":
    main()
