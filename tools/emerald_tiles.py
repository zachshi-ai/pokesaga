#!/usr/bin/env python3
"""把绿宝石（pokeemerald）原版 metatile 渲染成 16x16 PNG 图集。

GBA 规则（Emerald）：
  metatiles.bin 每个 metatile 16 字节 = 8 个 u16
    前 4 个是底层 tile（左上、右上、左下、右下），后 4 个是顶层
  u16 位域：bit0-9 tile 索引，bit10 flipX，bit11 flipY，bit12-15 调色板号
  tiles.png 每格 8x8，像素值就是调色板索引（0-15），真实颜色在 palettes/NN.pal
  顶层索引为 0 的像素透明
"""
import struct, os, json
from PIL import Image, ImageOps

BASE = "/root/build/pokeemerald-expansion-master/data/tilesets"


def load_pal(path):
    with open(path, "r", errors="ignore") as f:
        lines = f.read().replace("\r", "").split("\n")
    # JASC-PAL 头三行：签名 / 版本 / 颜色数
    cols = []
    for ln in lines[3:]:
        p = ln.strip().split()
        if len(p) >= 3:
            cols.append((int(p[0]), int(p[1]), int(p[2])))
    while len(cols) < 16:
        cols.append((0, 0, 0))
    return cols


class Tileset:
    """secondary 的 tile 索引 >= 512 才指向自己的 tiles.png，<512 回落到 primary。"""
    def __init__(self, path, fallback=None):
        self.fallback = fallback
        self.base_tiles = 0
        self.path = path
        im = Image.open(os.path.join(path, "tiles.png"))
        self.im = im.convert("P")
        self.px = self.im.load()
        self.w, self.h = self.im.size
        self.cols = self.w // 8
        self.meta = open(os.path.join(path, "metatiles.bin"), "rb").read()
        self.count = len(self.meta) // 16
        self.pals = {}
        pdir = os.path.join(path, "palettes")
        if os.path.isdir(pdir):
            for fn in sorted(os.listdir(pdir)):
                if fn.endswith(".pal"):
                    self.pal_index = int(fn.split(".")[0], 10) if fn.split(".")[0].isdigit() else None
                    self.pals[self.pal_index] = load_pal(os.path.join(pdir, fn))

    def tile_px(self, tid):
        # 组合 tileset：primary 占前 N 个 tile，secondary 的索引从 N 起。
        # 这个 N 是 primary 的 tile 总数（火红是 640，绿宝石是 512），不能写死。
        tid &= 0x3FF
        base = self.base_tiles
        if self.fallback is not None and tid < base:
            return self.fallback.tile_px(tid)
        if self.fallback is not None:
            tid -= base
        if tid >= self.cols * (self.h // 8):
            if self.fallback is not None:
                return self.fallback.tile_px(tid)
            return [[0] * 8 for _ in range(8)]
        tx = (tid % self.cols) * 8
        ty = (tid // self.cols) * 8
        return [[self.px[tx + x, ty + y] for x in range(8)] for y in range(8)]

    def layer_type(self, mid):
        """metatile 的图层类型。绿宝石是 16 位属性（bit12-15），火红是 32 位（bit29-30）。"""
        p = os.path.join(self.path, "metatile_attributes.bin")
        if not os.path.exists(p) or self.count == 0:
            return 0
        raw = open(p, "rb").read()
        step = len(raw) // self.count if self.count else 0
        if mid * step + step > len(raw):
            return 0
        if step >= 4:
            v = struct.unpack_from("<I", raw, mid * step)[0]
            return (v >> 29) & 0x3
        v = struct.unpack_from("<H", raw, mid * step)[0]
        return (v >> 12) & 0xF

    def render_split(self, mid):
        """按原版图层规则切开一个 metatile，返回 (人物之下, 人物之上)。

        原版 GBA 有两个背景层 BG2/BG1，精灵夹在中间：
          NORMAL  —— 底 4 块进 BG2（人下面），顶 4 块进 BG1（人上面）
          COVERED —— 8 块全在 BG3/BG2（都在人下面）
          SPLIT   —— 底 4 块进 BG3，顶 4 块进 BG1（人上面）
        之前把 8 块直接压平，屋顶树冠就永远盖不住人。
        """
        lt = self.layer_type(mid)
        base = mid * 16
        entries = struct.unpack("<8H", self.meta[base:base + 16])
        below = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        above = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        if lt == 1:      # COVERED
            self._blit(below, entries[0:4], 0)
            self._blit(below, entries[4:8], 0)
        elif lt == 2:    # SPLIT
            self._blit(below, entries[0:4], 0)
            self._blit(above, entries[4:8], 0)
        else:            # NORMAL
            self._blit(below, entries[0:4], 0)
            self._blit(above, entries[4:8], 0)
        return below, above

    def _blit(self, dest, entries, layer):
        ox = dest.load()
        for k in range(4):
            e = entries[k]
            pal_no = (e >> 12) & 0xF
            pal = self.pals.get(pal_no) or self.pals.get(0) or [(0, 0, 0)] * 16
            if pal_no not in self.pals and self.fallback is not None:
                pal = self.fallback.pals.get(pal_no) or self.fallback.pals.get(0) or pal
            tx = (k % 2) * 8
            ty = (k // 2) * 8
            px = self.tile_px(e)
            flipx = bool(e & 0x400)
            flipy = bool(e & 0x800)
            for y in range(8):
                for x in range(8):
                    v = px[y][x]
                    if v == 0:
                        continue
                    sx = 7 - x if flipx else x
                    sy = 7 - y if flipy else y
                    r, g, b = pal[v & 0xF]
                    ox[tx + sx, ty + sy] = (r, g, b, 255)

    def render(self, mid):
        """渲染一个 metatile 成 16x16 RGBA"""
        base = mid * 16
        entries = struct.unpack("<8H", self.meta[base:base + 16])
        out = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        ox = out.load()
        for layer in (0, 1):
            for k in range(4):
                e = entries[layer * 4 + k]
                pal_no = (e >> 12) & 0xF
                pal = self.pals.get(pal_no) or self.pals.get(0) or [(0, 0, 0)] * 16
                if pal_no not in self.pals and self.fallback is not None:
                    pal = self.fallback.pals.get(pal_no) or self.fallback.pals.get(0) or pal
                tx = (k % 2) * 8
                ty = (k // 2) * 8
                px = self.tile_px(e)
                flipx = bool(e & 0x400)
                flipy = bool(e & 0x800)
                for y in range(8):
                    for x in range(8):
                        v = px[y][x]
                        if layer == 1 and v == 0:
                            continue          # 顶层索引 0 透明
                        sx = 7 - x if flipx else x
                        sy = 7 - y if flipy else y
                        r, g, b = pal[v & 0xF]
                        ox[tx + sx, ty + sy] = (r, g, b, 255)
        return out


def build(primary_name, out_png, ids, report_path=None):
    ts = Tileset(os.path.join(BASE, "primary", primary_name))
    cols = len(ids)
    sheet = Image.new("RGBA", (cols * 16, 16), (0, 0, 0, 0))
    for i, mid in enumerate(ids):
        if mid >= ts.count:
            continue
        sheet.paste(ts.render(mid), (i * 16, 0))
    sheet.save(out_png)
    if report_path:
        json.dump({"primary": primary_name, "ids": ids}, open(report_path, "w"))
    print(out_png, sheet.size, "from", primary_name)


if __name__ == "__main__":
    # 冒烟测试：把 general 前 32 个 metatile 铺出来
    ts = Tileset(os.path.join(BASE, "primary", "general"))
    print("general metatiles:", ts.count, "palettes:", sorted(ts.pals.keys())[:5])
    sheet = Image.new("RGBA", (16 * 16, 2 * 16), (255, 0, 255, 255))
    for i in range(32):
        sheet.paste(ts.render(i), ((i % 16) * 16, (i // 16) * 16))
    sheet = sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST)
    sheet.save("/root/.openclaw/workspace/tmpimg/emerald_meta_test.png")
    print("saved test sheet")
