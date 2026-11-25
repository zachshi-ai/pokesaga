"""Re-lay recurring ground tiles, leaving landmark art and special floors intact."""

import json, zlib

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, PngImagePlugin
from scipy import ndimage

from galar_atlas.art import ROOT, chip, mask, prop, surface
from switch_fields.galar_streets import repeat

# These palette centroids identify repeated 16px source ground families. Unique
# rails, bridge planks, roofs, signs, etc. stay in the original composite.
FAMILIES = [
    ((118, 196, 173), "L"),
    ((79, 156, 105), "G"),
    ((100, 173, 81), "F"),
    ((103, 181, 148), "G"),
    ((220, 205, 134), "S"),
    ((156, 133, 117), "R"),
    ((154, 136, 120), "C"),
    ((215, 226, 220), "N"),
    ((164, 219, 247), "I"),
    ((115, 194, 242), "W"),
    ((91, 120, 207), "W"),
    ((178, 165, 146), "P"),
    ((162, 168, 163), "P"),
    ((115, 118, 134), "P"),
    ((167, 132, 105), "C"),
    ((145, 129, 95), "R"),
    ((126, 163, 178), "N"),
    ((197, 212, 196), "N"),
]
TOWN = {"galar_ballonlea", "galar_circhester", "galar_stow", "galar_turffield"}
DLC = {
    "armor_cave",
    "armor_fields",
    "armor_steps",
    "armor_wetland",
    "armor_forest",
    "crown_freezington",
    "crown_bed",
    "crown_lake",
    "crown_slope",
    "crown_tree",
    "crown_ruins",
}
ROAD = {
    "galar_" + x
    for x in "1 2 3 4 5 6 7 8 9 10 mine mine2 slope tangle tunnel weald wild_lake wild_north wild_south lake_out pass_armor_fields pass_crown_freezington pass_kalos_cyllage".split()
}
REV = "emerald-ground-1"


def metadata():
    out = PngImagePlugin.PngInfo()
    out.add_text("GalarMapGround", REV)
    return out


def finish(em, mid, m, path):
    src = Image.open(path)
    if src.info.get("GalarMapGround") == REV:
        return
    im = src.convert("RGB")
    pix = np.array(im)
    size = im.size
    w, h = m["size"]
    cells = pix.reshape(h, 16, w, 16, 3).transpose(0, 2, 1, 3, 4)
    blocks = cells.reshape(h * w, -1)
    unique, inverse, counts = np.unique(
        blocks, axis=0, return_counts=True, return_inverse=True
    )
    a = np.full((h, w), "?", dtype="U1")
    families = np.asarray([v for v, k in FAMILIES])
    phys = np.array(m["tiles"])
    for i, sample in enumerate(unique):
        if counts[i] < 4:
            continue
        c = sample.reshape(256, 3).mean(axis=0)
        dif = np.linalg.norm(families - c, axis=1)
        j = np.argmin(dif)
        if dif[j] > 33:
            continue
        kind = FAMILIES[j][1]
        bits = inverse.reshape(h, w) == i
        if kind == "W":
            # Only actual water or the wet forms of this specific floor.
            bits &= phys == 2
        if kind in "RL" and mid in (
            "galar_9",
            "galar_10",
            "galar_slope",
            "galar_pass_crown_freezington",
        ):
            kind = "R" if kind == "R" else "N"
        if mid in (
            "galar_mine",
            "galar_mine2",
            "galar_tunnel",
            "galar_pass_kalos_cyllage",
            "armor_cave",
        ):
            if kind in "LSPMR":
                kind = "C" if kind != "R" else "R"
        if mid == "galar_6" and kind in "LS":
            kind = "D"
        if mid == "galar_8" and kind == "S":
            kind = "P"
        if mid == "galar_tangle" or mid == "galar_ballonlea":
            if kind in "FL":
                kind = "H"
            if kind == "S":
                kind = "M"
        if mid in (
            "galar_circhester",
            "crown_freezington",
            "crown_bed",
            "crown_lake",
            "crown_slope",
        ):
            if kind in "LIS":
                kind = "N"
        if mid == "galar_stow" and kind in "LS":
            kind = "D"
        if mid == "galar_4" and kind == "G":
            kind = "D"
        a[bits] = kind
    a[phys == 2] = "W"
    if not np.any(a != "?"):
        return
    # Restore neighbouring material across corners without softening the pixel art.
    missing = a == "?"
    idx = ndimage.distance_transform_edt(
        missing, return_distances=False, return_indices=True
    )
    b = a[tuple(idx)]
    replace = mask(~missing, size, 2)
    ground = surface(em, b, zlib.crc32(mid.encode()))
    im.paste(ground, (0, 0), replace)
    # The Freezington high street and museum terrace are paved despite their snow cover.
    # A temple glyph and field boundaries are features in the ground rather than objects
    # competing for actors' movement cells.
    d = ImageDraw.Draw(im)
    if mid == "galar_turffield":
        # White chalk geoglyph on the cliff flank to the west of the stadium.
        lines = [
            [(3, 6), (5, 4), (7, 5), (5, 7), (5, 9)],
            [(2, 8), (4, 7), (5, 7), (7, 8), (8, 7)],
            [(5, 9), (3, 11), (2, 11)],
            [(5, 9), (7, 11), (8, 10)],
        ]
        for line in lines:
            p = [(x * 13 + 13, y * 9 + 8) for x, y in line]
            d.line(p, fill="#a3a689", width=4)
            d.line(p, fill="#dfddc2", width=2)
    if mid == "galar_circhester":
        x, y = 14 * 16 + 8, 15 * 16 + 5
        d.rounded_rectangle(
            (x - 32, y - 20, x + 32, y + 13),
            7,
            fill="#c9c8ad",
            outline="#898c83",
            width=2,
        )
        d.rounded_rectangle(
            (x - 26, y - 16, x + 26, y + 8),
            5,
            fill="#8ab6bb",
            outline="#779b9f",
            width=2,
        )
        for dx, dy in [(-17, -9), (5, -2), (-6, 3)]:
            d.arc((x + dx, y + dy, x + dx + 9, y + dy + 3), 15, 165, fill="#bad3cf")
    im.save(path, pnginfo=metadata(), optimize=True)


def apply(em):
    for mid in sorted(
        (TOWN | DLC | ROAD) - {"crown_tree", "crown_lake", "crown_freezington"}
    ):
        path = ROOT / "content/regions" / mid.split("_")[0] / "maps" / (mid + ".json")
        m = json.loads(path.read_bytes())
        art = ROOT / m["hoenn_art"]["scene"][0][6:]
        finish(em, mid, m, art)
