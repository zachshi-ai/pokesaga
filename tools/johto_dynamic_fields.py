"""Compile scripted room returns, elevator stops and Ruins of Alph floor drops."""
from collections import defaultdict
import json


def native(mid, at):
    return {"region": "johto", "map": mid, "at": list(at), "hgss": True}


def floor_name(header):
    floor = header.rsplit("_", 1)[-1]
    return {"BASEMENT": "B1F", "ROOF": "屋顶", "HQ": "一楼", "ROOM": "洛托姆房间"}.get(floor, floor)


def install(fields, ids, bank, local):
    stops = defaultdict(list)
    for header, mid in ids.items():
        field = fields[mid]
        entrances = {tuple(row["at"]): row for row in field["warps"]}
        for original in bank(header)["warps"]:
            dest, anchor = original["header"], original["anchor"]
            if dest not in ids:
                continue
            warps = bank(dest)["warps"]
            if anchor >= len(warps) or warps[anchor]["header"] != 4095:
                continue
            at = local(header, original)
            door = entrances.get(at)
            if not door or door["to"]["map"] != ids[dest] or "remember_passage" in door["to"]:
                continue
            key = "hgss-return:" + ids[dest]
            stop = native(mid, (at[0], at[1] + 1))
            stop["facing"] = "down"
            door["to"]["remember_passage"] = {"key": key, "destination": stop}
            back = local(dest, warps[anchor])
            cabin = fields[ids[dest]]
            if not any(row["at"] == list(back) for row in cabin["warps"]):
                cabin["warps"].append({"at": list(back), "trigger": "down", "to": {**stop, "recall_passage": key}})
            if dest.endswith("_ELEVATOR"):
                door["to"]["at"] = [3, 5]
                stops[dest].append({**stop, "lift_label": floor_name(header)})
    for header, rows in stops.items():
        if header == "MAP_GOLDENROD_DEPARTMENT_STORE_ELEVATOR":
            rows.append({"region": "johto", "map": "johto_goldenrod_dept_store_roof", "at": [3, 2], "lift_label": "屋顶"})
        rows.sort(key=lambda row: (row["lift_label"] != "B1F", row["lift_label"]))
        fields[ids[header]].update(lift_stops=rows, lift_panel=[4, 3])

    # D24R0212–0215 and D24R0203/07/09/10 issue Warp inside the
    # coordinate script. These fall-through passages have no zone warp entry.
    for wing, landing, hall in (
        ("NORTHEAST", (11, 7), (25, 6)), ("NORTHWEST", (11, 14), (5, 24)),
        ("SOUTHEAST", (11, 7), (25, 42)), ("SOUTHWEST", (11, 7), (5, 42)),
    ):
        prefix = "MAP_RUINS_OF_ALPH_" + wing
        hidden = prefix + "_HIDDEN_ROOM"
        for src, dest, target in ((prefix + "_ENTRANCE_SECOND_ROOM", hidden, landing), (hidden, "MAP_RUINS_OF_ALPH_UNDERGROUND_HALL", hall)):
            field = fields[ids[src]]
            at = list(local(src, bank(src)["coords"][0]))
            field["warps"] = [row for row in field["warps"] if row["at"] != at]
            field["warps"].append({"at": at, "trigger": "step", "to": native(ids[dest], target)})


def registry(root, fields, index, merged_ids):
    # The raw archive includes unused interiors and event-exclusive alternates.
    # Publish the native additions connected to an ordinary game map.
    graph = {}
    for path in (root / 'content/regions').glob('*/maps/*.json'):
        graph[(path.parent.parent.name, path.stem)] = json.loads(path.read_text())
    for mid, field in fields.items():
        graph['johto', mid] = field
    todo = [('kanto', 'pallet_town_players_house_2f')]
    reached = set(todo)
    while todo:
        current = graph[todo.pop()]
        destinations = list(current.get('lift_stops', ()))
        for warp in current.get('warps', ()):
            target = warp['to']
            destinations.append(target)
            if 'clefairy_night' in target:
                destinations.append(target['clefairy_night'])
            if 'remember_passage' in target:
                destinations.append(target['remember_passage']['destination'])
        for target in destinations:
            key = (target['region'], target['map'])
            if key in graph and key not in reached:
                todo.append(key)
                reached.add(key)
    if ('johto','hgss_safari_zone_entrance_exterior') in reached:
        # All twelve areas can occupy any of the six playable Safari slots.
        reached.update(('johto',f'hgss_safari_zone_{i:02}') for i in range(1,13))
    return {"native": sorted(mid for mid in index if ('johto', mid) in reached), "merged": sorted(merged_ids)}
