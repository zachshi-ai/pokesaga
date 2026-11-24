"""Draw the public promenade along Castelia's original curved pedestrian rail."""

from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.interpolate import PchipInterpolator
from unova_castelia import DOCKS, number
from unova_streets import FIELD, grass_tile


def stamp(key, colors, size):
    """Keep the joints and wave clusters from the Emerald metatile."""
    values = grass_tile(key)[:, :, :3].astype(int).sum(2)
    ramp = np.array([tuple(bytes.fromhex(c)) for c in colors], dtype=np.uint8)
    levels, codes = np.unique(values, return_inverse=True)
    ranks = np.linspace(0, len(ramp) - 1, len(levels)).round().astype(int)
    chip = ramp[ranks[codes.reshape(16, 16)]]
    w, h = size
    return np.tile(chip, (h // 16, w // 16, 1))


def paving(doc, walk):
    h, w = walk.shape
    size = (w * 16, h * 16)
    # An open U of pedestrian cells wraps the peninsula. Separate the inland
    # frontage from the sea even where both share the same impassable collision.
    land = Image.new("1", (w, h))
    coast = [
        (24, 0),
        (24, 31),
        (24, 53),
        (27, 60),
        (34, 66),
        (43, 71),
        (49, 74),
        (57, 70),
        (65, 64),
        (71, 58),
        (73, 40),
        (77, 30),
        (78, 0),
    ]
    ImageDraw.Draw(land).polygon(coast, fill=1)
    inland = np.asarray(land) & ~walk
    sea = ~np.asarray(land) & ~walk

    def distance(mask):
        # Rounding just the corners retains steps and the shape of every dock mouth.
        small = np.repeat(np.repeat(mask, 4, axis=0), 4, axis=1)
        rounded = ndimage.gaussian_filter(small.astype(float), 1.1) > 0.5
        signed = (
            ndimage.distance_transform_edt(~rounded)
            - ndimage.distance_transform_edt(rounded)
        ) * 4
        return np.asarray(
            Image.fromarray(signed.astype("float32")).resize(
                size, Image.Resampling.BILINEAR
            )
        )

    from_sea = distance(sea)
    from_block = distance(inland)
    yy, xx = np.indices((size[1], size[0]))
    floor = stamp("stone", ("c6b59f", "cebea4", "d8cab0", "dfd2b7"), size)
    inner = stamp("pave", ("899699", "98a1a0", "a0aaa6", "a6afaa"), size)
    # The city-side sidewalk, a narrow service road and the waterside walk
    # remain continuous through all four changes of direction. Where the rail
    # tapers to a single exit, the service road yields to the pedestrian paving.
    # The carriageway is surveyed separately from the edges: following the
    # midpoint of every pier mouth makes a road snake into the docks.
    bends = (
        np.array(
            [
                (24, 31),
                (24, 43),
                (24, 53),
                (25, 58),
                (30, 63),
                (38, 69),
                (45, 73),
                (50, 74),
                (56, 71),
                (64, 67),
                (70, 60),
                (72, 55),
                (73, 46),
                (73, 38),
                (75, 33),
                (78, 28),
            ]
        )
        * 16
        + 8
    )
    stations = np.r_[0, np.cumsum(np.hypot(*np.diff(bends, axis=0).T))]
    curve = PchipInterpolator(stations, bends)(np.arange(0, stations[-1] + 1, 2))
    axis = Image.new("1", size)
    ImageDraw.Draw(axis).line(
        [tuple(pt) for pt in curve.round().astype(int)], fill=1, width=1
    )
    offset = ndimage.distance_transform_edt(~np.asarray(axis))
    # Short terminal ramps narrow when the playable rail joins a street.
    width = np.minimum(15, np.minimum(from_sea - 9, from_block - 6))
    road = offset < width
    road_color = stamp("grass", ("82898a", "858e91", "899294", "8a9496"), size)
    floor[road] = road_color[road]
    curb = (width > 3) & (abs(offset - width) < 2)
    floor[curb] = (232, 221, 190)
    gutter = road & (width - offset < 3.5) & ~curb
    floor[gutter] = (100, 113, 117)
    # Flush iron drain covers sit just inside the curb with the long dimension
    # parallel to the road. These do not introduce a raised obstacle.
    for i in range(85, len(curve) - 30, 67):
        tangent = curve[i + 1] - curve[i - 1]
        tangent /= np.linalg.norm(tangent)
        normal = np.array([-tangent[1], tangent[0]])
        cx, cy = curve[i] + 10 * normal
        box = (slice(round(cy) - 8, round(cy) + 9), slice(round(cx) - 8, round(cx) + 9))
        rx, ry = xx[box] - cx, yy[box] - cy
        along, across = (
            rx * tangent[0] + ry * tangent[1],
            rx * normal[0] + ry * normal[1],
        )
        iron = road[box] & (abs(along) < 5) & (abs(across) < 2.5)
        floor[box][iron] = (97, 108, 109)
        floor[box][iron & (along.astype(int) % 3 == 0)] = (162, 169, 158)
    sea_color = stamp("water", ("397d99", "39849f", "458ba6", "579bb1"), size)
    floor[from_block < 0] = inner[from_block < 0]
    # A long dark line and its brass return follow the *shore*, even at turns.
    floor[(from_sea > 3) & (from_sea < 6)] = (109, 128, 128)
    floor[(from_sea >= 6) & (from_sea < 8)] = (225, 212, 171)
    floor[(from_block > -2) & (from_block < 1)] = (116, 119, 107)
    floor[(from_block >= 1) & (from_block < 3)] = (232, 220, 193)
    # Keep the waterside rail on the first solid cell. Seaward of the cap, the
    # masonry drops to dark pilings with a narrow band of reflected light.
    floor[from_sea < -13] = sea_color[from_sea < -13]
    floor[(from_sea >= -13) & (from_sea < -11)] = (98, 156, 168)
    wall = (from_sea >= -11) & (from_sea < -6)
    floor[wall] = (103, 120, 124)
    floor[wall & ((xx + yy // 4) % 18 == 0)] = (78, 99, 103)
    floor[(from_sea >= -6) & (from_sea <= 2)] = (211, 202, 174)
    pic = Image.fromarray(floor)
    draw = ImageDraw.Draw(pic)

    # Forecourts lead from the actual street/indoor warps into the promenade.
    # Some native streets have two warps; dress both independently.
    street_mouth = {31: (-1, 0), 33: (0, 1), 34: (1, 0), 35: (-1, 0)}
    approach = Image.fromarray(
        stamp("stone", ("a89e90", "b8ac99", "c5b8a1", "cdbfa7"), size)
    )
    for warp in doc["warps"]:
        n = number(warp)
        if n not in (*DOCKS, 31, 33, 34, 35, 41, 42, 44):
            continue
        x, y = warp["at"]
        cx, cy = x * 16 + 8, y * 16 + 8
        wood = n in DOCKS
        surface = from_sea if wood else from_block
        # Direction lies along the original waterfront facing, including corner ramps.
        cy0, cx0 = max(0, cy - 12), max(0, cx - 12)
        cy1, cx1 = min(size[1] - 1, cy + 12), min(size[0] - 1, cx + 12)
        dx = float(surface[cy, cx1] - surface[cy, cx0])
        dy = float(surface[cy1, cx] - surface[cy0, cx])
        if abs(dx) > abs(dy):
            ax, ay = (1 if dx >= 0 else -1), 0
        else:
            ax, ay = 0, (1 if dy >= 0 else -1)
        if n in street_mouth:
            ax, ay = street_mouth[n]
        elif n in (41, 44):
            ax, ay = 0, 1
        if wood:
            # Each landing has a pedestrian crossing along its own approach.
            # Paint only marks that intersect the asphalt.
            local = (
                slice(max(0, cy - 163), min(size[1], cy + 164)),
                slice(max(0, cx - 163), min(size[0], cx + 164)),
            )
            along = (xx[local] - cx) * ax + (yy[local] - cy) * ay
            across = (yy[local] - cy) * ax - (xx[local] - cx) * ay
            crossing = road[local] & (along > 0) & (abs(across) < 11) & (along % 8 < 4)
            marks = Image.fromarray((crossing * 255).astype("uint8"))
            pic.paste(
                "#ded9bf",
                (local[1].start, local[0].start, local[1].stop, local[0].stop),
                marks,
            )
        # Non-walkable extension of the gangway is the continuation on the next map.
        back, front, radius = 19, 12, 10
        if n in street_mouth:
            back, front, radius = 80, 6, 13
        elif not wood:
            back, front, radius = 10, 5, 8

        def pos(s, t, origin=(cx, cy), direction=(ax, ay)):
            dx, dy = direction
            return origin[0] + s * dx - t * dy, origin[1] + s * dy + t * dx

        if not wood:
            # The footway continues into each street mouth. A shop only needs
            # a sill beneath its real door, never a plywood patch on the square.
            left, top = pos(-back, -radius)
            right, bottom = pos(front, radius)
            box = (
                min(left, right),
                min(top, bottom),
                max(left, right) + 1,
                max(top, bottom) + 1,
            )
            pic.paste(approach.crop(box), box[:2])
            for side in (-radius, radius):
                draw.line((pos(-back, side), pos(front, side)), fill="#d3c6ac")
            if n not in street_mouth:
                draw.line((pos(front, -radius), pos(front, radius)), fill="#aa9b89")
            continue
        draw.polygon(
            [
                pos(-back, -radius),
                pos(front, -radius),
                pos(front, radius),
                pos(-back, radius),
            ],
            fill="#c5a47c",
        )
        for s in range(-back, front + 1, 5):
            draw.line((pos(s, -radius), pos(s, radius)), fill="#987759")
            draw.line((pos(s + 1, -radius), pos(s + 1, radius)), fill="#d8bb8e")
        for t in (-radius, radius):
            draw.line((pos(-back, t), pos(front, t)), fill="#7b7465")
            for s in (-back + 2, front - 1):
                px, py = pos(s, t)
                draw.rectangle((px - 1, py - 3, px + 2, py + 1), fill="#655e53")
                draw.line((px - 1, py - 3, px + 1, py - 3), fill="#d5c29b")
    return pic


@lru_cache(None)
def furnishing(kind):
    if kind == "bench":
        im = Image.new("RGBA", (25, 17))
        p = ImageDraw.Draw(im)
        for x in (3, 20):
            p.rectangle((x, 5, x + 2, 15), fill="#535e60")
            p.point((x, 15), fill="#384e53")
        for y in (3, 6, 10):
            p.rectangle((1, y, 23, y + 2), fill="#8f684e")
            p.line((2, y, 22, y), fill="#c9a276")
        p.line((1, 13, 23, 13), fill="#695b51")
    elif kind == "tree_box":
        im = Image.new("RGBA", (31, 38))
        p = ImageDraw.Draw(im)
        p.ellipse((1, 29, 30, 37), fill="#9c9a87")
        p.polygon(
            [
                (1, 27),
                (5, 23),
                (25, 23),
                (29, 27),
                (29, 33),
                (25, 35),
                (5, 35),
                (1, 32),
            ],
            fill="#a58d73",
            outline="#736c60",
        )
        p.rectangle((4, 27, 26, 30), fill="#605f50")
        p.line([(2, 29), (6, 31), (26, 31), (28, 29)], fill="#ddd0ae")
        with Image.open(FIELD / "tree_compact.png") as tree:
            im.alpha_composite(tree.convert("RGBA"), (8, 5))
        for px, py in ((5, 27), (24, 26), (6, 29), (23, 28)):
            p.line((px, py + 1, px + 2, py + 1), fill="#68875f")
            p.point((px + 1, py), fill="#e1c78e")
    else:
        im = Image.new("RGBA", (14, 16))
        p = ImageDraw.Draw(im)
        p.ellipse((1, 11, 13, 15), fill="#78868a")
        p.rectangle((4, 5, 9, 12), fill="#515e60")
        p.rectangle((5, 4, 7, 11), fill="#889599")
        p.ellipse((2, 3, 11, 6), fill="#556366")
        p.line((4, 3, 9, 3), fill="#c4cbc0")
    return im


def furniture(doc, walk, props, save_sprite):
    # Quayside resting places and tie-up points stay on existing solid ground.
    # Select individual bays to leave the five gangways and their signs clear.
    bays = [
        ("bench", 32, 46),
        ("planter", 31, 50),
        ("streetlamp", 31, 54),
        ("bench", 37, 64),
        ("planter", 40, 65),
        ("bench", 47, 66),
        ("streetlamp", 54, 68),
        ("planter", 58, 66),
        ("bench", 65, 60),
        ("streetlamp", 66, 52),
        ("planter", 67, 46),
        ("bench", 68, 40),
        ("bollard", 20, 44),
        ("bollard", 20, 53),
        ("bollard", 32, 72),
        ("bollard", 43, 78),
        ("bollard", 58, 73),
        ("bollard", 68, 68),
        ("bollard", 77, 53),
        ("bollard", 77, 42),
        ("tree_box", 30, 49),
        ("tree_box", 30, 42),
        ("tree_box", 34, 62),
        ("tree_box", 44, 66),
        ("tree_box", 51, 67),
        ("tree_box", 62, 63),
        ("tree_box", 67, 50),
        ("tree_box", 69, 44),
        ("tree_box", 69, 37),
    ]
    blocked = {tuple(v["at"]) for v in [*doc["warps"], *doc["objects"], *doc["npcs"]]}
    blocked.update((v[1], v[2]) for v in props)
    near = ndimage.distance_transform_edt(~walk)
    for kind, sx, sy in bays:
        options = []
        for y in range(sy - 2, sy + 3):
            for x in range(max(0, sx - 2), min(walk.shape[1], sx + 3)):
                if not 0 < near[y, x] <= 1.5:
                    continue
                if kind in ("bench", "planter", "tree_box") and (
                    walk[y, max(0, x - 1)] or walk[y, min(walk.shape[1] - 1, x + 1)]
                ):
                    continue
                if all(max(abs(x - bx), abs(y - by)) > 1 for bx, by in blocked):
                    options.append(((sx - x) ** 2 + (sy - y) ** 2, y, x))
        if not options:
            continue
        _, y, x = min(options)
        if kind in ("bench", "bollard", "tree_box"):
            img = furnishing(kind)
            props.append(
                [
                    save_sprite("castelia_" + kind, img),
                    x,
                    y,
                    [img.width // 2, img.height],
                ]
            )
        else:
            props.append([kind, x, y])
        blocked.add((x, y))
