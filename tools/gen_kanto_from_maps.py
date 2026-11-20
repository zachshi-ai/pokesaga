#!/usr/bin/env python3
"""直接按原版 data/maps/<Map>/map.json 生成游戏地图。

原版每张地图都有 warp_events（门/楼梯的精确坐标 + 目标地图 + 目标 warp 序号）
和 object_events（NPC 坐标 + 图形），照抄这两份数据，门就精确落在原版那扇门上，
NPC 也站在原版位置，不用手标。

输出：
  content/emerald_maps/<layout>.png/.json   （渲染好的整图 + 碰撞）
  content/regions/kanto/maps/<id>.json       （warps / npcs / spawn）
"""
import json, os, glob, struct

ROOT = "/root/build/pokeemerald-expansion-master"
EMAPS = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions"

import sys
sys.path.insert(0, "/root/build/pokesaga/tools")
from render_emerald_maps import get_primary, get_secondary, PRIMARY, SECONDARY
from PIL import Image

# 要接进游戏的关都地图（原版 map 名）
KANTO = [
    "PalletTown_Frlg", "Route1_Frlg", "ViridianCity_Frlg", "Route2_Frlg",
    "ViridianForest_Frlg", "PewterCity_Frlg",
    "Route2_ViridianForest_SouthEntrance_Frlg", "Route2_ViridianForest_NorthEntrance_Frlg",
    "PalletTown_PlayersHouse_1F_Frlg", "PalletTown_RivalsHouse_Frlg",
    "PalletTown_ProfessorOaksLab_Frlg",
    "ViridianCity_PokemonCenter_1F_Frlg", "ViridianCity_Mart_Frlg",
    "ViridianCity_Gym_Frlg", "ViridianCity_School_Frlg", "ViridianCity_House_Frlg",
    "PewterCity_Gym_Frlg", "PewterCity_Museum_1F_Frlg", "PewterCity_House_Frlg",
    "PewterCity_PokemonCenter_1F_Frlg", "PewterCity_Mart_Frlg",
]

# 原版图形 -> 我这边的人物贴图与称呼
GFX = {
    "FAT_MAN": ("man", "胖大叔"), "OLD_MAN": ("old_man", "老爷爷"),
    "OLD_WOMAN": ("old_man", "老奶奶"), "WOMAN": ("lass", "大姐"),
    "GIRL": ("lass", "小女孩"), "BOY": ("youngster", "小男孩"),
    "LITTLE_GIRL": ("lass", "小女孩"), "LITTLE_BOY": ("youngster", "小男孩"),
    "MAN": ("man", "大叔"), "WOMAN_2": ("lass", "女士"),
    "NURSE": ("nurse", "护士"), "MART_EMPLOYEE": ("clerk", "店员"),
    "CLERK": ("clerk", "店员"), "SCIENTIST": ("scientist", "研究员"), "EXPERT_M": ("expert_m", "专家"),
    "COOLTRAINER_M": ("cooltrainer_m", "训练家"), "COOLTRAINER_F": ("teala", "训练家"),
    "BUG_CATCHER": ("bug_catcher", "捕虫少年"), "HIKER": ("hiker", "登山男"),
    "CAMPER": ("camper", "露营少年"), "LASS": ("lass", "少女"),
    "YOUNGSTER": ("youngster", "短裤小子"), "SAILOR": ("sailor", "水手"),
    "BROCK": ("brock", "馆主 小刚"),
    "MOM": ("mom", "妈妈"), "PROF_OAK": ("oak", "大木博士"),
    "BLUE": ("cooltrainer_m", "小茂"), "GIRL_2": ("lass", "女孩"),
    "WOMAN_3": ("lass", "女士"), "MAN_2": ("man", "大叔"),
}
# 这些不是人，跳过
SKIP_GFX = ["CUTTABLE_TREE", "ROCK_SMASH", "BOULDER", "SIGNPOST", "CUT_TREE",
            "BREAKABLE_ROCK", "FOSSIL", "ITEM", "BALL", "CLIPBOARD"]


def norm(x):
    # 原版 dest_map 是 MAP_VIRIDIAN_CITY，我这边地图名带 _Frlg 后缀，比较时统一去掉
    x = x.replace("_Frlg", "").replace("_FRLG", "").replace("Frlg", "")
    return "".join(ch for ch in x.lower() if ch.isalnum())


def load_layouts():
    return {l["id"]: l for l in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}


def render_layout_png(layout, name):
    png_path = os.path.join(EMAPS, name + ".png")
    meta_path = os.path.join(EMAPS, name + ".json")
    if os.path.exists(png_path) and os.path.exists(meta_path):
        return json.load(open(meta_path))
    w, h = int(layout["width"]), int(layout["height"])
    prim = get_primary(layout["primary_tileset"])
    sec = get_secondary(layout["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return None
    data = open(os.path.join(ROOT, layout["blockdata_filepath"]), "rb").read()
    if len(data) < w * h * 2:
        return None
    img = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 255))
    col = []
    prim_count = prim.count
    for y in range(h):
        row = []
        for x in range(w):
            val = struct.unpack_from("<H", data, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            row.append((val >> 10) & 0x3)
            ts = prim if mid < prim_count else sec
            local = mid if mid < prim_count else mid - prim_count
            try:
                img.paste(ts.render(local), (x * 16, y * 16))
            except Exception:
                pass
        col.append(row)
    img.save(png_path)
    meta = {"id": layout["id"], "size": [w, h], "png": name + ".png",
            "collision": col, "primary": layout["primary_tileset"],
            "secondary": layout["secondary_tileset"], "layout": layout}
    json.dump(meta, open(meta_path, "w"), separators=(",", ":"))
    return meta


CN = {
    "PalletTown_Frlg": "真新镇", "Route1_Frlg": "1 号道路", "ViridianCity_Frlg": "常磐市",
    "Route2_Frlg": "2 号道路", "ViridianForest_Frlg": "常磐森林", "PewterCity_Frlg": "尼比市",
    "PalletTown_PlayersHouse_1F_Frlg": "真新镇·自己的家",
    "PalletTown_RivalsHouse_Frlg": "真新镇·小茂的家",
    "PalletTown_ProfessorOaksLab_Frlg": "大木研究所",
    "ViridianCity_PokemonCenter_1F_Frlg": "常磐市·宝可梦中心",
    "ViridianCity_Mart_Frlg": "常磐市·友好商店",
    "ViridianCity_Gym_Frlg": "常磐道馆",
    "ViridianCity_School_Frlg": "常磐市·训练家学校",
    "ViridianCity_House_Frlg": "常磐市·民宅",
    "PewterCity_Gym_Frlg": "尼比道馆",
    "PewterCity_Museum_1F_Frlg": "尼比科学博物馆",
    "PewterCity_PokemonCenter_1F_Frlg": "尼比市·宝可梦中心",
    "PewterCity_Mart_Frlg": "尼比市·友好商店",
    "Route2_ViridianForest_SouthEntrance_Frlg": "常磐森林·南入口",
    "Route2_ViridianForest_NorthEntrance_Frlg": "常磐森林·北入口",
}


def map_id(map_name):
    return map_name.replace("_Frlg", "").replace("_FRLG", "").lower()


def gfx_name(gid):
    g = gid.replace("OBJ_EVENT_GFX_", "").replace("_FRLG", "")
    for k, v in GFX.items():
        if g == k:
            return v
    for k, v in GFX.items():
        if g.startswith(k):
            return v
    return ("man", "路人")


def main():
    layouts = load_layouts()
    info = {}
    for m in KANTO:
        p = os.path.join(ROOT, "data/maps", m, "map.json")
        if not os.path.exists(p):
            print("missing map", m)
            continue
        d = json.load(open(p))
        info[m] = d

    # 先把所有 layout 渲染出来
    metas = {}
    for m, d in info.items():
        lay = layouts.get(d["layout"])
        if not lay:
            print("missing layout", d["layout"])
            continue
        name = d["layout"].replace("LAYOUT_", "").lower()
        meta = render_layout_png(lay, name)
        if meta:
            metas[m] = (name, meta)
    print("rendered", len(metas))

    known = set(info.keys())
    for m, d in info.items():
        if m not in metas:
            continue
        name, meta = metas[m]
        w, h = meta["size"]
        # 出生点：优先用原版 object_events 里的玩家起始点，否则找可走格
        spawn = None
        for oe in d.get("object_events", []):
            if "PLAYER" in str(oe.get("graphics_id", "")) if False else False:
                pass
        col = meta["collision"]
        if not spawn:
            for yy in range(h - 3, 1, -1):
                for xx in range(w // 2, w):
                    if col[yy][xx] == 0:
                        spawn = [xx, yy]
                        break
                if spawn:
                    break
        warps = []
        for i, we in enumerate(d.get("warp_events", [])):
            dest = we.get("dest_map", "")
            dwid = int(we.get("dest_warp_id", 0) or 0)
            tgt = dest.replace("MAP_", "")
            # 目标地图名回到 CamelCase
            cand = [k for k in known if norm(k) == norm(tgt)]
            if not cand:
                continue
            tname = cand[0]
            tmeta = metas.get(tname)
            if not tmeta:
                continue
            twe = info[tname].get("warp_events", [])
            at = [0, 0]
            if 0 <= dwid < len(twe):
                at = [int(twe[dwid]["x"]), int(twe[dwid]["y"])]
            else:
                continue
            warps.append({"at": [int(we["x"]), int(we["y"])],
                          "to": {"region": "kanto", "map": map_id(tname), "at": at}})
        npcs = []
        for oe in d.get("object_events", []):
            gid = str(oe.get("graphics_id", ""))
            if any(s in gid for s in SKIP_GFX):
                continue
            tex, label = gfx_name(gid)
            npcs.append({"at": [int(oe["x"]), int(oe["y"])], "name": label,
                         "gfx": tex, "script": str(oe.get("script", ""))})
        # 连接（原版是滚动接壤）：在边界开出口，落点放到目标地图对应边
        for c in d.get("connections", []) or []:
            tgt_raw = c.get("map", "").replace("MAP_", "")
            cand = [k for k in known if norm(k) == norm(tgt_raw)]
            if not cand:
                continue
            tname = cand[0]
            tmeta = metas.get(tname)
            if not tmeta:
                continue
            tw, th = tmeta[1]["size"]
            tcol = tmeta[1]["collision"]
            direction = c.get("direction", "up")
            off = int(c.get("offset", 0) or 0)
            if direction == "up":
                src_y = 1
                dst_y = th - 2
                cx = w // 2 + off
            else:
                src_y = h - 2
                dst_y = 1
                cx = w // 2 + off
            def find_open(colr, cx0, y, width):
                best = None
                for dx in range(0, width):
                    for x in (cx0 + dx, cx0 - dx):
                        if 0 <= x < width and colr[y][x] == 0:
                            return x
                return best
            sx = find_open(col, cx, src_y, w)
            tx = find_open(tcol, cx, dst_y, tw)
            if sx is None or tx is None:
                continue
            warps.append({"at": [sx, src_y],
                          "to": {"region": "kanto", "map": map_id(tname), "at": [tx, dst_y]}})

        # 同一扇门的三格只留一个入口，避免重复触发
        seen_tgt = set()
        uniq = []
        for wp in warps:
            key = (wp["to"]["map"], tuple(wp["to"]["at"]))
            if key in seen_tgt:
                continue
            seen_tgt.add(key)
            uniq.append(wp)
        warps = uniq

        out = {"name": "关都·" + CN.get(m, m.replace("_Frlg", "").replace("_", " ")),
               "emerald": name, "size": [w, h], "spawn": spawn or [w // 2, h // 2],
               "npcs": npcs, "warps": warps}
        path = os.path.join(REG, "kanto", "maps", map_id(m) + ".json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        json.dump(out, open(path, "w"), ensure_ascii=False, indent=1)
        print("%-34s %2dx%-3d warps %d npcs %d" % (map_id(m), w, h, len(warps), len(npcs)))


if __name__ == "__main__":
    main()
