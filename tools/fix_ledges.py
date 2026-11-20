#!/usr/bin/env python3
"""把「土坡 / 冰面 / 水流 / 方向阻挡」四张网格补全并修干净。

毛病复盘：
  * 只有 23 张图有 ledge / dirblock，其余 287 张一片空白 —— 那些图里没有坡、
    没有方向阻挡，走位手感跟原版对不上。
  * dirblock 里混进了 JUMP 的位，等于把坡沿当成了单向墙，站在坡边被自己拦住。
  * 丰缘的坡是「前面一格是坡沿、再往前落两格」；关都的坡只有一格宽。
    落点距离交给游戏运行时判断，这里只写准「哪一格是坡沿、能往哪边跳」。
  * 原版还有冰面打滑（MB_SLIDE_*）、洋流（MB_*WARD_CURRENT）、斜向土坡
    （MB_JUMP_NORTHEAST 等），这些之前一格都没写。

位掩码统一用 1 上 / 2 下 / 4 右 / 8 左 / 16 右上 / 32 左上 / 64 右下 / 128 左下。
"""
from asset_paths import project_path, source_path

import json
import os
import struct
import sys

ROOT = source_path("emerald")
POKE = project_path()
EMAPS = os.path.join(POKE, "content/emerald_maps")

sys.path.insert(0, os.path.join(POKE, "tools"))
from annotate_encounters import behaviors, behavior_of  # noqa: E402
from render_emerald_maps import get_primary, get_secondary  # noqa: E402

BH = behaviors()
INV = {v: k for k, v in BH.items()}  # 编号 -> 名字
N, S, E, W = 1, 2, 4, 8
BITS = {
    "MB_JUMP_NORTH": N, "MB_JUMP_SOUTH": S, "MB_JUMP_EAST": E, "MB_JUMP_WEST": W,
    "MB_JUMP_NORTHEAST": 16, "MB_JUMP_NORTHWEST": 32,
    "MB_JUMP_SOUTHEAST": 64, "MB_JUMP_SOUTHWEST": 128,
    # 关都（火红叶绿）的坡沿编号跟绿宝石不同，单独映射
    "MB_FRLG_JUMP_EAST": E, "MB_FRLG_JUMP_WEST": W,
    "MB_FRLG_JUMP_NORTH": N, "MB_FRLG_JUMP_SOUTH": S,
}
SLIDE = {
    "MB_SLIDE_EAST": E, "MB_SLIDE_WEST": W, "MB_SLIDE_NORTH": N, "MB_SLIDE_SOUTH": S,
    "MB_FRLG_SLIDE_EAST": E, "MB_FRLG_SLIDE_WEST": W,
    "MB_FRLG_SLIDE_NORTH": N, "MB_FRLG_SLIDE_SOUTH": S,
}
ICE_NAMES = {"MB_ICE", "MB_THIN_ICE", "MB_CRACKED_ICE"}
HOLE_NAMES = {"MB_CRACKED_FLOOR_HOLE", "MB_MT_PYRE_HOLE", "MB_SECRET_BASE_HOLE"}
DEEP_NAMES = {"MB_DEEP_WATER", "MB_INTERIOR_DEEP_WATER", "MB_SOOTOPOLIS_DEEP_WATER"}
CLIMB_NAMES = {"MB_ROCK_CLIMB"}
WHIRL_NAMES = {"MB_WHIRLPOOL", "MB_FRLG_WHIRLPOOL"}
WATERFALL_NAMES = {"MB_WATERFALL"}
BUTTON_NAMES = {"MB_STRENGTH_BUTTON"}  # 关都/七岛没有冰面地形，冰格按普通地面处理
CURRENT = {
    "MB_EASTWARD_CURRENT": E, "MB_WESTWARD_CURRENT": W,
    "MB_NORTHWARD_CURRENT": N, "MB_SOUTHWARD_CURRENT": S,
    "MB_FRLG_EASTWARD_CURRENT": E, "MB_FRLG_WESTWARD_CURRENT": W,
    "MB_FRLG_NORTHWARD_CURRENT": N, "MB_FRLG_SOUTHWARD_CURRENT": S,
}
DIRBLOCK = {}
for name, mask in {
    "MB_IMPASSABLE_NORTH": N, "MB_IMPASSABLE_SOUTH": S,
    "MB_IMPASSABLE_EAST": E, "MB_IMPASSABLE_WEST": W,
    "MB_IMPASSABLE_NORTHEAST": N | E, "MB_IMPASSABLE_NORTHWEST": N | W,
    "MB_IMPASSABLE_SOUTHEAST": S | E, "MB_IMPASSABLE_SOUTHWEST": S | W,
    "MB_IMPASSABLE_SOUTH_AND_NORTH": N | S, "MB_IMPASSABLE_WEST_AND_EAST": W | E,
    "MB_FRLG_IMPASSABLE_NORTH": N, "MB_FRLG_IMPASSABLE_SOUTH": S,
    "MB_FRLG_IMPASSABLE_EAST": E, "MB_FRLG_IMPASSABLE_WEST": W,
    "MB_FRLG_IMPASSABLE_NORTHEAST": N | E, "MB_FRLG_IMPASSABLE_NORTHWEST": N | W,
    "MB_FRLG_IMPASSABLE_SOUTHEAST": S | E, "MB_FRLG_IMPASSABLE_SOUTHWEST": S | W,
}.items():
    if name in BH:
        DIRBLOCK[BH[name]] = mask

FRLG_RAW = None


def frlg_raw_table():
    """火红叶绿的 metatile 属性用的是另一套编号，直接按十六进制值建表。"""
    global FRLG_RAW
    if FRLG_RAW is not None:
        return FRLG_RAW
    table = {}
    path = os.path.join(ROOT, "include/constants/metatile_behaviors_frlg.h")
    for line in open(path, errors="ignore"):
        line = line.split("//")[0].strip()
        if not line.startswith("#define MB_FRLG_"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        name = parts[1]
        try:
            val = int(parts[2], 16)
        except ValueError:
            continue
        if name in BITS:
            table.setdefault(val, 0)
            table[val] |= BITS[name]
        elif name in SLIDE:
            table.setdefault(val, 0)
        elif name in DIRBLOCK:
            pass
    FRLG_RAW = table
    return table


def frlg_dir_table():
    path = os.path.join(ROOT, "include/constants/metatile_behaviors_frlg.h")
    out = {}
    for line in open(path, errors="ignore"):
        line = line.split("//")[0].strip()
        if not line.startswith("#define MB_FRLG_"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            val = int(parts[2], 16)
        except ValueError:
            continue
        if parts[1] in DIRBLOCK:
            out[val] = DIRBLOCK[parts[1]]
    return out


def frlg_kind_table(kind):
    path = os.path.join(ROOT, "include/constants/metatile_behaviors_frlg.h")
    src = BITS if kind == "jump" else (SLIDE if kind == "slide" else CURRENT)
    out = {}
    for line in open(path, errors="ignore"):
        line = line.split("//")[0].strip()
        if not line.startswith("#define MB_FRLG_"):
            continue
        parts = line.split()
        if len(parts) < 3 or parts[1] not in src:
            continue
        try:
            val = int(parts[2], 16)
        except ValueError:
            continue
        out[val] = src[parts[1]]
    return out


FRLG_JUMP = None
FRLG_SLIDE = None
FRLG_CURRENT = None
FRLG_DIR = None


def grids_of(lay):
    global FRLG_JUMP, FRLG_SLIDE, FRLG_CURRENT, FRLG_DIR
    prim = get_primary(lay["primary_tileset"])
    sec = get_secondary(lay["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return None
    path = os.path.join(ROOT, lay["blockdata_filepath"])
    if not os.path.exists(path):
        return None
    block = open(path, "rb").read()
    w, h = int(lay["width"]), int(lay["height"])
    if FRLG_JUMP is None:
        FRLG_JUMP = frlg_kind_table("jump")
        FRLG_SLIDE = frlg_kind_table("slide")
        FRLG_CURRENT = frlg_kind_table("current")
        FRLG_DIR = frlg_dir_table()
    pc = prim.count
    lg, sl, cu, db, wf, bt = [], [], [], [], [], []
    ho, dp, cl, wh = [], [], [], []
    for y in range(h):
        rl, rs, rc, rd, rw, rb = [], [], [], [], [], []
        rh, rdp, rcl, rwh = [], [], [], []
        for x in range(w):
            val = struct.unpack_from("<H", block, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            b = behavior_of(ts, local)
            nm = INV.get(b, "")
            rl.append(BITS.get(nm, 0))
            rs.append(255 if nm in ICE_NAMES else SLIDE.get(nm, 0))
            rc.append(CURRENT.get(nm, 0))
            rd.append(DIRBLOCK.get(b, 0))
            rw.append(1 if nm in WATERFALL_NAMES else 0)
            rb.append(1 if nm in BUTTON_NAMES else 0)
            rh.append(1 if nm in HOLE_NAMES else 0)
            rdp.append(1 if nm in DEEP_NAMES else 0)
            rcl.append(1 if nm in CLIMB_NAMES else 0)
            rwh.append(1 if nm in WHIRL_NAMES else 0)
        wf.append(rw)
        bt.append(rb)
        ho.append(rh)
        dp.append(rdp)
        cl.append(rcl)
        wh.append(rwh)
        lg.append(rl)
        sl.append(rs)
        cu.append(rc)
        db.append(rd)
    return {"w": w, "h": h, "ledge": lg, "slide": sl, "current": cu,
            "dirblock": db, "waterfall": wf, "button": bt,
            "hole": ho, "deep": dp, "climb": cl, "whirl": wh}


def load_layouts():
    with open(os.path.join(ROOT, "data/layouts/layouts.json")) as f:
        return {l["id"]: l for l in json.load(f)["layouts"]}


def layout_for(meta, layouts):
    lid = meta.get("id") or meta.get("layout_id") or ""
    if lid in layouts:
        return layouts[lid]
    if "LAYOUT_" + lid in layouts:
        return layouts["LAYOUT_" + lid]
    return None


def main():
    layouts = load_layouts()
    done = 0
    skipped = []
    for name in sorted(os.listdir(EMAPS)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(EMAPS, name)
        meta = json.load(open(path))
        if "collision" not in meta or "size" not in meta:
            continue
        W, H = int(meta["size"][0]), int(meta["size"][1])
        if meta.get("member_maps"):
            if W * H > 300000:
                skipped.append(name)
                continue
            lg = [[0] * W for _ in range(H)]
            sl = [[0] * W for _ in range(H)]
            cu = [[0] * W for _ in range(H)]
            db = [[0] * W for _ in range(H)]
            wf = [[0] * W for _ in range(H)]
            bt = [[0] * W for _ in range(H)]
            ho = [[0] * W for _ in range(H)]
            dp = [[0] * W for _ in range(H)]
            cl = [[0] * W for _ in range(H)]
            wh = [[0] * W for _ in range(H)]
            for key, off in meta["member_maps"].items():
                lay = layouts.get(key) or layouts.get("LAYOUT_" + key)
                if lay is None:
                    lay = next((v for k, v in layouts.items()
                                if k.replace("LAYOUT_", "") == key), None)
                if lay is None:
                    continue
                sub = grids_of(lay)
                if not sub:
                    continue
                for y in range(sub["h"]):
                    for x in range(sub["w"]):
                        gy, gx = int(off[1]) + y, int(off[0]) + x
                        if 0 <= gy < H and 0 <= gx < W:
                            lg[gy][gx] = sub["ledge"][y][x]
                            sl[gy][gx] = sub["slide"][y][x]
                            cu[gy][gx] = sub["current"][y][x]
                            db[gy][gx] = sub["dirblock"][y][x]
                            wf[gy][gx] = sub["waterfall"][y][x]
                            bt[gy][gx] = sub["button"][y][x]
                            ho[gy][gx] = sub["hole"][y][x]
                            dp[gy][gx] = sub["deep"][y][x]
                            cl[gy][gx] = sub["climb"][y][x]
                            wh[gy][gx] = sub["whirl"][y][x]
        else:
            lay = layout_for(meta, layouts)
            if lay is None:
                skipped.append(name)
                continue
            sub = grids_of(lay)
            if not sub:
                skipped.append(name)
                continue
            lg, sl, cu, db = sub["ledge"], sub["slide"], sub["current"], sub["dirblock"]
            wf = sub["waterfall"]
            bt = sub["button"]
            ho, dp, cl, wh = sub["hole"], sub["deep"], sub["climb"], sub["whirl"]
        for y in range(len(db)):
            for x in range(len(db[y])):
                db[y][x] = int(db[y][x]) & ~int(lg[y][x]) & 15
        meta["ledge"] = lg
        meta["slide"] = sl
        meta["current"] = cu
        meta["dirblock"] = db
        meta["waterfall"] = wf
        meta["button"] = bt
        meta["hole"] = ho
        meta["deep"] = dp
        meta["climb"] = cl
        meta["whirl"] = wh
        json.dump(meta, open(path, "w"), separators=(",", ":"))
        done += 1
        n = (sum(1 for r in lg for v in r if v), sum(1 for r in sl for v in r if v),
             sum(1 for r in cu for v in r if v))
        if any(n):
            print("%-42s 坡 %4d 冰 %3d 流 %3d" % (name, n[0], n[1], n[2]))
    print("处理 %d 张，跳过 %d 张 %s" % (done, len(skipped), skipped[:5]))


if __name__ == "__main__":
    main()
