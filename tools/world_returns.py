"""Restore scripted return doors that are absent from the static Crystal/FRLG imports."""

import json
from pathlib import Path


def restore_returns(regions_root: Path, write, landing) -> None:
    def room(region, mid):
        path = regions_root / region / "maps" / (mid + ".json")
        if path not in changed:
            changed[path] = json.loads(path.read_text())
        return changed[path]

    def to(region, mid, at):
        return {"region": region, "map": mid, "at": at}

    def recall(data, at, slot, fallback):
        old = next((w for w in data["warps"] if w["at"] == at), None)
        target = {**fallback, "recall_passage": slot}
        if old:
            old["to"] = target
        else:
            data["warps"].append({"at": at, "to": target})

    def store(target, slot, destination):
        target["remember_passage"] = {"key": slot, "destination": destination}

    def clear_corridor(data, source, free):
        npc = next((n for n in data["npcs"] if n["at"] == source), None)
        if npc:
            if any(n["at"] == free for n in data["npcs"]):
                raise ValueError(f"Occupied NPC position in {data['name']}: {free}")
            npc["at"] = free

    changed = {}
    center = "johto_pokecenter_2f"
    # The Crystal stair event uses warp ID -1. Save the actual first floor
    # when entering the shared upstairs, including across save/continue.
    for path in sorted((regions_root / "johto/maps").glob("*.json")):
        data = json.loads(path.read_text())
        entrances = [
            w
            for w in data.get("warps", [])
            if w["to"]["map"] == center
            and not w["to"].get("recall_passage")
            and ("pokecenter_1f" in path.stem or "pokecom_center" in path.stem)
        ]
        if not entrances:
            continue
        for w in entrances:
            at = w["at"]
            # An NPC immediately above the stair can enclose it between the
            # two exterior entrance triggers. Only move an actual blocker.
            x, y = at
            if x == 0 and any(n["at"] == [0, y - 1] for n in data["npcs"]):
                stand = landing(data, [3, 1])
                clear_corridor(data, [0, y - 1], stand)
            retreat = landing(data, at)
            w["to"]["at"] = [1, 3]
            store(w["to"], "johto_center", to("johto", path.stem, retreat))
        changed[path] = data
    upstairs = room("johto", center)
    recall(
        upstairs,
        [0, 3],
        "johto_center",
        to("johto", "johto_cherrygrove_pokecenter_1f", [0, 2]),
    )
    battle = room("johto", "johto_mobile_battle_room")
    if not any(w["at"] == [2, 3] for w in battle["warps"]):
        battle["warps"].append({"at": [2, 3], "to": to("johto", center, [4, 2])})

    # The Crystal ship gangway is warp_event 25,1 (half-scale map tile 12,0).
    # A regular voyage docks at the other port. Interior cabin visits must not
    # change the berth selected when boarding.
    ship = "johto_fast_ship_1f"
    deck = room("johto", ship)
    clear_corridor(deck, [12, 1], [14, 3])
    ports = ("johto_olivine_port", "johto_vermilion_port")
    berths = ([3, 8], [3, 7])
    for i, port in enumerate(ports):
        dock = room("johto", port)
        clear_corridor(dock, berths[i], [3, 11] if i == 0 else [6, 5])
        for w in dock["warps"]:
            if w["to"]["map"] == ship:
                w["to"]["at"] = [12, 1]
                store(w["to"], "johto_ship", to("johto", ports[1 - i], berths[1 - i]))
    recall(deck, [12, 0], "johto_ship", to("johto", ports[0], berths[0]))

    # Crystal's elevator cutscene connects the entrance and battle hallway.
    lift = "johto_battle_tower_elevator"
    floors = ("johto_battle_tower_1f", "johto_battle_tower_hallway")
    stops = ([3, 1], [6, 1])
    for i, floor in enumerate(floors):
        data = room("johto", floor)
        if i == 1:
            # The original attendant moves during the cutscene. Free the
            # single-tile aisle on the scale-reduced hallway.
            clear_corridor(data, [5, 1], [0, 0])
        for w in data["warps"]:
            if w["to"]["map"] == lift:
                store(w["to"], "johto_lift", to("johto", floors[1 - i], stops[1 - i]))
    data = room("johto", lift)
    for i in range(2):
        recall(data, [i, 1], "johto_lift", to("johto", floors[i], stops[i]))

    # FRLG's TrainerTower_Elevator door is MAP_DYNAMIC at (2,5). Without a
    # selected lobby trip it opens on the same floor as the boarder's entry.
    # Stepping up to the original call panel on the northwest wall serves the
    # second original functional choice: direct return to the lobby.
    lift = "trainer_tower_elevator"
    lobby = "trainer_tower_lobby"
    podium = to("sevii", lobby, [17, 9])
    for path in sorted((regions_root / "sevii/maps").glob("trainer_tower_*.json")):
        data = room("sevii", path.stem)
        for w in data["warps"]:
            if w["to"]["map"] == lift:
                retreat = landing(data, w["at"])
                w["to"]["at"] = [2, 4]
                store(w["to"], "sevii_lift", to("sevii", path.stem, retreat))
    cab = room("sevii", lift)
    recall(cab, [2, 5], "sevii_lift", podium)
    if not any(w["at"] == [0, 2] for w in cab["warps"]):
        cab["warps"].append({"at": [0, 2], "to": podium})
    if not any(
        o.get("text", "").startswith("电梯操作盘") for o in cab.get("objects", [])
    ):
        cab.setdefault("objects", []).append(
            {
                "kind": "sign",
                "at": [1, 2],
                "text": "电梯操作盘　左侧操作盘通往大厅，南侧门返回进入电梯时的楼层。",
            }
        )

    for path, data in changed.items():
        write(path, data, path.read_text().startswith('{"'))
