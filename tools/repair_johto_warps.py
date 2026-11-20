#!/usr/bin/env python3
"""Repair old projected doors in place, preserving authored NPCs, battles, docks and elevators.

Run POKESAGA_CRYSTAL=/path/to/pokecrystal python3 tools/repair_johto_warps.py.
The source snapshot used for the v4.46 migration is 9ce4c4e5068ffdf56e23ca3d8dc9178b2465d482.
"""
import argparse
import json
from collections import defaultdict, deque
from pathlib import Path

import gen_johto
from johto_warps import ambiguous, blocking_objects, landing, place_warps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", action="append", default=[], help="Also restore projected doors on this map ID")
    requested = set(parser.parse_args().map)
    directory = Path(gen_johto.REG) / "maps"
    files = {p.stem: p for p in sorted(directory.glob("*.json"))}
    rooms = {k: json.loads(p.read_text()) for k, p in files.items()}
    meta = {k: json.loads((Path(gen_johto.EMAPS) / (m["emerald"] + ".json")).read_text())
            for k, m in rooms.items()}
    room_for = {gen_johto.const_of(v["map"]): k for k, v in meta.items()}
    assigned = {}
    moved = {}
    door_cells = {}
    for room_id, room in rooms.items():
        # Post-processing adds crossings/docks and can remove unused rooms. Pair
        # surviving ROM events in declaration order per destination, not JSON array index.
        events, _, _ = gen_johto.parse_map_events(meta[room_id]["map"], {})
        by_target = defaultdict(deque)
        for n, event in enumerate(events):
            if event["idx"] > 0 and event["to"] in room_for:
                by_target[room_for[event["to"]]].append(n)
        matched = {}
        reserved = set()
        for warp in room["warps"]:
            to = warp["to"]
            if not warp.get("edge") and to["region"] == "johto" and by_target[to["map"]]:
                matched[by_target[to["map"]].popleft()] = warp
            else:
                reserved.add(tuple(warp["at"]))
        assigned[room_id] = (events, matched, reserved)

    while True:
        newly_moved = 0
        for room_id, room in rooms.items():
            if room_id in moved:
                continue
            events, matched, reserved = assigned[room_id]
            if room_id not in requested and not ambiguous(room["warps"]):
                continue
            blocked = blocking_objects(room) | reserved
            positions = place_warps(meta[room_id], [events[n] for n in matched], blocked)
            moved[room_id] = {n + 1: p for n, p in zip(matched, positions)}
            for n, warp in matched.items():
                warp["at"] = moved[room_id][n + 1]
            door_cells[room_id] = {tuple(w["at"]) for w in room["warps"]}
            newly_moved += 1
        if not newly_moved:
            break
        for events, matches, _ in assigned.values():
            for n, warp in matches.items():
                dst = warp["to"]["map"]
                door = moved.get(dst, {}).get(events[n]["idx"])
                if door is not None:
                    warp["to"]["at"] = landing(meta[dst], door, door_cells[dst], blocking_objects(rooms[dst]))

    for room_id, room in rooms.items():
        if ambiguous(room["warps"]):
            raise ValueError(f"Conflicting destinations remain in {room_id}")
    changed = 0
    for key, path in files.items():
        original = path.read_text()
        before = json.loads(original)
        if before["warps"] == rooms[key]["warps"]:
            continue
        before["warps"] = rooms[key]["warps"]
        options = {"indent": 1} if original.startswith("{\n") else {"separators": (",", ":")}
        path.write_text(json.dumps(before, ensure_ascii=False, **options) + ("\n" if original.endswith("\n") else ""))
        changed += 1
    print(f"Restored exits in {len(moved)} rooms, updated {changed} map files.")


if __name__ == "__main__":
    main()
