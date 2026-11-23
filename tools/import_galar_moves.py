"""Import Sword/Shield level-up moves, matching move symbols to PokeSaga's catalogue."""
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def build(pokemon_moves, moves):
    with moves.open() as stream:
        symbols={re.sub("[^a-z0-9]","",m["key"].lower()):m["id"] for m in json.loads((ROOT/"content/moves.json").read_text())}
        numbers={row["id"]:symbols.get(row["identifier"].replace("-","")) for row in csv.DictReader(stream)}
    species={}
    for sid,entry in json.loads((ROOT/"content/dex_catalog.json").read_text())["species"].items():
        for variant in entry["variants"]:
            species.setdefault(str(variant["pokeapi_id"]),variant["form"] or sid)
    levels=defaultdict(list)
    with pokemon_moves.open() as stream:
        for row in csv.DictReader(stream):
            if row["version_group_id"]!="20" or row["pokemon_move_method_id"]!="1":
                continue
            key=species.get(row["pokemon_id"])
            move=numbers.get(row["move_id"])
            if key and move:
                levels[key].append((int(row["level"]),int(row["order"] or 0),move))
    data={key:[[lv,move] for lv,_,move in sorted(set(rows))] for key,rows in levels.items()}
    assert all(key in data for key in ("810","813","816","831","829","830"))
    (ROOT/"content/galar_moves.json").write_text(json.dumps(data,separators=(",",":"))+"\n")


if __name__=="__main__":
    build(Path(sys.argv[1]),Path(sys.argv[2]))
