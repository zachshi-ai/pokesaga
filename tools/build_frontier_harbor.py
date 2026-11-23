#!/usr/bin/env python3
"""Adapt the Emerald Battle Tower and Slateport wharves to the legacy island's four arrival cells."""

import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import Emerald, pack

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/frontier_port"
MAPS = ROOT / "content/regions/frontier/maps"
L = "BattleFrontier_BattleTowerLobby"
T = "BattleFrontier_OutsideEast"
S = "SlateportCity"


def chip(e, layout, x, y):
    return e.metatile(layout, int(e.grid(layout)[y, x])).convert("RGB")


def store(mid, im, grid, props, signs=None):
    p = MAPS / (mid + ".json")
    m = json.loads(p.read_bytes())
    if signs is not None:
        m["objects"] = signs
    if mid == "tower_lobby":
        for npc in m["npcs"]:
            npc["field_art"] = "clerk"
    w, h = m["size"]
    assert (w * 16, h * 16) == im.size
    img = OUT / (mid + ".png")
    im.save(img, optimize=True)
    m.update(
        tiles=grid.tolist(),
        hoenn_art={
            "s": [w, h],
            "t": pack(np.zeros((h, w), dtype="<u2")),
            "p": props,
            "scene": ["res://" + str(img.relative_to(ROOT)), 0, 0],
        },
    )
    p.write_text(json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n")


def harbor(e):
    w, h = 28, 20
    im = Image.new("RGB", (16 * w, 16 * h))
    grid = np.full((h, w), 2, dtype=np.uint8)
    shore = Image.new("1", (w, h))
    draw = ImageDraw.Draw(shore)
    draw.polygon(
        [
            (5, 0),
            (24, 0),
            (24, 2),
            (19, 3),
            (14, 3),
            (14, 5),
            (16, 6),
            (20, 6),
            (22, 8),
            (22, 10),
            (20, 12),
            (20, 14),
            (18, 16),
            (9, 16),
            (7, 14),
            (4, 12),
            (4, 9),
            (6, 7),
            (7, 5),
            (5, 4),
        ],
        fill=1,
    )
    land = np.array(shore, dtype=bool)
    land[3:6, 17:] = False
    land[6, 19:] = False
    grid[land] = 0
    sea = e.metatile("LittlerootTown", 0xA1).convert("RGB")
    promenade = chip(e, T, 12, 21)
    turf = e.metatile("LittlerootTown", 1).convert("RGB")
    quay = chip(e, S, 28, 40)
    stone = chip(e, S, 34, 33)
    d = ImageDraw.Draw(im)
    for y in range(h):
        for x in range(w):
            if not land[y, x]:
                im.paste(sea, (x * 16, y * 16))
                n = (x * 37 + y * 17) % 29
                if n < 5:
                    d.line(
                        (
                            x * 16 + 2,
                            y * 16 + 5 + n,
                            x * 16 + 6,
                            y * 16 + 6 + n,
                            x * 16 + 9,
                            y * 16 + 5 + n,
                        ),
                        fill="#a9d4df",
                    )
            else:
                tile = (
                    turf if (x < 10 and 6 < y < 14 or x > 16 and y > 7) else promenade
                )
                im.paste(tile, (x * 16, y * 16))
                if y < h - 1 and not land[y + 1, x]:
                    d.rectangle(
                        (x * 16, y * 16 + 12, x * 16 + 15, y * 16 + 15), fill="#768b94"
                    )
                    d.line(
                        (x * 16, y * 16 + 11, x * 16 + 15, y * 16 + 11), fill="#d7d7bf"
                    )
                for dx in (-1, 1):
                    if 0 <= x + dx < w and not land[y, x + dx]:
                        a = x * 16 + (15 if dx > 0 else 0)
                        d.line((a, y * 16, a, y * 16 + 15), fill="#97a9a8", width=2)

    def pad(x1, y1, x2, y2, tile):
        for y in range(y1, y2 + 1):
            for x in range(x1, x2 + 1):
                im.paste(tile, (x * 16, y * 16))
                grid[y, x] = 0

    # The original tower door is at (16,14); the harbor meets it from the south.
    tower = e.patch(T, 8, 13, 17, 4).convert("RGB")
    for yy in range(4):
        for xx in range(17):
            if land[yy, xx + 6]:
                im.paste(
                    tower.crop((xx * 16, yy * 16, xx * 16 + 16, yy * 16 + 16)),
                    ((xx + 6) * 16, yy * 16),
                )
    grid[0:2, 6:23] = 1
    grid[1, 14] = 0
    # The two boarding positions preserve the ferry journey's old coordinates.
    pad(13, 3, 14, 15, quay)
    pad(14, 4, 17, 4, stone)
    pad(11, 14, 17, 16, stone)
    pad(11, 17, 16, 17, stone)
    pad(5, 8, 10, 8, quay)
    pad(6, 8, 6, 8, chip(e, T, 13, 17))
    # Put the golden Battle Frontier symbol in front of the tower door.
    im.paste(e.patch(T, 15, 15, 3, 2).convert("RGB"), (13 * 16, 2 * 16))
    grid[2:4, 13:16] = 0
    # Reuse Slateport's flowerbed kerbs, warning signs and bollards separately from its buildings.
    bollard = chip(e, S, 34, 34)
    for x, y in [(11, 14), (17, 14), (11, 17), (16, 17), (16, 4)]:
        if (x, y) in [(16, 4)]:
            continue
        im.paste(bollard, (x * 16, y * 16))
        grid[y, x] = 1
    props = []
    for key, x, y in [
        ("tree", 8, 7),
        ("tree", 9, 13),
        ("tree", 6, 12),
        ("planter", 19, 10),
        ("flowers", 17, 8),
        ("flowers", 18, 9),
        ("sign", 10, 6),
        ("sign", 12, 14),
        ("sign", 8, 9),
        ("streetlamp", 16, 7),
    ]:
        props.append([key, x, y])
        grid[y, x] = 1
    # A covered loading shed uses the real shipyard roof. The central walking lane remains clear.
    shed = (
        e.patch(S, 24, 32, 8, 8)
        .convert("RGB")
        .resize((64, 64), Image.Resampling.NEAREST)
    )
    im.paste(shed, (8 * 16, 10 * 16))
    grid[10:14, 8:12] = 1

    # Clamp the visible hull silhouette to the water; the gangplank ends alongside it.
    def boat(name, x, y, frame=None):
        donor = Image.open(
            e.source / "graphics/object_events/pics/misc" / (name + ".png")
        )
        donor = donor if frame is None else donor.crop(frame)
        spr = donor.convert("RGBA")
        spr.putalpha(
            Image.fromarray(np.where(np.array(donor) == 0, 0, 255).astype("uint8"))
        )
        im.paste(spr, (x, y), spr)
        for yy in range(max(0, y // 16), min(h, (y + spr.height + 15) // 16)):
            for xx in range(max(0, x // 16), min(w, (x + spr.width + 15) // 16)):
                if (
                    grid[yy, xx] == 2
                    and spr.getchannel("A")
                    .crop(
                        (xx * 16 - x, yy * 16 - y, xx * 16 - x + 16, yy * 16 - y + 16)
                    )
                    .getbbox()
                ):
                    grid[yy, xx] = 1

    boat("ss_tidal", 17 * 16 + 3, 3 * 16 + 4)
    boat("mr_brineys_boat", 14 * 16 + 3, 18 * 16, (64, 0, 96, 32))
    # Pier labels live on the permanent harbour signs so boarding cells don't look like anonymous floor.
    for x, y in [(14, 4), (14, 17), (6, 8)]:
        d.rectangle(
            (x * 16 + 3, y * 16 + 5, x * 16 + 12, y * 16 + 12),
            fill="#cbab61",
            outline="#84794f",
        )
        d.polygon(
            [
                (x * 16 + 5, y * 16 + 8),
                (x * 16 + 9, y * 16 + 8),
                (x * 16 + 7, y * 16 + 11),
            ],
            fill="#f4e9af",
        )
    signs = [
        {"kind": "sign", "at": [10, 6], "text": "北边的蓝色塔门通往对战塔大厅。"},
        {
            "kind": "sign",
            "at": [12, 14],
            "text": "南栈桥去未白镇，北侧的联络船去枯叶港。",
        },
        {"kind": "sign", "at": [8, 9], "text": "向西走到海堤，沿堤可以前往武斗岛。"},
    ]
    store("harbor", im, grid, props, signs)


def lobby(e):
    w, h = 18, 16
    im = Image.new("RGB", (w * 16, h * 16))
    g = np.zeros((h, w), dtype=np.uint8)
    g[:, [0, -1]] = 1
    g[[0, -1], :] = 1
    floor = chip(e, L, 11, 7)
    for y in range(h):
        for x in range(w):
            im.paste(floor, (x * 16, y * 16))
    # Tile the original steel fascia, then put each reception recess around its stored actor cell.
    for x in range(w):
        im.paste(chip(e, L, 4, 0), (x * 16, 0))
    for x in (3, 9, 13):
        im.paste(e.patch(L, 4, 2, 4, 5).convert("RGB"), ((x - 2) * 16, 0))
        g[0:4, x - 2 : x + 2] = 1
        g[3, x] = 0
        g[4, x] = 0
    # The source hall uses dark blue seams to lead visitors from the entrance rug to the desks.
    stripe = chip(e, L, 6, 8)
    for x in range(1, w - 1):
        im.paste(stripe, (x * 16, 9 * 16))
    for y in range(5, 15):
        im.paste(stripe, (9 * 16, y * 16))
    for x in (0, w - 2):
        im.paste(e.patch(L, 0, 8, 2, 2).convert("RGB"), (x * 16, 13 * 16))
        g[14, x : x + 2] = 1
    im.paste(e.patch(L, 12, 9, 2, 1).convert("RGB"), (9 * 16, 15 * 16))
    g[15, 9] = 0
    props = [
        ["carebench", 3, 8],
        ["carebench", 3, 11],
        ["carebench", 15, 8],
        ["carebench", 15, 11],
        ["plant_indoor", 1, 7],
        ["plant_indoor", 16, 7],
    ]
    for k, x, y in props:
        g[y, x] = 1
        g[y, x - 1] = 1 if k == "carebench" else g[y, x - 1]
    store("tower_lobby", im, g, props)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("emerald", type=Path)
    e = Emerald(p.parse_args().emerald)
    OUT.mkdir(exist_ok=True, parents=True)
    harbor(e)
    lobby(e)
