"""Bind existing story actors/items to named HGSS event objects in native tile space."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "content/hgss"
JOHTO = ROOT / "content/regions/johto"
DIRECTIONS = ["up", "down", "left", "right"]


def read(p):
    return json.loads(p.read_text())


def xy(cell):
    return ",".join(map(str, cell))


def roles(mid, campaign, postgame, old):
    revised = campaign["actors"].get(mid, {})
    base = []
    for row in old.get("npcs", []):
        change = revised.get(xy(row["at"]), {})
        base.append(({**row, **change}, row["at"]))
    for row in campaign["add"].get(mid, []) + postgame["actors"].get(mid, []):
        base.append((row, row["at"]))
    return base


def compile_anchors():
    catalog = read(DATA / "events.json")
    banks, headers = catalog["banks"], catalog["headers"]
    def resolve(hid, group, i):
        h = headers[hid]
        row = banks[str(h["event_bank"])][group][i]
        source = row.get("id", f"{h['code']}:{group}:{i}")
        result = {"header":hid, "source_id":source, "at":[row["x"]-h["origin"][0],row["z"]-h["origin"][1]],
                  "kind":group, "script":row.get("scriptId",0)}
        if group == "objects":
            result["sprite"] = row["spriteId"]
            direction = row["facingDirection"]
            result["facing"] = DIRECTIONS[direction] if direction in range(4) else "down"
        elif group == "coords":
            result["size"] = [row["w"], row["h"]]
        return result

    rules = {}
    for line in Path(__file__).with_name("hgss_anchor_rules.txt").read_text().splitlines():
        if not line or line.startswith("#"): continue
        short, *pairs = line.split()
        rules.setdefault("johto_"+short, {}).update(pair.split("=",1) for pair in pairs)
    campaign = read(JOHTO / "campaign.json")
    postgame = read(JOHTO / "postgame.json")
    gifts = {}
    gd = (ROOT / "core/johto_items.gd").read_text()
    for mid, x, y, flag in re.findall(r'"(johto_\w+)":\[\[(\d+),(\d+)\],"[^"]+","(j_\w+)"', gd):
        gifts.setdefault(mid, {})[flag] = f"{x},{y}"
    out = {}
    for p in sorted((JOHTO/"maps").glob("*.json")):
        mid = p.stem
        native = catalog["split_maps"].get(mid, [catalog["aliases"].get(mid)])
        if not native[0]: continue
        old = read(p)
        actors = roles(mid, campaign, postgame, old)
        sites, bindings, objects, triggers = {}, {}, {}, {}
        assigned = set()
        for key, spec in rules.get(mid, {}).items():
            target = native[0]
            if ":" in spec:
                symbol, spec = spec.split(":",1)
                target = "MAP_"+symbol
            selector, _, override = spec.partition("@")
            bank = banks[str(headers[target]["event_bank"])]
            if selector.startswith("tile"):
                # A retained visitor from Crystal has no matching HGSS event.
                # Place visitors on a reviewed free tile without borrowing a different character's sprite.
                px,py=map(int,selector[4:].split(","))
                item={"header":target,"at":[px,py],"source_id":f"{mid}:{key}","kind":"compatibility"}
            elif selector.startswith("bg") and selector[2:].isdigit():
                item = resolve(target, "bgs", int(selector[2:]))
            else:
                match = [i for i,r in enumerate(bank["objects"]) if r["id"].split("_",2)[2]==selector]
                if len(match) != 1: raise ValueError((mid,key,target,selector,match))
                item = resolve(target, "objects",match[0])
            if override:
                item["source_at"] = item["at"]
                item["at"] = list(map(int,override.split(",")))
            assigned.add(item["source_id"])
            if "," in key: sites[key] = item
            else:
                bindings[key] = item
                if key in gifts.get(mid,{}): sites[gifts[mid][key]]=item
        for row, original in actors:
            key = row.get("role")
            if key in bindings:
                sites.setdefault(xy(original),bindings[key])
                sites[xy(row["at"])] = bindings[key]

        candidates = [(h,group,i,r) for h in native for group in ("objects","bgs")
                      for i,r in enumerate(banks[str(headers[h]["event_bank"])][group])]
        for obj in old.get("objects",[]):
            item = obj.get("item","").removeprefix("ITEM_").lower()
            scripts = {"cut":"std_field_cut","boulder":"std_field_strength","rock":"std_field_rock_smash"}
            action = scripts.get(obj.get("kind"))
            item_prefix = "std_hiddenitem_" if obj.get("kind")=="hidden" else "std_itemball_"
            matches = [(h,g,i,r) for h,g,i,r in candidates if (action and r["scriptId"]==action) or
                       (item and str(r["scriptId"]).startswith(item_prefix) and str(r["scriptId"]).endswith("_"+item))]
            if len(matches)==1:
                h,g,i,r=matches[0]
                bound=resolve(h,g,i)
                for key in ("source_script","flag"):
                    if obj.get(key): objects[obj[key]]=bound
                sites.setdefault(xy(obj["at"]),bound)
        for row,original in actors:
            pos=xy(row["at"])
            if pos in sites: continue
            target=[]
            trainer = re.sub(r"(?<=[a-z])(?=[A-Z])","_",str(row.get("trainer",""))).split("_")[-1].upper()
            for h,g,i,r in candidates:
                if g!="objects" or r["id"] in assigned: continue
                label=r["id"].split("_",2)[2]; script=str(r["scriptId"])
                if (trainer and script.startswith("std_trainer") and script.endswith("_"+trainer+")") or
                    row.get("heal") and label=="pcwoman1" or row.get("shop") and label=="shopm1_2"):
                    target.append((h,g,i))
            if len(target)==1:
                bound=resolve(*target[0]); sites[pos]=bound; assigned.add(bound["source_id"])
        # Step-trigger rectangles can be larger than one native tile.
        # Rectangle keys remain in Crystal coordinates. The active native
        # script supplies the entire trigger rectangle, including its floor.
        source_steps = {
            "elms_lab":((2,4,3,5),0),
            "cherrygrove_city":((16,2,18,5),1),
            "sprout_tower_3f":((3,1,7,4),0),
            "azalea_town":((2,4,3,7),0),
            "goldenrod_gym":((3,3,6,6),0),
            "burned_tower_1f":((3,4,5,5),1),
            "burned_tower_b1_f":((4,2,7,4),0),
            "olivine_city":((6,6,7,7),0),
            "cianwood_city":((5,8,6,9),0),
            "team_rocket_base_b3_f":((4,4,5,6),0),
            "goldenrod_underground_switch_room_entrances":((9,1,12,4),0),
            "dragons_den_b1_f":((8,2,12,6),0),
            "indigo_plateau_pokecenter_1f":((8,2,9,3),0),
            "power_plant":((0,5,5,9),0),
            "route_25":((21,3,22,4),0),
            "victory_road":((6,3,7,6),0),
        }
        if mid.removeprefix("johto_") in source_steps:
            rect, index = source_steps[mid.removeprefix("johto_")]
            header = "MAP_VICTORY_ROAD_3F" if mid=="johto_victory_road" else native[0]
            entry = resolve(header,"coords",index)
            for y in range(rect[1],rect[3]):
                for x in range(rect[0],rect[2]):
                    triggers[f"{x},{y}"] = entry
        if sites or bindings or objects or triggers:
            out[mid]={"sites":sites,"roles":bindings,"objects":objects,"triggers":triggers}
    (DATA/"anchors.json").write_text(json.dumps({"maps":out},ensure_ascii=False,separators=(",",":"))+"\n")
    print(f"{len(out)} maps, {sum(len(m['roles']) for m in out.values())} reviewed roles, "
          f"{sum(len(m['sites']) for m in out.values())} sites, {sum(len(m['objects']) for m in out.values())} item and field object references")


if __name__=="__main__":
    compile_anchors()
