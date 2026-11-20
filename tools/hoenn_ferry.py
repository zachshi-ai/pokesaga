"""Apply the transfer from Littleroot's south path to the Battle Frontier ferry."""
import json
from pathlib import Path

from asset_paths import project_path

HOENN_LANDING = [10, 17]
FRONTIER_LANDING = [14, 16]
FRONTIER_GUIDE = ["南边栈桥的尽头通往丰缘未白镇。", "要回关都枯叶港，走到栈桥北侧、对战塔前的乘船点。"]


def apply_transfer():
    path = Path(project_path("content/regions/hoenn/maps/littleroot_town.json"))
    with path.open() as f:
        town = json.load(f)
    to = {"region": "frontier", "map": "harbor", "at": FRONTIER_LANDING}
    at = [10, 18]
    warps = town["warps"]
    if any(w["at"] == at and w["to"]["region"] != "frontier" for w in warps):
        raise ValueError("Littleroot transfer would hide a different doorway")
    warps[:] = [w for w in warps if not (w["to"]["region"] == "frontier" and w["to"]["map"] == "harbor")]
    warps.append({"at": at, "to": to})
    npcs = town["npcs"]
    npcs[:] = [n for n in npcs if n.get("name") != "开拓区接驳员"]
    npcs.append({"at": [9, 18], "name": "开拓区接驳员", "gfx": "sailor",
                 "lines": ["这里是前往对战开拓区的接驳点。走到我身旁右边的空地即可出发。",
                           "回关都的话，先去开拓区，再从那边北侧的码头坐船。"]})
    path.write_text(json.dumps(town, ensure_ascii=False, indent=1))


def apply_kanto_landings():
    # The tile south of the boarding line is enclosed by water. Land on the north side.
    for room in ("johto/maps/johto_olivine_port", "sevii/maps/one_island_harbor", "frontier/maps/harbor"):
        path = Path(project_path("content/regions/" + room + ".json"))
        if not path.exists():
            continue
        raw = path.read_text()
        data = json.loads(raw)
        changed = False
        for warp in data["warps"]:
            dest = warp["to"]
            if dest["region"] == "kanto" and dest["map"] == "kanto_main" and dest["at"] != [287,234]:
                dest["at"] = [287,234]
                changed = True
        if changed:
            layout = {"indent":1} if raw.startswith("{\n") else {"separators":(",",":")}
            path.write_text(json.dumps(data, ensure_ascii=False, **layout))


if __name__ == "__main__":
    apply_transfer()
    apply_kanto_landings()
