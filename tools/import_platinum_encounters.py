"""Import Platinum's field permissions and encounter slots with original weights and levels."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAND = [20,20,10,10,10,10,5,5,4,4,1,1]
SURF = [60,30,5,4,1]
ROD = [40,40,15,4,1]


def build(source):
    maps = source/"res/field/maps"
    ids = (source/"generated/species.txt").read_text().splitlines()
    registry = json.loads((ROOT/"content/platinum_native/index.json").read_text())
    fields = {}
    for header,mid in registry.items():
        folder = maps/header.removeprefix("MAP_HEADER_").lower()
        raw = json.loads((folder/"header.json").read_text())
        data = {"fly":raw["isFlyAllowed"],"bike":raw["isBikeAllowed"],"run":raw["isRunningAllowed"]}
        path = folder/"encounters.json"
        if path.exists():
            wild = json.loads(path.read_text())
            for mode,weights in [("land", LAND),("surf", SURF),("old_rod", SURF),("good_rod",ROD),("super_rod",ROD)]:
                if not wild[mode+"_rate"]: continue
                pool = []
                assert len(wild[mode+"_encounters"])==len(weights)
                for entry,weight in zip(wild[mode+"_encounters"],weights):
                    sid = ids.index(entry["species"])
                    if sid:
                        pool.append({"species":sid,"min":entry.get("level",entry.get("level_min")),
                                     "max":entry.get("level",entry.get("level_max")),"weight":weight})
                data[mode]=pool
                data[mode+"_rate"]=wild[mode+"_rate"]/100
            if "land" in data:
                for period in ("day","night"):
                    data[period]=[ids.index(sid) for sid in wild[period]]
                data["unown"]=wild["unown_table"]
        fields[mid]=data
    (ROOT/"content/platinum_native/habitats.json").write_text(json.dumps(fields,separators=(",",":"))+"\n")
    print(len(fields),"locations;",sum("land" in v for v in fields.values()),"land tables")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("source",type=Path)
    build(p.parse_args().source)
