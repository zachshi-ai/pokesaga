#!/usr/bin/env python3
"""从原版地图里把建筑（房子 / 宝可梦中心 / 道馆）切成可复用的预制件。

原理：
  1. 解析 metatile_attributes.bin，拿到每个 metatile 的 behavior（门是 MB_*_DOOR）
  2. 在地图上找到门所在的格
  3. 从门上方那一格做"阻挡块"洪水填充，取包围盒 —— 这就是这栋建筑的完整外框
  4. 把这块矩形的 metatile、渲染图、碰撞表、门位置一起存成 prefab

以后要在别的城镇放一栋房子，直接贴 prefab，不用再拼瓦片。
"""
from asset_paths import project_path, source_path

import json, os, struct, glob
from PIL import Image

ROOT = source_path("emerald")
EMAPS = project_path("content/emerald_maps")
OUT = project_path("content/prefabs")

import sys
sys.path.insert(0, project_path("tools"))
from emerald_tiles import Tileset

PRIMARY = {}
SECONDARY = {}
for kind, table in (("primary", PRIMARY), ("secondary", SECONDARY)):
    d = os.path.join(ROOT, "data/tilesets", kind)
    for name in os.listdir(d):
        if os.path.isdir(os.path.join(d, name)) and os.path.exists(os.path.join(d, name, "metatiles.bin")):
            table["".join(ch for ch in name.lower() if ch.isalnum())] = os.path.join(d, name)


def norm(x):
    return "".join(ch for ch in x.lower() if ch.isalnum())


def behaviors():
    """解析 behavior 枚举，隐式值按出现顺序数"""
    vals = {}
    n = 0
    for line in open(os.path.join(ROOT, "include/constants/metatile_behaviors.h"), errors="ignore"):
        ln = line.split("//")[0].strip()
        if not ln.startswith("MB_"):
            continue
        name = ln.rstrip(",")
        if name.startswith("MB_"):
            vals[name] = n
            n += 1
    return vals


_c = {}


def get_ts(name, fallback=None):
    key = norm(name.replace("gTileset_", ""))
    path = PRIMARY.get(key) or PRIMARY.get(key + "frlg") or SECONDARY.get(key) or SECONDARY.get(key + "frlg")
    if not path:
        return None
    if path not in _c:
        _c[path] = Tileset(path, fallback=fallback)
        if fallback is not None:
            _c[path].base_tiles = fallback.cols * (fallback.h // 8)
    elif fallback is not None and _c[path].fallback is None:
        _c[path].fallback = fallback
        _c[path].base_tiles = fallback.cols * (fallback.h // 8)
    return _c[path]


def door_behaviors(bh):
    want = ["MB_NON_ANIMATED_DOOR", "MB_ANIMATED_DOOR", "MB_ANIMATED_DOOR_WARP",
            "MB_DOOR", "MB_EAST_ARROW_WARP", "MB_WEST_ARROW_WARP"]
    return {bh[k] for k in want if k in bh}


def behavior_at(ts, local_mid):
    path = os.path.join(ts.path, "metatile_attributes.bin")
    if not os.path.exists(path):
        return -1
    d = open(path, "rb").read()
    if (local_mid + 1) * 2 > len(d):
        return -1
    return struct.unpack_from("<H", d, local_mid * 2)[0] & 0xFF


def bbox_from(col, sx, sy, limit=260):
    """从 (sx,sy) 出发找阻挡连通块，返回矩形包围盒"""
    h = len(col)
    w = len(col[0])
    if not (0 <= sx < w and 0 <= sy < h) or col[sy][sx] == 0:
        return None
    seen = {(sx, sy)}
    stack = [(sx, sy)]
    minx = maxx = sx
    miny = maxy = sy
    while stack and len(seen) < limit:
        x, y = stack.pop()
        minx, maxx = min(minx, x), max(maxx, x)
        miny, maxy = min(miny, y), max(maxy, y)
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and 0 <= ny < h):
                continue
            if (nx, ny) in seen or col[ny][nx] == 0:
                continue
            seen.add((nx, ny))
            stack.append((nx, ny))
    return [minx, miny, maxx, maxy]


def building_box(col, dx, dy, w, h, max_h=6, max_w=14):
    """以门为锚点向上、向左右扩，切出建筑正面矩形。
    这样切出来的边缘是建筑自己的轮廓，不带周围的草地和树。"""
    # 向上：连续阻挡行
    top = dy
    for y in range(dy, max(-1, dy - max_h - 1), -1):
        if y < 0 or col[y][dx] == 0:
            break
        top = y
    if top == dy:
        return None
    # 左右：在最宽的一行（通常是屋檐那行）找连续阻挡
    left = dx
    right = dx
    for y in (top, min(top + 1, dy)):
        l = dx
        while l - 1 >= 0 and col[y][l - 1] != 0:
            l -= 1
        r = dx
        while r + 1 < w and col[y][r + 1] != 0:
            r += 1
        left = min(left, l)
        right = max(right, r)
    # 底行必须是"建筑基线"：门这一行的两侧立刻可走，说明切到轮廓了
    if left == right:
        return None
    bw = right - left + 1
    bh = dy - top + 1
    if bw < 3 or bh < 2 or bw > max_w or bh > max_h:
        return None
    return [left, top, right, dy]


def extract(map_name, meta):
    """返回这张图里的建筑 prefab 列表"""
    lay = meta["layout"]
    prim = get_ts(lay["primary_tileset"])
    sec = get_ts(lay["secondary_tileset"], fallback=prim)
    if not prim or not sec:
        return []
    bh = behaviors()
    doors = door_behaviors(bh)
    blockdata = open(os.path.join(ROOT, lay["blockdata_filepath"]), "rb").read()
    w, h = meta["size"]
    col = meta["collision"]
    pc = prim.count

    found = []
    for y in range(h):
        for x in range(w):
            val = struct.unpack_from("<H", blockdata, (y * w + x) * 2)[0]
            mid = val & 0x3FF
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            b = behavior_at(ts, local)
            if b in doors:
                bb = building_box(col, x, y, w, h)
                if bb:
                    found.append({"door": [x, y], "box": bb})
    # 合并重叠的建筑（同一个连通块可能识别出多个门）
    merged = []
    for f in found:
        dup = False
        for m in merged:
            if not (f["box"][2] < m["box"][0] or f["box"][0] > m["box"][2]
                    or f["box"][3] < m["box"][1] or f["box"][1] > m["box"][3]):
                dup = True
                break
        if not dup:
            merged.append(f)
    return merged


def save_prefab(map_name, meta, item, idx):
    x0, y0, x1, y1 = item["box"]
    w = x1 - x0 + 1
    h = y1 - y0 + 1
    if w < 3 or h < 2 or w > 14 or h > 12:
        return None
    lay = meta["layout"]
    prim = get_ts(lay["primary_tileset"])
    sec = get_ts(lay["secondary_tileset"], fallback=prim)
    blockdata = open(os.path.join(ROOT, lay["blockdata_filepath"]), "rb").read()
    mw, mh = meta["size"]
    pc = prim.count
    png = Image.new("RGBA", (w * 16, h * 16), (0, 0, 0, 0))
    metas = []
    col = []
    for y in range(y0, y1 + 1):
        row = []
        crow = []
        for x in range(x0, x1 + 1):
            val = struct.unpack_from("<H", blockdata, (y * mw + x) * 2)[0]
            mid = val & 0x3FF
            row.append(mid)
            crow.append(meta["collision"][y][x])
            ts = prim if mid < pc else sec
            local = mid if mid < pc else mid - pc
            try:
                png.paste(ts.render(local), ((x - x0) * 16, (y - y0) * 16))
            except Exception:
                pass
        metas.append(row)
        col.append(crow)
    name = "%s_%d" % (map_name, idx)
    os.makedirs(OUT, exist_ok=True)
    png.save(os.path.join(OUT, name + ".png"))
    data = {
        "id": name,
        "from": map_name,
        "size": [w, h],
        "metatiles": metas,
        "collision": col,
        "door": [item["door"][0] - x0, item["door"][1] - y0],
        "primary": lay["primary_tileset"],
        "secondary": lay["secondary_tileset"],
    }
    json.dump(data, open(os.path.join(OUT, name + ".json"), "w"), separators=(",", ":"))
    return name, w, h


def main():
    for f in sorted(glob.glob(os.path.join(EMAPS, "*.json"))):
        meta = json.load(open(f))
        name = os.path.basename(f)[:-5]
        items = extract(name, meta)
        made = 0
        for i, it in enumerate(items):
            r = save_prefab(name, meta, it, i)
            if r:
                made += 1
                print("prefab", r)
        print(name, "buildings", len(items), "saved", made)


if __name__ == "__main__":
    main()
