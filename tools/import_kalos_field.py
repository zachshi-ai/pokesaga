"""Build X/Y field data from the original zones and PokéAPI version group 15."""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def import_tables(directory, atlas):
    def rows(name):
        with (directory / (name + ".csv")).open() as stream:
            yield from csv.DictReader(stream)

    machines = {int(row["machine_number"]): int(row["move_id"])
                for row in rows("machines") if row["version_group_id"] == "15"}
    levels = defaultdict(list)
    compatible = defaultdict(set)
    for row in rows("pokemon_moves"):
        if row["version_group_id"] != "15":
            continue
        species = int(row["pokemon_id"])
        move = int(row["move_id"])
        if row["pokemon_move_method_id"] == "4":
            compatible[species].add(move)
        elif row["pokemon_move_method_id"] == "1":
            levels[species].append((int(row["level"]), int(row["order"] or 0), move))
    zones = json.loads(atlas.read_bytes())["zones"]
    data = {
        "machines": machines,
        "levels": {s: [[lv, mv] for lv, _, mv in sorted(values)] for s, values in levels.items()},
        "compatible": {s: sorted(moves) for s, moves in compatible.items()},
        "wild": {z: row["wild"] for z, row in zones.items() if row.get("wild")},
    }
    assert len(machines) == 105 and len(levels) >= 721 and len(data["wild"]) > 40
    path = ROOT / "content/kalos_field.json"
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_directory", type=Path)
    parser.add_argument("zone_atlas", type=Path)
    args = parser.parse_args()
    import_tables(args.csv_directory, args.zone_atlas)
