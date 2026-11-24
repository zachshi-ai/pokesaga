"""Dress each playable BW/B2 field from its own matrix, original textures and prop placements."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from ds_pixel_art import fit_spawn
from ds_stage_floor import light_floor
from unova_art import ROOT
from unova_interiors import bake
from unova_locations import assign
from unova_source import UnovaSource


def dress(bw, b2, black_models, era, selected):
    sequel = UnovaSource(bw, b2, "b2")
    source = sequel if era == "b2" else UnovaSource(bw, b2, era)
    source.companion = sequel
    source.black_glbs = black_models
    assign(source)
    from unova_transit_art import PLACES, paint, atlas

    atlas()
    total, missing = 0, []
    for file in sorted((ROOT / "content/unova_native" / era).glob("*.json")):
        doc = json.loads(file.read_bytes())
        if selected and doc["id"] not in selected:
            continue
        art = doc["hoenn_art"]
        if doc["id"] in PLACES:
            paint(doc)
            file.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n")
            total += 1
            continue
        if art.get("scene", [""])[0].startswith("res://assets/unova/landmarks/"):
            light_floor(doc)
            if "/scenery/" in art.get("scene", [""])[0]:
                file.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n")
            continue
        zone = source.zones[doc["unova_zone_id"]]
        if doc["id"] != zone["mid"]:
            zone = dict(zone, mid=doc["id"])
        area = {
            "z": zone,
            "size": doc["size"],
            "blocks": source.blocks(zone["i"]),
            "origin": doc["unova_origin"],
            "warps": doc["warps"],
            "grass": np.array(doc["physics"].get("grass", []), dtype=bool),
            "collision": np.array(doc["physics"]["collision"], dtype=bool),
        }
        scene = bake(source, area)
        if not scene:
            missing.append(doc["id"])
            continue
        art["scene"] = scene
        with Image.open(ROOT / scene[0][6:]) as sheet:
            fit_spawn(doc, sheet.convert("RGBA"), "unova_previous_spawn", scene[1:])
        # The model includes signs, foliage and the original architecture. Keep
        # the tile layer below it on walkable rail approaches outside the model.
        art["p"] = area.get("street_facades", [])
        light_floor(doc)
        file.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n")
        total += 1
        if total % 50 == 0:
            print(era, total, flush=True)
    print(era, "dressed", total, "no native geometry", missing, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bw", "b2", "black_models"):
        parser.add_argument(name, type=Path)
    parser.add_argument("era", choices=("bw", "b2"))
    parser.add_argument("maps", nargs="*")
    args = parser.parse_args()
    dress(args.bw, args.b2, args.black_models, args.era, args.maps)
