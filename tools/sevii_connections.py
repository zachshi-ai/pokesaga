"""Rebuild the canonically aligned FireRed island borders, including the matching return crossing."""
from collections import defaultdict
import json
from pathlib import Path


OPPOSITE = {"up": "down", "down": "up", "left": "right", "right": "left"}


def edge(width, height, side, index):
    if side == "left":
        return (0, index)
    if side == "right":
        return (width - 1, index)
    if side == "up":
        return (index, 0)
    return (index, height - 1)


def normalized(name):
    return "".join(c for c in name.lower().removeprefix("map_").removesuffix("_frlg") if c.isalnum())


def rebuild(region_dir, terrain_dir, source_dir, dry=False):
    files = {p.stem: p for p in sorted(Path(region_dir).glob("*.json"))
             if json.loads(p.read_text()).get("emerald")}
    rooms = {k: json.loads(p.read_text()) for k, p in files.items()}
    ids = {normalized(k): k for k in rooms}
    terrain = {k: json.loads((Path(terrain_dir) / (r["emerald"] + ".json")).read_text())
               for k, r in rooms.items()}
    source = {}
    for path in sorted(Path(source_dir).glob("*/map.json")):
        key = ids.get(normalized(path.parent.name))
        if key:
            source[key] = json.loads(path.read_text())
    if set(source) != set(rooms):
        raise ValueError(f"Missing island sources: {sorted(set(rooms) - set(source))}")
    neighbors = defaultdict(dict)
    for key, original in source.items():
        for c in original.get("connections") or []:
            dest = ids.get(normalized(c["map"]))
            if dest:
                neighbors[key][dest] = (c["direction"], int(c["offset"]))

    used = {}
    passable = {}
    for key, room in rooms.items():
        # Preserve doors, berries, ferry departures, etc. Only replace old
        # generated crossings between canonical neighbors along that border.
        original_doors = {(e["x"], e["y"]) for e in source[key].get("warp_events", [])}
        width, height = room["size"]
        kept = []
        for warp in room["warps"]:
            pos = tuple(warp["at"])
            neighbor = neighbors[key].get(warp["to"]["map"])
            if neighbor and pos not in original_doors:
                side = neighbor[0]
                index = pos[0] if side in {"up", "down"} else pos[1]
                if pos == edge(width, height, side, index):
                    continue
            kept.append(warp)
        room["warps"] = kept
        used[key] = {tuple(w["at"]) for w in kept}
        m = terrain[key]
        passable[key] = {(x, y) for y, row in enumerate(m["collision"]) for x, solid in enumerate(row)
                         if not solid}
        passable[key] -= {tuple(n["at"]) for n in room["npcs"]}
        passable[key] -= {tuple(o["at"]) for o in room.get("objects", [])
                          if o.get("kind") in {"sign", "rock", "cut", "boulder", "berry_tree"}}

    count = 0
    for key in sorted(neighbors):
        for dest, (side, offset) in sorted(neighbors[key].items()):
            if dest < key:
                continue
            # PokeFireRed stores offsets in metatiles, already the unit of
            # these rendered maps. Six Island/Green Path/Ruin Valley share
            # the same edge of Water Path at distinct offsets 40/0/80.
            width, height = rooms[key]["size"]
            tw, th = rooms[dest]["size"]
            end = width if side in {"up", "down"} else height
            added = 0
            for i in range(end):
                p = edge(width, height, side, i)
                q = edge(tw, th, OPPOSITE[side], i - offset)
                if (p not in passable[key] or q not in passable[dest]
                        or p in used[key] or q in used[dest]):
                    continue
                for a, tile, b, other, direction in ((key,p,dest,q,side),(dest,q,key,p,OPPOSITE[side])):
                    rooms[a]["warps"].append({"at": list(tile), "trigger":direction, "edge":True,
                                              "to":{"region":"sevii", "map":b, "at":list(other), "connection":True}})
                    used[a].add(tile)
                added += 1
            if not added:
                raise ValueError(f"No usable paired border for {key} ↔ {dest} ({offset})")
            count += added
    changed = 0
    for key, path in files.items():
        before = path.read_text()
        if json.loads(before)["warps"] == rooms[key]["warps"]:
            continue
        if not dry:
            path.write_text(json.dumps(rooms[key], ensure_ascii=False, indent=1)
                            + ("\n" if before.endswith("\n") else ""))
        changed += 1
    print(f"Sevii: {count} paired crossings, {changed} maps changed.")
