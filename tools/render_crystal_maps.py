#!/usr/bin/env python3
"""把 pokecrystal 的原版地图（.blk + 两套 tileset + palette map）渲染成 PNG + 碰撞表。

跟 render_emerald_maps.py 同一套输出格式（content/emerald_maps/<id>.png/.json），
这样游戏内核不用为城都改任何东西。

每块 4×4 个 8 像素图块。按上游双显存区、分图块配色与分组屋顶绘制，游戏显示时缩放到逻辑格，保留原生像素。
--active-art 仅更新在用地图图像，保留已修正的碰撞、门点和事件。
"""
from asset_paths import project_path, source_path

import json
import os
import re
import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image

ROOT = source_path("crystal")
OUT_MAIN = project_path("content/emerald_maps")

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


def palette_colors(line):
    values = [int(n) * 255 // 31 for n in re.findall(r"\d+", line.split(";")[0])]
    return list(zip(values[::3], values[1::3], values[2::3]))


@lru_cache(None)
def palette_sections(filename):
    groups = {"": []}
    label = ""
    for line in Path(TS_DIR_PNG, filename).read_text().splitlines():
        line = line.strip()
        if line.startswith(";"):
            label = line[1:].strip().lower()
            groups.setdefault(label, [])
        elif line.startswith("RGB "):
            groups[label].extend(palette_colors(line))
    return groups


@lru_cache(None)
def map_profiles():
    group = 0
    profiles = {}
    for line in Path(ROOT, "data/maps/maps.asm").read_text().splitlines():
        if re.match(r"MapGroup_\w+:$", line):
            group += 1
        match = re.match(r"\s*map (\w+), TILESET_\w+, (\w+),", line)
        if match:
            profiles[match[1]] = (group, match[2])
    return profiles


@lru_cache(None)
def roof_types():
    table = read(os.path.join(ROOT, "data/maps/roofs.asm")).split("MapGroupRoofs:", 1)[1]
    return re.findall(r"^\s*db (ROOF_\w+|-1)", table, re.M)


@lru_cache(None)
def tiles_from(filename):
    # White is palette index 0 in the upstream 2bpp graphics.
    img = Image.open(os.path.join(TS_DIR_PNG, filename)).convert("L")
    img = img.point([3 - min(3, (v + 42) // 85) for v in range(256)])
    return [img.crop((x, y, x+8, y+8)) for y in range(0, img.height, 8)
            for x in range(0, img.width, 8)]


class Tileset:
    def __init__(self, name, group, environment):
        blocks = Path(TS_DIR_META, name + "_metatiles.bin").read_bytes()
        self.meta = [blocks[i:i+16] for i in range(0, len(blocks), 16)]
        self.coll = []
        for line in Path(TS_DIR_META, name + "_collision.asm").read_text().splitlines():
            line = line.partition(";")[0].strip()
            if line.startswith("tilecoll "):
                self.coll.append([coll_value(v) for v in line.split(None, 1)[1].split(",")])

        colors = palette_sections("bg_tiles.pal")
        outside = environment in ("TOWN", "ROUTE")
        base = colors["indoor" if environment in ("GATE", "INDOOR") else "day"]
        palettes = [base[n:n+4] for n in range(0, 32, 4)]
        if outside:
            palettes[3] = colors["overworld water"][:4]
            roofs = palette_sections("roofs.pal")
            roof_colors = next(v for k, v in roofs.items() if k.startswith(f"group {group} "))
            palettes[6] = [palettes[6][0], *roof_colors[:2], palettes[6][3]]
        special = ("mansion_1" if name == "mansion" else name) + ".pal"
        if Path(TS_DIR_PNG, special).exists() and not (name == "ice_path" and environment == "INDOOR"):
            custom = [c for part in palette_sections(special).values() for c in part]
            palettes = [custom[i:i+4] for i in range(0,32,4)]
            if name == "mansion":
                palettes[3], palettes[6] = custom[24:28], custom[32:36]
                palettes[4] = next(v[:4] for v in palette_sections("mansion_2.pal").values() if v)

        # The two VRAM banks hold 96 tiles each, addressed at $00 and $80.
        flat = tiles_from(name + ".png")
        art = {i if i < 96 else i+32: tile for i, tile in enumerate(flat)}
        if name in ("johto", "johto_modern", "battle_tower_outside"):
            roof = roof_types()[group]
            if roof != "-1":
                art.update(enumerate(tiles_from("roofs/"+roof[5:].lower()+".png"), 10))
        if name in ("johto", "johto_modern", "kanto", "park", "forest", "port"):
            art[0x14] = tiles_from("water/water.png")[0]
            if name != "port":
                art[3] = tiles_from("flower/cgb_1.png")[0]

        self.tiles = {}
        cursor = [0, 128]
        for line in Path(TS_DIR_PNG, name + "_palette_map.asm").read_text().splitlines():
            match = re.match(r"\s*tilepal ([01]), (.+)", line.partition(";")[0])
            if not match:
                continue
            bank = int(match[1])
            for entry in match[2].split(","):
                tid = cursor[bank]
                cursor[bank] += 1
                if tid in art:
                    tile = art[tid].convert("P")
                    color = palettes[PAL_NAMES.index(entry.strip())]
                    tile.putpalette([c for triplet in color for c in triplet])
                    self.tiles[tid] = tile.convert("RGB")
        self.blocks = {}
        self.foregrounds = {}

    def render(self, mid):
        if mid not in self.blocks:
            cell = Image.new("RGB", (32, 32))
            for i, tid in enumerate(self.meta[mid]):
                tile = self.tiles.get(tid)
                if tile is None:
                    raise ValueError(f"Missing tile {tid:#x} in metatile {mid:#x}")
                cell.paste(tile, ((i % 4) * 8, (i // 4)*8))
            self.blocks[mid] = cell
        return self.blocks[mid]

    def render_fg(self, mid):
        # Only tree quadrants occlude a passing player. The sixteen block bytes
        # are tile IDs and contain no sprite-priority or flip flags.
        if mid not in self.foregrounds:
            art = self.render(mid)
            layer = Image.new("RGBA", art.size)
            for i, kind in enumerate(self.coll[mid][:4]):
                if kind in (0x15, 0x1d):
                    x, y = i%2*16, i//2*16
                    layer.paste(art.crop((x,y,x+16,y+16)), (x,y))
            self.foregrounds[mid] = layer
        return self.foregrounds[mid]


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


@lru_cache(None)
def tileset(name, group, environment):
    return Tileset(name, group, environment)


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


def render_map(map_name, ts_name, w, h, out_dir=OUT_MAIN, out_id=None, art_only=False):
    ts = tileset(ts_name, *map_profiles()[map_name])
    data = load_blockdata(map_name)
    if len(data) < w * h:
        return None
    img = Image.new("RGB", (w * 32, h * 32), (0, 0, 0))
    fg = Image.new("RGBA", (w * 32, h * 32), (0, 0, 0, 0))
    collision = [[0] * w for _ in range(h)]
    water = [[0] * w for _ in range(h)]
    ledge = [[0] * w for _ in range(h)]
    grass = [[0] * w for _ in range(h)]
    doors = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            bid = data[y * w + x]
            if bid < len(ts.meta):
                img.paste(ts.render(bid), (x * 32, y * 32))
                fg.paste(ts.render_fg(bid), (x * 32, y * 32))
            if art_only:
                continue
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
    if art_only:
        return name, w, h
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
    if args == ["--active-art"]:
        rooms = sorted(Path(project_path("content/regions/johto/maps")).glob("*.json"))
        if not rooms:
            sys.exit("No active Johto maps found")
        for path in rooms:
            key = json.loads(path.read_text())["emerald"]
            meta = json.loads(Path(OUT_MAIN, key + ".json").read_text())
            if not render_map(meta["map"], meta["tileset"], *meta["size"], out_id=key, art_only=True):
                sys.exit(f"Invalid size: {key}")
        print(f"Rendered {len(rooms)} active Johto maps")
        sys.exit()
    map_name = args[0] if args else "NewBarkTown"
    ts_name = args[1] if len(args) > 1 else "johto"
    w = int(args[2]) if len(args) > 2 else 10
    h = int(args[3]) if len(args) > 3 else 9
    print(render_map(map_name, ts_name, w, h, out_id="test_" + map_name.lower()))
