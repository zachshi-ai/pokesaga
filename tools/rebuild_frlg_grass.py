#!/usr/bin/env python3
"""Rebuild FireRed grass tiles and land and fishing encounter tables from pret/pokefirered layout data."""
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
        # fieldmap.c extracts METATILE_ATTRIBUTE_ENCOUNTER_TYPE from bits 24–26.
        grass.append(int(((table[index] >> 24) & 7) == 1))
    return [grass[i:i + width] for i in range(0, len(grass), width)]


def build(source, project):
    layouts = {row["id"]: row for row in read(source / "data/layouts/layouts.json")["layouts"] if "id" in row}
    base = project / "content/emerald_maps"
    composed_path = base / "kanto_main.json"
    composed = read(composed_path)
    members = composed["member_maps"]
    field = read(project / "content/regions/kanto/maps/kanto_main.json")
    targets = {"LAYOUT_" + zone["name"] for zone in field["zones"] if zone.get("encounters")}
    wild_group = read(source / "src/data/wild_encounters.json")["wild_encounter_groups"][0]
    land_weights = next(f["encounter_rates"] for f in wild_group["fields"] if f["type"] == "land_mons")
    species = {s["key"]: s["id"] for s in read(project / "content/species.json")}
    rod_field = next(f for f in wild_group["fields"] if f["type"] == "fishing_mons")
    fishing = {}
    encounters = {}
    for row in wild_group["encounters"]:
        if row.get("fishing_mons") and row["base_label"].endswith("_FireRed"):
            key = row["map"].removeprefix("MAP_").replace("_", "").lower()
            slots = row["fishing_mons"]["mons"]
            fishing[key] = [[{"species": species[slots[i]["species"].removeprefix("SPECIES_")],
                              "min": slots[i]["min_level"], "max": slots[i]["max_level"],
                              "weight": rod_field["encounter_rates"][i]} for i in indices]
                            for indices in [rod_field["groups"][rod] for rod in ("old_rod", "good_rod", "super_rod")]]
        if row.get("land_mons") and row["base_label"].endswith("_FireRed"):
            encounters[row["map"].removeprefix("MAP_").replace("_", "").lower()] = row["land_mons"]
    for region in ("kanto", "sevii"):
        for file in (project / "content/regions" / region / "maps").glob("*.json"):
            entry = read(file)
            if file.stem == "kanto_main":
                for area in entry["areas"]:
                    member = next((key for key, xy in members.items() if xy == [area["x0"],area["y0"]]), "")
                    table = fishing.get(member.replace("_","").lower())
                    if table: area["fishing"] = table
            else:
                table = fishing.get(file.stem.replace("_", ""))
                if table: entry["fishing"] = table
            land = encounters.get(file.stem.replace("_","")) or encounters.get(str(entry.get("emerald","")).replace("_",""))
            if land:
                mons = [{"species": species[m["species"].removeprefix("SPECIES_")], "min": m["min_level"],
                         "max": m["max_level"], "weight": w} for m,w in zip(land["mons"], land_weights)]
                if entry.get("encounters") != mons or not entry.get("encounter_rate"):
                    entry["encounters"] = mons
                    entry["encounter_rate"] = round(land["encounter_rate"] / 100.0, 3)
            original = file.read_text()
            if json.loads(original) != entry:
                style = {"indent":1} if original.startswith("{\n") else {"separators":(",",":")}
                file.write_text(json.dumps(entry, ensure_ascii=False, **style) + ("\n" if original.endswith("\n") else ""))
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
