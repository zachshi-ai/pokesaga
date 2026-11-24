"""Paint walkable ferry aprons and service lanes on the original Aether dock platform."""

from pathlib import Path

import numpy as np
from kalos_gym_rooms import tile
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
P = 16


def sheet(chip, size):
    w, h = size
    return Image.fromarray(
        np.tile(
            np.asarray(chip),
            (
                (h + chip.height - 1) // chip.height,
                (w + chip.width - 1) // chip.width,
                1,
            ),
        )[:h, :w]
    )


def tinted(key, color, strength):
    light = np.asarray(tile(key).convert("L"), dtype=float)
    detail = np.round((light - light.mean()) * strength / 3) * 3
    return Image.fromarray(np.uint8(np.clip(color + detail[:, :, None], 0, 255)))


def docks(m):
    w, h = m["size"]
    assert (w, h) == (196, 147)
    size = (w * P, h * P)
    water = np.asarray(m["physics"]["water"], bool)
    solid = np.asarray(m["physics"]["collision"], bool)
    # The outer invisible map border is not part of the island's hull.
    deck = ~water & (ndimage.distance_transform_edt(solid | water) < 10)
    mask = Image.fromarray(deck.astype("uint8") * 255).resize(
        size, Image.Resampling.BILINEAR
    )
    mask = mask.filter(ImageFilter.GaussianBlur(4)).point(
        lambda n: 255 if n >= 126 else 0
    )
    water_art = sheet(tinted("water", (93, 154, 173), 0.62), size)
    water_art.paste("#819eac", (0, 0, *size), mask.filter(ImageFilter.MaxFilter(9)))
    hull = sheet(tinted("pave", (192, 197, 185), 0.16), size)
    d = ImageDraw.Draw(hull)

    def line(pts, color, width=1):
        d.line(
            [(round(x * P), round(y * P)) for x, y in pts],
            fill=color,
            width=width,
            joint="curve",
        )

    def box(bounds, color, outline=None):
        d.rectangle([round(n * P) for n in bounds], fill=color, outline=outline)

    # The trunk links the passenger ferry gates to the north platform, while the marked
    # east-west service lane connects the freight cranes on both sides of the dock.
    spine = [(98, 16), (98, 65), (98, 81), (98, 91)]
    loading = [
        (7, 93),
        (49, 93),
        (64, 89),
        (82, 88),
        (98, 91),
        (115, 88),
        (132, 89),
        (147, 93),
        (190, 93),
    ]
    for pts, width in [(spine, 3), (loading, 4)]:
        for color, breadth in [
            ("#778c92", width * P + 8),
            ("#e8e4c9", width * P + 5),
            ("#a8b4b2", width * P),
        ]:
            line(pts, color, breadth)
    # Each coloured track belongs to an actual pair of docks. Interrupt the line at service
    # junctions and do not paint crossings over the true water gaps.
    for x1, x2 in [(8, 44), (149, 187)]:
        for x in range(x1, x2, 4):
            line([(x, 93), (x + 1.5, 93)], "#ede6c8", 2)
    for v in range(27, 77, 6):
        line([(97.2, v), (97.2, v + 2)], "#f0e7c8", 2)
    for cx in (15, 180):
        box((cx - 4, 87.8, cx + 4, 91.2), "#c3ccbd", "#829792")
        for x in (cx - 3, cx + 3):
            line([(x, 88.2), (x, 91)], "#e9e5ca", 3)

    # Working bays, drainage channels and service covers distinguish open vehicle clearance
    # from the unloading positions. The markings belong to the floor and can be walked on.
    for left, right in [(9, 42), (52, 85), (110, 138), (148, 186)]:
        for y in (82, 101, 112):
            for x in range(left, right - 6, 10):
                box((x, y, x + 6, y + 3.5), "#b5c0b7")
                for xx in (x, x + 6):
                    line(
                        [
                            (xx, y + 2.6),
                            (xx, y + 3.5),
                            (xx + (0.8 if xx == x else -0.8), y + 3.5),
                        ],
                        "#ebd995",
                        3,
                    )
                line([(x + 0.45, y + 0.35), (x + 5.55, y + 0.35)], "#94a5a2", 2)
        line([(left, 97.4), (right, 97.4)], "#8b9c9d", 2)
        for x in range(left + 2, right, 4):
            box((x, 97.25, x + 0.5, 97.55), "#708a8a")
    for x, y in [
        (48, 88),
        (143, 91),
        (97, 75),
        (62, 84),
        (142, 86),
        (97, 26),
        (104, 26),
    ]:
        box((x - 1.6, y - 0.7, x + 1.6, y + 0.65), "#a2b0ac", "#7e9393")
        for i in range(-16, 18, 4):
            px, py = round(x * P) + i, round((y + 0.3) * P)
            d.line((px, py, px + 3, py - 4), fill="#e8cf8d", width=2)
    for y in (65, 81, 98, 120, 131):
        for x in (30, 64, 98, 132, 166):
            box((x - 0.6, y - 0.3, x + 0.6, y + 0.3), "#a5b0ab", "#86999a")
            line([(x - 0.35, y), (x + 0.35, y)], "#c9d0c1", 1)
    # Machinery bases on the exact solid islands visually explain the collision.
    occupied = solid & deck
    for y, x in np.argwhere(occupied):
        box((x, y, x + 1, y + 1), "#a3b1aa")
        if y and not occupied[y - 1, x]:
            line([(x, y + 0.06), (x + 1, y + 0.06)], "#d9daca", 2)
        if y + 1 < h and not occupied[y + 1, x]:
            box((x, y + 0.75, x + 1, y + 0.98), "#889b9b")
            line([(x, y + 0.73), (x + 1, y + 0.73)], "#e4d6b4", 2)
            if x % 2 == 0:
                line([(x + 0.5, y + 0.83), (x + 0.5, y + 0.96)], "#758a8d", 1)
    for warp in m["warps"]:
        x, y = warp["at"]
        line(
            [(x + 0.15, y + 0.7), (x + 0.5, y + 0.45), (x + 0.85, y + 0.7)],
            "#667f86",
            4,
        )
        line(
            [(x + 0.15, y + 0.63), (x + 0.5, y + 0.38), (x + 0.85, y + 0.63)],
            "#f4e0a7",
            2,
        )
    # White coping on the entire platform, with a narrow shadow in the water.
    water_art.paste("#f0e7c9", (0, 0, *size), mask)
    water_art.paste(hull, (0, 0), mask.filter(ImageFilter.MinFilter(5)))
    water_art.quantize(128, dither=Image.Dither.NONE).save(
        ROOT / m["hoenn_art"]["scene"][0][6:], optimize=True
    )


def hauoli(field):
    """Follow the existing commercial avenue from the port to the shops and fountain."""
    size = field.surface.size
    image = field.surface
    paved = np.isin(field.layers, ("quay", "cobbles")) & ~field.water & ~field.grass

    def edge(bits):
        raw = Image.fromarray(bits.astype("uint8") * 255).resize(
            size, Image.Resampling.BILINEAR
        )
        return raw.filter(ImageFilter.GaussianBlur(5)).point(
            lambda n: 255 if n >= 125 else 0
        )

    sidewalk = edge(paved)
    street = edge((field.layers == "cobbles") & paved)
    inset = Image.new("RGB", (48, 32), "#d4c4a3")
    pen = ImageDraw.Draw(inset)
    for y in (0, 8, 16, 24):
        pen.line((0, y, 47, y), fill="#c5b79b")
        for x in range((y // 8 % 2) * 12, 48, 24):
            pen.line((x, y + 1, x, y + 7), fill="#cabea2")
    image.paste("#8b967e", (0, 0, *size), sidewalk.filter(ImageFilter.MaxFilter(3)))
    image.paste(sheet(inset, size), (0, 0), sidewalk)
    image.paste("#e6d7af", (0, 0, *size), street.filter(ImageFilter.MaxFilter(5)))
    image.paste("#9d9f91", (0, 0, *size), street.filter(ImageFilter.MaxFilter(3)))
    image.paste(sheet(tinted("pave", (165, 166, 152), 0.26), size), (0, 0), street)
    # The fountain, souvenir market and civic square each sit on a single shared court.
    courts = image.copy()
    d = ImageDraw.Draw(courts)
    for cx, cy, rx, ry in [
        (52.5, 36, 6.5, 3.9),
        (37.5, 51.3, 3.2, 2.2),
        (60.5, 25, 3.3, 1.9),
    ]:
        x0, y0, x1, y1 = map(
            round, ((cx - rx) * P, (cy - ry) * P, (cx + rx) * P, (cy + ry) * P)
        )
        d.rounded_rectangle(
            (x0, y0, x1, y1), radius=18, fill="#cbbb98", outline="#8e927c", width=2
        )
        d.rounded_rectangle(
            (x0 + 4, y0 + 4, x1 - 4, y1 - 4), radius=15, outline="#ebd8aa", width=2
        )
        for dy in range(y0 + 12, y1 - 6, 12):
            d.line((x0 + 8, dy, x1 - 8, dy), fill="#beae91")
            for dx in range(x0 + 20 + ((dy - y0) // 12 % 2) * 12, x1 - 8, 24):
                d.line((dx, dy, dx, min(y1 - 7, dy + 10)), fill="#c2b395")
    for dest in field.m["warps"]:
        if dest["to"]["map"].removeprefix("alola_") not in (
            "center_hauoli",
            "hauoli_mall",
            "hauoli_police",
            "tourism_bureau",
            "malasada_shop",
        ):
            continue
        x, y = dest["at"]
        for i in range(2):
            top = round((y + 1.1) * P) + i * 4
            d.line(
                ((x - 0.6) * P, top, (x + 1.6) * P, top),
                fill=("#ac987b", "#e9d8b5")[i],
                width=2,
            )
    usable = Image.fromarray((~field.water & ~field.grass).astype("uint8") * 255)
    image.paste(courts, (0, 0), usable.resize(size, Image.Resampling.NEAREST))


def cargo_stacks(m):
    """Populate the pre-existing solid crane platforms without taking a step from the player."""
    tint = {
        "freight_green": ("#7a9b8f", "#bad0ab", "#587c78"),
        "freight_red": ("#bd806c", "#dfb290", "#936e64"),
    }
    artdir = ROOT / "assets/alola/facilities"
    for key, (body, top, side) in tint.items():
        im = Image.new("RGBA", (48, 29))
        d = ImageDraw.Draw(im)
        d.polygon(
            [(1, 24), (7, 20), (46, 20), (46, 24), (39, 28), (3, 28)], fill="#768d87"
        )
        d.polygon([(2, 11), (11, 5), (45, 5), (36, 11)], fill=top, outline="#626f69")
        for x in range(10, 37, 5):
            d.line((x, 9, x + 5, 6), fill=body)
        d.rectangle((2, 11, 36, 25), fill=body, outline="#606d68")
        d.polygon([(36, 11), (45, 5), (45, 20), (36, 25)], fill=side, outline="#606d68")
        for x in range(6, 34, 4):
            d.line((x, 13, x, 23), fill=side)
            d.line((x + 1, 13, x + 1, 23), fill=body)
        d.rectangle((5, 14, 10, 17), fill="#e1d4ad")
        d.line((3, 11, 35, 11), fill=top)
        d.line((4, 24, 35, 24), fill=side)
        d.line((38, 13, 43, 10), fill=body)
        im.save(artdir / (key + ".png"), optimize=True)
    booth = Image.new("RGBA", (76, 46))
    d = ImageDraw.Draw(booth)
    d.polygon([(1, 39), (9, 33), (74, 33), (74, 40), (67, 45), (2, 45)], fill="#7e9591")
    d.polygon(
        [(4, 19), (12, 12), (69, 12), (69, 36), (62, 41), (4, 41)],
        fill="#dddbbd",
        outline="#526c72",
    )
    d.polygon(
        [(62, 21), (69, 16), (69, 36), (62, 41)], fill="#9fae9e", outline="#526c72"
    )
    d.polygon(
        [(1, 19), (11, 8), (67, 8), (73, 15), (63, 22), (1, 22)],
        fill="#98bcb7",
        outline="#536e77",
    )
    d.line((4, 19, 62, 19, 70, 14), fill="#e8e5c4", width=2)
    for x in (8, 25, 42):
        d.rectangle((x, 25, x + 13, 32), fill="#597e89", outline="#506977")
        d.line((x + 2, 26, x + 11, 26), fill="#a1c5be")
    d.line((5, 34, 60, 34), fill="#7a9e9c", width=2)
    d.line((9, 39, 58, 39), fill="#b7ac8d")
    booth.save(artdir / "dock_office.png", optimize=True)
    rows = m["hoenn_art"]["p"]
    # Each berth is five cells wide. Use the broadside of Emerald's passenger
    # ferry and retain the bright hull and upper deck at the Alola pier scale.
    ship = Image.open(ROOT / "assets/hoenn_native/actors/SSTidal.png").convert("RGBA")
    frame = ship.crop((0, 0, 96, 40)).resize((80, 33), Image.Resampling.NEAREST)
    frame.save(artdir / "passenger_ferry.png", optimize=True)
    ferry = "res://assets/alola/facilities/passenger_ferry.png"
    rows[:] = [
        row
        for row in rows
        if row[0] not in ("res://assets/island_landmarks/boat.png", ferry)
    ]
    for berth in (2, 193):
        rows.append([ferry, berth, 92, [40, 29]])
    solid = np.asarray(m["physics"]["collision"], bool)
    water = np.asarray(m["physics"]["water"], bool)
    # The old centre-of-deck boat occupied a five-cell service island. Give that island an
    # actual dispatch office, and reserve the water under each moored hull for the boats.
    office = "res://assets/alola/facilities/dock_office.png"
    service = [office, 97, 74, [38, 46]]
    if service not in rows:
        rows.append(service)
    for row in rows:
        if row[0] == "officecounter":
            row[0], row[3] = office, [38, 46]
    for x in (2, 193):
        solid[92, x - 2 : x + 3] |= water[92, x - 2 : x + 3]
    m["physics"]["collision"] = solid.astype("uint8").tolist()
    pads = [
        (51, 90),
        (54, 86),
        (51, 82),
        (48, 78),
        (52, 78),
        (53, 70),
        (56, 74),
        (148, 90),
        (147, 86),
        (149, 82),
        (144, 78),
        (148, 78),
        (144, 70),
        (146, 74),
        (88, 22),
        (91, 24),
        (101, 22),
        (103, 25),
        (111, 22),
        (96, 17),
    ]
    for i, (x, y) in enumerate(pads):
        if not solid[y, x - 1 : x + 2].all() or water[y, x - 1 : x + 2].any():
            continue
        color = list(tint)[(i + i // 3) % 2]
        prop = ["res://assets/alola/facilities/" + color + ".png", x, y, [24, 28]]
        if prop not in rows:
            rows.append(prop)
