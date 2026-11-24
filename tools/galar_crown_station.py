"""The Crown Tundra railhead, Max Lair entrance and trail south to Freezington."""

from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw

from bake_emerald_field import pack
from kalos_gym_rooms import tile, sprite
from galar_expansion_ground import repaint

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "content/regions/crown/maps"
OUT = ROOT / "assets/galar/landmarks"


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")


def warp(cell, mid, landing, trigger=""):
    entry = {"at": cell, "to": {"region": "crown", "map": mid, "at": landing}}
    if trigger:
        entry["trigger"] = trigger
    return entry


def plan(mid, tiles, props):
    h, w = tiles.shape
    return {
        "s": [w, h],
        "t": pack(np.zeros((h, w), dtype="<u2")),
        "p": props,
        "scene": ["res://assets/galar/landmarks/" + mid + ".png", 0, 0],
    }


def fir():
    im = Image.new("RGBA", (29, 45))
    d = ImageDraw.Draw(im)
    d.rectangle((12, 30, 16, 43), fill="#7d6c60", outline="#50544d")
    for yy, width in ((27, 13), (18, 11), (10, 8), (4, 5)):
        x = 14
        p = [
            (x, yy - 3),
            (x - width // 2, yy + 3),
            (x - width, yy + 10),
            (x - 3, yy + 9),
            (x + 1, yy + 11),
            (x + 8, yy + 8),
            (x + width, yy + 9),
            (x + width // 2, yy + 2),
        ]
        d.polygon(p, fill="#58746a", outline="#465961")
        d.polygon(
            [
                (x, yy - 3),
                (x - width + 3, yy + 6),
                (x - 4, yy + 5),
                (x - 1, yy + 6),
                (x + 2, yy + 4),
                (x + 5, yy + 5),
            ],
            fill="#d4dfd2",
        )
        d.line((x - width + 3, yy + 8, x - 4, yy + 6), fill="#89a69a")
    im.save(OUT / "snow_fir.png", optimize=True)


def slope(cavern_art):
    mid = "crown_slippery"
    w, h = 41, 29
    y, x = np.mgrid[:h, :w]
    left = 3 + np.rint(2.0 * np.cos(y * 0.37)).astype(int)
    right = w - 3 - np.rint(2.0 * np.sin(y * 0.35)).astype(int)
    walls = ((x < left) | (x > right) | (y < 3) | (y >= h - 2)).astype("uint8")
    walls[22:, 19:23] = 0
    # Northern railway embankment and the hollow in the east-facing rock ridge.
    walls[4:7, 7:14] = 1
    walls[6:11, 27:32] = 1
    walls[8:11, 32:38] = 1
    pos = [
        (4, 7),
        (3, 14),
        (7, 18),
        (5, 22),
        (9, 25),
        (14, 25),
        (30, 23),
        (34, 18),
        (35, 15),
        (24, 5),
        (19, 5),
        (36, 22),
    ]
    props = []
    for xx, yy in pos:
        walls[yy, xx] = 1
        props.append(["res://assets/galar/landmarks/snow_fir.png", xx, yy, [14, 45]])
    props.append(["res://assets/galar/landmarks/max_lair.png", 29, 10, [50, 55]])
    # The canopy and clock borrow the railway silhouette used across Galar.
    station = Image.open(ROOT / "assets/switch_fields/props/station.png")
    props.append(
        [
            "res://assets/switch_fields/props/station.png",
            10,
            6,
            [station.width // 2, station.height],
        ]
    )
    warps = [
        warp([29, 11], "crown_max_lair", [14, 16], "door"),
        warp([21, h - 1], "crown_freezington", [17, 1]),
    ]
    m = {
        "name": "滑溜坡",
        "size": [w, h],
        "spawn": [10, 8],
        "style": "snow",
        "biome": "snow",
        "tiles": walls.tolist(),
        "warps": warps,
        "objects": [
            {
                "kind": "sign",
                "at": [12, 8],
                "text": "王冠雪原车站。往东是极巨巢穴，沿雪道向南可到冻凝村。",
            }
        ],
        "npcs": [],
        "hoenn_art": plan(mid, walls, props),
    }
    out = OUT / (mid + ".png")
    repaint(mid, m, out)
    im = Image.open(out).convert("RGB")
    d = ImageDraw.Draw(im)
    # Rails and ties run behind the canopy. The platform is accessible from below.
    for yy in (49, 66):
        for xx in range(2 * 16, 17 * 16, 9):
            d.rectangle((xx, yy - 4, xx + 2, yy + 5), fill="#8b735e")
        d.line((2 * 16, yy - 2, 17 * 16, yy - 2), fill="#58616b", width=2)
        d.line((2 * 16, yy + 3, 17 * 16, yy + 3), fill="#a8b4b3", width=2)
    for row in (7, 8):
        for xx in range(6, 12):
            col, rowp = xx * 16, row * 16
            d.rectangle((col, rowp, col + 15, rowp + 15), fill="#abaea2")
            d.line((col, rowp, col + 15, rowp), fill="#d9dacf")
            d.line((col, rowp, col, rowp + 14), fill="#939c92")
    pts = [(10, 8), (14, 11), (18, 13), (22, 13), (27, 12), (29, 11)]
    turns = [(18, 13), (17, 16), (18, 19), (22, 22), (21, 27)]
    for path in (pts, turns):
        for a, b in zip(path, path[1:]):
            ax, ay = a
            bx, by = b
            n = 2 * max(abs(ax - bx), abs(ay - by))
            for i in range(n):
                u = int((ax + (bx - ax) * i / n) * 16 + 7)
                v = int((ay + (by - ay) * i / n) * 16 + 9) + i % 2 * 3
                d.line((u, v, u + 2, v + 1), fill="#aebfc1", width=2)
    im.save(out, optimize=True)
    save(MAPS / (mid + ".json"), m)
    cavern_art.save(OUT / "max_lair.png", optimize=True)


def chamber():
    mid = "crown_max_lair"
    w, h = 29, 19
    y, x = np.mgrid[:h, :w]
    floor = (
        (x >= 3 + np.rint(np.sin(y * 0.65)).astype(int))
        & (x < 26 + np.rint(np.sin(y * 0.55)).astype(int))
        & (y >= 3)
        & (y < 17)
    )
    floor[16:, 13:16] = True
    walls = (~floor).astype("uint8")
    im = Image.new("RGB", (w * 16, h * 16))
    ground = np.asarray(tile("rockfloor")).astype(float)
    chip = Image.fromarray(
        np.uint8(np.clip(ground * [0.71, 0.83, 1.05] + [12, 15, 19], 0, 255))
    )
    for yy in range(h):
        for xx in range(w):
            im.paste(chip, (xx * 16, yy * 16))
    d = ImageDraw.Draw(im)
    for yy, xx in np.argwhere(~floor):
        p, q = xx * 16, yy * 16
        d.rectangle((p, q, p + 15, q + 15), fill="#43475c")
        if yy + 1 < h and floor[yy + 1, xx]:
            d.polygon(
                [
                    (p, q),
                    (p + 10, q + 3),
                    (p + 15, q),
                    (p + 15, q + 13),
                    (p + 7, q + 15),
                    (p, q + 11),
                ],
                fill="#787591",
                outline="#55536c",
            )
            d.line((p + 3, q + 3, p + 9, q + 5), fill="#9491a2")
    # The research station is lit at the mouth; the violet tunnel is the raid route.
    d.polygon(
        [(12 * 16, 49), (13 * 16, 22), (15 * 16, 13), (17 * 16, 24), (18 * 16, 48)],
        fill="#6d6084",
        outline="#9991a7",
        width=3,
    )
    d.polygon(
        [(13 * 16, 50), (14 * 16, 27), (15 * 16, 24), (16 * 16, 30), (17 * 16, 49)],
        fill="#3a394e",
    )
    for xx, yy in ((4, 7), (5, 8), (23, 5), (24, 5), (23, 13)):
        px, py = xx * 16, yy * 16
        d.polygon(
            [
                (px + 2, py + 10),
                (px + 4, py - 3),
                (px + 8, py - 7),
                (px + 11, py + 6),
                (px + 9, py + 12),
            ],
            fill="#a78fae",
            outline="#716782",
        )
        d.line((px + 5, py + 6, px + 8, py - 4), fill="#d7b6cb", width=2)
        walls[yy, xx] = 1
    props = []
    for key, xx, yy in (
        ("desk", 10, 8),
        ("pc", 9, 8),
        ("crate", 6, 12),
        ("crate", 7, 12),
        ("carebench", 20, 11),
    ):
        if key == "crate":
            art = Image.open(ROOT / "assets/switch_fields/props/crate.png")
            asset = "res://assets/switch_fields/props/crate.png"
        else:
            art = sprite(key)
            asset = key
        props.append([asset, xx, yy, [art.width // 2, art.height]])
        walls[yy, xx] = 1
    for i in range(6):
        x0 = (13 + i % 2) * 16 + 8
        y0 = (14 - i) * 16 + 6
        d.line((x0, y0, x0 + 4, y0 + 2), fill="#bba49d", width=2)
    # Mark the southern threshold so returning to the slope doesn't require guessing.
    for i in range(3):
        d.line(
            (13 * 16, 18 * 16 + i * 3, 16 * 16 - 1, 18 * 16 + i * 3),
            fill="#aba398",
            width=2,
        )
    im.save(OUT / (mid + ".png"), optimize=True)
    m = {
        "name": "极巨巢穴・调查营地",
        "size": [w, h],
        "spawn": [14, 16],
        "style": "interior",
        "biome": "cave",
        "tiles": walls.tolist(),
        "warps": [warp([14, 18], "crown_slippery", [29, 12], "down")],
        "objects": [],
        "npcs": [
            {
                "at": [11, 9],
                "name": "研究员",
                "gfx": "scientist",
                "lines": ["为免极巨粒子影响随行队伍，深入巢穴前请向我们借宝可梦。"],
            }
        ],
        "hoenn_art": plan(mid, walls, props),
    }
    save(MAPS / (mid + ".json"), m)


def build(cavern_art):
    fir()
    slope(cavern_art)
    chamber()
    registry = MAPS.parent / "region.json"
    r = json.loads(registry.read_bytes())
    for mid in ("crown_slippery", "crown_max_lair"):
        if mid not in r["maps"]:
            r["maps"].append(mid)
    registry.write_text(json.dumps(r, ensure_ascii=False, indent=1) + "\n")
    path = MAPS / "crown_freezington.json"
    v = json.loads(path.read_bytes())
    v["warps"] = [w for w in v["warps"] if w["to"]["map"] != "crown_slippery"]
    v["warps"].append(warp([17, 0], "crown_slippery", [21, 27]))
    v["tiles"][0][17] = 0
    sign = {"kind": "sign", "at": [18, 2], "text": "向北沿雪道去滑溜坡和王冠雪原车站。"}
    v["objects"] = [o for o in v["objects"] if o.get("text") != sign["text"]] + [sign]
    save(path, v)
    ground = ROOT / v["hoenn_art"]["scene"][0].removeprefix("res://")
    image = Image.open(ground).convert("RGB")
    d = ImageDraw.Draw(image)
    for y in range(5 * 16):
        x = 17 * 16 + 8 + (y // 13) % 2
        d.line((x - 8, y, x + 7, y), fill="#c7d3d0")
        if y % 6 == 2:
            d.line(
                (x - 3 + (y // 6) % 2 * 4, y, x - 1 + (y // 6) % 2 * 4, y),
                fill="#95abb1",
                width=2,
            )
    image.save(ground, optimize=True)
    snowpass = json.loads((MAPS / "crown_slope.json").read_bytes())
    repaint(
        "crown_slope",
        snowpass,
        ROOT / snowpass["hoenn_art"]["scene"][0].removeprefix("res://"),
    )
