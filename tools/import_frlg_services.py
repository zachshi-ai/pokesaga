"""Restore nurses, Poké Mart clerks and fishing gifts at their original coordinates."""
import argparse
import json
import re
from pathlib import Path

from asset_paths import project_path, source_path


def compact(name):
    return re.sub("[^a-z0-9]", "", name.lower())


def restore(project, source):
    maps = {compact(f.parent.name): f for f in (source / "data/maps").glob("*/map.json")}
    count = 0
    rods = {"VermilionCity_House1": "破旧钓竿", "FuchsiaCity_House2": "好钓竿", "Route12_FishingHouse": "厉害钓竿"}
    for region in ("kanto", "sevii"):
        for path in (project / "content/regions" / region / "maps").glob("*.json"):
            native = maps.get(compact(path.stem))
            if not native:
                continue
            original = path.read_text()
            room = json.loads(original)
            by_xy = {tuple(npc["at"]): npc for npc in room.get("npcs", [])}
            changed = False
            for event in json.loads(native.read_text()).get("object_events", []):
                xy = event["x"], event["y"]
                npc = by_xy.get(xy)
                script = str(event.get("script"))
                if npc is None:
                    continue
                if script.endswith("_EventScript_Nurse") and "PokemonCenter" in native.parent.name:
                    fields = {"name":"护士","heal":True,"gfx":"nurse"}
                elif script.endswith("_EventScript_Clerk") and (native.parent.name.endswith("_Mart") or native.parent.name == "IndigoPlateau_PokemonCenter_1F"):
                    fields = {"name":"店员","shop":True,"gfx":"clerk"}
                elif native.parent.name in rods and "FishingGuru" in script:
                    fields = {"name":"钓鱼人","gives_rod":rods[native.parent.name]}
                else:
                    continue
                if any(npc.get(k) != v for k,v in fields.items()):
                    npc.update(fields)
                    changed = True
            if changed:
                options = {"indent":1} if original.startswith("{\n") else {"separators":(",",":")}
                path.write_text(json.dumps(room,ensure_ascii=False,**options) + ("\n" if original.endswith("\n") else ""))
                count += 1
    print("Updated service NPC maps:", count)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,default=Path(project_path()))
    parser.add_argument("--source",type=Path,default=Path(source_path("firered")))
    args=parser.parse_args()
    restore(args.project,args.source)
