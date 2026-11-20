#!/usr/bin/env python3
"""给地图补一张「土坡 / 台阶」网格。

原版那些能跳下去的矮坡是 MB_JUMP_SOUTH / EAST / ... 系列：
    * 从高的那边往低的那边走，可以一步跨过去（落地在两格之外）
    * 反过来走是过不去的
之前把 JUMP 系列一律当成"挡路"，结果所有靠跳坡连通的路全断了，
只能绕远——地图通道走不了就是这么来的。

输出 ledge[y][x] 用位掩码记「允许往哪个方向跳」：
    1 上 / 2 下 / 4 右 / 8 左
"""
import json, os, glob, struct, sys

ROOT = "/root/build/pokeemerald-expansion-master"
EMAPS = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions"

sys.path.insert(0, "/root/build/pokesaga/tools")
from render_emerald_maps import get_primary, get_secondary
from annotate_encounters import behaviors, behavior_of

BH = behaviors()
DIR_BITS = {
    "MB_JUMP_NORTH": 1,
    "MB_JUMP_SOUTH": 2,
    "MB_JUMP_EAST": 4,
    "MB_JUMP_WEST": 8,
}
JUMP = {BH[k]: v for k, v in DIR_BITS.items() if k in BH}


def main():
    print("jump behaviors", JUMP)
    used = {}
    for f in glob.glob(os.path.join(REG, "*", "maps", "*.json")):
        d = json.load(open(f))
        if d.get("emerald"):
            used[os.path.normcase(d["emerald"])] = d

    for name, region_map in used.items():
        meta_path = os.path.join(EMAPS, name + ".json")
        if not os.path.exists(meta_path):
            continue
        meta = json.load(open(meta_path))
        lay = meta.get("layout") or {}
        w, h = meta["size"]

        if meta.get("composed") and meta.get("member_maps"):
            # 拼图：逐块渲染各自的 ledge 再贴回去
            grid = [[0] * w for _ in range(h)]
            lays = {}
            for lay_row in json.load(open(os.path.join(ROOT, "data/layouts/layouts.json")))["layouts"]:
                lays[lay_row["id"]] = lay_row
            for key, at in meta["member_maps"].items():
                l = lays.get(key) or lays.get("LAYOUT_" + key.upper())
                if not l:
                    continue
                sub = ledge_of(l)
                if not sub:
                    continue
                sw, sh = sub["w"], sub["h"]
                for y in range(sh):
                    for x in range(sw):
                        gy, gx = int(at[1]) + y, int(at[0]) + x
                        if 0 <= gy < h and 0 <= gx < w:
                            grid[gy][gx] = sub["grid"][y][x]
            meta["ledge"] = grid
            total = sum(1 for row in grid for v in row if v)
            json.dump(meta, open(meta_path, "w"), separators=(",", ":"))
            print("%-34s composed %dx%d ledge %d" % (name, w, h, total))
            continue

        sub = ledge_of(lay)
        if not sub:
            continue
        meta["ledge"] = sub["grid"]
        json.dump(meta, open(meta_path, "w"), separators=(",", ":"))
        total = sum(1 for row in sub["grid"] for v in row if v)
        print("%-34s %dx%-3d ledge %d" % (name, w, h, total))


def ledge_of(lay):
    if not lay or not lay.get("blockdata_filepath"):
        return None
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
    grid = []
    for y in range(h):
        row = []
        for x in range(w):
            val = struct.unpack_from("<H", block, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            row.append(JUMP.get(behavior_of(ts, local), 0))
        grid.append(row)
    return {"grid": grid, "w": w, "h": h}


if __name__ == "__main__":
    main()
