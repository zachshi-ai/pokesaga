"""Place the landmark floor, facade and wall ornament on the field's collision survey."""

import math
import numpy as np
from PIL import Image, ImageDraw
from island_metatiles import piece

ROOM_FLOORS = {
    "royalcourt": "arena_brown",
    "dojo": "arena_wood",
    "earthcourt": "arena_clay",
    "mooncourt": "arena_mauve",
    "skycourt": "arena_ice",
    "summit": "arena_mint",
    "crystalhall": "hall_tile",
    "cleanroom": "lab_tile",
    "laboratory": "lab_tile",
    "conservatory": "hall_tile",
    "gallery": "hall_tile",
    "civic": "office_tile",
    "study": "office_tile",
    "castle": "arena_mauve",
    "warpwing": "arena_mauve",
    "switchwing": "lab_tile",
    "throne": "arena_clay",
    "campus": "office_tile",
}
CAVES = set(
    "volcano caldera ravine deepcave ferncave cavern tidalcave basalt basaltshore dustbowl coppercliff mine upland gorge".split()
)
STAGES = set("royalcourt dojo earthcourt mooncourt skycourt summit".split())


def rocky_edges(f, grid):
    physical = f.terrain_solid & ~f.offmap & ~f.seascape
    dry = ~(f.terrain_solid | f.water)
    for name, delta, axis in [
        ("scarp_left", 1, 1),
        ("scarp_right", -1, 1),
        ("scarp_base", -1, 0),
    ]:
        side = physical & np.roll(dry, delta, axis=axis)
        # Join ground contours in long faces instead of isolated tiles in the middle of a path.
        grid[side] = np.asarray(piece(name))
        if axis == 0:
            grid[np.roll(side, -1, axis=0) & physical] = np.asarray(piece("scarp_top"))


def room_floor(f, grid):
    base = ROOM_FLOORS.get(f.style)
    if base:
        grid[~f.terrain_solid & ~f.water] = np.asarray(piece(base))


def walls(f, im):
    if f.style in STAGES | {
        "laboratory",
        "cleanroom",
        "gallery",
        "civic",
        "castle",
        "campus",
        "crystalhall",
        "manor",
        "market",
        "studio",
        "study",
        "atelier",
        "warehouse",
        "living",
        "nursery",
        "dining",
        "beachlodge",
        "roadside",
        "desertlodge",
        "switchwing",
        "warpwing",
        "throne",
        "resort",
        "derelict",
    }:
        wall = (
            "dome_seats"
            if f.style == "royalcourt"
            else "medal_wall"
            if f.style in {"earthcourt", "skycourt", "mooncourt", "crystalhall"}
            else "dojo_wall"
            if f.style in {"dojo", "dining", "manor", "living", "nursery"}
            else "prism_wall"
            if f.style == "summit"
            else "museum_wall"
            if f.style in {"cleanroom", "laboratory", "gallery"}
            else "office_wall"
        )
        tx = piece(wall)
        layer = Image.new("RGB", im.size)
        for yy in range(0, im.height, tx.height):
            for xx in range(0, im.width, tx.width):
                layer.paste(tx, (xx, yy))
        # Only the back side of a solid wall gets the frieze; never draw it through the floor.
        solid = f.terrain_solid & ~f.offmap
        contact = solid & np.roll(~f.terrain_solid, -1, axis=0)
        mask = contact.copy()
        for up in range(1, tx.height // 16):
            contact = np.roll(contact, -1, axis=0) & solid
            mask |= contact
        im.paste(
            layer,
            mask=Image.fromarray(mask.astype("uint8") * 255).resize(
                im.size, Image.Resampling.NEAREST
            ),
        )
    return im


def ring(f, image):
    st = f.style
    sx, sy = f.story
    cx = sx * 16 + 8
    cy = sy * 16 + 8
    # An actual raised mat and entrance apron put the opponent on a stage at walking scale.
    if st not in STAGES:
        return image
    drawing = image.copy()
    d = ImageDraw.Draw(drawing)
    if st in {"royalcourt", "dojo"}:
        mat = piece("dome_mat" if st == "royalcourt" else "dojo_mat")
        drawing.paste(mat, (cx - mat.width // 2, cy - mat.height // 2))
        if st == "royalcourt":
            for dx, dy, c in [
                (-44, -19, "#bd6a62"),
                (41, -19, "#b7ac68"),
                (41, 19, "#6994ac"),
                (-44, 19, "#689b79"),
            ]:
                d.rectangle(
                    (cx + dx - 6, cy + dy - 2, cx + dx + 6, cy + dy + 2), fill=c
                )
    elif st == "summit":
        d.polygon(
            [
                (cx - 65, cy - 28),
                (cx - 38, cy - 49),
                (cx + 39, cy - 49),
                (cx + 67, cy - 28),
                (cx + 67, cy + 24),
                (cx + 39, cy + 48),
                (cx - 39, cy + 48),
                (cx - 65, cy + 24),
            ],
            fill="#9bc4bf",
            outline="#476778",
            width=4,
        )
        d.ellipse((cx - 26, cy - 21, cx + 26, cy + 21), outline="#e7e0b7", width=3)
        stairs = piece("champ_stairs")
        drawing.paste(stairs, (cx - stairs.width // 2, cy + 41))
    else:
        pts = (
            {
                "earthcourt": [
                    (-61, -25),
                    (-35, -42),
                    (33, -42),
                    (61, -25),
                    (61, 25),
                    (34, 42),
                    (-35, 42),
                    (-61, 25),
                ],
                "mooncourt": [
                    (
                        round(math.cos(i * math.pi / 12) * 60),
                        round(math.sin(i * math.pi / 12) * 45),
                    )
                    for i in range(24)
                ],
                "skycourt": [
                    (-70, -33),
                    (-27, -20),
                    (0, -37),
                    (27, -20),
                    (70, -33),
                    (48, 3),
                    (23, 14),
                    (0, 38),
                    (-23, 14),
                    (-48, 3),
                ],
            }
        )[st]
        pal = {
            "earthcourt": ("#8c7663", "#c0a47b", "#e9cd96"),
            "mooncourt": ("#675a7d", "#9486ab", "#d4c6d3"),
            "skycourt": ("#75949b", "#a2c3c3", "#dce5d1"),
        }[st]
        for size, dy, color in [(1, 5, pal[0]), (1, 1, pal[2]), (0.94, 0, pal[1])]:
            p = [(int(cx + x * size), int(cy + y * size + dy)) for x, y in pts]
            d.polygon(p, fill=color, outline=pal[0])
        for i in range(4):
            angle = i * math.pi / 2
            ax = cx + round(26 * math.cos(angle))
            ay = cy + round(18 * math.sin(angle))
            d.polygon(
                [(ax, ay - 3), (ax + 3, ay), (ax, ay + 3), (ax - 3, ay)], fill=pal[2]
            )
        if st == "mooncourt":
            d.arc((cx - 17, cy - 14, cx + 16, cy + 13), 38, 285, fill=pal[2], width=3)
        elif st == "skycourt":
            for k in (-1, 1):
                d.line(
                    [
                        (cx + 4 * k, cy + 6),
                        (cx + 14 * k, cy - 2),
                        (cx + 24 * k, cy - 9),
                    ],
                    fill=pal[2],
                    width=2,
                )
        else:
            d.polygon(
                [(cx - 8, cy), (cx, cy - 9), (cx + 8, cy), (cx, cy + 7)],
                outline=pal[2],
                width=2,
            )
    mask = Image.fromarray(
        ((~f.terrain_solid & ~f.water) * 255).astype("uint8")
    ).resize(image.size, Image.Resampling.NEAREST)
    return Image.composite(drawing, image, mask)
