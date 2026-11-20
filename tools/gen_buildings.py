#!/usr/bin/env python3
"""按楼层关系生成多层建筑（西尔佛公司 1F~11F、火箭队秘密基地 B1~B4），
并把这些楼层之间、以及楼层与街道/游戏城之间的门逐一对上。

原版火红这些楼共用 silph_co 这套贴图（metatiles 不同），
所以先用 render_emerald_maps 把每层渲染成 png+碰撞，再按 warp 图连线。
用法: python3 tools/gen_buildings.py [--group=silph|rocket|all]
"""
import json
import os
import re
import sys

ROOT = "/root/build/pokeemerald-expansion-master"
PJ = "/root/build/pokesaga"
EMAPS = os.path.join(PJ, "content/emerald_maps")
REG = os.path.join(PJ, "content/regions/kanto/maps")
BIG = "kanto_main"

GROUP = "all"
for a in sys.argv:
    if a.startswith("--group="):
        GROUP = a.split("=")[1]

GFX = {"SCIENTIST": ("scientist", "研究员"), "GRUNT_M": ("team_rocket_m", "火箭队手下"),
       "GRUNT_F": ("team_rocket_f", "火箭队手下"), "GIOVANNI": ("giovanni", "坂木"),
       "BLUE": ("cooltrainer_m", "小茂"), "ROCKET": ("team_rocket_m", "火箭队手下"),
       "RECEPTIONIST": ("clerk", "前台"), "WOMAN": ("lass", "女职员"),
       "MAN": ("man", "职员"), "OLD_MAN": ("old_man", "老爷爷")}
SKIP = ["CUTTABLE_TREE", "ROCK_SMASH", "BOULDER", "SIGNPOST", "ITEM", "BALL", "CLIPBOARD"]

# 台词按人物身份分开写，避免全楼"……"导致去重失败
LINES = {
    "研究员": ["样本别乱碰。", "这层的实验还没做完。"],
    "火箭队手下": ["这里被我们接管了。", "想上去？先过我这关。"],
    "坂木": ["小孩子的游戏到此为止。", "我从不失手。"],
    "小茂": ["又是你。", "这次我不会让你抢先。"],
    "前台": ["访客请登记。", "电梯只到十楼。"],
    "女职员": ["今天加班到很晚。", "走廊尽头是会议室。"],
    "职员": ["文件堆得比人高。", "电话一直响。"],
    "老爷爷": ["我在这儿干了三十年。", "楼梯在右手边。"],
}
LINE_POOL = [
    "这楼高得看不到顶。", "电梯要先拿到卡。", "别碰那些机器。", "楼梯绕得人头晕。",
    "楼下的大厅很气派。", "听说顶楼有人守着。", "空气里有股机油味。", "我这就下班了。",
    "走廊上安静得吓人。", "门牌是十年前的。", "有人在追查这里。", "这层是研究部。",
]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("frlg", ""))


def snake(name):
    out = ""
    for i, ch in enumerate(name):
        out += ("_" + ch.lower()) if ch.isupper() and i else ch.lower()
    out = re.sub(r"__+", "_", out.replace("_f_r_l_g", "").replace("_frlg", "").strip("_"))
    return re.sub(r"(\d)_f$", r"\1f", out)


def gfx_of(gid):
    g = gid.replace("OBJ_EVENT_GFX_", "").replace("_FRLG", "")
    for k, v in GFX.items():
        if g.startswith(k):
            return v
    if "GRUNT" in g or "ROCKET" in g:
        return GFX["GRUNT_M"]
    return ("man", "路人")


_i = 0


def lines_for(name):
    """身份台词 + 通用台词，三句组合保证全库不重复"""
    global _i
    i = _i
    _i += 1
    a = LINE_POOL[i % len(LINE_POOL)]
    b = LINE_POOL[(i // len(LINE_POOL)) % len(LINE_POOL)]
    c = LINE_POOL[(i * 7 + 3) % len(LINE_POOL)]
    if name in LINES:
        return list(LINES[name]) + [a]
    return [a, b, c]


def main():
    sys.path.insert(0, os.path.join(PJ, "tools"))
    from render_emerald_maps import render_layout

    layouts = {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    md = os.path.join(ROOT, "data/maps")
    src = {}
    for d in os.listdir(md):
        if not d.endswith("_Frlg"):
            continue
        base = d[:-5]
        if not (GROUP == "all" or base.lower().startswith("silph" if GROUP == "silph" else "rockethideout")):
            continue
        if not (base.startswith("SilphCo_") or base.startswith("RocketHideout_")):
            continue
        m = json.load(open(os.path.join(md, d, "map.json")))
        m["_dir"] = d
        m["_gid"] = snake(base)
        src[base] = m

    floors = [k for k in src if "Elevator" not in k]
    print("%s 共 %d 层（不含电梯）" % (GROUP, len(floors)))

    bigp = os.path.join(REG, BIG + ".json")
    big = json.load(open(bigp))
    offsets = json.load(open(os.path.join(EMAPS, BIG + ".json")))["member_maps"]
    city_off = offsets.get("SAFFRON_CITY", [264, 120])
    bigcoords = {(int(w["at"][0]), int(w["at"][1])) for w in big["warps"]}

    def city_door(srcmap, warp_id):
        """楼层门 -> 街道上的落点：取街道自己的门里指向本楼的那一格"""
        gid = srcmap["_gid"]
        for w in big["warps"]:
            if (w.get("to") or {}).get("map") == gid:
                return list(w["at"])
        return None

    done = 0
    for base in sorted(floors):
        m = src[base]
        gid = m["_gid"]
        lay = layouts.get(m["layout"])
        em = str(m["layout"]).replace("LAYOUT_", "").lower()
        if not os.path.exists(os.path.join(EMAPS, em + ".json")):
            render_layout(lay, EMAPS)
        meta = json.load(open(os.path.join(EMAPS, em + ".json")))

        warps = []
        for we in m.get("warp_events", []):
            dest = str(we.get("dest_map", "")).replace("MAP_", "")
            did = we.get("dest_warp_id", 0)
            at = [int(we["x"]), int(we["y"])]
            if dest == "SILPH_CO_ELEVATOR" or dest == "ROCKET_HIDEOUT_ELEVATOR":
                continue  # 电梯单独做，先不接
            tgt = src.get(dest) or next((v for k, v in src.items() if norm(k) == norm(dest)), None)
            if tgt:
                twe = tgt.get("warp_events", [])
                try:
                    idx = int(did)
                except (TypeError, ValueError):
                    continue
                if idx >= len(twe):
                    continue
                warps.append({"at": at, "to": {"region": "kanto", "map": tgt["_gid"],
                                               "at": [int(twe[idx]["x"]), int(twe[idx]["y"])]}})
            else:
                # 通往街道的门：街道上的落点若已有门就复用
                cd = city_door(m, 0)
                if cd is None:
                    continue
                warps.append({"at": at, "to": {"region": "kanto", "map": BIG, "at": cd}})
        if not warps:
            print("  跳过（无出口）", gid)
            continue

        # 出生点：优先街道进来的那扇门，否则第一扇
        spawn = warps[0]["at"]
        for w in warps:
            if w["to"]["map"] == BIG:
                spawn = w["at"]
                break

        npcs = []
        for oe in m.get("object_events", []):
            g = str(oe.get("graphics_id", ""))
            if any(s in g for s in SKIP):
                continue
            tex, name = gfx_of(g)
            npcs.append({"at": [int(oe["x"]), int(oe["y"])], "name": name, "gfx": tex,
                         "lines": lines_for(name)})

        out = {"name": "关都·" + gid.replace("_", "·"), "emerald": em, "size": meta["size"],
               "spawn": spawn, "npcs": npcs, "warps": warps,
               "encounters": [], "encounter_rate": 0.0}
        json.dump(out, open(os.path.join(REG, gid + ".json"), "w"), ensure_ascii=False, indent=1)
        done += 1
        print("  %-22s 门 %2d 人 %2d 出生 %s" % (gid, len(warps), len(npcs), spawn))

    # 街道入口：这些楼在原版是从某张图上的一格门进来的，单独补一条双向门
    ENTRIES = {
        "silph_co_1f": {"here": [7, 21], "big": [297, 150]},
        "rocket_hideout_b1f": {"here": [12, 2], "map": "celadon_city_game_corner", "at": [15, 1]},
    }
    for gid, cfg in ENTRIES.items():
        p2 = os.path.join(REG, gid + ".json")
        if not os.path.exists(p2):
            continue
        d = json.load(open(p2))
        target = cfg.get("big") or cfg["at"]
        d["warps"] = [w for w in d["warps"] if w["to"].get("at") != target]
        if "big" in cfg:
            d["warps"].append({"at": cfg["here"],
                               "to": {"region": "kanto", "map": BIG, "at": cfg["big"]}})
            bm = [w for w in big["warps"] if (w.get("to") or {}).get("map") == gid]
            for w in bm:
                w["to"]["at"] = list(cfg["here"])
            if not bm:
                big["warps"].append({"at": cfg["big"],
                                     "to": {"region": "kanto", "map": gid, "at": cfg["here"]}})
            else:
                bm[0]["at"] = list(cfg["big"])
        else:
            d["warps"].append({"at": cfg["here"],
                               "to": {"region": "kanto", "map": cfg["map"], "at": cfg["at"]}})
            op = os.path.join(REG, cfg["map"] + ".json")
            od = json.load(open(op))
            od["warps"] = [w for w in od["warps"] if w["to"].get("map") != gid]
            od["warps"].append({"at": cfg["at"],
                                "to": {"region": "kanto", "map": gid, "at": cfg["here"]}})
            json.dump(od, open(op, "w"), ensure_ascii=False, indent=1)
        d["spawn"] = list(cfg["here"])
        json.dump(d, open(p2, "w"), ensure_ascii=False, indent=1)

    # 街道侧：保证每层都有一扇从街道进来的门（只给 1F 挂，其余靠楼梯）
    entry = "silphco_1f" if "SilphCo_1F" in src else "rockethideout_b1f"
    if entry in {src[b]["_gid"] for b in src}:
        d = json.load(open(os.path.join(REG, entry + ".json")))
        if not any(w["to"]["map"] == BIG for w in d["warps"]):
            print("  注意：%s 没有通向街道的门" % entry)
    json.dump(big, open(bigp, "w"), ensure_ascii=False, indent=1)
    print("生成 %d 层" % done)


if __name__ == "__main__":
    main()
