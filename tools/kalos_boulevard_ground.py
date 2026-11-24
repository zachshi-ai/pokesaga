"""Limestone footways and cobbled carriageways on Lumiose's native curved streets."""

import numpy as np
from kalos_gym_rooms import tile
from kalos_surfaces import WATER
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage


def surface(area, walk, road, px):
    h, w = walk.shape
    size = (w * px, h * px)
    ground = Image.new("RGB", size)

    def smooth(mask):
        # A diagonal on the movement grid is still a continuous kerb when drawn at street scale.
        enlarged = Image.fromarray(mask.astype("uint8") * 255).resize(
            size, Image.Resampling.BILINEAR
        )
        return enlarged.filter(ImageFilter.GaussianBlur(px * 0.4)).point(
            lambda p: 255 if p >= 125 else 0
        )

    def swatch(pic, color, strength):
        sample = np.asarray(pic.convert("L"), dtype=float)
        vals = np.round((sample - np.mean(sample)) * strength / 3) * 3
        return Image.fromarray(
            np.uint8(np.clip(np.array(color) + vals[:, :, None], 0, 255))
        )

    def fill(chip, mask=None):
        arr = np.asarray(chip)
        rows = (size[1] + chip.height - 1) // chip.height
        cols = (size[0] + chip.width - 1) // chip.width
        layer = Image.fromarray(np.tile(arr, (rows, cols, 1))[: size[1], : size[0]])
        ground.paste(layer, (0, 0), mask)

    turf = swatch(tile("grass"), (124, 159, 117), 0.30)
    fill(turf)
    pavement = Image.new("RGB", (48, 32), "#d7c9ab")
    d = ImageDraw.Draw(pavement)
    for y in (0, 8, 16, 24):
        d.line((0, y, 47, y), fill="#c8bda4")
        shift = (y // 8 % 2) * 12
        for x in range(shift, 48, 24):
            d.line((x, y + 1, x, y + 7), fill="#cbbfa5")
    accessible = smooth(walk)
    ground.paste("#7c8a73", (0, 0, *size), accessible.filter(ImageFilter.MaxFilter(5)))
    ground.paste("#ede0bc", (0, 0, *size), accessible.filter(ImageFilter.MaxFilter(3)))
    fill(pavement, accessible)
    # Original boulevards supply a named road material. Small plazas use their open paved
    # interiors, with a wide continuous walking strip below the façades.
    carriage = road if np.any(road) else (ndimage.distance_transform_edt(walk) > 4)
    carriage = ndimage.binary_closing(carriage, iterations=1)
    mainway = smooth(carriage & walk)
    ground.paste("#948e80", (0, 0, *size), mainway.filter(ImageFilter.MaxFilter(5)))
    ground.paste("#e3d4af", (0, 0, *size), mainway.filter(ImageFilter.MaxFilter(3)))
    fill(swatch(tile("pave"), (153, 146, 136), 0.25), mainway)
    fill(swatch(tile("water"), (113, 164, 179), 0.45), smooth(area.kind == WATER))

    # Restore the street address visually: a real stone apron continues from each door to its street.
    d = ImageDraw.Draw(ground)
    for entry in area.warps:
        if entry.get("source_warp") == "matrix":
            continue
        x, y = entry["at"]
        left, top = x * px, y * px
        apron = [
            (left - px, top - 2),
            (left + 2 * px, top - 2),
            (left + 2 * px, top + px // 2),
            (left + px + 3, top + px + 2),
            (left - 3, top + px + 2),
            (left - px, top + px // 2),
        ]
        d.polygon(apron, fill="#d1c1a2", outline="#ad9f88")
        d.line((left - 3, top + px, left + px + 3, top + px), fill="#efe0bb")
    return ground
