"""Fit Castelia's GBA waterfront to the original BW and B2 rail exits."""

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

# Both editions use the same zone numbers along the curved harbour. Street and
# pier pairings come from the four original guide signs in castelia_city.s.
LABELS = {
    30: "中央广场",
    31: "道馆街",
    32: "北街",
    33: "时尚街",
    34: "飞云街",
    35: "窄巷",
    36: "自由码头",
    37: "联合码头",
    38: "第一码头",
    39: "游览船码头",
    40: "拇指码头",
    42: "擦肩调查队总部",
    43: "飞云画室",
    44: "对战公司一楼",
}
SIGNS = {
    31: "道馆街　／　海侧通往自由码头",
    33: "时尚街　／　海侧通往第一码头",
    34: "飞云街　／　海侧通往游览船码头",
    35: "窄巷　／　海侧通往联合码头",
    36: "自由码头",
    37: "联合码头",
    38: "第一码头",
    39: "游览船码头",
    40: "拇指码头",
    41: "宝可梦中心",
    42: "擦肩调查队总部",
    44: "对战公司",
}
STREETS = (31, 33, 34, 35)
DOCKS = (36, 37, 38, 39, 40)
PAVERS = (
    "harbor_flagstone",
    "harbor_speckle",
    "towpath",
    "street_inlay",
    "quay_planks",
    "city_blocks",
)


def paving(key):
    base = {
        "harbor_flagstone": ("#baada0", "#ad9f93", "#cbc2ad"),
        "harbor_speckle": ("#c0b19d", "#ad9f93", "#cec2ae"),
        "towpath": ("#8d827c", "#70686a", "#aba296"),
        "street_inlay": ("#938d88", "#746d73", "#ddcfb3"),
        "quay_planks": ("#bd966c", "#816b5c", "#dbb584"),
        "city_blocks": ("#9bada3", "#7f948f", "#adbcaa"),
    }
    color, shade, light = base[key]
    im = Image.new("RGBA", (16, 16), color)
    p = ImageDraw.Draw(im)
    if key == "quay_planks":
        for y in (0, 5, 10, 15):
            p.line((0, y, 15, y), fill=shade)
            p.line((0, y + 1, 15, y + 1), fill=light)
        for x, y in ((2, 3), (12, 7), (6, 13)):
            p.line((x, y, x + 2, y), fill=shade)
    else:
        for x, y in ((1, 1), (12, 11), (6, 7)):
            p.point((x, y), fill=light)
        for y, x in ((0, 5), (8, 13)):
            p.line((0, y, 15, y), fill=shade)
            p.line((x, y, x, y + 7), fill=shade)
            p.line((x + 1, y + 1, x + 4, y + 1), fill=light)
        if key == "street_inlay":
            p.rectangle((2, 0, 4, 15), fill="#695e62")
            p.rectangle((3, 0, 4, 15), fill="#ead9ae")
            p.rectangle((12, 0, 14, 15), fill="#695e62")
            p.rectangle((12, 0, 13, 15), fill="#ead9ae")
    return im


def number(warp):
    name = warp["to"]["map"]
    tail = name.rsplit("_", 1)[-1]
    return (
        int(tail)
        if name.startswith(("unova_bw_zone_", "unova_b2_zone_")) and tail.isdecimal()
        else -1
    )


def inside(walk, x, y):
    return 0 <= x < walk.shape[1] and 0 <= y < walk.shape[0]


def harbour(doc, tiles, walk, props, index, tower):
    from unova_art import ROOT

    h, w = walk.shape
    coords = {(int(x), int(y)) for y, x in np.argwhere(walk)}
    # Land is on the *inside* of the peninsula. Its coast is traced from the
    # outermost walkable point in each original rail column. Keep the western
    # and eastern wharves outside, and give the city a hinterland to its north.
    coast = np.zeros_like(walk)
    for x in range(20, w):
        ys = np.flatnonzero(walk[:, x])
        if len(ys):
            coast[: ys[-1] + 1, x] = True
    apron = ndimage.binary_dilation(walk, iterations=2)
    seawall = ndimage.binary_dilation(walk, iterations=3)
    tiles[seawall & ~coast] = index["seawall"]
    tiles[coast] = index["city_blocks"]
    tiles[apron & ~walk] = index["quay"]
    y, x = np.indices(walk.shape)
    tiles[walk] = np.where(
        (x // 3 + 2 * (y // 3)) % 5 == 0,
        index["harbor_speckle"],
        index["harbor_flagstone"],
    )[walk]
    tiles[walk & ~ndimage.binary_erosion(walk)] = index["towpath"]
    ends = {tuple(v["at"]) for v in doc["warps"]}
    avoid = ends | {
        tuple(obj["at"])
        for obj in [*doc["objects"], *doc["npcs"]]
        if not obj.get("castelia_board")
    }
    doc["objects"] = [obj for obj in doc["objects"] if not obj.get("castelia_board")]
    approach = coords - ends
    signs = set()
    facades = set()
    # The city spline has two native entrances for several streets. Mark every
    # actual transition underfoot, even when the second entry is several metres away.
    for warp in doc["warps"]:
        n = number(warp)
        if n not in SIGNS:
            continue
        xx, yy = warp["at"]
        tiles[yy, xx] = index["quay_planks" if n in DOCKS else "street_inlay"]
        if n in DOCKS:
            for y1 in range(max(0, yy - 1), min(h, yy + 2)):
                for x1 in range(max(0, xx - 1), min(w, xx + 2)):
                    if walk[y1, x1]:
                        tiles[y1, x1] = index["quay_planks"]
        elif n in STREETS:
            # Street mouths continue through the inland block beyond the step trigger.
            dx, dy = {31: (1, 0), 33: (0, -1), 34: (-1, 0), 35: (1, 0)}[n]
            for step in range(1, 5):
                x1, y1 = xx + step * dx, yy + step * dy
                if inside(walk, x1, y1) and not walk[y1, x1]:
                    tiles[y1, x1] = index["towpath"]
        if n in signs:
            continue
        candidates = []
        for y1 in range(yy - 3, yy + 4):
            for x1 in range(xx - 3, xx + 4):
                if not inside(walk, x1, y1) or (x1, y1) in avoid or walk[y1, x1]:
                    continue
                if any(
                    (x1 + dx, y1 + dy) in approach
                    for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1))
                ):
                    distance = abs(x1 - xx) + abs(y1 - yy)
                    candidates.append((distance, y1 > yy, abs(x1 - xx), y1, x1))
        if candidates:
            _, _, _, y1, x1 = min(candidates)
            avoid.add((x1, y1))
            signs.add(n)
            doc["objects"].append(
                {
                    "kind": "sign",
                    "at": [x1, y1],
                    "text": SIGNS[n],
                    "castelia_board": True,
                }
            )
            props.append(["sign", x1, y1])
        if n in (41, 44):
            if n == 41:
                uri = "res://assets/unova/facades/center_64.png"
                with Image.open(ROOT / uri[6:]) as img:
                    anchor = [24, img.height]
            else:
                uri, anchor = tower("low")
            # Both original south-facing entrances sit below an inland block.
            if not walk[yy - 1, xx]:
                props.append([uri, xx, yy - 1, anchor])
                facades.add((xx, yy - 1))
    # Set solid skyline blocks back from the walk plane. Use the signed inland
    # direction so the view from any street mouth has buildings on the city side.
    occupied = avoid | facades
    for row, x1 in enumerate(range(22, w - 3, 5)):
        ys = np.flatnonzero(walk[:, x1])
        if not len(ys):
            continue
        inland = [
            n
            for n in range(int(ys[-1]) - 3, 1, -1)
            if coast[n, x1]
            and not walk[max(0, n - 1) : n + 1, x1 - 2 : x1 + 3].any()
            and all(abs(x1 - sx) > 3 or abs(n - sy) > 3 for sx, sy in occupied)
        ]
        if not inland:
            continue
        y1 = inland[0]
        uri, anchor = tower(("tall", "corner", "mid", "low")[row % 4])
        props.append([uri, x1, y1, anchor])
        occupied.add((x1, y1))
    for y1, x1 in np.argwhere(apron & ~walk):
        if (
            (x1 + 3 * y1) % 19 == 0
            and all(abs(x1 - sx) + abs(y1 - sy) > 3 for sx, sy in occupied)
            and (x1, y1 + 1) in coords
        ):
            props.append(["streetlamp", int(x1), int(y1)])
