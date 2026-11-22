#!/usr/bin/env python3
"""Build Emerald's field item tables from the same checkout as build_hoenn_native.py."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("--tmhm", type=Path, help="override the learnset path in a sparse checkout")
args = parser.parse_args()
source = args.source
read = lambda file: json.loads(file.read_text())
maps = read(ROOT / "content/hoenn_native/index.json")
species = {v["key"]: v["id"] for v in read(ROOT / "content/species.json") if v["id"] <= 386}
moves = {"CUT":15,"FLY":19,"SURF":57,"STRENGTH":70,"FLASH":148,"ROCK_SMASH":249,"WATERFALL":127,"DIVE":291}
machine_table = {move_id: [] for move_id in moves.values()}
txt = (args.tmhm or source / "src/data/pokemon/tmhm_learnsets.h").read_text()
for key, machine_list in re.findall(r'\[SPECIES_(\w+)\]\s*=\s*\{\s*\.learnset\s*=\s*\{([^}]*)',txt):
    if key not in species:
        continue
    for move in re.findall(r'\.(\w+)\s*=\s*TRUE',machine_list):
        if move in moves:
            machine_table[moves[move]].append(species[key])
assert 258 in machine_table[57] and 255 not in machine_table[57]
fishing = {}
wild = read(source / "src/data/wild_encounters.json")["wild_encounter_groups"][0]
layout = next(f for f in wild["fields"] if f["type"] == "fishing_mons")
for record in wild["encounters"]:
    if not record.get("fishing_mons") or record.get("map") not in maps:
        continue
    pool = []
    for indexes in layout["groups"].values():
        row = []
        for index in indexes:
            mon = record["fishing_mons"]["mons"][index]
            row.append(dict(species=species[mon["species"][8:]],min=mon["min_level"],
                            max=mon["max_level"],weight=layout["encounter_rates"][index]))
        pool.append(row)
    fishing[record["map"]] = pool
names = {"LITTLEROOT":"未白镇","OLDALE":"古玫镇","DEWFORD":"武斗镇","LAVARIDGE":"釜炎镇",
         "FALLARBOR":"秋叶镇","VERDANTURF":"绿荫镇","PACIFIDLOG":"暮水镇","PETALBURG":"橙华市",
         "SLATEPORT":"凯那市","MAUVILLE":"紫堇市","RUSTBORO":"卡那兹市","FORTREE":"茵郁市",
         "LILYCOVE":"水静市","MOSSDEEP":"绿岭市","SOOTOPOLIS":"琉璃市","EVER":"彩幽市"}
fly = []
for loc in read(source / "src/data/heal_locations.json")["heal_locations"]:
    key=loc["map"]
    if key[4:].split("_")[0] not in names or not key.endswith(("_TOWN","_CITY")):
        continue
    if loc["id"].endswith("MAYS_HOUSE"): continue
    name = "丰缘宝可梦联盟" if loc["id"].endswith("_POKEMON_LEAGUE") else names[key[4:].split("_")[0]]
    fly.append({"name": name, "map":"hoenn/"+maps[key], "at":[loc["x"],loc["y"]]})
route = read(source / "data/maps/Route111/map.json")
gates = [[e["x"],e["y"]] for e in route["coord_events"] if "ViciousSandstorm" in e["script"]]
assert len(fly)==17 and len(fishing)>25 and gates
out = dict(learn=machine_table,fishing=fishing,fly=fly,sand_gates=gates)
(ROOT/"content/hoenn_field_items.json").write_text(json.dumps(out,ensure_ascii=False,separators=(",",":"))+"\n")
