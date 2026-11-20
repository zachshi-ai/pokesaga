#!/usr/bin/env python3
"""七之岛：把 FRLG 的 1~7 号岛及其周边（焰之山道、冰落洞窟、田能寺遗迹、点穴、
变化洞窟、树果园、训练家塔、火箭队仓库……）做成独立地区 sevii。

七岛不像关都那样能拼成一张大地图，各岛之间隔着海，所以每张图各算一张，
岛和岛之间靠港口坐船（这里简化成一圈轮渡：1→2→…→7→1）。
用法: python3 tools/gen_sevii.py [--dry]
"""
from asset_paths import project_path, source_path

import json
import os
import re
import sys

ROOT = source_path("emerald")
PJ = project_path()
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/sevii/maps")
FRLG_WILD = source_path("firered", "src/data/wild_encounters.json")

INCLUDE = [
    "OneIsland", "TwoIsland", "ThreeIsland", "FourIsland", "FiveIsland",
    "SixIsland", "SevenIsland", "MtEmber", "NavelRock", "BirthIsland",
    "IcefallCave", "SevaultCanyon", "TanobyRuins", "DottedHole", "AlteringCave",
    "BerryForest", "BondBridge", "CapeBrink", "KindleRoad", "TreasureBeach",
    "MemorialPillar", "ResortGorgeous", "WaterLabyrinth", "RocketWarehouse",
    "TrainerTower", "PatternBush", "RuinValley", "WaterPath", "GreenPath",
    "OutcastIsland", "LostCave", "EmberSpa", "ThreeIslandPort",
]
SKIP = ("Route11_EastEntrance", "InsideOfTruck")

ISLAND = {
    "ONE_ISLAND": "一号岛", "TWO_ISLAND": "二号岛", "THREE_ISLAND": "三号岛",
    "FOUR_ISLAND": "四号岛", "FIVE_ISLAND": "五号岛", "SIX_ISLAND": "六号岛",
    "SEVEN_ISLAND": "七号岛",
}
CN = {
    "HARBOR": "港口", "POKEMON_CENTER_1F": "宝可梦中心", "POKEMON_CENTER_2F": "宝可梦中心 2F",
    "MART": "商店", "HOUSE1": "民居 1", "HOUSE2": "民居 2", "HOUSE3": "民居 3",
    "HOUSE4": "民居 4", "HOUSE5": "民居 5", "HOUSE": "民居", "HOUSE_ROOM1": "民居 1",
    "HOUSE_ROOM2": "民居 2", "MOVE_DELETERS_HOUSE": "忘招式屋",
    "MOVE_RELEARNERS_HOUSE": "学招式屋", "GAME_CORNER": "游戏城",
    "POKEMON_DAY_CARE": "饲养屋", "LORELEIS_HOUSE": "科拿的家",
    "MEADOW": "花田", "MEMORIAL_PILLAR": "纪念柱", "RESORT_GORGEOUS": "豪华度假村",
    "ROCKET_WAREHOUSE": "火箭队仓库", "WATER_LABYRINTH": "水之迷宫",
    "ICEFALL_CAVE_1F": "冰落洞窟 1F", "ICEFALL_CAVE_B1F": "冰落洞窟 B1F",
    "ICEFALL_CAVE_BACK": "冰落洞窟 深处", "ICEFALL_CAVE_ENTRANCE": "冰落洞窟 入口",
    "LOST_CAVE_ENTRANCE": "失落洞窟 入口", "LOST_CAVE": "失落洞窟",
    "ALTERING_CAVE": "变化洞窟", "DOTTED_HOLE_1F": "点穴 1F", "DOTTED_HOLE_B1F": "点穴 B1F",
    "DOTTED_HOLE_B2F": "点穴 B2F", "DOTTED_HOLE_B3F": "点穴 B3F", "DOTTED_HOLE_B4F": "点穴 B4F",
    "DOTTED_HOLE_SAPPHIRE_ROOM": "点穴 蓝宝石之间",
    "SEVAULT_CANYON": "七宝峡谷", "SEVAULT_CANYON_ENTRANCE": "七宝峡谷 入口",
    "SEVAULT_CANYON_HOUSE": "七宝峡谷 民居", "SEVAULT_CANYON_TANOBY_KEY": "七宝峡谷 石室",
    "TANOBY_RUINS": "田能寺遗迹", "BERRY_FOREST": "树果园", "BOND_BRIDGE": "绊桥",
    "CAPE_BRINK": "海角", "KINDLE_ROAD": "火种之路", "TREASURE_BEACH": "宝之海滩",
    "EMBER_SPA": "火焰温泉", "PATTERN_BUSH": "花纹草丛", "RUIN_VALLEY": "遗迹之谷",
    "WATER_PATH": "水路", "GREEN_PATH": "绿道", "OUTCAST_ISLAND": "孤岛",
    "TRAINER_TOWER": "训练家塔", "TRAINER_TOWER_LOBBY": "训练家塔 大厅",
    "MT_EMBER_EXTERIOR": "焰之山 山麓", "MT_EMBER_SUMMIT": "焰之山 山顶",
    "MT_EMBER_RUBY_PATH_1F": "焰之山 红宝石之路 1F",
    "MT_EMBER_SUMMIT_PATH_1F": "焰之山 山顶道 1F",
    "NAVEL_ROCK_EXTERIOR": "肚脐岩 外缘", "NAVEL_ROCK_ENTRANCE": "肚脐岩 入口",
    "NAVEL_ROCK_SUMMIT": "肚脐岩 山顶", "NAVEL_ROCK_BASE": "肚脐岩 底层",
    "BIRTH_ISLAND_EXTERIOR": "诞生之岛", "BIRTH_ISLAND_HARBOR": "诞生之岛 港口",
    "PORT": "码头", "THREE_ISLAND_PORT": "三号岛 码头",
}


def norm(s):
    s = str(s).lower().replace("frlg", "")
    return re.sub(r"[^a-z0-9]", "", s)


def snake(s):
    out = []
    for ch in s:
        if ch.isupper() and out and out[-1] != "_":
            out.append("_")
        out.append(ch.lower())
    return re.sub(r"__+", "_", "".join(out)).strip("_")


def fix_gid(g):
    return re.sub(r"(\d)_f$", r"\1f", g)


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
    for k, v in GFX:
        if k in g:
            return v
    return "man"


LINES_A = [
    "这座岛上的风是咸的。", "船一天只来两趟。", "你从关都来的吧。", "岛上没什么人，安静。",
    "往北走有条小路。", "听说洞里藏着东西。", "这里的果子比别处甜。", "我在这住了大半辈子。",
    "夏天的游客最多。", "别在礁石上乱跑。", "遗迹那边不让人进。", "海面今天很平。",
    "码头那位脾气怪。", "我养了三只宝可梦。", "岛上没有大医院。", "火种这条路不太好走。",
    "我们这儿靠打鱼过活。", "你要去山上是吧。", "太阳落山就起雾。", "有事问船夫。",
]
LINES_B = [
    "路上小心。", "慢点走吧。", "欢迎来岛上。", "有空再来。", "别急着赶路。",
    "天黑前回码头。", "我这儿没什么好招待的。", "带够水了吗。", "鞋子要防滑。",
    "海风会把人吹傻。", "这岛不大，走走就到。", "别乱捡地上的东西。", "有事就喊。",
    "记得看看日出。", "我一个人住惯了。", "这季节雨多。", "果子熟了随便摘。",
    "路标不太准。", "往那边走能到海边。", "我不太清楚。",
]
_npc_i = 0


def line_pair():
    """三句组合：20*20*20=8000 种，够全库不重复"""
    global _npc_i
    i = _npc_i
    _npc_i += 1
    a = LINES_A[i % len(LINES_A)]
    b = LINES_B[(i // len(LINES_A)) % len(LINES_B)]
    c = LINES_A[(i // (len(LINES_A) * len(LINES_B))) % len(LINES_A)]
    return [a, b, c]


def tileset_ok(lay):
    ts = str(lay.get("secondary_tileset", "")).replace("gTileset_", "").lower()
    n = ts.replace("_", "").replace("frlg", "")
    base = os.path.join(ROOT, "data/tilesets/secondary")
    for d in os.listdir(base):
        if d.replace("_", "").replace("frlg", "") == n:
            return os.path.exists(os.path.join(base, d, "tiles.png"))
    return True


def cn_name(mid):
    body = mid.replace("MAP_", "")
    prefix = ""
    for k, v in sorted(ISLAND.items(), key=lambda x: -len(x[0])):
        if body.startswith(k):
            prefix = v
            body = body[len(k):].lstrip("_")
            break
    if not prefix:
        prefix = "七之岛"
    if body == "":
        return prefix
    name = CN.get(body)
    if name is None:
        for k, v in sorted(CN.items(), key=lambda x: -len(x[0])):
            if body.startswith(k):
                name = v + body[len(k):].replace("_", " ")
                break
    if name is None:
        name = body.replace("_", " ").lower()
    return prefix + "·" + name


def far_spot(col, occ, spawn):
    """从落点出发 BFS，找离得最远的可走格当另一扇门，避免堵在门口"""
    from collections import deque
    H, W = len(col), len(col[0])
    sx, sy = int(spawn[0]), int(spawn[1])
    dist = {(sx, sy): 0}
    q = deque([(sx, sy)])
    while q:
        cx, cy = q.popleft()
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            n = (cx + dx, cy + dy)
            if n in dist or not (0 <= n[1] < H and 0 <= n[0] < W):
                continue
            if int(col[n[1]][n[0]]) != 0:
                continue
            dist[n] = dist[(cx, cy)] + 1
            q.append(n)
    cand = [c for c in dist if c not in occ and dist[c] > 1]
    if not cand:
        return None
    return max(cand, key=lambda c: dist[c])


def main():
    dry = "--dry" in sys.argv
    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    sys.path.insert(0, os.path.join(PJ, "tools"))
    from render_emerald_maps import render_layout

    os.makedirs(REG, exist_ok=True)

    # 原版野生表
    wild = {}
    if os.path.exists(FRLG_WILD):
        for e in json.load(open(FRLG_WILD))["wild_encounter_groups"][0]["encounters"]:
            old = wild.get(e["map"])
            if old is None or (not old.get("land_mons", {}).get("encounter_rate")
                               and e.get("land_mons", {}).get("encounter_rate")):
                wild[e["map"]] = e
    species = {s["key"]: s["id"] for s in json.load(open(os.path.join(PJ, "content/species.json")))}

    md = os.path.join(ROOT, "data/maps")
    allmaps = {}
    for d in os.listdir(md):
        p = os.path.join(md, d, "map.json")
        if not os.path.exists(p):
            continue
        try:
            m = json.load(open(p))
        except Exception:
            continue
        allmaps[m.get("id", "")] = (d, m)

    cand = {}
    for mid, (d, m) in allmaps.items():
        if not d.endswith("_Frlg"):
            continue
        base = d[:-5]
        if any(base.startswith(x) for x in SKIP):
            continue
        if not any(base.startswith(x) for x in INCLUDE):
            continue
        cand[mid] = (d, m, fix_gid(snake(base)))

    print("七岛候选 %d 张" % len(cand))
    made, noart, noexit = [], [], []
    for mid, (d, m, gid) in sorted(cand.items()):
        lay = layouts.get(m.get("layout"))
        if not lay:
            continue
        if not tileset_ok(lay):
            noart.append(d)
            continue
        em = str(m.get("layout", "")).replace("LAYOUT_", "").lower()
        mp = os.path.join(EMAPS, em + ".json")
        if not os.path.exists(mp):
            if dry:
                made.append(gid + "(待渲染)")
                continue
            render_layout(lay, EMAPS)
        if not os.path.exists(mp):
            continue
        meta = json.load(open(mp))

        warps, entry = [], None
        for we in m.get("warp_events", []):
            dest = we.get("dest_map", "")
            try:
                did = int(we.get("dest_warp_id", 0) or 0)
            except (TypeError, ValueError):
                continue
            cell = [int(we["x"]), int(we["y"])]
            if dest not in cand:
                continue
            dd, dm, tgid = cand[dest]
            twe = dm.get("warp_events", [])
            if did >= len(twe):
                continue
            warps.append({"at": cell, "to": {"region": "sevii", "map": tgid,
                                             "at": [int(twe[did]["x"]), int(twe[did]["y"])]}})
        if not warps:
            # 没有 warp 不代表没出口：有些图靠「地图连接」和隔壁连成一片，
            # 这里照样生成，连接由 gen_connections.py 补
            noexit.append(d)
        # 出生点：优先用「从别处传进来时踩到的那扇门」（按 dest_warp_id 反查本图的门），
        # 拿别人的坐标当自己的会越界，这里必须用本图自己的门格
        spawn = warps[0]["at"] if warps else [int(m["x"]) if "x" in m else 1, 1]
        mine = m.get("warp_events", [])
        for k, (dd, dm, g) in cand.items():
            if k == mid:
                continue
            for we2 in dm.get("warp_events", []):
                if we2.get("dest_map") != mid:
                    continue
                idx = int(we2.get("dest_warp_id", 0) or 0)
                if idx < len(mine):
                    spawn = [int(mine[idx]["x"]), int(mine[idx]["y"])]
                    break
            else:
                continue
            break

        npcs = []
        for oe in m.get("object_events", []):
            g = str(oe.get("graphics_id", ""))
            if any(x in g for x in ("ITEM", "BALL", "SIGNPOST", "BOULDER", "FOSSIL", "CUT", "DOLL")):
                continue
            npcs.append({"at": [int(oe["x"]), int(oe["y"])], "name": "岛民",
                         "gfx": gfx_of(g), "lines": line_pair()})

        enc, rate = [], 0.0
        w = wild.get(mid)
        if w:
            land = w.get("land_mons") or {}
            weights = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
            for i, mo in enumerate((land.get("mons") or [])[:12]):
                sid = species.get(mo["species"].replace("SPECIES_", ""))
                if not sid:
                    continue
                enc.append({"species": sid, "min": int(mo["min_level"]),
                            "max": int(mo["max_level"]), "weight": weights[i]})
            rate = float(land.get("encounter_rate", 0)) / 100.0
        out = {"name": cn_name(mid), "emerald": em, "size": meta["size"], "spawn": spawn,
               "npcs": npcs, "warps": warps, "encounters": enc, "encounter_rate": rate}
        if not dry:
            json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
        made.append("%s(%d门 %d人 %d遇敌)" % (gid, len(warps), len(npcs), len(enc)))

    print("生成 %d 张" % len(made))

    # 港口轮渡：1→2→…→7→1，把七座岛的港口串成一圈
    harbors = []
    for i in range(1, 8):
        name = snake((["One", "Two", "Three", "Four", "Five", "Six", "Seven"][i - 1] + "Island_Harbor").strip())
        gid = fix_gid(name)
        if os.path.exists(os.path.join(REG, gid + ".json")):
            harbors.append(gid)
    for extra in ("navel_rock_harbor", "birth_island_harbor"):
        if os.path.exists(os.path.join(REG, extra + ".json")):
            harbors.append(extra)
    ferry = 0
    if not dry and len(harbors) >= 2:
        for i, gid in enumerate(harbors):
            nxt = harbors[(i + 1) % len(harbors)]
            p = os.path.join(REG, gid + ".json")
            d = json.load(open(p))
            em = os.path.join(EMAPS, d["emerald"] + ".json")
            meta = json.load(open(em))
            col = meta.get("collision")
            occupied = {(int(w["at"][0]), int(w["at"][1])) for w in d["warps"]}
            occupied |= {(int(n["at"][0]), int(n["at"][1])) for n in d.get("npcs", [])}
            nd = json.load(open(os.path.join(REG, nxt + ".json"))) if os.path.exists(os.path.join(REG, nxt + ".json")) else None
            if not nd:
                continue
            tgt = nd["spawn"]
            spot = None
            sx, sy = d["spawn"]
            for r in range(1, 6):
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        c = (sx + dx, sy + dy)
                        if c in occupied:
                            continue
                        x, y = c
                        if y < 0 or y >= len(col) or x < 0 or x >= len(col[0]):
                            continue
                        if int(col[y][x]) != 0:
                            continue
                        spot = c
                        break
                    if spot:
                        break
                if spot:
                    break
            if not spot:
                continue
            d["warps"].append({"at": [spot[0], spot[1]],
                               "to": {"region": "sevii", "map": nxt, "at": tgt}})
            json.dump(d, open(p, "w"), ensure_ascii=False, indent=1)
            ferry += 1

    # 一号岛 ↔ 关都枯叶市港口（双向）
    if not dry and os.path.exists(os.path.join(REG, "one_island_harbor.json")):
        h = json.load(open(os.path.join(REG, "one_island_harbor.json")))
        if not any(w["to"].get("region") == "kanto" for w in h["warps"]):
            meta = json.load(open(os.path.join(EMAPS, h["emerald"] + ".json")))
            col = meta.get("collision")
            occ = {(int(w["at"][0]), int(w["at"][1])) for w in h["warps"]}
            occ |= {(int(n["at"][0]), int(n["at"][1])) for n in h.get("npcs", [])}
            spot = far_spot(col, occ, h["spawn"])
            if spot:
                h["warps"].append({"at": [spot[0], spot[1]],
                                   "to": {"region": "kanto", "map": "kanto_main", "at": [287, 234]}})
                json.dump(h, open(os.path.join(REG, "one_island_harbor.json"), "w"),
                          ensure_ascii=False, indent=1)
                bp = os.path.join(PJ, "content/regions/kanto/maps/kanto_main.json")
                b = json.load(open(bp))
                if not any(w["to"].get("map") == "one_island_harbor" for w in b["warps"]):
                    b["warps"].append({"at": [287, 235], "to": {"region": "sevii",
                                                                "map": "one_island_harbor",
                                                                "at": h["spawn"]}})
                    json.dump(b, open(bp, "w"), ensure_ascii=False, indent=1)

    # region.json
    ids = sorted(f[:-5] for f in os.listdir(REG) if f.endswith(".json"))
    if not dry and ids:
        start = "one_island_harbor" if "one_island_harbor" in ids else ids[0]
        rp = os.path.join(PJ, "content/regions/sevii/region.json")
        json.dump({"id": "sevii", "name": "七之岛", "tileset": "kanto_general",
                   "music": "route_kanto", "maps": ids, "start": start,
                   "encounters": [], "encounter_rate": 0.0},
                  open(rp, "w"), ensure_ascii=False, indent=1)
    print("港口轮渡 %d 条；地区内 %d 张图" % (ferry, len(ids)))
    if noart:
        print("贴图缺失跳过 %d 张: %s" % (len(noart), ", ".join(noart)))
    if noexit:
        print("无出口跳过 %d 张: %s" % (len(noexit), ", ".join(noexit)))


if __name__ == "__main__":
    main()
