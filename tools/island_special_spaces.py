"""Tile plans for Alola destinations that have no original field mesh in the atlas.

The western landing preserves every retail-derived exit and event. Further into the
field, the walkable habitat, spur, water and encounter position belong to each site.
"""

import numpy as np
from PIL import Image, ImageDraw

# Dimensions, trail from the old landing to the encounter, and a returning exploration loop.
PLANS = {
    "ultra_forest": (
        (54, 37),
        [(25, 13), (31, 12), (32, 5), (42, 6), (45, 12), (47, 20), (42, 23)],
        [(30, 12), (28, 25), (35, 29), (44, 27), (42, 23)],
    ),
    "ultra_jungle": (
        (59, 44),
        [(25, 12), (33, 17), (37, 14), (35, 8), (43, 5), (52, 11), (50, 16)],
        [(34, 17), (31, 28), (40, 34), (48, 29), (48, 22), (50, 16)],
    ),
    "ultra_plant": (
        (49, 33),
        [(18, 8), (24, 8), (24, 15), (33, 15), (33, 7), (42, 7)],
        [(24, 15), (24, 24), (38, 24), (42, 18), (42, 7)],
    ),
    "ultra_crater": (
        (56, 39),
        [(18, 10), (25, 13), (33, 10), (39, 14), (42, 23), (49, 22), (49, 16)],
        [(25, 13), (24, 23), (31, 29), (41, 30), (42, 23)],
    ),
    "ultra_desert": (
        (60, 38),
        [(18, 9), (27, 13), (37, 12), (39, 6), (49, 7), (53, 13), (49, 18)],
        [(27, 13), (25, 22), (39, 26), (48, 23), (49, 18)],
    ),
    "ultra_ruin": (
        (55, 42),
        [(18, 9), (27, 9), (29, 18), (38, 18), (38, 27), (46, 30)],
        [(29, 18), (26, 28), (31, 34), (41, 34), (46, 30)],
    ),
    "ultra_deep_sea": (
        (55, 40),
        [(23, 11), (31, 12), (34, 6), (42, 8), (44, 17), (48, 21)],
        [(30, 14), (28, 24), (36, 30), (45, 28), (48, 21)],
    ),
    "ultra_space_wilds": (
        (59, 37),
        [(24, 12), (32, 15), (39, 11), (46, 14), (50, 20)],
        [(31, 15), (32, 24), (41, 27), (50, 20)],
    ),
    "battle_tree": (
        (44, 35),
        [(21, 10), (27, 10), (30, 15), (34, 16), (37, 12)],
        [(27, 10), (27, 22), (32, 26), (37, 22), (37, 12)],
    ),
    "big_wave_beach": (
        (52, 29),
        [(23, 11), (31, 11), (36, 8), (43, 8)],
        [(30, 11), (34, 17), (42, 17), (43, 8)],
    ),
    "heahea_beach": (
        (53, 30),
        [(23, 10), (29, 13), (36, 13), (41, 10), (45, 14)],
        [(30, 13), (34, 19), (42, 21), (45, 14)],
    ),
    "ulaula_beach": (
        (52, 32),
        [(24, 10), (30, 10), (35, 15), (42, 13), (45, 8)],
        [(31, 11), (31, 23), (39, 23), (43, 17), (45, 8)],
    ),
    "poni_beach": (
        (55, 29),
        [(24, 10), (32, 11), (36, 7), (44, 8), (48, 13)],
        [(32, 11), (30, 17), (39, 20), (45, 18), (48, 13)],
    ),
    "poni_wilds_beach": (
        (49, 33),
        [(23, 10), (28, 13), (30, 19), (38, 20), (43, 15)],
        [(30, 18), (33, 10), (40, 8), (43, 15)],
    ),
}


def expand(m, mid):
    if mid not in PLANS:
        return
    (w, h), route, loop = PLANS[mid]
    ow, oh = m["size"]
    phy = m["physics"]
    # Rock borders the crater/desert; water separates the beach headlands and the deep sea.
    coastal = ("beach" in mid) or mid == "ultra_deep_sea"
    terrain = Image.new("L", (w, h), 1)
    draw = ImageDraw.Draw(terrain)
    ox, oy = m["spawn"]
    draw.line([(ox, oy), *route], fill=0, width=5, joint="curve")
    draw.line(loop, fill=0, width=3, joint="curve")
    for at in route[::2] + loop[1::2]:
        x, y = at
        r = 4 if mid != "ultra_plant" else 3
        if mid in {"ultra_plant", "ultra_ruin"}:
            draw.rectangle((x - r, y - r, x + r, y + r), fill=0)
        else:
            draw.ellipse((x - r - 2, y - r, x + r + 1, y + r + 1), fill=0)
    solid = np.asarray(terrain).astype(bool)
    water = solid.copy() if coastal else np.zeros_like(solid)
    if coastal:
        # Northern rock headlands retain a three-cell coastline before the sea opens.
        yy, xx = np.indices(solid.shape)
        promontory = yy < (3.3 + 1.8 * np.cos(xx * 0.14))
        solid &= promontory
        water &= ~promontory
    old = np.asarray(phy["collision"], bool)
    solid[:oh, :ow] = old
    water[:oh, :ow] = np.asarray(phy.get("water", np.zeros_like(old)), bool)
    entry = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(entry)
    # Open the former eastern boundary, joining the established dry landing to the new trail.
    join = next(
        (i for i, point in enumerate(route) if point[0] >= ow + 2), len(route) - 1
    )
    d.line([(ox, oy), *route[: join + 1]], fill=1, width=3, joint="curve")
    bridge = np.asarray(entry, bool)
    solid[bridge] = False
    water[bridge] = False
    # Actual event coordinates remain valid at the entry courtyard. Wild or activity NPCs move to
    # the authored habitat. Access rules and individual battle/quest flags are read by the same map ID.
    anchors = m["alola_anchors"]
    if mid.startswith("ultra_") or mid == "battle_tree":
        anchors["side1"] = list(route[-1])
        if mid == "battle_tree":
            anchors["side2"] = list(loop[2])
            anchors["side3"] = list(loop[3])
    m["size"] = phy["size"] = [w, h]
    phy["collision"] = solid.astype("uint8").tolist()
    if water.any():
        phy["water"] = water.astype("uint8").tolist()
    elif "water" in phy:
        del phy["water"]
    if "grass" in phy:
        grass = np.zeros_like(solid)
        grass[:oh, :ow] = np.array(phy["grass"], bool)
        phy["grass"] = grass.astype("uint8").tolist()


def finish(f):
    mid = f.mid
    if mid not in PLANS:
        return
    size, trail, loop = PLANS[mid]
    for i, (x, y) in enumerate(trail[1::2] + loop[1::2]):
        key = f.features[(i + 1) % len(f.features)]
        f.place(key, (x - 2, y - 3), 4)
    if mid == "ultra_plant":
        for x, y in [(23, 7), (32, 14), (39, 22), (43, 6)]:
            f.place("coil", (x, y), 3)


def conduits(f, im):
    if f.mid not in PLANS:
        return
    _, route, loop = PLANS[f.mid]
    if f.mid == "ultra_plant":
        d = ImageDraw.Draw(im)
        for branch in [route[1:], loop]:
            pts = [(x * 16 + 7, y * 16 + 9) for x, y in branch]
            d.line(pts, fill="#617370", width=7, joint="curve")
            d.line(pts, fill="#b7cb96", width=3, joint="curve")
            for x, y in pts:
                d.rectangle(
                    (x - 4, y - 3, x + 4, y + 3), fill="#84978a", outline="#4e6b6c"
                )
    elif f.mid == "ultra_ruin":
        d = ImageDraw.Draw(im)
        for x, y in route[1:]:
            x = x * 16
            y = y * 16
            d.line(
                [
                    (x - 15, y + 2),
                    (x - 5, y + 4),
                    (x, y - 1),
                    (x + 9, y + 1),
                    (x + 14, y - 7),
                ],
                fill="#746e70",
                width=2,
            )
    elif f.mid == "battle_tree":
        # A broad training dais sits under the tree's canopy at the far end.
        from island_metatiles import piece

        x, y = route[-1]
        mat = piece("dojo_mat")
        im.paste(mat, (16 * x + 8 - mat.width // 2, 16 * y + 8 - mat.height // 2))
