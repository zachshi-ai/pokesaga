"""Compile Platinum breeding and Seven Stars records. Later species use PokeAPI families."""
import argparse
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text())


def breeding(pt, csv_dir):
    species = (pt / "generated/species.txt").read_text().splitlines()
    moves = (pt / "generated/moves.txt").read_text().splitlines()
    groups = (pt / "generated/egg_groups.txt").read_text().splitlines()
    book = {}
    for index, name in enumerate(species[1:494], 1):
        row = read(pt / "res/pokemon" / name[8:].lower() / "data.json")
        book[index] = [sorted({groups.index(k) for k in row["egg_groups"]}),
                       species.index(row["offspring"]), row["hatch_cycles"],
                       [moves.index(k) for k in row["learnset"].get("egg_moves", [])]]
    modern = {int(row["id"]): row for row in csv.DictReader((csv_dir / "pokemon_species.csv").open())}
    max_id = max(row["id"] for row in read(ROOT / "content/species.json"))
    for index in range(494, max_id + 1):
        base = index
        while parent := modern[base]["evolves_from_species_id"]:
            base = int(parent)
        book[index] = [[], base, int(modern[index]["hatch_counter"] or 20), []]
    for row in csv.DictReader((csv_dir / "pokemon_egg_groups.csv").open()):
        index = int(row["species_id"])
        if 493 < index <= max_id:
            book[index][0].append(int(row["egg_group_id"]))
    assert all(row[0] for row in book.values())
    return book


def restaurant(pt, translations):
    field = pt / "res/field/maps/restaurant"
    actors = read(field / "events.json")["object_events"]
    pairs = dict.fromkeys(re.findall(r'StartTrainerBattle TRAINER_(\w+), TRAINER_(\w+)', (field / "scripts.s").read_text()))
    species = (pt / "generated/species.txt").read_text().splitlines()
    moves = (pt / "generated/moves.txt").read_text().splitlines()
    trainers = (pt / "generated/trainers.txt").read_text().splitlines()
    cn = translations / "Pt/zh_Hans"
    names = read(cn / "trname.json")
    multipliers = dict(re.findall(r'\[(TRAINER_CLASS_\w+)\]\s*=\s*(\d+)', (pt / "include/data/trainer_class_prize_mul.h").read_text()))
    texts = read(cn / "l02r0101.json")
    ids = read(pt / "res/text/restaurant.json")["messages"]
    assert len(texts) == len(ids)
    messages = {m["id"][16:]: t["translation"].replace("\\r", "").replace("\\f", "").replace("\n", "")
                for m,t in zip(ids,texts)}
    result = {}
    for first, second in pairs:
        key = next(a["hidden_flag"] for a in actors if a["script"][11:].lower() == first.replace("_","").lower())
        row = {"trainers": [], "team": [], "prize": 0}
        for group, trainer in zip(["first","second"], [first,second]):
            data = read(pt / "res/trainers/data" / (trainer.lower() + ".json"))
            row["trainers"].append(names[trainers.index("TRAINER_" + trainer)]["translation"])
            row["prize"] += int(multipliers[data["class"]]) * 4 * data["party"][-1]["level"]
            for mon in data["party"]:
                unit = {"species": species.index(mon["species"]), "level": mon["level"], "trainer_group": group,
                        "moves": [moves.index(m) for m in (mon.get("moves") or []) if m != "MOVE_NONE"]}
                if mon.get("item"):
                    unit["held"] = mon["item"][5:]
                row["team"].append(unit)
        result[key] = row
    assert len(result) == 9 and len(messages) == 236
    return {"pairs":result, "texts":messages}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    for key in ["platinum","translations","pokeapi_csv"]:
        parser.add_argument(key, type=Path)
    args = parser.parse_args()
    for key, table in [("breeding", breeding(args.platinum, args.pokeapi_csv)),
                       ("restaurant", restaurant(args.platinum, args.translations))]:
        (ROOT / "content" / ("sinnoh_" + key + ".json")).write_text(
            json.dumps(table, ensure_ascii=False, separators=(",", ":")) + "\n")
