#!/usr/bin/env python3
"""把站在门口/门格上的 NPC 挪到最近的空地。

原版有些 NPC 本来就站在门口（水手、门卫），我们照着放会把门堵死，
玩家明明看到门却进不去。这里统一挪一格，保证每扇门都能踩到。
"""
import json
import glob
import os

ROOT = "/root/build/pokesaga"


def free(npc_at, warps, collision, npc_set, w, h):
    for r in range(1, 4):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                x, y = npc_at[0] + dx, npc_at[1] + dy
                if not (0 <= x < w and 0 <= y < h):
                    continue
                if (x, y) in warps or (x, y) in npc_set:
                    continue
                if int(collision[y][x]) != 0:
                    continue
                return [x, y]
    return None


def main():
    moved = 0
    for f in glob.glob(os.path.join(ROOT, "content/regions/*/maps/*.json")):
        reg = f.split("/")[-3]
        if reg not in ("johto", "frontier"):
            continue
        mid = os.path.basename(f)[:-5]
        data = json.load(open(f))
        warps = {(int(w["at"][0]), int(w["at"][1])) for w in data.get("warps", [])}
        if not warps:
            continue
        ep = os.path.join(ROOT, "content/emerald_maps", "%s.json" % mid)
        if not os.path.exists(ep):
            continue
        em = json.load(open(ep))
        coll = em.get("collision")
        door = em.get("door")
        if not coll:
            continue
        h, w = len(coll), len(coll[0])
        # 门格也算"不能站人"，否则人站在门洞里同样挡路
        door_cells = set()
        if door:
            for y in range(min(h, len(door))):
                for x in range(min(w, len(door[y]))):
                    if int(door[y][x]) == 1:
                        door_cells.add((x, y))
        npcs = data.get("npcs", [])
        npc_set = {(int(n["at"][0]), int(n["at"][1])) for n in npcs}
        changed = False
        for n in npcs:
            at = (int(n["at"][0]), int(n["at"][1]))
            if at not in warps and at not in door_cells:
                continue
            npc_set.discard(at)
            spot = free(list(at), warps, coll, npc_set | door_cells, w, h)
            if spot is None:
                npc_set.add(at)
                continue
            n["at"] = spot
            npc_set.add(tuple(spot))
            moved += 1
            changed = True
        if changed:
            json.dump(data, open(f, "w"), ensure_ascii=False, indent=1)
    print("挪开挡门 NPC %d 个" % moved)


if __name__ == "__main__":
    main()
