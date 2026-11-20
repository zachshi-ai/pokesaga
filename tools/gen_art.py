#!/usr/bin/env python3
"""PokeSaga 美术生成：16x16 瓦片图集 + 16x24 角色行走图集。
纯像素绘制，无抗锯齿；配色走明亮清新的 GBA 风。
"""
from PIL import Image, ImageDraw
import random
import math

T = 16
OUT = "/root/build/pokesaga/assets"

# ---------- 调色板 ----------
C = {
    "grass_a": (108, 178, 78), "grass_b": (94, 160, 66), "grass_c": (124, 194, 92),
    "tree_d": (38, 88, 50), "tree_m": (52, 112, 62), "tree_l": (74, 140, 78),
    "trunk_d": (86, 58, 36), "trunk_l": (120, 84, 52),
    "water_d": (62, 126, 196), "water_m": (78, 148, 218), "water_l": (104, 176, 236),
    "path_a": (216, 194, 142), "path_b": (198, 174, 122), "path_c": (232, 212, 164),
    "stone_d": (128, 128, 132), "stone_m": (156, 156, 160), "stone_l": (188, 188, 192),
    "wall_a": (236, 222, 186), "wall_b": (208, 190, 152),
    "roof_a": (176, 86, 74), "roof_b": (146, 66, 58), "roof_l": (200, 112, 98),
    "door_a": (116, 78, 48), "door_l": (146, 102, 62),
    "fence_a": (150, 112, 70), "fence_b": (120, 88, 54),
    "sand_a": (232, 214, 160), "sand_b": (214, 194, 140),
    "flower_w": (250, 250, 250), "flower_y": (250, 214, 96), "flower_p": (232, 132, 168),
    "outline": (32, 44, 36),
}


def tile_grass(seed=1):
    im = Image.new("RGB", (T, T), C["grass_a"])
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for _ in range(26):
        x, y = rnd.randrange(T), rnd.randrange(T)
        d.point((x, y), C["grass_b"])
    for _ in range(10):
        x, y = rnd.randrange(T), rnd.randrange(T)
        d.point((x, y), C["grass_c"])
    return im


def tile_flowers(seed=3):
    im = tile_grass(seed)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed + 7)
    for i in range(3):
        x, y = 2 + i * 5 + rnd.randrange(2), 3 + rnd.randrange(9)
        petal = C["flower_w"] if i != 1 else C["flower_p"]
        d.point((x, y), petal)
        d.point((x - 1, y), petal)
        d.point((x + 1, y), petal)
        d.point((x, y - 1), petal)
        d.point((x, y + 1), petal)
        d.point((x, y), C["flower_y"])
    return im


def tile_tree():
    im = Image.new("RGB", (T, T), C["grass_b"])
    d = ImageDraw.Draw(im)
    d.rectangle([7, 10, 9, 15], fill=C["trunk_d"])
    d.rectangle([7, 10, 8, 15], fill=C["trunk_l"])
    d.ellipse([-1, -2, 16, 12], fill=C["tree_d"])
    d.ellipse([1, 0, 14, 10], fill=C["tree_m"])
    d.ellipse([3, 1, 10, 7], fill=C["tree_l"])
    d.point((5, 3), (110, 176, 110))
    d.point((9, 5), (110, 176, 110))
    return im


def tile_water(seed=5):
    im = Image.new("RGB", (T, T), C["water_m"])
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for y in range(0, T, 4):
        x0 = rnd.randrange(0, 6)
        d.line([x0, y + 1, x0 + 6, y + 1], fill=C["water_l"])
        d.line([x0 + 8, y + 3, x0 + 13, y + 3], fill=C["water_d"])
    return im


def tile_shore():
    im = tile_water(9)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, T - 1, 2], fill=C["sand_a"])
    d.rectangle([0, 3, T - 1, 3], fill=C["sand_b"])
    for x in range(T):
        if x % 3 == 0:
            d.point((x, 4), C["water_l"])
    return im


def tile_path(seed=11):
    im = Image.new("RGB", (T, T), C["path_a"])
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for _ in range(18):
        x, y = rnd.randrange(T), rnd.randrange(T)
        d.point((x, y), C["path_b"])
    for _ in range(8):
        x, y = rnd.randrange(T), rnd.randrange(T)
        d.point((x, y), C["path_c"])
    return im


def tile_path_stone(seed=13):
    im = tile_path(seed)
    d = ImageDraw.Draw(im)
    for (x, y) in [(4, 5), (10, 9)]:
        d.rectangle([x, y, x + 2, y + 1], fill=C["stone_m"])
        d.point((x, y), C["stone_l"])
    return im


def tile_rock():
    im = tile_grass(21)
    d = ImageDraw.Draw(im)
    d.ellipse([2, 4, 13, 14], fill=C["stone_d"])
    d.ellipse([4, 5, 12, 12], fill=C["stone_m"])
    d.ellipse([5, 6, 9, 9], fill=C["stone_l"])
    return im


def tile_wall():
    im = Image.new("RGB", (T, T), C["wall_a"])
    d = ImageDraw.Draw(im)
    d.rectangle([0, T - 2, T - 1, T - 1], fill=(198, 178, 142))
    for y in range(0, T, 5):
        d.line([0, y, T, y], fill=C["wall_b"])
    for y in range(0, T, 10):
        for x in range(3, T, 8):
            d.line([x, y, x, y + 4], fill=C["wall_b"])
    return im


def tile_roof():
    im = Image.new("RGB", (T, T), C["roof_a"])
    d = ImageDraw.Draw(im)
    for y in range(0, T, 4):
        d.line([0, y, T, y], fill=C["roof_b"])
        for x in range((y // 4) % 2 * 4, T, 8):
            d.line([x, y, x, y + 3], fill=C["roof_l"])
    return im


def tile_door():
    im = tile_wall()
    d = ImageDraw.Draw(im)
    d.rectangle([3, 2, 12, 15], fill=C["door_a"])
    d.rectangle([4, 3, 11, 15], fill=C["door_l"])
    d.rectangle([7, 3, 8, 15], fill=C["door_a"])
    d.point((10, 9), C["flower_y"])
    return im


def tile_fence():
    im = tile_grass(31)
    d = ImageDraw.Draw(im)
    d.rectangle([1, 6, T - 2, 8], fill=C["fence_b"])
    d.rectangle([1, 6, T - 2, 7], fill=C["fence_a"])
    for x in [2, 7, 12]:
        d.rectangle([x, 3, x + 1, 13], fill=C["fence_b"])
        d.rectangle([x, 3, x, 12], fill=C["fence_a"])
    return im


def tile_sand(seed=41):
    im = Image.new("RGB", (T, T), C["sand_a"])
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for _ in range(22):
        x, y = rnd.randrange(T), rnd.randrange(T)
        d.point((x, y), C["sand_b"])
    return im


def autotile(fill_a, fill_b, edge, seed, wave=None):
    """按 4 位邻接掩码生成 16 个变体：bit0=上 bit1=右 bit2=下 bit3=左（1=邻居同地形）"""
    out = []
    inner = 3
    for mask in range(16):
        im = Image.new("RGB", (T, T), fill_a)
        d = ImageDraw.Draw(im)
        rnd = random.Random(seed * 100 + mask)
        for _ in range(20):
            x, y = rnd.randrange(T), rnd.randrange(T)
            d.point((x, y), fill_b)
        if wave:
            for y in range(2, T, 5):
                d.line([2, y, T - 3, y], fill=wave)
        # 不规则边缘：逐列/逐行随机凸起 1px，消掉笔直网格感
        if not (mask & 1):
            for x in range(T):
                h = inner + rnd.randrange(0, 3)
                d.rectangle([x, 0, x, h - 1], fill=edge)
                d.point((x, h), edge)
        if not (mask & 4):
            for x in range(T):
                h = inner + rnd.randrange(0, 3)
                d.rectangle([x, T - h, x, T - 1], fill=edge)
        if not (mask & 8):
            for y in range(T):
                w = inner + rnd.randrange(0, 3)
                d.rectangle([0, y, w - 1, y], fill=edge)
        if not (mask & 2):
            for y in range(T):
                w = inner + rnd.randrange(0, 3)
                d.rectangle([T - w, y, T - 1, y], fill=edge)
        out.append(im)
    return out


def tile_tallgrass(seed=61):
    im = Image.new("RGB", (T, T), C["grass_b"])
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for i in range(9):
        x = 1 + i * 2 + rnd.randrange(0, 1)
        h = 6 + rnd.randrange(0, 4)
        d.line([x, T - 1, x, T - 1 - h], fill=(70, 132, 62))
        d.line([x + 1, T - 1, x + 1, T - 2 - h], fill=(88, 156, 74))
        d.point((x, T - 2 - h), (120, 186, 96))
    return im


def tile_signpost():
    im = tile_grass(71)
    d = ImageDraw.Draw(im)
    d.rectangle([7, 8, 8, 15], fill=C["trunk_d"])
    d.rectangle([3, 3, 12, 8], fill=C["fence_a"])
    d.rectangle([3, 3, 12, 4], fill=(196, 158, 106))
    d.rectangle([3, 3, 12, 8], outline=C["fence_b"])
    d.line([5, 6, 10, 6], fill=C["fence_b"])
    return im


def tile_floor_wood(seed=71):
    """室内木地板：横向长条 + 接缝"""
    im = Image.new("RGB", (T, T), (196, 158, 108))
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for i in range(0, T, 4):
        y = i + 1
        d.line([(0, y), (T - 1, y)], fill=(168, 132, 88))
        for _ in range(6):
            d.point((rnd.randrange(T), rnd.randrange(y, min(T, y + 3))), (212, 176, 124))
    d.line([(7, 0), (7, T - 1)], fill=(176, 140, 94))
    return im


def tile_carpet(seed=73):
    """室内地毯：深红底 + 浅色菱形纹"""
    im = Image.new("RGB", (T, T), (158, 74, 78))
    d = ImageDraw.Draw(im)
    for y in range(T):
        for x in range(T):
            if (x + y) % 8 == 0 or (x - y) % 8 == 0:
                d.point((x, y), (188, 102, 104))
    d.rectangle([0, 0, T - 1, T - 1], outline=(128, 58, 62))
    return im


def build_variants():
    """同一类地形多几套长相，渲染时按坐标散开，避免整片像方格纸。"""
    made = []
    made.append(tile_tree_variant(1))
    made.append(tile_tree_variant(2))
    made.append(tile_grass(21))
    made.append(tile_grass(22))
    made.append(tile_flowers(23))
    made.append(tile_roof_variant())
    return made


def tile_tree_variant(v):
    """三种长相：矮胖冠、高尖冠、大冠压边；连树干位置也错开，成片才不像阵列。"""
    im = Image.new("RGB", (T, T), C["grass_b"])
    d = ImageDraw.Draw(im)
    rnd = random.Random(700 + v)
    # 地面先散点草，避免树冠边缘是一块纯色
    for _ in range(14):
        d.point((rnd.randrange(T), rnd.randrange(T)), C["grass_b"])

    if v == 1:
        # 矮胖冠
        d.rectangle([6, 11, 9, 15], fill=C["trunk_d"])
        d.rectangle([6, 11, 7, 15], fill=C["trunk_l"])
        d.ellipse([-3, 1, 16, 14], fill=C["tree_d"])
        d.ellipse([-1, 3, 14, 12], fill=C["tree_m"])
        d.ellipse([1, 4, 9, 10], fill=C["tree_l"])
        d.point((12, 6), C["tree_l"])
    elif v == 2:
        # 高尖冠
        d.rectangle([7, 12, 9, 15], fill=C["trunk_d"])
        d.rectangle([7, 12, 8, 15], fill=C["trunk_l"])
        d.polygon([(8, -2), (16, 12), (0, 12)], fill=C["tree_d"])
        d.polygon([(8, 1), (14, 11), (2, 11)], fill=C["tree_m"])
        d.polygon([(8, 4), (11, 10), (5, 10)], fill=C["tree_l"])
    else:
        # 大冠压边
        d.rectangle([7, 11, 10, 15], fill=C["trunk_d"])
        d.rectangle([7, 11, 8, 15], fill=C["trunk_l"])
        d.ellipse([-4, -2, 18, 13], fill=C["tree_d"])
        d.ellipse([-2, 0, 16, 11], fill=C["tree_m"])
        d.ellipse([0, 1, 11, 8], fill=C["tree_l"])
        d.point((13, 4), C["tree_l"])
        d.point((4, 6), C["tree_l"])
    return im


def tile_roof_variant():
    im = Image.new("RGB", (T, T), C["roof_a"])
    d = ImageDraw.Draw(im)
    for y in range(0, T, 4):
        d.line([(0, y), (T - 1, y)], fill=C["roof_b"])
        for x in range(0, T, 8):
            d.line([((x + (4 if (y // 4) % 2 else 0)) % T, y),
                    ((x + (4 if (y // 4) % 2 else 0)) % T, y + 3)], fill=C["roof_b"])
    d.line([(0, T - 2), (T - 1, T - 2)], fill=C["roof_l"])
    return im


TILES = [
    tile_grass(), tile_flowers(), tile_tree(), tile_water(),
    tile_shore(), tile_path(), tile_path_stone(), tile_rock(),
    tile_wall(), tile_roof(), tile_door(), tile_fence(),
    tile_sand(), tile_grass(2), tile_grass(3), tile_path(17),
    tile_tallgrass(), tile_signpost(),
]


PATH_IDX = len(TILES)
TILES += autotile(C["path_a"], C["path_b"], (100, 166, 70), 11)
WATER_IDX = len(TILES)
TILES += autotile(C["water_m"], C["water_d"], (222, 200, 148), 5, wave=C["water_l"])

# 室内两张，追加在最后，不影响前面 0-15 / 16-31 / 32-47 的下标约定
FLOOR_WOOD_IDX = len(TILES)
TILES.append(tile_floor_wood())
CARPET_IDX = len(TILES)
TILES.append(tile_carpet())

# 地形变体，紧跟其后，索引 52 起
TREE_B_IDX = len(TILES)
TILES.append(tile_tree_variant(1))
TREE_C_IDX = len(TILES)
TILES.append(tile_tree_variant(2))
GRASS_B_IDX = len(TILES)
TILES.append(tile_grass(21))
GRASS_C_IDX = len(TILES)
TILES.append(tile_grass(22))
FLOWER_B_IDX = len(TILES)
TILES.append(tile_flowers(23))
ROOF_B_IDX = len(TILES)
TILES.append(tile_roof_variant())


# 六套 NPC 配色：村民、少女、老人、水手、研究员、训练家
NPC_PALETTES = [
    dict(coat=(110, 96, 156), coat_l=(138, 124, 184), pants=(70, 60, 96),
         cap=(196, 176, 120), cap_l=(216, 200, 148), hair=(64, 48, 40)),
    dict(coat=(214, 128, 148), coat_l=(236, 158, 176), pants=(150, 96, 112),
         cap=(232, 196, 132), cap_l=(248, 220, 168), hair=(96, 62, 40), cap_on=False),
    dict(coat=(150, 150, 148), coat_l=(178, 178, 176), pants=(104, 104, 104),
         cap=(210, 210, 206), cap_l=(232, 232, 228), hair=(214, 212, 208), cap_on=False),
    dict(coat=(64, 118, 164), coat_l=(92, 148, 194), pants=(48, 70, 104),
         cap=(228, 228, 224), cap_l=(248, 248, 244), hair=(52, 40, 36)),
    dict(coat=(238, 238, 232), coat_l=(252, 252, 248), pants=(96, 104, 120),
         cap=(120, 150, 176), cap_l=(150, 180, 204), hair=(58, 44, 38)),
    dict(coat=(96, 148, 96), coat_l=(124, 176, 124), pants=(64, 88, 72),
         cap=(206, 84, 72), cap_l=(228, 108, 92), hair=(48, 38, 34)),
]


def build_npcs():
    import os
    for i, pal in enumerate(NPC_PALETTES):
        build_char_sheet(f"{OUT}/npc_{i}.png", pal)
    print("npcs:", len(NPC_PALETTES))


TREE_TONES = [
    ((44, 96, 54), (62, 124, 68), (88, 156, 88), (118, 186, 108)),   # 深绿
    ((50, 104, 56), (72, 138, 72), (100, 168, 96), (134, 198, 118)),  # 标准
    ((58, 110, 60), (82, 148, 76), (116, 178, 100), (154, 208, 128)), # 偏黄
    ((38, 88, 50), (56, 114, 62), (80, 146, 82), (108, 174, 100)),    # 更暗
]


def decal_tree(seed, size=52, tone=1):
    """跨格的树冠贴花：盖住网格接缝，让树块看起来是一整片林子。"""
    rnd = random.Random(seed)
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = size / 2, size / 2 + 2
    t0 = TREE_TONES[tone % len(TREE_TONES)]
    layers = [(1.00, t0[0]), (0.86, t0[1]), (0.66, t0[2]), (0.40, t0[3])]
    for k, (scale, col) in enumerate(layers):
        pts = []
        n = 14
        for i in range(n):
            a = 2 * math.pi * i / n
            r = size * 0.5 * scale * (0.82 + rnd.random() * 0.30)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.92))
        d.polygon(pts, fill=col)
    # 叶脉碎点
    for _ in range(26):
        a = rnd.random() * 2 * math.pi
        r = rnd.random() * size * 0.42
        d.point((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.9), (128, 190, 116))
    # 底部压暗，做出体积
    d.arc([cx - size * 0.46, cy - size * 0.46, cx + size * 0.46, cy + size * 0.5],
          20, 160, fill=(34, 78, 46), width=3)
    return im


def decal_bush(seed, size=22):
    rnd = random.Random(seed)
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for _ in range(5):
        rx = rnd.uniform(2, size - 8)
        ry = rnd.uniform(3, size - 8)
        r = rnd.uniform(3.4, 6.0)
        d.ellipse([rx, ry, rx + r * 2, ry + r * 1.7], fill=C["tree_m"])
        d.ellipse([rx + 1, ry + 1, rx + r * 1.2, ry + r * 1.1], fill=C["tree_l"])
    return im


def decal_grass(seed, size=16):
    rnd = random.Random(seed)
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for _ in range(7):
        x = rnd.randrange(1, size - 2)
        y = rnd.randrange(size // 2, size - 1)
        h = rnd.randrange(3, 6)
        col = rnd.choice([C["grass_b"], C["grass_c"], (150, 206, 110)])
        d.line([(x, y), (x + rnd.choice([-1, 0, 1]), y - h)], fill=col)
    return im


def decal_shade(size=16):
    """树底下的一小片投影，铺在紧挨树的地面上，把林缘和草地分开。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(size):
        a = int(56 * (1 - i / size))
        d.line([(0, i), (size - 1, i)], fill=(24, 52, 34, a))
    return im


def build_decals():
    for i in range(6):
        decal_tree(900 + i, tone=i).save(f"{OUT}/decal_tree_{i}.png")
    for i in range(3):
        decal_bush(950 + i).save(f"{OUT}/decal_bush_{i}.png")
        decal_grass(990 + i).save(f"{OUT}/decal_grass_{i}.png")
    decal_shade().save(f"{OUT}/decal_shade.png")
    print("decals:", 6 + 3 + 3 + 1)


def build_tileset():
    cols = 4
    rows = (len(TILES) + cols - 1) // cols
    im = Image.new("RGB", (cols * T, rows * T), (0, 0, 0))
    for i, t in enumerate(TILES):
        im.paste(t, ((i % cols) * T, (i // cols) * T))
    im.save(f"{OUT}/tiles.png")
    print("tiles.png", im.size, len(TILES))


# ---------- 角色 ----------
PW, PH = 16, 24
SKIN = (248, 208, 168)
HAIR = (58, 46, 40)
COAT = (52, 132, 132)
COAT_L = (74, 160, 156)
PANTS = (58, 74, 112)
SHOE = (44, 40, 44)
CAP = (206, 84, 72)
CAP_L = (228, 108, 92)


def draw_char(direction, frame, pal=None):
    """frame: 0 站立, 1 左脚, 2 右脚；pal 可以整套换衣服/头发/帽子色"""
    p = pal or {}
    skin = p.get("skin", SKIN)
    hair = p.get("hair", HAIR)
    coat = p.get("coat", COAT)
    coat_l = p.get("coat_l", COAT_L)
    pants = p.get("pants", PANTS)
    shoe = p.get("shoe", SHOE)
    cap = p.get("cap", CAP)
    cap_l = p.get("cap_l", CAP_L)
    uses_cap = p.get("cap_on", True)
    im = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bob = 1 if frame == 1 else 0

    # 腿
    if frame == 1:
        d.rectangle([4, 19, 6, 22], fill=pants)
        d.rectangle([9, 19, 11, 21], fill=pants)
        d.rectangle([9, 22, 11, 22], fill=shoe)
        d.rectangle([4, 23, 6, 23], fill=shoe)
    elif frame == 2:
        d.rectangle([4, 19, 6, 21], fill=pants)
        d.rectangle([9, 19, 11, 22], fill=pants)
        d.rectangle([4, 22, 6, 22], fill=shoe)
        d.rectangle([9, 23, 11, 23], fill=shoe)
    else:
        d.rectangle([4, 19, 6, 22], fill=pants)
        d.rectangle([9, 19, 11, 22], fill=pants)
        d.rectangle([4, 23, 6, 23], fill=shoe)
        d.rectangle([9, 23, 11, 23], fill=shoe)

    # 身体
    d.rectangle([3, 12 + bob, 12, 19 + bob], fill=coat)
    d.rectangle([3, 12 + bob, 12, 13 + bob], fill=coat_l)
    d.rectangle([7, 14 + bob, 8, 18 + bob], fill=(240, 240, 232))

    # 手臂
    if direction == "down":
        d.rectangle([2, 14 + bob, 3, 18 + bob], fill=coat)
        d.rectangle([12, 14 + bob, 13, 18 + bob], fill=coat)
    elif direction == "up":
        d.rectangle([2, 14 + bob, 3, 18 + bob], fill=coat_l)
        d.rectangle([12, 14 + bob, 13, 18 + bob], fill=coat_l)
    else:
        d.rectangle([2, 14 + bob, 4, 18 + bob], fill=coat)

    # 头
    hy = 4 + bob
    d.rectangle([4, hy, 11, hy + 7], fill=skin)
    d.rectangle([4, hy - 1, 11, hy + 1], fill=hair)
    if uses_cap:
        d.rectangle([3, hy - 2, 12, hy], fill=cap)
        d.rectangle([3, hy - 2, 12, hy - 1], fill=cap_l)

    if direction == "down":
        d.point((6, hy + 3), (40, 40, 48))
        d.point((9, hy + 3), (40, 40, 48))
        d.point((7, hy + 6), (196, 120, 108))
    elif direction == "left":
        d.point((5, hy + 3), (40, 40, 48))
        d.rectangle([4, hy + 3, 4, hy + 4], fill=SKIN)
    elif direction == "right":
        d.point((10, hy + 3), (40, 40, 48))
        d.rectangle([11, hy + 3, 11, hy + 4], fill=SKIN)
    else:
        d.rectangle([4, hy, 11, hy + 7], fill=hair)
        if uses_cap:
            d.rectangle([3, hy - 2, 12, hy + 2], fill=cap)
            d.rectangle([3, hy - 2, 12, hy - 1], fill=cap_l)

    return im


def add_outline(im, color=(26, 32, 30)):
    out = Image.new("RGBA", (im.width + 2, im.height + 2), (0, 0, 0, 0))
    src = im.load()
    ol = Image.new("RGBA", out.size, (0, 0, 0, 0))
    od = ol.load()
    for y in range(im.height):
        for x in range(im.width):
            if src[x, y][3] > 0:
                for dx, dy in ((1, 0), (2, 0), (0, 2), (1, 2), (2, 2), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < ol.width and 0 <= ny < ol.height:
                        od[nx, ny] = color + (255,)
    out.alpha_composite(ol)
    out.alpha_composite(im, (1, 1))
    return out


def build_char_sheet(path, palette=None):
    dirs = ["down", "left", "right", "up"]
    FW, FH = PW + 2, PH + 2
    sheet = Image.new("RGBA", (FW * 3, FH * 4), (0, 0, 0, 0))
    for r, dirn in enumerate(dirs):
        for c in range(3):
            sheet.paste(add_outline(draw_char(dirn, c, palette)), (c * FW, r * FH))
    sheet.save(path)
    print(path, sheet.size)


def build_shadow():
    im = Image.new("RGBA", (18, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 1, 17, 6], fill=(24, 32, 28, 90))
    d.ellipse([2, 2, 15, 5], fill=(24, 32, 28, 60))
    im.save(f"{OUT}/shadow.png")
    print("shadow.png", im.size)




# ---------- 生物立绘（按属性配色的原创小怪，64x64）----------
TYPE_PALETTE = {
    "grass":   ((126, 196, 92), (86, 158, 62), (176, 226, 140), (60, 110, 52)),
    "fire":    ((240, 150, 74), (206, 108, 48), (255, 196, 128), (150, 70, 40)),
    "water":   ((96, 164, 226), (62, 118, 186), (156, 206, 246), (44, 84, 140)),
    "electric":((246, 210, 84), (206, 168, 44), (255, 238, 152), (168, 130, 36)),
    "rock":    ((170, 158, 138), (128, 118, 102), (208, 198, 178), (92, 84, 72)),
    "normal":  ((226, 210, 184), (188, 172, 148), (246, 238, 220), (150, 136, 116)),
    "poison":  ((186, 132, 206), (146, 96, 168), (216, 176, 232), (108, 68, 128)),
    "bug":     ((176, 196, 96), (132, 152, 62), (212, 226, 146), (96, 112, 44)),
    "flying":  ((176, 196, 226), (132, 152, 186), (216, 230, 246), (94, 112, 142)),
    "psychic": ((246, 132, 168), (206, 92, 130), (255, 180, 204), (156, 62, 96)),
    "fighting":((206, 106, 86), (166, 72, 58), (238, 152, 130), (124, 50, 40)),
    "ghost":   ((148, 130, 186), (108, 92, 148), (186, 172, 218), (76, 62, 110)),
    "ground":  ((216, 190, 140), (176, 150, 104), (242, 222, 178), (134, 112, 76)),
    "dragon":  ((126, 140, 226), (88, 100, 182), (168, 180, 246), (62, 72, 138)),
    "ice":     ((146, 216, 226), (104, 176, 190), (190, 238, 246), (74, 132, 146)),
    "dark":    ((126, 114, 110), (90, 80, 78), (162, 150, 146), (62, 54, 52)),
    "steel":   ((184, 190, 200), (142, 148, 158), (216, 222, 232), (104, 110, 120)),
    "fairy":   ((246, 176, 208), (208, 132, 168), (255, 212, 232), (158, 96, 126)),
}

OUTLINE = (38, 34, 40)


def creature(species_id, kind, size=64):
    """程序化小怪：64x64 直接像素绘制，不做缩放，避免重采样糊边。"""
    base, dark, light, deep = TYPE_PALETTE.get(kind, TYPE_PALETTE["normal"])
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    cx, cy = 32, 40
    variant = species_id % 4
    rw = [18, 16, 20, 17][variant]
    rh = [17, 19, 15, 18][variant]

    # 角 / 耳
    if variant == 0:
        for sx in (-1, 1):
            d.polygon([(cx + sx * 6, cy - rh + 4), (cx + sx * 12, cy - rh - 6),
                       (cx + sx * 2, cy - rh + 2)], fill=dark, outline=OUTLINE)
    elif variant == 1:
        d.polygon([(cx, cy - rh), (cx - 5, cy - rh - 9), (cx + 5, cy - rh - 7)],
                  fill=light, outline=OUTLINE)
    elif variant == 2:
        for sx in (-1, 1):
            d.ellipse([cx + sx * 13 - 4, cy - rh - 8, cx + sx * 13 + 4, cy - rh + 2],
                      fill=dark, outline=OUTLINE)

    # 尾巴
    if variant == 3:
        d.ellipse([cx + rw - 3, cy + 2, cx + rw + 9, cy + 12], fill=dark, outline=OUTLINE)

    # 脚
    for sx in (-1, 1):
        d.ellipse([cx + sx * 9 - 5, cy + rh - 5, cx + sx * 9 + 5, cy + rh + 3],
                  fill=dark, outline=OUTLINE)

    # 身体
    d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=base, outline=OUTLINE)
    # 肚皮
    d.ellipse([cx - rw + 5, cy - 2, cx + rw - 5, cy + rh - 3], fill=light)
    # 阴影
    d.arc([cx - rw, cy - rh, cx + rw, cy + rh], 30, 150, fill=dark, width=3)

    # 眼睛（左右各一，中心对称）
    for sx in (-1, 1):
        ex = cx + sx * 8
        d.ellipse([ex - 5, cy - 11, ex + 5, cy - 1], fill=(252, 252, 250), outline=OUTLINE)
        d.ellipse([ex - 2, cy - 8, ex + 2, cy - 4], fill=OUTLINE)
        d.point((ex - 1, cy - 8), (255, 255, 255))

    # 嘴
    d.arc([cx - 5, cy - 1, cx + 5, cy + 6], 20, 160, fill=deep, width=1)
    return im


def build_creatures():
    """按 content/species.json 全量出图，属性取自第一条，颜色随属性走。
    这样补一条物种数据就自动多一张图，不用改这份脚本。"""
    import json
    rows = json.load(open("/root/build/pokesaga/content/species.json"))
    made = []
    for row in rows:
        sid = int(row["id"])
        types = row.get("types") or ["normal"]
        kind = types[0] if types[0] in TYPE_PALETTE else "normal"
        creature(sid, kind).save(f"{OUT}/mon_{sid}.png")
        made.append(sid)
    print("creatures:", len(made), sorted(made))


if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    build_tileset()
    build_char_sheet(f"{OUT}/player.png")
    build_shadow()
    build_creatures()
    build_npcs()
    build_decals()
