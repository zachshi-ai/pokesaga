"""Paint a continuous 16px field from the same relief used for movement."""

from functools import lru_cache
from pathlib import Path
from random import Random

import numpy as np
from PIL import Image, ImageDraw, ImageChops, ImageFilter

from switch_fields.galar_streets import repeat

ROOT = Path(__file__).resolve().parents[2]
# Shade native Emerald materials locally while retaining the original pixel clusters.
TONE = {
    "L": ("LittlerootTown", 1, (132, 177, 116), 0.64),
    "F": ("LittlerootTown", 1, (111, 151, 113), 0.63),
    "H": ("LittlerootTown", 1, (98, 125, 116), 0.52),
    "G": ("LittlerootTown", 1, (122, 166, 108), 0.79),
    "R": ("Route113", 0x71, (148, 139, 118), 0.45),
    "C": ("GraniteCave_1F", 0x201, (140, 134, 123), 0.30),
    "W": ("LittlerootTown", 0xA1, (103, 164, 187), 0.62),
    "S": ("LittlerootTown", 0x121, (219, 201, 156), 0.60),
    "D": ("Route111", 0x251, (204, 181, 134), 0.48),
    "N": ("Route113", 0x71, (215, 226, 220), 0.38),
    "I": ("ShoalCave_LowTideIceRoom", 0x38D, (168, 199, 204), 0.42),
    "M": ("LittlerootTown", 0x121, (151, 152, 119), 0.55),
    "P": ("RustboroCity", 0x2BB, (167, 167, 151), 0.70),
    "T": ("LittlerootTown", 0x121, (196, 177, 139), 0.64),
}


@lru_cache(None)
def chip(em, k):
    layout, i, base, scale = TONE[k]
    a = np.asarray(em.metatile(layout, i).convert("RGB"), dtype=float)
    l = a @ [0.29, 0.57, 0.14]
    return Image.fromarray(
        np.clip(np.array(base) + (l - l.mean())[:, :, None] * scale, 0, 255).astype(
            "uint8"
        )
    )


def mask(cells, size, radius=6):
    a = Image.fromarray(cells.astype("uint8") * 255).resize(
        size, Image.Resampling.NEAREST
    )
    return a.filter(ImageFilter.GaussianBlur(radius)).point(
        lambda v: 255 if v >= 123 else 0
    )


def surface(em, m, seed):
    h, w = m.shape
    size = w * 16, h * 16
    im = repeat(chip(em, "L"), size)
    for k in "FRCHSGMDNPITW":
        active = m == k
        if not active.any():
            continue
        boundary = mask(active, size, 2 if k == "P" else 6)
        im.paste(repeat(chip(em, k), size), (0, 0), boundary)
        if k == "W":
            shore = ImageChops.subtract(
                boundary, boundary.filter(ImageFilter.MinFilter(7))
            )
            im.paste("#c6d6be", (0, 0, *size), shore)
        if k == "R":
            # Southern ledges expose their strata, naturally stopping at a corner.
            lip = ImageChops.subtract(boundary, ImageChops.offset(boundary, 0, -8))
            lip.paste(0, (0, size[1] - 8, size[0], size[1]))
            im.paste("#877967", (0, 0, *size), lip)
            lower = ImageChops.subtract(lip, ImageChops.offset(lip, 0, -2))
            im.paste("#756f66", (0, 0, *size), lower)
    rng = Random(seed)
    d = ImageDraw.Draw(im)
    # Contiguous patches of low vegetation, pebbles, fresh snow and ripples.
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            k = m[y, x]
            if k not in "GFLHCWNSDM" or rng.random() > (0.68 if k == "G" else 0.16):
                continue
            X = x * 16 + rng.randint(4, 10)
            Y = y * 16 + rng.randint(5, 10)
            if k in "GFLH":
                shade = "#62845f" if k in "HF" else "#6d995e"
                for i in range(3 if k == "G" else 1):
                    dx = i * 4 - 4
                    dy = (i * 3) % 4
                    d.line(
                        (
                            X + dx - 2,
                            Y + dy - 3,
                            X + dx,
                            Y + dy,
                            X + dx + 2,
                            Y + dy - 4,
                        ),
                        fill=shade,
                    )
            elif k == "W":
                d.line((X - 4, Y, X - 1, Y + 1, X + 3, Y + 1, X + 5, Y), fill="#99bcc7")
            else:
                c = {
                    "C": "#ac9d87",
                    "N": "#c2d1d0",
                    "S": "#c5b18d",
                    "D": "#b59e78",
                    "M": "#a1a684",
                }[k]
                d.line((X - 1, Y, X + 2, Y - 1), fill=c)
                d.point((X + 4, Y + 1), fill=c)
    return im


def prop_path(key):
    for folder in [
        "assets/galar/architecture",
        "assets/switch_fields/props",
        "assets/emerald/field",
    ]:
        p = ROOT / folder / (key + ".png")
        if p.is_file():
            return p
    raise KeyError(key)


def prop(data, key, x, y):
    p = prop_path(key)
    with Image.open(p) as im:
        w, h = im.size
    data.append(
        ["res://" + p.relative_to(ROOT).as_posix(), int(x), int(y), [w // 2, h]]
    )
