"""Stream the Underground's 225 matrix cells with a compact native wall/floor atlas."""

import math

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

from bake_emerald_field import pack
from platinum_layout import ROOT
from platinum_scenery import base_height, mesh, paint
from unova_interiors import palette


def paint_maze(doc, rows, geo, cache):
    # Sixteen reusable labyrinth chunks form a 480 by 480 field. A single scenery
    # image would exceed mobile texture limits. Preserve the native cells and
    # approximate visually similar 16px chips with a shared Emerald-colour tile.
    unique = {}
    counts = []
    raw_tiles = []
    parts = {}
    for land in sorted(set(rows.values())):
        shapes = mesh(cache / f"ground_{land}_{geo['area']}.glb")
        pixels = np.zeros((512, 512, 4), "uint8")
        z = np.full((512, 512), -1e20, "float32")
        paint(shapes, pixels, z, (256, 256), ground=True, base=base_height(shapes))
        im = Image.fromarray(pixels)
        image = im.convert("RGB").quantize(palette=palette(), dither=Image.Dither.NONE).convert("RGBA")
        image.putalpha(im.getchannel("A"))
        ids = np.zeros((32, 32), int)
        for y, x in np.ndindex(ids.shape):
            t = image.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16))
            key = t.tobytes()
            if key not in unique:
                unique[key] = len(raw_tiles)
                counts.append(0)
                raw_tiles.append(t)
            i = unique[key]
            ids[y, x] = i
            counts[i] += 1
        parts[land] = ids
    features = np.array(
        [np.asarray(t.resize((4, 4), Image.Resampling.BOX)).ravel() for t in raw_tiles], dtype="float32"
    )
    selected = list(np.argsort(-np.array(counts), kind="stable")[:128])
    dist, _ = cKDTree(features[selected]).query(features)
    for _ in range(min(256, len(dist) - len(selected))):
        far = int(np.argmax(dist))
        if dist[far] < 1:
            break
        selected.append(far)
        dist = np.minimum(dist, np.linalg.norm(features - features[far], axis=1))
    _, nearest = cKDTree(features[selected]).query(features)
    atlas = ROOT / "assets/platinum_native/tiles.png"
    with Image.open(atlas) as f:
        old = f.convert("RGBA")
    chips = [
        old.crop((x, y, x + 16, y + 16)) for y in range(0, old.height, 16) for x in range(0, old.width, 16)
    ]
    used = {}
    for i, chip in enumerate(chips):
        used.setdefault(chip.tobytes(), i)
    offsets = []
    for src in selected:
        key = raw_tiles[src].tobytes()
        if key not in used:
            used[key] = len(chips)
            chips.append(raw_tiles[src])
        offsets.append(used[key])
    out = Image.new("RGBA", (256, 16 * math.ceil(len(chips) / 16)))
    for i, chip in enumerate(chips):
        out.paste(chip, (16 * (i % 16), 16 * (i // 16)))
    if out.size != old.size or out.tobytes() != old.tobytes():
        out.save(atlas, optimize=True)
    grid = np.zeros(doc["size"][::-1], dtype=np.uint16)
    remap = np.array(offsets)[nearest]
    for (x, y), land in rows.items():
        grid[y * 32 : y * 32 + 32, x * 32 : x * 32 + 32] = remap[parts[land]]
    doc["hoenn_art"]["t"] = pack(grid)
