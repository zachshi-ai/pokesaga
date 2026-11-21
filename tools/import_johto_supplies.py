"""Restore working services and ordinary item balls from the Crystal map scripts."""
import argparse
import json
import re
from pathlib import Path

from asset_paths import project_path, source_path
from gen_world_extras import ITEM_ZH


def write(path, data):
    original = path.read_text()
    if json.loads(original) == data:
        return
    style = {"indent": 1} if original.startswith("{\n") else {"separators": (",", ":")}
    path.write_text(json.dumps(data, ensure_ascii=False, **style) + ("\n" if original.endswith("\n") else ""))


def restore(project, crystal):
    held = {i["key"]: i["name"] for i in json.loads((project/"content/items.json").read_text())}
    moves = {m["key"]:m for m in json.loads((project/"content/moves.json").read_text())}
    tm_file = project/"content/tm_map.json"
    tms = json.loads(tm_file.read_text())
    aliases = {"ELIXER":"ELIXIR","MAX_ELIXER":"MAX_ELIXIR","PARLYZ_HEAL":"PARALYZE_HEAL",
               "NEVERMELTICE":"NEVER_MELT_ICE","SOLARBEAM":"SOLAR_BEAM","SMOKEBALL":"SMOKE_BALL"}
    berries = {"MYSTERYBERRY":("苹野果","LEPPA"), "GOLD_BERRY":("文柚果","SITRUS"),
               "BERRY":("橙橙果","ORAN"), "PSNCUREBERRY":("桃桃果","PECHA")}
    extra = {"X_ATTACK":"力量强化","X_DEFEND":"防御强化","X_SPEED":"速度强化","X_SPECIAL":"特攻强化",
             "X_ACCURACY":"命中强化","DIRE_HIT":"要害攻击","GUARD_SPEC":"能力防守"}
    equivalents = {"ENERGYPOWDER":"伤药","ENERGY_ROOT":"厉害伤药","HEAL_POWDER":"万灵药","REVIVAL_HERB":"活力块"}
    native = (crystal/"data/maps/maps.asm").read_text()
    settings = dict(re.findall(r"^\s*map (\w+), \w+, (\w+),", native, re.M))
    pickups = services = 0
    for path in sorted((project/"content/regions/johto/maps").glob("*.json")):
        room = json.loads(path.read_text())
        meta_path = project/"content/emerald_maps"/(room.get("emerald","")+".json")
        if not meta_path.is_file(): continue
        meta = json.loads(meta_path.read_text())
        if "map" not in meta: continue
        src = crystal/"maps"/(meta["map"]+".asm")
        if not src.exists(): continue
        raw = src.read_text()
        # A projected doormat can share its only accessible neighbor with a story actor.
        # Stand on the indoor mat to turn or talk, then exit by walking south.
        if settings.get(meta["map"]) == "INDOOR":
            for warp in room.get("warps", []):
                target = warp["to"].get("map", "")
                if warp["at"][1] == room["size"][1] - 1 and (target.endswith(("_city","_town")) or re.fullmatch(r"johto_route_\d+",target)):
                    warp.setdefault("trigger","down")
        for npc in room["npcs"]:
            if npc["name"] == "护士" and "PokecenterNurseScript" in raw and "Pokecenter" in src.stem:
                npc["heal"] = True
                services += 1
            if npc["name"] == "店员" and "pokemart " in raw and ("Mart" in src.stem or "DeptStore" in src.stem or "IndigoPlateau" in src.stem):
                npc["shop"] = True
                services += 1
        balls = [n for n in room["npcs"] if n["name"] == "道具球"]
        existing = {o.get("source_script") for o in room.get("objects", [])}
        definitions = dict(re.findall(r"^(\w+):\s*\n\s*itemball (\w+)",raw,re.M))
        for line in raw.splitlines():
            if "OBJECTTYPE_ITEMBALL" not in line: continue
            row = line.strip().split("object_event ",1)[-1].split(",")
            script = row[11].strip()
            item = definitions.get(script)
            if not item or script in existing or not balls: continue
            pos = (int(row[0])//2, int(row[1])//2)
            actor = min(balls,key=lambda n:sum(abs(a-b) for a,b in zip(n["at"],pos)))
            balls.remove(actor)
            if item in ("HM_WATERFALL","COIN_CASE"): continue
            key = aliases.get(item,item)
            obj = {"kind":"item","at":actor["at"],"source_script":script,"flag":row[12].strip(),"sprite":"item"}
            if item.startswith("TM_"):
                move = moves.get(aliases.get(item[3:],item[3:]))
                if not move: continue
                name = "城都招式学习器·"+move["name"]
                tms[name] = move["id"]
                obj.update(name=name, category="tm")
            elif key in held:
                obj.update(name=held[key], category="held", held=key)
            elif key in berries:
                name, berry = berries[key]
                obj.update(name=name, category="berry", berry=berry)
            elif key in extra:
                obj.update(name=extra[key], category="battle",item="ITEM_"+key)
            elif key == "DRAGON_SCALE":
                obj.update(name="龙之鳞片",category="evo",item="ITEM_DRAGON_SCALE")
            elif key in equivalents:
                obj.update(name=equivalents[key], category="heal")
            elif "ITEM_"+key in ITEM_ZH:
                name, category, _ = ITEM_ZH["ITEM_"+key]
                obj.update(name=name,category=category,item="ITEM_"+key)
            else: continue
            room["npcs"].remove(actor)
            room.setdefault("objects",[]).append(obj)
            pickups += 1
        write(path,room)
    write(tm_file,tms)
    print("Service NPCs:",services,"restored item balls:",pickups)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project",type=Path,default=Path(project_path()))
    parser.add_argument("--crystal",type=Path,default=Path(source_path("crystal")))
    args = parser.parse_args()
    restore(args.project,args.crystal)
