"""Finish Route 1's coastal bluff, hillside clearings and two item detours from the 4.62 layout."""

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from alola_melemele import pack
from island_metatiles import piece
from kalos_gym_rooms import tile


def paint(f, source):
    """Work directly over the authored through-road; the two little paths rejoin it on foot."""
    f.terrain_solid = f.s.copy()
    f.survey(source)
    image = Image.open(source / "assets/alola/maps/1.png").convert("RGB")
    f.props = list(f.m["hoenn_art"]["p"])
    for prop in f.props:
        x, y = prop[1:3]
        if 0 <= x < f.w and 0 <= y < f.h:
            f.occupied[y, x] = True
    # A rocky lip runs parallel to the island's northern shore. The clearings
    # leave two entrances facing the original item at (70,15) and the second at (108,15).
    belts = [
        [(54, 17), (60, 13), (65, 11), (69, 12)],
        [(74, 12), (82, 10), (89, 10), (94, 12)],
        [(110, 11), (118, 13), (123, 16), (127, 18)],
        [(47, 36), (51, 34), (57, 34), (60, 35)],
        [(77, 38), (82, 38), (86, 40), (90, 42)],
        [(34, 54), (40, 55), (46, 56), (50, 55)],
    ]
    imask = Image.new("1", (f.w, f.h))
    brush = ImageDraw.Draw(imask)
    for chain in belts:
        brush.line(chain, fill=1, width=2, joint="curve")
    belt = np.asarray(imask, bool) & ~(f.water | f.grass)
    safe = ~(f.s | f.water)
    trunk = Image.new("1", (f.w, f.h))
    pen = ImageDraw.Draw(trunk)
    for chain in [
        [(54, 28), (59, 24), (61, 19), (65, 16), (70, 15)],
        [(73, 29), (75, 24), (81, 19), (91, 17), (99, 14), (108, 15)],
        [(49, 29), (53, 40), (61, 43), (70, 46)],
    ]:
        pen.line(chain, fill=1, width=2, joint="curve")
    branch = np.asarray(trunk, bool) & safe & ~f.grass
    protection = np.zeros_like(belt)
    for x, y in f.reserved:
        protection[y, x] = True
    belt &= ~(ndimage.binary_dilation(protection, iterations=1) | branch)
    # Test connected segments independently, so the additions cannot close a former passage.
    groups, n = ndimage.label(belt)
    accepted = np.zeros_like(belt)
    for k in range(1, n + 1):
        part = groups == k
        old = f.s[part].copy()
        f.s[part] = True
        if f.accessible():
            accepted |= part
        else:
            f.s[part] = old
    img = np.asarray(image).copy().reshape(f.h, 16, f.w, 16, 3)
    cells = img.transpose(0, 2, 1, 3, 4)
    for x, y in [
        (24, 9),
        (32, 15),
        (58, 19),
        (87, 16),
        (104, 12),
        (119, 29),
        (54, 37),
        (62, 40),
        (102, 51),
        (22, 47),
        (33, 49),
    ]:
        xx = f.x - x
        yy = f.y - y
        if x > 70:
            patch = xx * xx / 40 + yy * yy / 5 < 1
        else:
            patch = xx * xx / 16 + yy * yy / 6 < 1
        patch &= ~(f.s | f.grass | f.water | branch)
        for off in [0, 1]:
            group = patch & ((f.x * 5 + f.y * 3) % 7 < (3 if off else 7))
            grass = tile("grass").copy()
            a = np.array(grass).astype(float)
            cells[group] = np.uint8(np.clip(a * [0.95, 0.98, 0.85] + [2, 1, 0], 0, 255))
            if off:
                d = ImageDraw.Draw(grass)
                for cx, cy in [(3, 6), (9, 10), (13, 3)]:
                    d.line((cx, cy, cx - 1, cy + 2), fill="#477e5c")
                    d.point((cx, cy - 1), fill="#d5b97c")
                cells[group] = np.asarray(grass)
    side = accepted & ~np.roll(accepted, -1, axis=0)
    cells[accepted] = np.asarray(piece("scarp_top"))
    cells[side] = np.asarray(piece("scarp_base"))
    # Narrow, sun-bleached trails have soil showing through grass. Their endpoints are real pickups.
    for y, x in np.argwhere(branch):
        chip = tile("grass").copy()
        dd = ImageDraw.Draw(chip)
        for xx, yy in [(2, 3), (4, 11), (11, 7), (12, 13), (7, 4)]:
            dd.line((xx, yy, xx + 2, yy), fill="#abc18a")
            dd.point((xx, yy + 1), fill="#bac796")
        cells[y, x] = np.array(chip)
    for x, y in [
        (66, 11),
        (73, 13),
        (83, 10),
        (90, 10),
        (115, 14),
        (124, 17),
        (56, 34),
        (85, 40),
        (47, 55),
    ]:
        f.place("palm" if y < 20 else "tree", (x, y), 3, scenic=True)
    for x, y in [
        (53, 19),
        (80, 13),
        (105, 16),
        (117, 23),
        (51, 35),
        (68, 44),
        (39, 52),
        (90, 41),
    ]:
        f.place("rock", (x, y), 2)
    from alola_melemele import IMAGES, MAPS, write

    Image.fromarray(img.reshape(f.h * 16, f.w * 16, 3)).quantize(
        192, dither=Image.Dither.NONE
    ).save(IMAGES / "1.png", optimize=True)
    f.m["physics"]["collision"] = f.s.astype("uint8").tolist()
    f.m["hoenn_art"]["p"] = f.props
    f.m["hoenn_art"]["t"] = pack(np.zeros_like(f.s, dtype="<u2"))
    f.m["island_field_revision"] = 1
    write(MAPS / "alola_1.json", f.m)
