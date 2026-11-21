#!/usr/bin/env python3
"""特殊世界与岛屿：三层结构图（L0 主盘 / L1 地理附属 / L2 平行异层）。"""
from asset_paths import project_path

from PIL import Image, ImageDraw, ImageFont
import math, json
from pathlib import Path
from gen_world_map import fb, fr

W, H = 1600, 1100
OCEAN = (9, 18, 26)
GRID = (20, 33, 43)
INK = (232, 240, 238)
DIM = (138, 158, 160)
MINT = (108, 205, 184)
GOLD = (236, 206, 120)

# 主盘九地区（横排，保持东西向顺序：西→东）
MAIN = [
    ("alola", "阿罗拉", "夏威夷", 7, (224, 164, 92)),
    ("unova", "合众", "纽约", 5, (139, 111, 176)),
    ("galar", "伽勒尔", "英国", 8, (78, 127, 168)),
    ("kalos", "卡洛斯", "法国", 6, (217, 125, 166)),
    ("paldea", "帕底亚", "西班牙", 9, (194, 91, 91)),
    ("hoenn", "丰缘", "九州", 3, (63, 168, 140)),
    ("johto", "城都", "关西", 2, (217, 160, 60)),
    ("kanto", "关都", "关东", 1, (224, 92, 75)),
    ("sinnoh", "神奥", "北海道", 4, (91, 127, 199)),
]

# L1：地理附属岛，挂在主地区旁
ISLANDS = [
    ("sevii", "七之岛", "kanto", "火红·叶绿", "关都南方海 · 渡轮", "七座小岛，网罗二三代宝可梦"),
    ("orange", "橘子群岛", "kanto", "动画设定", "关都东南 · 帆船", "群岛挑战，四天王杯"),
    ("armor", "铠岛", "galar", "剑·盾 DLC", "伽勒尔南 · 火车", "武馆修行，熊徒弟"),
    ("crown", "王冠雪原", "galar", "剑·盾 DLC", "伽勒尔北 · 火车", "极巨大冒险，传说鸟"),
    ("kitakami", "北上乡", "paldea", "朱·紫 DLC", "帕底亚东北 · 巴士", "祭典与鬼，太晶团体战"),
    ("blueberry", "蓝莓学园", "unova", "朱·紫 DLC", "合众海域 · 潜水艇", "海底学园，蓝之圆盘"),
    ("aether", "以太乐园", "alola", "日·月", "阿罗拉海上 · 渡轮", "人工岛，保护与研究设施"),
    ("frontier", "对战开拓区", "hoenn", "绿宝石", "丰缘东南 · 渡轮", "七座对战设施，徽章挑战"),
]

# L2：平行/异层，不是新地方
LAYERS = [
    ("hisui", "洗翠地区", "sinnoh", "神奥的过去", "神奥·枪之柱 / 时光机", "古代神奥，捕捉宝可梦的起点"),
    ("distortion", "反转世界", "sinnoh", "神奥的背面", "神奥·天冠山 裂缝", "重力错乱的空岛，骑拉帝纳"),
    ("ultra", "究极空间", "alola", "阿罗拉之外", "阿罗拉·究极之洞", "异兽栖息的异次元"),
    ("dream", "梦世界", "unova", "合众的梦境", "合众·梦境同步", "宝可梦的梦境，隐藏特性"),
]


def curve(d, p0, p1, color, width=2, lift=0.0, bend=0.0):
    """二次贝塞尔：控制点在两点中间偏上，各条线不会重合。"""
    cx = (p0[0] + p1[0]) / 2 + bend
    cy = min(p0[1], p1[1]) - lift
    pts = []
    n = 48
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * cx + t ** 2 * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * cy + t ** 2 * p1[1]
        pts.append((x, y))
    d.line(pts, fill=color, width=width, joint="curve")


def dashed(d, p0, p1, color, width=3, dash=12, gap=8):
    x0, y0 = p0
    x1, y1 = p1
    seg = math.hypot(x1 - x0, y1 - y0)
    if seg == 0:
        return
    t = 0.0
    on = True
    while t < seg:
        step = min(dash if on else gap, seg - t)
        if on:
            ax = x0 + (x1 - x0) * t / seg
            ay = y0 + (y1 - y0) * t / seg
            bx = x0 + (x1 - x0) * (t + step) / seg
            by = y0 + (y1 - y0) * (t + step) / seg
            d.line([(ax, ay), (bx, by)], fill=color, width=width)
        t += step
        on = not on


def main():
    graph = json.loads(Path(project_path("content/world_graph.json")).read_text())
    specials = {s["id"]:s for s in graph["specials"]}
    im = Image.new("RGB", (W, H), OCEAN)
    d = ImageDraw.Draw(im, "RGBA")

    for x in range(40, W - 30, 80):
        d.line([(x, 120), (x, H - 70)], fill=GRID, width=1)
    for y in range(120, H - 70, 80):
        d.line([(40, y), (W - 30, y)], fill=GRID, width=1)

    d.text((48, 34), "宝可梦 · 特殊世界与岛屿", font=fb(38), fill=INK)
    d.text((48, 88), "八个附属地区和四个异层地区各有独立步行入口。每条通道两端都可步行返回。",
           font=fr(19), fill=DIM)

    # ---- L0 主盘 ----
    lx, ly = 48, 138
    d.text((lx, ly), "L0  现世主盘 · 九个地区", font=fb(20), fill=MINT)

    tw, th = 146, 70
    gap = 12
    pos = {}
    for i, (key, name, proto, gen, c) in enumerate(MAIN):
        x = lx + i * (tw + gap)
        y = ly + 40
        pos[key] = (x + tw / 2, y + th)
        base = (int(c[0] * 0.20) + 10, int(c[1] * 0.20) + 14, int(c[2] * 0.20) + 18)
        d.rounded_rectangle([x, y, x + tw, y + th], radius=12, fill=base,
                            outline=(c[0], c[1], c[2], 240), width=2)
        d.rounded_rectangle([x, y, x + 6, y + th], radius=3, fill=c)
        d.text((x + 18, y + 10), name, font=fb(23), fill=INK)
        d.text((x + 18, y + 40), "第%d世代 · %s" % (gen, graph["regions"][key]["status"]), font=fr(13), fill=DIM)

    # ---- L1 岛屿 ----
    l1y = 300
    d.text((lx, l1y), "L1  附属地区 · 海堤、栈道与山间古道", font=fb(20), fill=MINT)

    iw, ih = 178, 108
    igap = 12
    for i, (key, name, parent, src, route, note) in enumerate(ISLANDS):
        x = lx + i * (iw + igap)
        y = l1y + 44
        px, py = pos[parent]
        cx = x + iw / 2
        lift = 26 + (i % 4) * 16
        curve(d, (px, py + 3), (cx, y), (68, 108, 118), width=2,
              lift=lift, bend=(i - 3.5) * 12)
        d.ellipse([px - 3, py - 1, px + 3, py + 5], fill=(126, 196, 206))

        d.rounded_rectangle([x, y, x + iw, y + ih], radius=12, fill=(16, 27, 35),
                            outline=(52, 96, 104), width=2)
        d.text((x + 14, y + 10), name, font=fb(20), fill=INK)
        d.text((x + 14, y + 40), "归属 " + dict((k, n) for k, n, *_ in MAIN)[parent],
               font=fr(13), fill=(120, 190, 200))
        d.text((x + 14, y + 60), specials[key]["walk_label"], font=fr(12), fill=DIM)
        d.text((x + 14, y + 78), src + " · " + specials[key]["status"], font=fr(12), fill=GOLD)

    # ---- L2 异层 ----
    l2y = 540
    d.text((lx, l2y), "L2  异层地区 · 从现世的遗迹、裂隙与梦境入口进入", font=fb(20), fill=MINT)

    lw, lh = 350, 118
    lgap = 20
    for i, (key, name, parent, kind, entry, note) in enumerate(LAYERS):
        x = lx + i * (lw + lgap)
        y = l2y + 46
        d.rounded_rectangle([x, y, x + lw, y + lh], radius=12, fill=(22, 20, 34),
                            outline=(96, 82, 140), width=2)
        d.rounded_rectangle([x, y, x + 6, y + lh], radius=3, fill=(120, 100, 178))
        d.text((x + 18, y + 8), dict((k, n) for k, n, *_ in MAIN)[parent] + "  ›  异层",
               font=fr(12), fill=(150, 132, 200))
        d.text((x + 18, y + 30), name, font=fb(22), fill=INK)
        d.text((x + 18, y + 66), kind + " · " + specials[key]["status"], font=fr(13), fill=GOLD)
        d.text((x + 18, y + 84), specials[key]["walk_label"], font=fr(12), fill=DIM)
        d.text((x + 18, y + 100), note, font=fr(11), fill=(150, 160, 165))

    # ---- 说明 ----
    ny = 740
    d.rounded_rectangle([lx, ny, W - 48, ny + 296], radius=14, fill=(13, 22, 30),
                        outline=(40, 66, 74), width=1)
    d.text((lx + 22, ny + 16), "沿途说明", font=fb(19), fill=MINT)

    lines = [
        ("七之岛", "七座岛的港口另有六段海堤相连。从一之岛港向东沿栈桥前行，或沿西侧长廊返回关都。", ""),
        ("异层入口", "从神奥的神和镇附近可经时空遗迹步廊前往洗翠，从送泉可经裂隙步径进入反转世界。", ""),
        ("异层入口", "从阿罗拉的祭坛可经光桥进入究极空间，从合众的梦的遗址可沿梦烟小径进入梦世界。", ""),
        ("旅行", "每个地区都有领航员。步行可以自由往返各地，也可以在领航员处选择其他地区的枢纽。", ""),
    ]
    y = ny + 52
    for tag, a, b in lines:
        d.text((lx + 22, y), tag, font=fb(15), fill=(236, 206, 120))
        d.text((lx + 108, y), a, font=fr(14), fill=(206, 218, 220))
        d.text((lx + 108, y + 24), b, font=fr(14), fill=(206, 218, 220))
        y += 58

    im.save(project_path("doc/world_specials.png"), quality=95)
    print("saved", im.size)


if __name__ == "__main__":
    main()
