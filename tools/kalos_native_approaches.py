"""Restore X/Y thresholds whose approaches cross water, a canopy, a tidal bar or a roof."""

import heapq
import json
from pathlib import Path

import numpy as np
from kalos_mesh import FieldModel
from kalos_surfaces import put

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "content/regions/kalos/maps"
# Each target coordinate is read from the original XY warp table. The landing
# offset is the adjacent usable tile outside the model door.
LOCATIONS = [
    ("kalos_azure", 0, (-1, 0), "step"),
    ("kalos_14", 1, (0, 1), "door"),
    ("kalos_shalour", 8, (0, 1), "door"),
    ("kalos_league_gate", 0, (0, 1), "step"),
]


def footprint(source, room, match):
    model = source / ("view-" + str(room["kalos_matrix"]) + ".glb.gzip")
    w, h = room["size"]
    active = np.zeros((h, w), "int16")
    height = np.full((h, w), -1e6, "float32")
    for _, name, xyz, _, triangles, *_ in FieldModel(model).parts():
        if match(name):
            put(height, active, xyz, triangles, 1, room["kalos_origin"])
    return active.astype(bool)


def forest_path(source, room, collision, target):
    roads = footprint(
        source, room, lambda m: "michi" in m or "hashi" in m or "kaidan" in m
    )
    # The floor continues for two tiles beneath overhanging autumn foliage there.
    # Check the source floor triangles before exposing these two cells.
    lawn = footprint(source, room, lambda m: m == "au_kusa01")
    for x, y in [(28, 45), (28, 46)]:
        if not lawn[y, x]:
            raise ValueError(("Missing Route 14 marsh bank", x, y))
        roads[y, x] = True
    start = tuple(room["spawn"])
    h, w = collision.shape
    queue = [(0, start)]
    previous = {}
    dist = {start: 0}
    while queue:
        cost, here = heapq.heappop(queue)
        if here == target:
            break
        if dist[here] != cost:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x, y = here[0] + dx, here[1] + dy
            if not (0 <= x < w and 0 <= y < h) or (collision[y, x] and not roads[y, x]):
                continue
            step = cost + (35 if collision[y, x] else 1)
            if step < dist.get((x, y), 1e20):
                previous[x, y] = here
                dist[x, y] = step
                heapq.heappush(queue, (step, (x, y)))
    here = target
    if here not in previous:
        raise ValueError("No source-supported path to the Scary House")
    while here != start:
        x, y = here
        collision[y, x] = False
        here = previous[here]


def join_fields(
    room, other_id, point, receiving_point, approach, receiving_approach, water=False
):
    path = MAPS / (other_id + ".json")
    other = json.loads(path.read_bytes())
    for data, dest, gate_at, arrival, heading in (
        (room, other_id, point, receiving_approach, "down" if water else "up"),
        (other, room["id"], receiving_point, approach, "up" if water else "down"),
    ):
        gate = next(
            w
            for w in data["warps"]
            if w.get("source_warp") == "matrix" and w["to"]["map"] == dest
        )
        gate["at"] = gate_at
        gate["trigger"] = heading
        gate["to"]["at"] = arrival
        gate["to"]["facing"] = heading
        if water:
            gate["to"]["surf_arrival"] = True
    path.write_text(json.dumps(other, ensure_ascii=False, separators=(",", ":")) + "\n")


def paint_tidal_bar(pic, room, pixels):
    """Connect the two waterlines to the surfable cells of Shalour's causeway."""
    from PIL import Image
    from kalos_field_palette import pattern

    left, top, right, bottom = 36 * pixels, 54 * pixels, 49 * pixels, 93 * pixels
    original = np.asarray(pic.crop((left, top, right, bottom))).copy()
    yy, xx = np.indices(original.shape[:2])
    gx, gy = xx + left, yy + top
    coast = np.asarray(room["physics"]["water"], bool)
    lo, hi = np.empty(bottom - top), np.empty(bottom - top)
    for j in range(bottom - top):
        row = (top + j) // pixels
        center = 42
        west = east = center
        while west > 37 and not coast[row, west - 1]:
            west -= 1
        while east < 47 and not coast[row, east + 1]:
            east += 1
        lo[j], hi[j] = west * pixels, (east + 1) * pixels
    # Taper the margin within the tile. Every walkable tile center stays dry.
    from scipy.ndimage import gaussian_filter1d

    lo = gaussian_filter1d(lo, 4)[:, None] + 3 * np.sin(gy / 23) + np.sin(gy / 8)
    hi = gaussian_filter1d(hi, 4)[:, None] + 3 * np.sin(gy / 31 + 0.6) + np.sin(gy / 6)
    distance = np.minimum(gx - lo, hi - gx)
    wet = pattern("water")[gy % 16, gx % 16].astype(float)
    sand = pattern("sand")[gy % 16, gx % 16].astype(float)
    strip = np.where((distance >= 0)[:, :, None], sand, wet)
    for mn, mx, color in [
        (-5, -2, [109, 167, 188]),
        (-2, 0, [193, 210, 192]),
        (0, 4, [208, 188, 152]),
    ]:
        mask = (distance >= mn) & (distance < mx)
        strip[mask] = np.asarray(color) * 0.83 + strip[mask] * 0.17
    end = np.minimum(yy, bottom - top - yy - 1) / (pixels * 2)
    side = np.minimum(xx, right - left - xx - 1) / (pixels * 1.7)
    weight = np.clip(np.minimum(end, side), 0, 1)[:, :, None]
    result = (strip * weight + original * (1 - weight)).astype("uint8")
    pic.paste(Image.fromarray(result), (left, top))


def install(source):
    zones = json.loads((source / "map.json").read_bytes())["zones"]
    for mid, index, landing_offset, trigger in LOCATIONS:
        parent = MAPS / (mid + ".json")
        room = json.loads(parent.read_bytes())
        xy = zones[str(room["kalos_zone"])]["warps"][index]
        ox, oy = room["kalos_origin"]
        x, y = int(xy[0] // 18) - ox, int(xy[2] // 18) - oy
        gate = next(
            w for w in room["warps"] if w.get("source_warp") == "xy_" + str(index)
        )
        child = MAPS / (gate["to"]["map"] + ".json")
        inside = json.loads(child.read_bytes())
        back = next(w for w in inside["warps"] if w["to"]["map"] == mid)
        landing = (x + landing_offset[0], y + landing_offset[1])
        phy = room["physics"]
        collision = np.asarray(phy["collision"], bool)
        if mid == "kalos_azure":
            # Keep the older save's elevated southern picnic area and its event
            # anchors accessible. A two-tile landing descends to the sea.
            collision[167:170, 99:101] = False
            room["kalos_shore_steps"] = [99, 167, 2, 3]
            # Route 12 meets the bay over water at the shared matrix edge.
            join_fields(room, "kalos_12", [55, 204], [55, 5], [55, 203], [55, 6], True)
        elif mid == "kalos_14":
            # The south-facing facade covers five cells. Retain the single
            # up-facing door and keep the player outside its two wall wings.
            collision[19:23, 8:13] = True
            forest_path(source, room, collision, landing)
            # Laverre's southern edge is at global row 519. Its former seam
            # intercepted the only footpath halfway through the forest.
            join_fields(room, "kalos_laverre", [22, 5], [23, 82], [22, 6], [23, 81])
        elif mid == "kalos_shalour":
            # The exposed tidal bar is three tiles across for most of its length.
            # The sea mesh under it and the masonry at the island edge had sealed the approach.
            wet = np.asarray(phy["water"], bool)
            for row in range(53, 94):
                left, right = (
                    (41, 43) if row < 77 else (40, 43) if row < 82 else (41, 43)
                )
                collision[row, left : right + 1] = False
                wet[row, left : right + 1] = False
            phy["water"] = wet.astype("uint8").tolist()
        elif mid == "kalos_league_gate":
            deck = footprint(
                source,
                room,
                lambda m: m in ("gate_kaidan01", "gate_yuka02", "gate_yuka01"),
            )
            yy, xx = np.indices(collision.shape)
            collision[deck & (xx > 9) & (xx < 22) & (yy > 3) & (yy < 49)] = False
            # The height changes again where the tiled walkway passes under the stone lintel.
            collision[14:18, 13:17] = False
        gate["at"] = [x, y]
        gate["trigger"] = trigger
        back["to"]["at"] = list(landing)
        if collision[landing[1], landing[0]]:
            raise ValueError((mid, "blocked return", landing))
        phy["collision"] = collision.astype("uint8").tolist()
        for file, doc in ((parent, room), (child, inside)):
            file.write_text(
                json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n"
            )


if __name__ == "__main__":
    import sys

    install(Path(sys.argv[1]))
