#!/usr/bin/env python3
"""把 pokecrystal 的原版地图（.blk + 两套 tileset + palette map）渲染成 PNG + 碰撞表。

跟 render_emerald_maps.py 同一套输出格式（content/emerald_maps/<id>.png/.json），
这样游戏内核不用为城都改任何东西。

tileset 的贴图是 4 级灰度（GBC 2bpp），颜色来自 palette map 里给每个 metatile
指定的调色板（GRAY/RED/GREEN/WATER/YELLOW/BROWN/ROOF），配色取 bg_tiles.pal 的
白天那一组。碰撞取 data/tilesets/<ts>_collision.asm，四象限里取左上角那一格。
"""
import json
import os
import re
import sys

from PIL import Image

ROOT = "/root/build/pokecrystal"
OUT_MAIN = "/root/build/pokesaga/content/emerald_maps"

TS_DIR_PNG = os.path.join(ROOT, "gfx/tilesets")
TS_DIR_META = os.path.join(ROOT, "data/tilesets")

PAL_NAMES = ["GRAY", "RED", "GREEN", "WATER", "YELLOW", "BROWN", "ROOF", "TEXT"]

# 碰撞类型 -> 引擎里的含义
LEDGE_OF = {0x41: 4, 0x42: 8, 0x43: 1, 0x44: 2,
            0x50: 4, 0x51: 8, 0x52: 1, 0x53: 2}
# 城都的坡是 0xA0+序号：0 右 / 1 左 / 2 上 / 3 下 / 4 右下 / 5 左下 / 6 右上 / 7 左上
CRYSTAL_LEDGE = {0xA0: 4, 0xA1: 8, 0xA2: 1, 0xA3: 2,
                 0xA4: 2 | 4, 0xA5: 2 | 8, 0xA6: 1 | 4, 0xA7: 1 | 8}
WATER_COLL = {0x29, 0x21, 0x30, 0x31, 0x32, 0x33, 0x38, 0x39, 0x3A, 0x3B, 0x27, 0x24, 0x2C}
CUT_COLL = {0x12, 0x08, 0x28, 0x1A}
GRASS_COLL = {0x14, 0x18, 0x10, 0x1C, 0x48, 0x49, 0x4A, 0x4B, 0x4C}
ICE_COLL = {0x23, 0x2B}
# 门 / 楼梯 / 洞窟口：站得上去，站上去就触发切换
WARP_COLL = {0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
             0x7A, 0x7B, 0x7C, 0x7D, 0x7E}


def read(path):
    with open(path, "r", errors="ignore") as f:
        return f.read().replace("\r", "")


def parse_pal_file(path, want=None):
    """解析 .pal：返回 {段名: [(r,g,b), ...]}（扁平，4 个一组）。"""
    if not os.path.exists(path):
        return {}
    out = {}
    cur = None
    lines = read(path).split("\n")
    for ln in lines:
        s = ln.strip()
        if not s:
            continue
        if s.startswith(";"):
            name = s[1:].strip().lower()
            if not name:
                continue
            if want and name != want:
                cur = None
                continue
            cur = name
            out.setdefault(cur, [])
            continue
        if s.upper().startswith("RGB") and cur:
            nums = [int(x) for x in re.findall(r"\d+", s.split(";")[0])]
            for i in range(0, len(nums) - 2, 3):
                r, g, b = nums[i], nums[i + 1], nums[i + 2]
                out[cur].append(((r * 255) // 31, (g * 255) // 31, (b * 255) // 31))
    return out


_BG_PAL = None


# bg_tiles.pal 里 8 组配色的固定顺序
BG_ORDER = ["gray", "red", "green", "water", "yellow", "brown", "roof", "text"]


def bg_palettes():
    """bg_tiles.pal 的白天配色，拆成 {gray:[4色], red:[4色], ...}。"""
    global _BG_PAL
    if _BG_PAL is None:
        flat = parse_pal_file(os.path.join(TS_DIR_PNG, "bg_tiles.pal"), want="day").get("day", [])
        out = {}
        for i, nm in enumerate(BG_ORDER):
            cols = flat[i * 4:i * 4 + 4]
            if len(cols) == 4:
                out[nm] = cols
        _BG_PAL = out
    return _BG_PAL


class Tileset:
    def __init__(self, name):
        self.name = name
        img = Image.open(os.path.join(TS_DIR_PNG, name + ".png")).convert("L")
        self.w, self.h = img.size
        self.cols = self.w // 8
        self.tiles = []
        px = img.load()
        for ty in range(self.h // 8):
            for tx in range(self.cols):
                tile = [[0] * 8 for _ in range(8)]
                for y in range(8):
                    for x in range(8):
                        v = px[tx * 8 + x, ty * 8 + y]
                        tile[y][x] = min(3, (v + 42) // 85)
                self.tiles.append(tile)

        meta_path = os.path.join(TS_DIR_META, name + "_metatiles.bin")
        raw = open(meta_path, "rb").read()
        self.count = len(raw) // 16
        self.meta = [raw[i * 16:(i + 1) * 16] for i in range(self.count)]

        # 碰撞：每行 4 个象限
        self.coll = []
        cpath = os.path.join(TS_DIR_META, name + "_collision.asm")
        if os.path.exists(cpath):
            for ln in read(cpath).split("\n"):
                s = ln.strip()
                if not s.startswith("tilecoll"):
                    continue
                body = s.split(";")[0]
                args = [a.strip() for a in body.split(",", 1)[1].split(",")]
                self.coll.append([coll_value(a) for a in args])

        # palette map
        self.palmap = {}
        ppath = os.path.join(TS_DIR_PNG, name + "_palette_map.asm")
        if os.path.exists(ppath):
            for ln in read(ppath).split("\n"):
                s = ln.strip()
                if not s.startswith("tilepal"):
                    continue
                parts = [p.strip() for p in s.split(",")]
                grp = int(parts[0].split()[1])
                names = parts[1:]
                base = grp * 128 + len([k for k in self.palmap if k // 128 == grp]) * 8
                for i, nm in enumerate(names[:8]):
                    self.palmap[base + i] = PAL_NAMES.index(nm) if nm in PAL_NAMES else 0

        self.pal = bg_palettes()
        # 少数 tileset（house / battle_tower_inside 等）自带一份 .pal，按顺序覆盖
        own = parse_pal_file(os.path.join(TS_DIR_PNG, name + ".pal"))
        for seg, flat in own.items():
            if seg in ("morn", "day", "nite", "dark"):
                continue
            for i, nm in enumerate(BG_ORDER):
                cols = flat[i * 4:i * 4 + 4]
                if len(cols) == 4:
                    self.pal[nm] = cols

    def colors(self, mid):
        idx = self.palmap.get(mid, 0)
        name = PAL_NAMES[idx].lower()
        cols = self.pal.get(name)
        if not cols or len(cols) < 4:
            cols = self.pal.get("gray") or [(255, 255, 255), (170, 170, 170), (85, 85, 85), (0, 0, 0)]
        return cols

    def render_fg(self, mid):
        """只画「盖住人物」的那一半：属性字节的 bit5 是优先级（树冠、屋顶）。"""
        if mid >= len(self.meta):
            mid = 0
        cols = self.colors(mid)
        entry = self.meta[mid]
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        px = img.load()
        for i in range(4):
            tid = entry[i * 2]
            attr = entry[i * 2 + 1]
            if not (attr & 0x20):
                continue
            tile = self.tiles[tid] if tid < len(self.tiles) else [[0] * 8 for _ in range(8)]
            ox = (i % 2) * 8
            oy = (i // 2) * 8
            fx = bool(attr & 0x08)
            fy = bool(attr & 0x10)
            for y in range(8):
                for x in range(8):
                    sx = 7 - x if fx else x
                    sy = 7 - y if fy else y
                    v = tile[sy][sx]
                    if v == 0:
                        continue
                    r, g, b = cols[v]
                    px[ox + x, oy + y] = (r, g, b, 255)
        return img

    def render(self, mid):
        """返回 16x16 RGB 图。"""
        if mid >= len(self.meta):
            mid = 0
        cols = self.colors(mid)
        entry = self.meta[mid]
        img = Image.new("RGB", (16, 16))
        px = img.load()
        for i in range(4):
            tid = entry[i * 2]
            attr = entry[i * 2 + 1]
            if tid >= len(self.tiles):
                tile = [[0] * 8 for _ in range(8)]
            else:
                tile = self.tiles[tid]
            ox = (i % 2) * 8
            oy = (i // 2) * 8
            fx = bool(attr & 0x20)
            fy = bool(attr & 0x40)
            for y in range(8):
                for x in range(8):
                    sx = 7 - x if fx else x
                    sy = 7 - y if fy else y
                    px[ox + x, oy + y] = cols[tile[sy][sx]]
        return img


def cls_of(c):
    if c in CRYSTAL_LEDGE or c in LEDGE_OF:
        return "ledge"
    if c in WARP_COLL:
        return "warp"
    if c in WATER_COLL:
        return "water"
    if c in GRASS_COLL:
        return "grass"
    if c in ICE_COLL:
        return "ice"
    if c in CUT_COLL:
        return "cut"
    return "floor" if c == 0 else "wall"


def coll_value(name):
    name = name.strip().upper()
    if name.startswith("COLL_"):
        name = name[5:]
    table = {
        "FLOOR": 0, "01": 1, "03": 1, "04": 1, "WALL": 7,
        "CUT_08": 8, "TALL_GRASS_10": 0x10, "CUT_TREE": 0x12,
        "LONG_GRASS": 0x14, "HEADBUTT_TREE": 0x15, "TALL_GRASS": 0x18,
        "CUT_TREE_1A": 0x1A, "LONG_GRASS_1C": 0x1C, "HEADBUTT_TREE_1D": 0x1D,
        "WATER_21": 0x21, "ICE": 0x23, "WHIRLPOOL": 0x24, "BUOY": 0x27,
        "CUT_28": 0x28, "WATER": 0x29, "ICE_2B": 0x2B, "WHIRLPOOL_2C": 0x2C,
        "WATERFALL_RIGHT": 0x30, "WATERFALL_LEFT": 0x31, "WATERFALL_UP": 0x32,
        "WATERFALL": 0x33, "CURRENT_RIGHT": 0x38, "CURRENT_LEFT": 0x39,
        "CURRENT_UP": 0x3A, "CURRENT_DOWN": 0x3B, "BRAKE": 0x40,
        "WALK_RIGHT": 0x41, "WALK_LEFT": 0x42, "WALK_UP": 0x43, "WALK_DOWN": 0x44,
        "BRAKE_45": 0x45, "BRAKE_46": 0x46, "BRAKE_47": 0x47,
        "GRASS_48": 0x48, "GRASS_49": 0x49, "GRASS_4A": 0x4A, "GRASS_4B": 0x4B,
        "GRASS_4C": 0x4C, "WALK_RIGHT_ALT": 0x50, "WALK_LEFT_ALT": 0x51,
        "WALK_UP_ALT": 0x52, "WALK_DOWN_ALT": 0x53, "BRAKE_ALT": 0x54,
        "BRAKE_55": 0x55, "BRAKE_56": 0x56, "BRAKE_57": 0x57, "5B": 0x5B,
        "PIT": 0x60, "VIRTUAL_BOY": 0x61, "64": 0x64, "65": 0x65, "PIT_68": 0x68,
        "WARP_CARPET_DOWN": 0x70, "DOOR": 0x71, "LADDER": 0x72, "STAIRCASE_73": 0x73,
        "CAVE_74": 0x74, "DOOR_75": 0x75, "WARP_CARPET_LEFT": 0x76, "WARP_77": 0x77,
        "WARP_CARPET_UP": 0x78, "DOOR_79": 0x79, "STAIRCASE": 0x7A, "CAVE": 0x7B,
        "WARP_PANEL": 0x7C, "DOOR_7D": 0x7D, "WARP_CARPET_RIGHT": 0x7E,
        # 城都的坡
        "HOP_RIGHT": 0xA0, "HOP_LEFT": 0xA1, "HOP_UP": 0xA2, "HOP_DOWN": 0xA3,
        "HOP_DOWN_RIGHT": 0xA4, "HOP_DOWN_LEFT": 0xA5,
        "HOP_UP_RIGHT": 0xA6, "HOP_UP_LEFT": 0xA7,
    }
    if name in table:
        return table[name]
    try:
        return int(name, 16)
    except ValueError:
        return 0


_ts_cache = {}


def tileset(name):
    if name not in _ts_cache:
        _ts_cache[name] = Tileset(name)
    return _ts_cache[name]


_BLOCK_ALIAS = None


def block_file_of(map_name):
    """一张地图的 .blk 路径。原版里很多地图共用同一份方块数据
    （所有友好商店都指向 maps/Mart.blk），所以要先解析 blocks.asm 的标签别名。"""
    global _BLOCK_ALIAS
    if _BLOCK_ALIAS is None:
        _BLOCK_ALIAS = {}
        txt = read(os.path.join(ROOT, "data/maps/blocks.asm"))
        pending = []
        for ln in txt.split("\n"):
            s = ln.strip()
            m = re.match(r"^(\w+)_Blocks::?$", s)
            if m:
                pending.append(m.group(1))
                continue
            m2 = re.match(r'INCBIN\s+"([^"]+)"', s)
            if m2 and pending:
                for lab in pending:
                    _BLOCK_ALIAS[lab] = m2.group(1)
                pending = []
            elif s and not s.startswith(";"):
                pending = []
    return _BLOCK_ALIAS.get(map_name)


def load_blockdata(map_name):
    rel = block_file_of(map_name)
    if rel:
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            return open(p, "rb").read()
    path = os.path.join(ROOT, "maps", map_name + ".blk")
    if os.path.exists(path):
        return open(path, "rb").read()
    raise FileNotFoundError(rel or path)


def render_map(map_name, ts_name, w, h, out_dir=OUT_MAIN, out_id=None):
    ts = tileset(ts_name)
    data = load_blockdata(map_name)
    if len(data) < w * h:
        return None
    img = Image.new("RGB", (w * 16, h * 16), (0, 0, 0))
    fg = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 0))
    collision = [[0] * w for _ in range(h)]
    water = [[0] * w for _ in range(h)]
    ledge = [[0] * w for _ in range(h)]
    grass = [[0] * w for _ in range(h)]
    doors = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            bid = data[y * w + x]
            if bid < len(ts.meta):
                img.paste(ts.render(bid), (x * 16, y * 16))
                fg.paste(ts.render_fg(bid), (x * 16, y * 16), ts.render_fg(bid))
            # 一块 16x16 在原版里是 4 个 8x8 象限，各自有碰撞。
            # 引擎一格就是整块，所以按「四象限里有一块能站」判定，
            # 只取左上角会把很多门前的路误判成墙（道馆、塔的门口全是这种）。
            vals = list(ts.coll[bid][:4]) if bid < len(ts.coll) else [0, 0, 0, 0]
            while len(vals) < 4:
                vals.append(vals[0])
            kinds = [cls_of(c) for c in vals]
            if "ledge" in kinds:
                lv = vals[kinds.index("ledge")]
                ledge[y][x] = CRYSTAL_LEDGE.get(lv) or LEDGE_OF.get(lv, 0)
                collision[y][x] = 0
            elif "warp" in kinds:
                collision[y][x] = 0
                doors[y][x] = 1
            elif "water" in kinds and "floor" not in kinds:
                water[y][x] = 1
                collision[y][x] = 1
            elif kinds[2] == "floor" or kinds[2] == "grass" or kinds[2] == "ice" \
                    or (kinds[3] == "floor" and kinds[2] not in ("water", "cut")):
                if "grass" in kinds:
                    grass[y][x] = 1
                collision[y][x] = 0
            else:
                collision[y][x] = 1

    name = out_id or map_name.lower()
    png = os.path.join(out_dir, name + ".png")
    img.save(png)
    fg.save(png.replace(".png", "_fg.png"))
    meta = {
        "id": name,
        "size": [w, h],
        "png": os.path.basename(png),
        "collision": collision,
        "water": water,
        "ledge": ledge,
        "grass": grass,
        "door": doors,
        "source": "pokecrystal",
        "map": map_name,
        "tileset": ts_name,
    }
    json.dump(meta, open(os.path.join(out_dir, name + ".json"), "w"), separators=(",", ":"))
    return name, w, h


if __name__ == "__main__":
    args = sys.argv[1:]
    map_name = args[0] if args else "NewBarkTown"
    ts_name = args[1] if len(args) > 1 else "johto"
    w = int(args[2]) if len(args) > 2 else 10
    h = int(args[3]) if len(args) > 3 else 9
    print(render_map(map_name, ts_name, w, h, out_id="test_" + map_name.lower()))
