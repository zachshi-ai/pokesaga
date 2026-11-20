#!/usr/bin/env python3
"""按原版 FRLG 数据批量生成关都室内地图（民居、商店楼层、游戏城、公寓、旅馆、
狩猎区小屋、宝可梦屋、地鼠洞、地下通道、道路关卡等）。

规则：
- 只处理关都范围内的 FRLG 地图（_Frlg 后缀，排除七之岛等离岛）
- 贴图缺失的 tileset（silph_co）直接跳过并报出来，不硬凑
- 单元内的门按 dest_map/dest_warp_id 互连；通往室外的门落进关都大图并补反向门
用法: python3 tools/gen_rooms_auto.py [--dry]
"""
import json
import os
import sys

ROOT = "/root/build/pokeemerald-expansion-master"
PJ = "/root/build/pokesaga"
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"

# 关都范围：按目录前缀收录
INCLUDE = [
    "PalletTown", "ViridianCity", "PewterCity", "CeruleanCity", "VermilionCity",
    "LavenderTown", "CeladonCity", "SaffronCity", "FuchsiaCity", "CinnabarIsland",
    "PokemonMansion", "PokemonTower", "PowerPlant", "DiglettsCave", "UndergroundPath",
    "RockTunnel", "MtMoon", "CeruleanCave", "SeafoamIslands", "VictoryRoad",
    "SafariZone", "PokemonLeague", "IndigoPlateau", "SilphCo", "SSAnne",
    "RocketHideout", "Route",
]
SKIP_DIRS = {"InsideOfTruck"}
# 早期手工建过、命名不一样的同名房间：别再生成一份
ALIAS = {
    "seafoam_islands_1f": "seafoam_1f",
    "seafoam_islands_b1f": "seafoam_b1f",
    "saffron_city_pokemon_trainer_fan_club": "saffroncity_fan_club",
    "fuchsia_city_safari_zone_entrance": "safarizone_entrance",
}

CN = {
    "POKEMON_CENTER_1F": "宝可梦中心", "POKEMON_CENTER_2F": "宝可梦中心 2F",
    "MART": "商店", "GYM": "道馆", "HOUSE1": "民居 1", "HOUSE2": "民居 2",
    "HOUSE3": "民居 3", "HOUSE4": "民居 4", "HOUSE5": "民居 5",
    "HOUSE": "民居", "SCHOOL": "训练家学校", "MUSEUM_1F": "博物馆 1F",
    "MUSEUM_2F": "博物馆 2F", "BIKE_SHOP": "自行车店",
    "DEPARTMENT_STORE_1F": "百货 1F", "DEPARTMENT_STORE_2F": "百货 2F",
    "DEPARTMENT_STORE_3F": "百货 3F", "DEPARTMENT_STORE_4F": "百货 4F",
    "DEPARTMENT_STORE_5F": "百货 5F", "DEPARTMENT_STORE_ROOF": "百货楼顶",
    "DEPARTMENT_STORE_ELEVATOR": "百货电梯",
    "GAME_CORNER": "游戏城", "GAME_CORNER_PRIZE_ROOM": "游戏城兑奖处",
    "CONDOMINIUMS_1F": "公寓 1F", "CONDOMINIUMS_2F": "公寓 2F",
    "CONDOMINIUMS_3F": "公寓 3F", "CONDOMINIUMS_ROOF": "公寓楼顶",
    "CONDOMINIUMS_ROOF_ROOM": "公寓屋顶小屋",
    "HOTEL": "旅馆", "RESTAURANT": "餐厅",
    "POKEMON_FAN_CLUB": "宝可梦爱好者俱乐部",
    "VOLUNTEER_POKEMON_HOUSE": "义工之家",
    "SAFARI_ZONE_ENTRANCE": "狩猎区入口", "SAFARI_ZONE_OFFICE": "狩猎区办公室",
    "WARDENS_HOUSE": "园长之家",
    "POKEMON_LAB_ENTRANCE": "宝可梦研究所",
    "POKEMON_MANSION_1F": "宝可梦屋 1F", "POKEMON_MANSION_2F": "宝可梦屋 2F",
    "POKEMON_MANSION_3F": "宝可梦屋 3F", "POKEMON_MANSION_B1F": "宝可梦屋 B1F",
    "DIGLETTS_CAVE_B1F": "地鼠洞", "DIGLETTS_CAVE_NORTH_ENTRANCE": "地鼠洞 北口",
    "DIGLETTS_CAVE_SOUTH_ENTRANCE": "地鼠洞 南口",
    "UNDERGROUND_PATH_EAST_ENTRANCE": "地下通道 东口",
    "UNDERGROUND_PATH_WEST_ENTRANCE": "地下通道 西口",
    "UNDERGROUND_PATH_NORTH_ENTRANCE": "地下通道 北口",
    "UNDERGROUND_PATH_SOUTH_ENTRANCE": "地下通道 南口",
    "UNDERGROUND_PATH_EAST_WEST_TUNNEL": "地下通道 东西段",
    "UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL": "地下通道 南北段",
    "SEAFOAM_ISLANDS_1F": "双子岛 1F", "SEAFOAM_ISLANDS_B1F": "双子岛 B1F",
    "SEAFOAM_ISLANDS_B2F": "双子岛 B2F", "SEAFOAM_ISLANDS_B3F": "双子岛 B3F",
    "SEAFOAM_ISLANDS_B4F": "双子岛 B4F",
    "FISHING_HOUSE": "钓鱼屋", "SEA_COTTAGE": "海边小屋",
    "POKEMON_DAY_CARE": "饲养屋", "SAFARI_ZONE_REST_HOUSE": "狩猎区休息屋",
    "SAFARI_ZONE_SECRET_HOUSE": "狩猎区秘密屋",
    "EAST_ENTRANCE_1F": "东口 1F", "EAST_ENTRANCE_2F": "东口 2F",
    "WEST_ENTRANCE_1F": "西口 1F", "WEST_ENTRANCE_2F": "西口 2F",
    "NORTH_ENTRANCE_1F": "北口 1F", "NORTH_ENTRANCE_2F": "北口 2F",
    "SOUTH_ENTRANCE_1F": "南口 1F", "SOUTH_ENTRANCE_2F": "南口 2F",
}

GFX = [
    ("OLD_MAN", "old_man"), ("OLD_WOMAN", "old_woman"), ("LITTLE_GIRL", "lass"),
    ("LITTLE_BOY", "youngster"), ("WOMAN", "lass"), ("MAN", "man"),
    ("SAILOR", "sailor"), ("SCIENTIST", "scientist"), ("CLERK", "clerk"),
    ("SUPER_NERD", "scientist"), ("PSYCHIC", "expert_m"), ("BLACKBELT", "hiker"),
    ("HIKER", "hiker"), ("CAMPER", "camper"), ("BUG_CATCHER", "bug_catcher"),
    ("FISHER", "sailor"), ("COOLTRAINER", "cooltrainer_m"), ("TEACHER", "lass"),
    ("NURSE", "nurse"), ("MOM", "mom"), ("OAK", "oak"),
]


def gfx_of(raw):
    g = str(raw).upper()
    for key, name in GFX:
        if key in g:
            return name
    return "man"


LINES_A = [
    "这条街我住了几十年。", "最近路上不太平。", "你知道道馆在哪边吗。", "我刚从医院回来。",
    "风一吹就想起小时候。", "屋里比外面暖和。", "这楼里的电梯总在修。", "别看我这样，年轻时也旅行过。",
    "我的宝可梦在睡午觉。", "东西涨价涨得厉害。", "今天天气不错。", "小心别踩到我的花。",
    "你看起来像个训练家。", "我在这儿等人。", "这附近有只野猫。", "听说是有人把门锁了。",
    "柜台后面那位脾气不好。", "我把钥匙忘在楼上了。", "别弄乱我的书架。", "客人不多，坐吧。",
]
LINES_B = [
    "有事就问我。", "慢走。", "别客气。", "再坐一会儿吧。", "下次再来。",
    "记得带伞。", "我什么都没说。", "你自己看吧。", "这个我不太清楚。",
    "问别人吧。", "我记性不太好。", "这年头谁都不容易。", "能帮就帮一把。",
    "路还长。", "天亮前要回去。", "你也早点休息。", "别乱翻抽屉。",
    "我这儿没什么好东西。", "想要就说一声。", "先歇歇脚。",
]
_npc_i = 0


def line_pair():
    """三句组合：20*20*20，全库不会撞"""
    global _npc_i
    i = _npc_i
    _npc_i += 1
    return [LINES_A[i % len(LINES_A)],
            LINES_B[(i // len(LINES_A)) % len(LINES_B)],
            LINES_A[(i // (len(LINES_A) * len(LINES_B))) % len(LINES_A)]]


def tileset_ok(lay):
    ts = str(lay.get("secondary_tileset", "")).replace("gTileset_", "").lower()
    norm = ts.replace("_", "").replace("frlg", "")
    base = os.path.join(ROOT, "data/tilesets/secondary")
    for d in os.listdir(base):
        if d.replace("_", "").replace("frlg", "") == norm:
            return os.path.exists(os.path.join(base, d, "tiles.png"))
    return False


def _norm(s):
    import re
    return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("frlg", ""))


def fix_gid(g):
    import re
    return re.sub(r"(\d)_f$", r"\1f", g)


def snake(s):
    out = []
    for ch in s:
        if ch.isupper() and out and out[-1] != "_":
            out.append("_")
        out.append(ch.lower())
    return "".join(out).replace("__", "_").strip("_")


def cn_name(dirname, mid):
    body = mid.replace("MAP_", "")
    city = {
        "PALLET_TOWN": "真新镇", "VIRIDIAN_CITY": "常磐市", "PEWTER_CITY": "尼比市",
        "CERULEAN_CITY": "华蓝市", "VERMILION_CITY": "枯叶市", "LAVENDER_TOWN": "紫苑镇",
        "CELADON_CITY": "玉虹市", "SAFFRON_CITY": "金黄市", "FUCHSIA_CITY": "浅红市",
        "CINNABAR_ISLAND": "红莲岛", "INDIGO_PLATEAU": "石英高原", "POKEMON_LEAGUE": "宝可梦联盟",
        "ROCK_TUNNEL": "岩山隧道", "MT_MOON": "月见山", "CERULEAN_CAVE": "华蓝洞窟",
        "SEAFOAM_ISLANDS": "双子岛", "VICTORY_ROAD": "冠军之路", "POKEMON_TOWER": "宝可梦塔",
        "POWER_PLANT": "无人发电所", "DIGLETTS_CAVE": "地鼠洞", "UNDERGROUND_PATH": "地下通道",
        "POKEMON_MANSION": "宝可梦屋", "SILPH_CO": "西尔佛公司", "SSANNE": "圣安奴号",
        "ROCKET_HIDEOUT": "火箭队秘密基地", "SAFARI_ZONE": "狩猎区",
    }
    prefix = ""
    rest = body
    for k in sorted(city, key=len, reverse=True):
        if body.startswith(k):
            prefix = city[k]
            rest = body[len(k):].lstrip("_")
            break
    if not prefix and body.startswith("ROUTE"):
        num = ""
        for ch in body[5:]:
            if ch.isdigit():
                num += ch
            else:
                break
        prefix = num + " 号道路"
        rest = body[5 + len(num):].lstrip("_")
    if not prefix:
        prefix = "关都"
    if rest == "":
        return prefix
    # 去掉重复的地名前缀，避免「宝可梦塔 POKEMON_TOWER_1F」
    name = CN.get(rest)
    if name is None:
        name = rest.replace("_", " ").lower()
    return prefix + "·" + name


def main():
    dry = "--dry" in sys.argv
    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    sys.path.insert(0, os.path.join(PJ, "tools"))
    from render_emerald_maps import render_layout

    bigp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bigp))
    offs = json.load(open(os.path.join(EMAPS, BIG + ".json")))["member_maps"]
    hosts = {k.upper(): k for k in offs}

    # 已有的房间按 id 去重（同一个 layout 可以有多间：每座城市的宝可梦中心都是同一张图）
    done_ids = set()
    for f in os.listdir(REG):
        if f.endswith(".json") and f != BIG + ".json":
            done_ids.add(f[:-5])
    done_norm = {_norm(k) for k in done_ids}

    allmaps = {}
    md = os.path.join(ROOT, "data/maps")
    for d in os.listdir(md):
        p = os.path.join(md, d, "map.json")
        if not os.path.exists(p):
            continue
        try:
            m = json.load(open(p))
        except Exception:
            continue
        allmaps[m.get("id", "")] = (d, m)

    # 候选：关都范围内的 FRLG 地图，且不是大图成员（室外）
    cand = {}
    for mid, (d, m) in allmaps.items():
        if not d.endswith("_Frlg"):
            continue
        base = d[:-5]
        if any(base.startswith(x) for x in SKIP_DIRS):
            continue
        if not any(base.startswith(x) for x in INCLUDE):
            continue
        key = mid.replace("MAP_", "")
        if key in hosts:
            continue  # 室外大图成员
        cand[mid] = (d, m)

    byid = {}
    for mid, (d, m) in cand.items():
        em = str(m.get("layout", "")).replace("LAYOUT_", "").lower()
        byid[mid] = (d, m, em)

    made, skipped_art, noexit = [], [], []
    for mid, (d, m, em) in sorted(byid.items()):
        _g = fix_gid(snake(d[:-5]))
        if _g in ALIAS and os.path.exists(os.path.join(REG, ALIAS[_g] + ".json")):
            continue
        if _g in done_ids or _norm(_g) in done_norm:
            continue
        lay = layouts.get(m.get("layout"))
        if not lay:
            continue
        if not tileset_ok(lay):
            skipped_art.append(d)
            continue
        gid = fix_gid(snake(d[:-5]))
        mp = os.path.join(EMAPS, em + ".json")
        if not os.path.exists(mp):
            if dry and not os.path.exists(mp):
                made.append(gid + "(待渲染)")
                continue
            if not os.path.exists(mp):
                render_layout(lay, EMAPS)
        if not os.path.exists(mp):
            continue
        meta = json.load(open(mp))

        warps = []
        entry = None
        missed = 0
        for we in m.get("warp_events", []):
            dest = we.get("dest_map", "")
            try:
                did = int(we.get("dest_warp_id", 0) or 0)
            except (TypeError, ValueError):
                continue
            cell = [int(we["x"]), int(we["y"])]
            dkey = dest.replace("MAP_", "")
            if dest in byid:
                dd, dm, _ = byid[dest]
                tgid = fix_gid(snake(dd[:-5]))
                twe = dm.get("warp_events", [])
                if did >= len(twe):
                    missed += 1
                    continue
                warps.append({"at": cell, "to": {"region": "kanto", "map": tgid,
                                                 "at": [int(twe[did]["x"]), int(twe[did]["y"])]}})
            elif dkey in hosts:
                host = hosts[dkey]
                hp = None
                for dn in os.listdir(md):
                    fp = os.path.join(md, dn, "map.json")
                    if not os.path.exists(fp):
                        continue
                    try:
                        if json.load(open(fp)).get("id", "") == dest:
                            hp = fp
                            break
                    except Exception:
                        pass
                if not hp:
                    missed += 1
                    continue
                hw = json.load(open(hp)).get("warp_events", [])
                if did >= len(hw):
                    missed += 1
                    continue
                at = [offs[host][0] + int(hw[did]["x"]), offs[host][1] + int(hw[did]["y"])]
                warps.append({"at": cell, "to": {"region": "kanto", "map": BIG, "at": at}})
                if entry is None:
                    entry = cell
                if not dry and not any(w["at"] == at for w in big["warps"]):
                    big["warps"].append({"at": at, "to": {"region": "kanto", "map": gid, "at": cell}})
            else:
                missed += 1
        if not warps:
            noexit.append(d)
            continue

        npcs = []
        for oe in m.get("object_events", []):
            g = str(oe.get("graphics_id", ""))
            if any(x in g for x in ("ITEM", "BALL", "SIGNPOST", "BOULDER", "FOSSIL", "CUT", "DOLL")):
                continue
            npcs.append({"at": [int(oe["x"]), int(oe["y"])], "name": "居民",
                         "gfx": gfx_of(g), "lines": line_pair()})
        out = {"name": "关都·" + cn_name(d, mid), "emerald": em, "size": meta["size"],
               "spawn": entry or warps[0]["at"], "npcs": npcs, "warps": warps,
               "encounters": [], "encounter_rate": 0.0}
        if not dry:
            json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
        made.append("%s(npc%d warp%d 缺%d)" % (gid, len(npcs), len(warps), missed))

    if not dry:
        json.dump(big, open(bigp, "w"), ensure_ascii=False, indent=1)
    print("生成 %d 间" % len(made))
    for x in made:
        print("  ", x)
    if skipped_art:
        print("贴图缺失跳过 %d 间: %s" % (len(skipped_art), ", ".join(skipped_art)))
    if noexit:
        print("无出口跳过 %d 间: %s" % (len(noexit), ", ".join(noexit)))
    print("大图门", len(big["warps"]))


if __name__ == "__main__":
    main()
