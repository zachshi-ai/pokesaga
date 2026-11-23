"""Store cropped, Emerald-paletted DS field art. Identical rooms share one texture."""

import hashlib
from pathlib import Path

import numpy as np
from PIL import Image


def save_scene(indexed, alpha, directory):
    # Quantize against a fixed palette. Pillow may choose indices used by equivalent
    # RGB entries; compact them and reserve exactly one transparent index.
    colors = np.array(indexed.getpalette(), dtype=np.uint8).reshape(-1, 3)
    pixels = np.asarray(indexed)
    covered = np.asarray(alpha) >= 128
    order = np.unique(pixels[covered])
    unique, reverse = np.unique(colors[order], axis=0, return_inverse=True)
    if len(unique) == 256:
        # Palette index zero is needed for transparency. Fold the closest pair.
        distances = np.sum((unique[:, None].astype(int) - unique[None, :]) ** 2, axis=2)
        np.fill_diagonal(distances, 1 << 30)
        low, high = sorted(np.unravel_index(np.argmin(distances), distances.shape))
        reverse[reverse == high] = low
        reverse[reverse > high] -= 1
        unique = np.delete(unique, high, axis=0)
    lookup = np.zeros(256, dtype=np.uint8)
    lookup[order] = reverse + 1
    rows = np.where(covered, lookup[pixels], 0).astype(np.uint8)
    palette = bytes(3) + unique.tobytes()
    key = hashlib.sha256(str(indexed.size).encode() + palette + rows.tobytes()).hexdigest()[:24]
    file = Path(directory) / (key + ".png")
    if not file.exists():
        file.parent.mkdir(parents=True, exist_ok=True)
        image = Image.frombytes("P", indexed.size, rows.tobytes())
        image.putpalette(palette)
        image.save(file, transparency=0, compress_level=7)
    return file


def fit_spawn(doc, background, previous_key, offset=(0, 0)):
    from collections import Counter
    from scipy import ndimage

    width, height = doc["size"]
    # Only sample the centres of walking cells covered by the cropped model.
    ix = np.arange(width) * 16 + 8 - offset[0]
    iy = np.arange(height) * 16 + 8 - offset[1]
    valid_x = (ix >= 0) & (ix < background.width)
    valid_y = (iy >= 0) & (iy < background.height)
    alpha = np.asarray(background.getchannel("A"))
    floor = alpha[np.clip(iy, 0, background.height - 1)[:, None], np.clip(ix, 0, background.width - 1)] > 128
    floor &= valid_x[None, :] & valid_y[:, None] & (np.asarray(doc["physics"]["collision"]) == 0)
    old = doc.get(previous_key, doc["spawn"])
    x, y = old
    if floor[y, x]:
        return
    labels, count = ndimage.label(floor)
    if not count:
        return
    # Inside a home or a facility the player must be able to walk to a real exit.
    touch = ndimage.maximum_filter(floor.astype("uint8"), size=3)
    scores = Counter()
    for warp in doc["warps"]:
        wx, wy = warp["at"]
        if warp.get("to", {}).get("map") == doc["id"] or not touch[wy, wx]:
            continue
        for nx, ny in ((wx, wy), (wx, wy - 1), (wx, wy + 1), (wx - 1, wy), (wx + 1, wy)):
            if 0 <= nx < width and 0 <= ny < height and labels[ny, nx]:
                scores[int(labels[ny, nx])] += 1
    candidates = (
        np.isin(labels, list(scores)) if scores else labels == np.bincount(labels.ravel())[1:].argmax() + 1
    )
    for v in [*doc["warps"], *doc["npcs"]]:
        nx, ny = v["at"]
        if 0 <= nx < width and 0 <= ny < height:
            candidates[ny, nx] = False
    inds = np.argwhere(candidates)
    if not len(inds):
        return
    ny, nx = inds[np.argmin(np.abs(inds[:, 0] - y) + np.abs(inds[:, 1] - x))]
    doc[previous_key] = old
    doc["spawn"] = [int(nx), int(ny)]
