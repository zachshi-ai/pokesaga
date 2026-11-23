"""Check every expanded habitat, international crossing, art reference and authentic room entrance."""

from collections import defaultdict
from pathlib import Path
import json

import numpy as np
from PIL import Image
from scipy import ndimage

from island_places import ALOLA, EXPEDITIONS, parse
from island_households import ROOMS
from island_special_spaces import PLANS
from island_scenery import edition_points

ROOT = Path(__file__).resolve().parents[1]


def read(p):
    return json.loads(p.read_bytes())


def main():
    allmaps = {
        (p.parent.parent.name, p.stem): read(p)
        for p in (ROOT / "content/regions").glob("*/maps/*.json")
    }
    requested = (
        set(parse(EXPEDITIONS))
        | {"alola_" + k for k in parse(ALOLA)}
        | {"alola_" + r[1] for r in ROOMS}
        | {"alola_1"}
    )
    arrivals = defaultdict(set)
    for m in allmaps.values():
        for w in m.get("warps", []):
            dest = w.get("to", {})
            if isinstance(dest.get("at"), list):
                arrivals[(dest.get("region"), dest["map"])].add(tuple(dest["at"]))
    checked = set()
    paths = 0
    objects = 0
    for (reg, mid), m in allmaps.items():
        if mid not in requested:
            continue
        assert m.get("island_field_revision") == 1, mid
        checked.add(mid)
        w, h = m["size"]
        a = m["hoenn_art"]
        with Image.open(ROOT / a["scene"][0][6:]) as img:
            assert img.size == (16 * w, 16 * h), (mid, img.size)
        assert len(a["p"]) >= 2, (mid, "landmark fixtures")
        for prop in a["p"]:
            asset = prop[0]
            file = ROOT / (
                asset[6:]
                if asset.startswith("res://")
                else "assets/emerald/field/" + asset + ".png"
            )
            assert file.is_file() and 0 <= prop[1] < w and 0 <= prop[2] < h, (mid, prop)
        if m.get("alola_native"):
            grid = ~np.asarray(m["physics"]["collision"], bool)
            if "water" in m["physics"]:
                grid &= ~np.asarray(m["physics"]["water"], bool)
        else:
            grid = ~np.isin(m["tiles"], [1, 2, 6, 7])
        for row in m.get("npcs", []) + m["warps"]:
            x, y = row["at"]
            grid[y, x] = False
        labels, _ = ndimage.label(grid)
        sx, sy = m["spawn"]
        assert labels[sy, sx], mid
        reachable = labels == labels[sy, sx]
        near = ndimage.binary_dilation(reachable)
        for x, y in arrivals[(reg, mid)]:
            assert reachable[y, x], (mid, "landing", x, y)
        for warp in m["warps"]:
            x, y = warp["at"]
            assert near[y, x], (mid, "exit", x, y)
            paths += 1
        for x, y in edition_points().get(mid, ()):
            assert near[y, x], (mid, "version-specific item", x, y)
            objects += 1
        short = mid.removeprefix("alola_")
        if reg == "alola" and short in PLANS:
            size, route, loop = PLANS[short]
            assert m["size"] == list(size), (mid, m["size"])
            for x, y in [route[-1], loop[2]]:
                assert near[y, x], (mid, "deep habitat", x, y)
    assert checked == requested, requested - checked
    for parent, key, *_ in ROOMS:
        town = allmaps[("alola", "alola_" + parent)]
        room = allmaps[("alola", "alola_" + key)]
        w = next(row for row in town["warps"] if row["to"]["map"] == room["id"])
        x, y = w["at"]
        assert room["warps"][0]["to"]["at"] == [x, y + 1]
        assert any(p[1:3] == [x, y - 1] for p in town["hoenn_art"]["p"]), (
            parent,
            key,
            "facade disconnected",
        )
    print(
        "ISLAND FIELDS PASS",
        len(checked),
        "redrawn maps,",
        paths,
        "exits,",
        objects,
        "version-specific item positions",
    )


if __name__ == "__main__":
    main()
