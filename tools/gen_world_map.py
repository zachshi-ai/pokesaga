#!/usr/bin/env python3
"""九地区世界大盘示意图：按现实原型地理位置排布，标注陆路、海岸栈道和隧道。"""
from asset_paths import project_path

from PIL import Image, ImageDraw, ImageFont
import json, math
from pathlib import Path

W, H = 1600, 1080
OCEAN = (9, 18, 26)
GRID = (20, 33, 43)
INK = (232, 240, 238)
DIM = (138, 158, 160)
MINT = (108, 205, 184)

FONT_B = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
FONT_R = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"


def fb(sz):
    return ImageFont.truetype(FONT_B, sz, index=2) if Path(FONT_B).exists() else ImageFont.truetype(project_path("assets/fonts/field-sans.otf"), sz)


def fr(sz):
    return ImageFont.truetype(FONT_R, sz, index=2) if Path(FONT_R).exists() else ImageFont.truetype(project_path("assets/fonts/field-sans.otf"), sz)


# 地区：中心点、色、原型、世代
REGIONS = {
    "kanto":  dict(name="关都", proto="日本·关东", gen=1, c=(224, 92, 75),  xy=(1225, 425)),
    "johto":  dict(name="城都", proto="日本·关西", gen=2, c=(217, 160, 60), xy=(1055, 520)),
    "hoenn":  dict(name="丰缘", proto="日本·九州", gen=3, c=(63, 168, 140), xy=(880, 645)),
    "sinnoh": dict(name="神奥", proto="日本·北海道", gen=4, c=(91, 127, 199), xy=(1270, 240)),
    "unova":  dict(name="合众", proto="美国·纽约", gen=5, c=(139, 111, 176), xy=(300, 615)),
    "kalos":  dict(name="卡洛斯", proto="法国", gen=6, c=(217, 125, 166), xy=(640, 380)),
    "alola":  dict(name="阿罗拉", proto="美国·夏威夷", gen=7, c=(224, 164, 92), xy=(200, 855)),
    "galar":  dict(name="伽勒尔", proto="英国", gen=8, c=(78, 127, 168), xy=(430, 235)),
    "paldea": dict(name="帕底亚", proto="西班牙", gen=9, c=(194, 91, 91), xy=(490, 540)),
}

BW, BH = 210, 112

# 通道：a, b, 类型, 标签, 控制点（曲线绕行）
CONTROL = {("kanto","johto"):(1140,445), ("kanto","hoenn"):(1170,683), ("johto","hoenn"):(960,610),
           ("johto","sinnoh"):(1210,380), ("kanto","sinnoh"):(1352,330), ("galar","kalos"):(520,300),
           ("kalos","paldea"):(585,460), ("paldea","unova"):(330,665), ("unova","alola"):(230,745),
           ("unova","galar"):(300,380), ("kanto","unova"):(700,900), ("alola","hoenn"):(520,940)}



def quad(p0, p1, pc, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * pc[0] + t ** 2 * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * pc[1] + t ** 2 * p1[1]
        pts.append((x, y))
    return pts


def dashed(d, pts, color, width=3, dash=15, gap=11):
    acc = 0.0
    on = True
    for i in range(1, len(pts)):
        x0, y0 = pts[i - 1]
        x1, y1 = pts[i]
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg == 0:
            continue
        t = 0.0
        while t < seg:
            step = min((dash if on else gap) - acc, seg - t)
            if on:
                ax = x0 + (x1 - x0) * t / seg
                ay = y0 + (y1 - y0) * t / seg
                bx = x0 + (x1 - x0) * (t + step) / seg
                by = y0 + (y1 - y0) * (t + step) / seg
                d.line([(ax, ay), (bx, by)], fill=color, width=width)
            t += step
            acc += step
            if acc >= (dash if on else gap) - 1e-6:
                acc = 0.0
                on = not on


def edge_pt(center, target, w=BW / 2 + 8, h=BH / 2 + 8):
    dx = target[0] - center[0]
    dy = target[1] - center[1]
    if dx == 0 and dy == 0:
        return center
    sx = (w / abs(dx)) if dx else 1e9
    sy = (h / abs(dy)) if dy else 1e9
    s = min(sx, sy)
    return (center[0] + dx * s, center[1] + dy * s)


def main():
    graph = json.loads(Path(project_path("content/world_graph.json")).read_text())
    links = [(w["a"], w["b"], w["kind"], w["label"] + (" · 待建" if w["status"] == "待建" else ""),
              CONTROL[w["a"],w["b"]]) for w in graph["links"]]
    im = Image.new("RGB", (W, H), OCEAN)
    d = ImageDraw.Draw(im, "RGBA")

    # 网格
    for x in range(60, W - 40, 80):
        d.line([(x, 130), (x, H - 92)], fill=GRID, width=1)
    for y in range(130, H - 92, 80):
        d.line([(60, y), (W - 40, y)], fill=GRID, width=1)

    # 标题
    d.text((60, 34), "宝可梦 · 九地区世界大盘", font=fb(38), fill=INK)
    d.text((60, 86), "九个地区之间可经海岸栈道、山口和隧道步行往返。关都与丰缘之间经过对战开拓区。",
           font=fr(19), fill=DIM)

    # 通道
    for a, b, kind, label, ctrl in links:
        pa, pb = REGIONS[a]["xy"], REGIONS[b]["xy"]
        p0 = edge_pt(pa, ctrl if ctrl else pb)
        p1 = edge_pt(pb, ctrl if ctrl else pa)
        pts = quad(p0, p1, ctrl)
        if kind == "land":
            d.line(pts, fill=(236, 226, 190), width=4, joint="curve")
        elif kind == "sea":
            dashed(d, pts, (120, 190, 220), width=4, dash=17, gap=12)
        elif kind == "tunnel":
            dashed(d, pts, (150, 160, 200), width=3, dash=7, gap=6)
            for off in (-4, 4):
                d.line([(p[0], p[1] + off) for p in pts], fill=(150, 160, 200), width=1)
        else:
            dashed(d, pts, (206, 176, 238), width=3, dash=5, gap=9)

    # 通道标签
    boxes = []
    for r in REGIONS.values():
        cx, cy = r["xy"]
        boxes.append([cx - BW / 2 - 4, cy - BH / 2 - 4, cx + BW / 2 + 4, cy + BH / 2 + 4])

    def free(x0, y0, x1, y1):
        for bx in boxes:
            if x0 < bx[2] and x1 > bx[0] and y0 < bx[3] and y1 > bx[1]:
                return False
        return True

    f = fr(14)
    placed = []
    for a, b, kind, label, ctrl in links:
        if not label:
            continue
        pa, pb = REGIONS[a]["xy"], REGIONS[b]["xy"]
        p0 = edge_pt(pa, ctrl)
        p1 = edge_pt(pb, ctrl)
        tw = d.textlength(label, font=f)
        best = None
        for t in (0.5, 0.42, 0.58, 0.34, 0.66, 0.27, 0.73):
            pts = quad(p0, p1, ctrl, 100)
            x, y = pts[int(t * 100)]
            x -= tw / 2
            y -= 9
            r = [x - 8, y - 5, x + tw + 8, y + 21]
            if not free(*r):
                continue
            clash = False
            for q in placed:
                if r[0] < q[2] and r[2] > q[0] and r[1] < q[3] and r[3] > q[1]:
                    clash = True
                    break
            if clash:
                continue
            best = (x, y, r)
            break
        if best is None:
            continue
        x, y, r = best
        placed.append(r)
        d.rounded_rectangle(r, radius=5, fill=(9, 18, 26, 235), outline=(44, 66, 74))
        d.text((x, y), label, font=f, fill=(200, 218, 222))

    # 地区块
    for key, r in REGIONS.items():
        cx, cy = r["xy"]
        box = [cx - BW / 2, cy - BH / 2, cx + BW / 2, cy + BH / 2]
        c = r["c"]
        base = (int(c[0] * 0.20) + 10, int(c[1] * 0.20) + 14, int(c[2] * 0.20) + 18)
        d.rounded_rectangle(box, radius=16, fill=base,
                            outline=(c[0], c[1], c[2], 240), width=2)
        # 左侧色条
        d.rounded_rectangle([box[0], box[1], box[0] + 7, box[3]], radius=4, fill=c)
        d.text((cx - BW / 2 + 22, cy - 40), r["name"], font=fb(30), fill=INK)
        d.text((cx - BW / 2 + 22, cy + 2), "原型 " + r["proto"], font=fr(15), fill=(210, 222, 220))
        d.text((cx - BW / 2 + 22, cy + 26), "第 %d 世代 · %s" % (r["gen"],graph["regions"][key]["status"]), font=fr(14), fill=DIM)

    # 图例
    lx, ly = 1140, 830
    d.rounded_rectangle([lx, ly, lx + 400, ly + 150], radius=12,
                        fill=(14, 24, 32, 235), outline=(52, 84, 92), width=1)
    d.text((lx + 18, ly + 14), "通道图例", font=fb(18), fill=MINT)
    rows = [("land", "陆路 · 峡谷、山口与古道"), ("sea", "海岸 · 浮桥、海堤与栈道"),
            ("tunnel", "隧道 · 地下与海底通道")]
    for i, (kind, text) in enumerate(rows):
        y = ly + 48 + i * 26
        if kind == "land":
            d.line([(lx + 20, y + 8), (lx + 78, y + 8)], fill=(236, 226, 190), width=4)
        elif kind == "sea":
            dashed(d, [(lx + 20, y + 8), (lx + 78, y + 8)], (120, 190, 220), width=4, dash=14, gap=9)
        elif kind == "tunnel":
            dashed(d, [(lx + 20, y + 8), (lx + 78, y + 8)], (150, 160, 200), width=3, dash=6, gap=6)
        else:
            dashed(d, [(lx + 20, y + 8), (lx + 78, y + 8)], (206, 176, 238), width=3, dash=5, gap=9)
        d.text((lx + 92, y), text, font=fr(14), fill=(206, 218, 220))

    # 底部说明
    d.text((60, H - 66), "从各地区的领航员可以查看全景图并前往另一地区。丰缘 101 至 134 号道路均可探索。",
           font=fr(15), fill=DIM)

    im.save(project_path("doc/world_map.png"), quality=95)
    print("saved", im.size)


if __name__ == "__main__":
    import os
    os.makedirs(project_path("doc"), exist_ok=True)
    main()
