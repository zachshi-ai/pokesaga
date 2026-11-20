"""Project Crystal warp events onto the smaller PokeSaga map grid."""
from collections import defaultdict

DIRECTIONS = ((0, 1), (0, -1), (1, 0), (-1, 0))


def free_tile(meta, tile, blocked):
    x, y = tile
    grid = meta["collision"]
    return (0 <= y < len(grid) and 0 <= x < len(grid[y])
            and grid[y][x] == 0 and tile not in blocked)


def place_warps(meta, warps, blocked=()):
    """Keep real entrances on their floor. Only look next to an anchor when its tile is occupied."""
    blocked = set(blocked)
    chosen = {}
    anchors = [(w["at8"][0] // 2, w["at8"][1] // 2) for w in warps]
    # Crystal labels this (0,0) beta doorway inaccessible. PokeSaga already ships
    # the bonus room with a working entrance at (3,6); keep it when regenerating.
    if meta["map"] == "OlivineCity":
        for i, warp in enumerate(warps):
            if warp["to"] == "OLIVINE_HOUSE_BETA" and warp["at8"] == [0, 0]:
                anchors[i] = (3, 6)
    reserved = set(anchors)
    result = []
    # Adjacent halves of a wide door can share a game tile and the same destination.
    for warp, anchor in zip(warps, anchors):
        key = (anchor, warp["to"], warp["idx"])
        if key not in chosen:
            ax, ay = anchor
            candidates = []
            for y in range(ay - 3, ay + 4):
                for x in range(ax - 3, ax + 4):
                    tile = (x, y)
                    if tile != anchor and tile in reserved:
                        continue
                    if not free_tile(meta, tile, blocked):
                        continue
                    if not any(free_tile(meta, (x + dx, y + dy), blocked)
                               for dx, dy in DIRECTIONS):
                        continue
                    distance = abs(ax - x) + abs(ay - y)
                    door = meta["door"][y][x]
                    candidates.append((distance, -door, y, x))
            if not candidates:
                raise ValueError(f"{meta['map']}: no distinct doorway near {anchor} for {key[1:]}")
            _, _, y, x = min(candidates)
            chosen[key] = (x, y)
            blocked.add((x, y))
        result.append(list(chosen[key]))
    return result


def landing(meta, door, all_doors, obstacles):
    """Prefer an immediately adjacent non-door. Landing on the door itself is safe:
    world.warp_to clears pending_warp, so a narrow staircase won't bounce back."""
    x, y = door
    for dx, dy in DIRECTIONS:
        tile = (x + dx, y + dy)
        if free_tile(meta, tile, obstacles) and tile not in all_doors:
            return list(tile)
    if free_tile(meta, (x, y), obstacles):
        return list(door)
    raise ValueError(f"{meta['map']}: blocked arrival at {door}")


def blocking_objects(room):
    tiles = {tuple(n["at"]) for n in room.get("npcs", [])}
    tiles.update(tuple(o["at"]) for o in room.get("objects", [])
                 if o.get("kind") in {"cut", "rock", "boulder", "sign", "berry_tree"})
    return tiles


def ambiguous(warps):
    by_cell = defaultdict(set)
    for warp in warps:
        to = warp["to"]
        by_cell[tuple(warp["at"])].add((to["region"], to["map"], tuple(to["at"])))
    return any(len(destinations) > 1 for destinations in by_cell.values())
