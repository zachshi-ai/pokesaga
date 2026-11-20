#!/usr/bin/env python3
"""按原版规则重算一份「通行三套表」。

原版判断能不能走，是三个东西：
  1. map.bin 里的 collision 位（0 可走，非 0 完全挡）
  2. metatile behavior 里的方向性阻挡 MB_IMPASSABLE_*：只挡某一个方向，
     从别的方向过来是能走的（屋檐、墙脚、台阶边都是这种）
  3. MB_JUMP_*：土坡，站在它前面按方向能跳过去，落到两格之外

之前把 1、2 一起当"整格挡住"，把 3 也整格挡住，结果：
  * 只挡一个方向的瓦片变成四面墙 —— 通道被堵死，走不到别的图
  * 土坡跳不下去，只能绕路

输出到 emerald_maps/<map>.json：
  collision 0/1    完全不能进入
  dirblock  位掩码  1 北 / 2 南 / 4 东 / 8 西，从该方向进不来
  ledge     位掩码  该格可朝哪个方向跳下去
"""
from asset_paths import project_path, source_path

import json, os, glob, struct, sys

ROOT = source_path("emerald")
EMAPS = project_path("content/emerald_maps")
REG = project_path("content/regions")

sys.path.insert(0, project_path("tools"))
from render_emerald_maps import get_primary, get_secondary
from annotate_encounters import behaviors, behavior_of

BH = behaviors()

N, S, E, W = 1, 2, 4, 8
DIRBLOCK = {}
for name, mask in {
    "MB_IMPASSABLE_NORTH": N,
    "MB_IMPASSABLE_SOUTH": S,
    "MB_IMPASSABLE_EAST": E,
    "MB_IMPASSABLE_WEST": W,
    "MB_IMPASSABLE_NORTHEAST": N | E,
    "MB_IMPASSABLE_NORTHWEST": N | W,
    "MB_IMPASSABLE_SOUTHEAST": S | E,
    "MB_IMPASSABLE_SOUTHWEST": S | W,
    "MB_IMPASSABLE_SOUTH_AND_NORTH": N | S,
    "MB_IMPASSABLE_WEST_AND_EAST": W | E,
    "MB_SECRET_BASE_BREAKABLE_DOOR": W | E,
}.items():
    if name in BH:
        DIRBLOCK[BH[name]] = mask

JUMP = {}
for name, mask in {
    "MB_JUMP_NORTH": N,
    "MB_JUMP_SOUTH": S,
    "MB_JUMP_EAST": E,
    "MB_JUMP_WEST": W,
}.items():
    if name in BH:
        JUMP[BH[name]] = mask


def grids_of(lay):
    prim = get_primary(lay["primary_tileset"])
    sec = get_secondary(lay["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return None
    p = os.path.join(ROOT, lay["blockdata_filepath"])
    if not os.path.exists(p):
        return None
    block = open(p, "rb").read()
    w, h = int(lay["width"]), int(lay["height"])
    pc = prim.count
    col, db, lg = [], [], []
    for y in range(h):
        cr, dr, lr = [], [], []
        for x in range(w):
            val = struct.unpack_from("<H", block, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            cbits = (val >> 10) & 3
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            b = behavior_of(ts, local)
            cr.append(1 if cbits != 0 else 0)
            dr.append(DIRBLOCK.get(b, 0) | JUMP.get(b, 0))
            lr.append(JUMP.get(b, 0))
        col.append(cr)
        db.append(dr)
        lg.append(lr)
    return {"collision": col, "dirblock": db, "ledge": lg, "w": w, "h": h}


def compositions():
    lays = {l["id"]: l for l in json.load(
        open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]}
    out = {}
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        d = json.load(open(f))
        e = d.get("emerald")
        if e:
            out[os.path.normcase(e)] = d
    return lays, out


def region_warps(name, rid=None):
    """从地区地图配置里读传送点；门格必须能进，否则落点卡死、门也踩不到。

    地区地图里的文件名/emerald 字段不一定同名（pallet_town_players_house_1f_frlg
    对 pallettown_playershouse_1f），所以两种都匹配。
    """
    out = []
    for pat in (os.path.join(REG, "*", "maps", name + ".json"),
                os.path.join(REG, "*", "maps", "*.json")):
        for f in glob.glob(pat):
            d = json.load(open(f))
            if String_eq(os.path.normcase(str(d.get("emerald", ""))), os.path.normcase(name)) or \
               os.path.basename(f) == name + ".json":
                out.extend(d.get("warps", []))
    return out


def String_eq(a, b):
    return a != "" and a == b


def main():
    lays, used = compositions()
    for name in sorted(glob.glob(os.path.join(EMAPS, "*.json"))):
        base = os.path.basename(name)[:-5]
        meta = json.load(open(name))
        if meta.get("member_maps"):
            # 拼图：逐块贴回来
            W, H = meta["size"]
            # 拼图里没被任何成员覆盖的空白必须算墙，否则玩家能走进黑色边缘
            col = [[1] * W for _ in range(H)]
            db = [[0] * W for _ in range(H)]
            lg = [[0] * W for _ in range(H)]
            for key, off in meta["member_maps"].items():
                l = lays.get(key) or lays.get("LAYOUT_" + key)
                if not l:
                    for k, v in lays.items():
                        if k.replace("LAYOUT_", "") == key:
                            l = v
                            break
                if not l:
                    print("  缺少 layout", key)
                    continue
                sub = grids_of(l)
                if not sub:
                    continue
                for y in range(sub["h"]):
                    for x in range(sub["w"]):
                        gy, gx = int(off[1]) + y, int(off[0]) + x
                        if 0 <= gy < H and 0 <= gx < W:
                            col[gy][gx] = sub["collision"][y][x]
                            db[gy][gx] = sub["dirblock"][y][x]
                            lg[gy][gx] = sub["ledge"][y][x]
            # 门口必须能进，不然落点就卡住
            for w in (meta.get("warps") or region_warps(base)):
                x, y = int(w["at"][0]), int(w["at"][1])
                if 0 <= y < H and 0 <= x < W:
                    col[y][x] = 0
                    db[y][x] = 0
            meta["collision"] = col
            meta["dirblock"] = db
            meta["ledge"] = lg
            json.dump(meta, open(name, "w"), separators=(",", ":"))
            b = sum(sum(r) for r in col)
            l = sum(1 for r in lg for v in r if v)
            print("%-34s 拼图 %dx%d 全挡 %d 土坡 %d" % (base, W, H, b, l))
            continue

        lay0 = meta.get("layout")
        if isinstance(lay0, dict) and lay0.get("blockdata_filepath"):
            sub = grids_of(lay0)
            if sub:
                for w in (meta.get("warps") or region_warps(base)):
                    wx, wy = int(w["at"][0]), int(w["at"][1])
                    if 0 <= wy < sub["h"] and 0 <= wx < sub["w"]:
                        sub["collision"][wy][wx] = 0
                        sub["dirblock"][wy][wx] = 0
                meta["collision"] = sub["collision"]
                meta["dirblock"] = sub["dirblock"]
                meta["ledge"] = sub["ledge"]
                json.dump(meta, open(name, "w"), separators=(",", ":"))
                b = sum(sum(r) for r in sub["collision"])
                l = sum(1 for r in sub["ledge"] for v in r if v)
                print("%-34s %dx%d 全挡 %d 土坡 %d" % (base, sub["w"], sub["h"], b, l))
                continue
        rid = used.get(os.path.normcase(base))
        lay = None
        if rid is not None:
            lay = lays.get(rid.get("layout_id") or "")
            if lay is None:
                lid = rid.get("layout", "")
                for k, v in lays.items():
                    if v.get("name", "").lower().replace("_layout", "") == lid.lower():
                        lay = v
                        break
        if lay is None:
            lid = meta.get("layout_id", "")
            lay = lays.get(lid) if lid else None
        if lay is None:
            lid = (meta.get("layout") or {}).get("id", "")
            lay = lays.get(lid) if lid else None
        if lay is None:
            print("%-34s 跳过（找不到 layout）" % base)
            continue
        sub = grids_of(lay)
        if not sub:
            print("%-34s 跳过（读不到）" % base)
            continue
        # 门格必须能踩上去，否则人走到门前就停住，进不去
        for w in (meta.get("warps") or region_warps(base)):
            wx, wy = int(w["at"][0]), int(w["at"][1])
            if 0 <= wy < sub["h"] and 0 <= wx < sub["w"]:
                sub["collision"][wy][wx] = 0
                sub["dirblock"][wy][wx] = 0
        meta["collision"] = sub["collision"]
        meta["dirblock"] = sub["dirblock"]
        meta["ledge"] = sub["ledge"]
        json.dump(meta, open(name, "w"), separators=(",", ":"))
        b = sum(sum(r) for r in sub["collision"])
        l = sum(1 for r in sub["ledge"] for v in r if v)
        print("%-34s %dx%d 全挡 %d 土坡 %d" % (base, sub["w"], sub["h"], b, l))


if __name__ == "__main__":
    main()
