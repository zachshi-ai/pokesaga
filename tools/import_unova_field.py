#!/usr/bin/env python3
"""Compile Black and Black 2 encounter slots, plus version-specific moves and machines.

Inputs: Black's extracted files/a/1/2/6, pokebw2 (field/encounters),
and the PokeAPI data/v2/csv directory. All map keys are original encounter IDs.
"""
import argparse
import csv
import json
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GROUPS = {"grass":12,"dark_grass":12,"shaking_grass":12,"surf":5,
          "rippling_surf":5,"fishing":5,"rippling_fishing":5}
SEASONS = ("spring","summer","autumn","winter")


def narc_files(path):
    data = path.read_bytes()
    assert data[:4] == b"NARC"
    fat = data.index(b"BTAF")
    body = data.index(b"GMIF") + 8
    count, = struct.unpack_from("<H",data,fat+8)
    for idx in range(count):
        start, end = struct.unpack_from("<II", data, fat+12+idx*8)
        yield data[body+start:body+end]


def bw_season(raw):
    entries = {}
    pos = 8
    for i,(method,count) in enumerate(GROUPS.items()):
        slots = []
        for j in range(count):
            code, low, high = struct.unpack_from("<HBB",raw,pos+j*4)
            slots.append([code & 2047,low,high,code>>11])
        if raw[i] and any(s[0] for s in slots):
            entries[method] = [raw[i],slots]
        pos += count*4
    assert pos == len(raw)
    entries["phenomenon_setting"] = int(raw[7])
    return entries


def habitat_tables(bw, b2):
    first = {}
    for i, raw in enumerate(narc_files(bw)):
        if len(raw) not in (232,928):
            raise ValueError(f"Invalid wild table {i}: {len(raw)} bytes")
        first[str(i)] = [bw_season(raw[n:n+232]) for n in range(0,len(raw),232)]
    species = {}
    for line in (b2/"generated/species.txt").read_text().splitlines():
        if line.startswith("SPECIES_"): species[line.split()[0]]=len(species)
    second = {}
    def black2(value):
        return value["black2"] if isinstance(value,dict) and "black2" in value else value
    for line in (b2/"generated/encounters.txt").read_text().splitlines():
        if not line.startswith("ENCOUNTERS_"):continue
        key = line.split()[0]
        file = b2/"res/field/encounters"/(key[11:].lower()+".json")
        table = json.loads(file.read_bytes())
        seasons = []
        for season in (("all_year",) if "all_year" in table else SEASONS):
            values = table[season]
            rates = black2(values["rates"])
            mapped = {"phenomenon_setting":int(rates.get("flags",0))}
            for method in GROUPS:
                slots = black2(values[method])
                if rates[method] and slots:
                    mapped[method] = [rates[method], [[species[row[0]],row[1],row[2],row[3] if len(row)>3 else 0] for row in slots]]
            seasons.append(mapped)
        second[key] = seasons
    return {"bw":first, "b2":second}


def moves_and_machines(root):
    def rows(name):
        with (root/(name+".csv")).open() as stream:
            yield from csv.DictReader(stream)
    eras = {"11":"bw","14":"b2"}
    result = {era:{"levels":defaultdict(list),"machines":{},"compatible":defaultdict(list)} for era in eras.values()}
    for row in rows("machines"):
        era = eras.get(row["version_group_id"])
        if era:result[era]["machines"][row["machine_number"]]=int(row["move_id"])
    for row in rows("pokemon_moves"):
        era = eras.get(row["version_group_id"])
        species = int(row["pokemon_id"])
        if not era or species>649:continue
        move = int(row["move_id"])
        if row["pokemon_move_method_id"]=="1":
            result[era]["levels"][species].append((int(row["level"]),int(row["order"] or 0),move))
        elif row["pokemon_move_method_id"]=="4":
            result[era]["compatible"][species].append(move)
    for data in result.values():
        data["levels"]={sid:[[level,move] for level,_,move in sorted(vals)] for sid,vals in data["levels"].items()}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("black_narc",type=Path)
    parser.add_argument("black2",type=Path)
    parser.add_argument("pokeapi_csv",type=Path)
    args=parser.parse_args()
    data={"encounters":habitat_tables(args.black_narc,args.black2), "training":moves_and_machines(args.pokeapi_csv)}
    (ROOT/"content/unova_field.json").write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")
