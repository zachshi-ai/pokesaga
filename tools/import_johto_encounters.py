"""Apply the Crystal grass, cave and surfing encounter slots for both sides of the league."""
import json
import re
from pathlib import Path

import gen_johto_battles as source
from import_johto_supplies import write


def pool(entries, weights):
    if len(entries) != len(weights):
        raise ValueError(entries)
    counts = {}
    for (level, name), weight in zip(entries, weights):
        species = source.sid(name)
        if not species:
            raise ValueError(name)
        key = species, level
        counts[key] = counts.get(key, 0) + weight
    return [{"species": species, "min": level, "max": level, "weight": weight}
            for (species, level), weight in counts.items()]


def main():
    areas = Path(source.ROOT, "data/maps/maps.asm").read_text()
    environments = dict(re.findall(r"^\s*map (\w+), \w+, (\w+),", areas, re.M))
    grass, water = {}, {}
    for side in ("johto", "kanto"):
        grass.update(source.parse_wild(side + "_grass.asm"))
        water.update(source.parse_wild(side + "_water.asm", water=True))
    mapped = set()
    for label, environment in environments.items():
        key = source.const_of(label)
        if key not in grass and key not in water:
            continue
        filename = source.map_id(label) + ".json"
        path, meta_path = Path(source.MAPSDIR, filename), Path(source.EMAPS, filename)
        room, meta = json.loads(path.read_text()), json.loads(meta_path.read_text())
        mapped.add(key)
        if key in grass:
            slots = grass[key]
            periods = {}
            for i, period in enumerate(("morn", "day", "nite")):
                periods[period] = {"pool": pool(slots["day"][7*i:7*i+7], source.SLOT_W),
                                   "rate": slots["rate"][i] / 100}
            room["encounters"] = periods["day"]["pool"]
            room["encounter_rate"] = periods["day"]["rate"]
            room["encounters_by_time"] = {k: v for k,v in periods.items() if v != periods["day"]}
            if environment == "CAVE":
                meta["wild_any"] = True
        if key in water:
            slots = water[key]
            room["water_encounters"] = pool(slots["day"], source.WATER_W)
            room["water_encounter_rate"] = slots["rate"][0] / 100
        write(path,room)
        write(meta_path,meta)
    missing = (set(grass) | set(water)) - mapped
    if missing:
        raise ValueError(sorted(missing))
    print(f"Crystal wild areas: {len(grass)} grass/cave and {len(water)} surfing.")


if __name__ == "__main__":
    main()
