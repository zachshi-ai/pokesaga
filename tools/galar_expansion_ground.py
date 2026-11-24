"""Paint the approach to the two training towers, Max Lair and Crown Shrine."""

from pathlib import Path
from random import Random

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from kalos_gym_rooms import tile


def repaint(map_id, data, out):
    tiles = np.asarray(data["tiles"])
    water = tiles == 2
    h, w = tiles.shape
    outside = tiles == 1
    # Only masses connected to the perimeter are terrain. Furniture footprints
    # and the tower foundation already have their own art.
    border = np.zeros_like(outside)
    border[[0, -1]] = outside[[0, -1]]
    border[:, [0, -1]] = outside[:, [0, -1]]
    hills = ndimage.binary_propagation(border, mask=outside)
    shore = map_id == "armor_water_tower"
    snow = map_id.startswith("crown")
    rng = Random(157)
    grass = np.asarray(tile("grass")).astype(int)
    sand = np.asarray(tile("sand")).astype(int)
    tall = np.asarray(tile("tall")).astype(int)
    rock = np.asarray(tile("rockfloor")).astype(int)
    colors = {
        "down": grass * [1.10, 0.90, 0.67] + [9, 0, 3],
        "meadow": grass * [1.02, 0.96, 0.77] + [10, 0, 0],
        "grass": tall * [1.04, 0.93, 0.76] + [12, 0, 0],
        "sand": sand * [1.0, 0.98, 1.1] + [4, 4, 6],
        "scree": rock * [0.87, 0.91, 0.88] + [19, 22, 21],
        "shelf": rock * [1.1, 1.14, 1.19] + [16, 20, 22],
        "snow": np.asarray(tile("snow")) * [0.38, 0.38, 0.36] + [153, 142, 138],
        "ice": np.asarray(tile("snow")) * [0.4, 0.4, 0.4] + [129, 127, 126],
    }
    chips = {
        k: Image.fromarray(np.clip(a, 0, 255).astype("uint8"))
        for k, a in colors.items()
    }
    im = Image.new("RGB", (w * 16, h * 16))
    dist = ndimage.distance_transform_edt(~water)
    sea_depth = ndimage.distance_transform_edt(water)
    for y in range(h):
        for x in range(w):
            if water[y, x]:
                color = (
                    "#72b5bc"
                    if sea_depth[y, x] < 2
                    else "#5795ac"
                    if sea_depth[y, x] < 4
                    else "#47859e"
                )
                d = ImageDraw.Draw(im)
                d.rectangle((16 * x, 16 * y, 16 * x + 15, 16 * y + 15), fill=color)
                if rng.randrange(3) == 0:
                    ax = x * 16 + rng.randint(1, 7)
                    ay = y * 16 + rng.randint(3, 12)
                    d.line(
                        [(ax, ay), (ax + 3, ay), (ax + 5, ay - 1), (ax + 8, ay - 1)],
                        fill="#84c7c6",
                    )
                continue
            if hills[y, x] and (snow or not shore):
                k = "shelf" if snow else "scree"
            elif tiles[y, x] == 11:
                k = "grass"
            elif snow:
                k = (
                    "ice"
                    if hills[max(0, y - 1), x] or (x + 2 * y) % 13 == 0
                    else "snow"
                )
            elif shore:
                k = "sand" if dist[y, x] < 8 or y >= 10 else "meadow"
            else:
                k = "down"
            chip = chips[k]
            if (x * 13 + y * 17) % 5 == 0:
                chip = chip.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            im.paste(chip, (x * 16, y * 16))
    d = ImageDraw.Draw(im)
    for y, x in np.argwhere(water):
        px, py = x * 16, y * 16
        for dx, dy, edge in [
            (0, -1, [(px, py), (px + 4, py + 1), (px + 10, py + 1), (px + 15, py)]),
            (
                0,
                1,
                [
                    (px, py + 15),
                    (px + 5, py + 14),
                    (px + 11, py + 15),
                    (px + 15, py + 15),
                ],
            ),
            (-1, 0, [(px, py), (px + 1, py + 6), (px, py + 11), (px, py + 15)]),
            (
                1,
                0,
                [
                    (px + 15, py),
                    (px + 14, py + 5),
                    (px + 15, py + 10),
                    (px + 15, py + 15),
                ],
            ),
        ]:
            xx, yy = x + dx, y + dy
            if 0 <= xx < w and 0 <= yy < h and not water[yy, xx]:
                d.line(edge, fill="#edf0d2", width=2)
                d.line([(a - dx * 2, b - dy * 2) for a, b in edge], fill="#a4d4ca")
    for y, x in np.argwhere(hills):
        if y + 1 < h and not hills[y + 1, x]:
            px, py = x * 16, y * 16 + 13
            d.line(
                [(px, py), (px + 4, py + 1), (px + 11, py), (px + 15, py + 1)],
                fill="#eff3e5" if snow else "#c9c297",
                width=2,
            )
            d.line((px, py + 2, px + 15, py + 2), fill="#839198" if snow else "#8a8167")
    if map_id == "armor_towers":
        # The access path comes from Challenge Road at the top, turning onto the
        # tower forecourt. Its floor is distinct from the wild grass at the ridge.
        trail = [(17, 0), (17, 3), (18, 5), (18, 9), (17, 11), (14, 11), (12, 10)]
        points = [(x * 16 + 8, y * 16 + 10) for x, y in trail]
        mask = Image.new("1", im.size)
        md = ImageDraw.Draw(mask)
        md.line(points, fill=1, width=27, joint="curve")
        base = im.copy()
        for y in range(h):
            for x in range(w):
                if tiles[y, x] not in (0,):
                    continue
                base.paste(chips["sand"], (x * 16, y * 16))
        im.paste(base, (0, 0), mask)
    if map_id == "armor_water_tower":
        # The tower's landing reaches the beach by a real strip of dry land.
        d = ImageDraw.Draw(im)
        for x, y in [(18, 8), (18, 9), (17, 9), (17, 10), (16, 10), (16, 11), (15, 11)]:
            for j in (0, 4, 8, 12):
                px, py = x * 16, y * 16 + j
                d.rectangle(
                    (px, py, px + 15, py + 3), fill="#b29670", outline="#967b5d"
                )
                d.line((px + 4, py + 1, px + 11, py + 1), fill="#c3aa7e")
        for x, y in [(14, 11), (9, 8), (12, 14), (23, 13), (26, 17)]:
            if tiles[y, x] != 0:
                continue
            d.line(
                [
                    (x * 16 + 4, y * 16 + 10),
                    (x * 16 + 6, y * 16 + 7),
                    (x * 16 + 9, y * 16 + 7),
                    (x * 16 + 11, y * 16 + 10),
                ],
                fill="#a48a70",
            )
            d.line((x * 16 + 6, y * 16 + 8, x * 16 + 9, y * 16 + 8), fill="#f3dfbc")
    if snow:
        # Visible broken stones lead to the shrine; compressed bootprints lead to
        # the mouth of the Max Lair. Neither decoration adds invisible walls.
        d = ImageDraw.Draw(im)
        if map_id == "crown_peak":
            for y in range(8, 15):
                for x in range(13, 20):
                    if abs(x - 16) + max(0, y - 11) > 4 or tiles[y, x] != 0:
                        continue
                    px, py = x * 16, y * 16
                    d.polygon(
                        [
                            (px + 1, py + 4),
                            (px + 10, py + 2),
                            (px + 15, py + 5),
                            (px + 14, py + 11),
                            (px + 4, py + 13),
                        ],
                        fill="#b0b9b2",
                        outline="#a2ada8",
                    )
                    d.line((px + 3, py + 4, px + 10, py + 3), fill="#dfe7da", width=2)
        else:
            for offset in range(27):
                x = 17 * 16 - offset * 5
                y = 12 * 16 - int(offset * 0.8) + (offset % 2) * 4
                d.line((x, y, x + 2, y + 1), fill="#abbec4", width=2)
    im.save(Path(out), optimize=True)
