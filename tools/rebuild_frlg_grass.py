#!/usr/bin/env python3
"""Rebuild FireRed outdoor encounter tiles from pret/pokefirered layout data."""
import argparse
import json
import struct
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))


def grass_grid(source, layout, primary, secondary, sizes):
    width, height = sizes
    raw = (source / layout["blockdata_filepath"]).read_bytes()
    if len(raw) != width * height * 2:
        raise ValueError(f"Unexpected map dimensions for {layout['name']}")
    grass = []
    for (block,) in struct.iter_unpack("<H", raw):
        tile = block & 0x3FF
        table, index = (primary, tile) if tile < len(primary) else (secondary, tile - len(primary))
        behavior = table[index] & 0x1FF
        grass.append(int(behavior in (0x02, 0xD1)))  # MB_TALL_GRASS / cycling-road encounter grass
    return [grass[i:i + width] for i in range(0, len(grass), width)]


def build(source, project):
    layouts = {row["id"]: row for row in read(source / "data/layouts/layouts.json")["layouts"] if "id" in row}
    base = project / "content/emerald_maps"
    composed_path = base / "kanto_main.json"
    composed = read(composed_path)
    members = composed["member_maps"]
    field = read(project / "content/regions/kanto/maps/kanto_main.json")
    targets = {"LAYOUT_" + zone["name"] for zone in field["zones"] if zone.get("encounters")}
    for region in ("kanto", "sevii"):
        for file in (project / "content/regions" / region / "maps").glob("*.json"):
            entry = read(file)
            if entry.get("encounters") and entry.get("emerald"):
                target = base / (entry["emerald"] + ".json")
                if target.exists():
                    targets.add(read(target).get("id", ""))
    tables = {}
    for path in (source / "data/tilesets").glob("*/*/metatile_attributes.bin"):
        # Upstream symbols omit underscores and capitalize each word.
        name = "gTileset_" + "".join(word.capitalize() for word in path.parent.name.split("_"))
        tables[name.casefold()] = [v for (v,) in struct.iter_unpack("<I", path.read_bytes())]
    changed = []
    for path in sorted(base.glob("*.json")):
        meta = read(path)
        key = meta.get("id", "")
        if key not in targets or key not in layouts:
            continue
        layout = layouts[key]
        if [layout["width"], layout["height"]] != meta["size"]:
            raise ValueError(f"Layout size mismatch: {path.name}")
        grid = grass_grid(source, layout, tables[layout["primary_tileset"].casefold()],
                          tables[layout["secondary_tileset"].casefold()], meta["size"])
        if (meta.get("grass") or any(any(row) for row in grid)) and grid != meta.get("grass"):
            meta["grass"] = grid
            save(path, meta)
            changed.append(path.stem)
        member = key.removeprefix("LAYOUT_")
        if member in members:
            x, y = members[member]
            for off, row in enumerate(grid):
                composed["grass"][y + off][x:x + len(row)] = row
    if composed["grass"] != read(composed_path)["grass"]:
        save(composed_path, composed)
        changed.append(composed_path.stem)
    print("Updated grass maps:", ", ".join(changed) or "already current")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("firered", type=Path, help="pret/pokefirered checkout (ce6406d8)")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    build(args.firered, args.project)
