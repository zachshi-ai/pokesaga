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
    # Keep all three original south arrows to the S.S. Anne. Board the extra
    # ferries deliberately from the side of the pier, on its walkable planks.
    piers = {("johto","johto_olivine_port"):([286,232],"left"),
             ("sevii","one_island_harbor"):([286,231],"left"),
             ("frontier","harbor"):([288,232],"right")}
    def write_map(path, data):
        original = path.read_text()
        if json.loads(original) != data:
            style = {"indent":1} if original.startswith("{\n") else {"separators":(",",":")}
            path.write_text(json.dumps(data,ensure_ascii=False,**style)+("\n" if original.endswith("\n") else ""))

    main = Path(project_path("content/regions/kanto/maps/kanto_main.json"))
    port = json.loads(main.read_text())
    for warp in port["warps"]:
        to = warp["to"]
        if (pier := piers.get((to["region"],to["map"]))) and not warp.get("atlas"):
            warp["at"], warp["trigger"] = pier
            if to["region"]=="sevii": to.update(at=[8,3],facing="up")
    for sign in port.get("objects",[]):
        if sign["at"] == [285,234] and sign.get("kind") == "sign":
            sign["lines"] = ["枯叶港乘船处", "栈桥左舷：北侧前往七岛，南侧前往城都。右舷前往对战开拓区。", "从栈桥尽头向南登上圣安奴号。"]
            sign["text"] = "\n".join(sign["lines"])
    write_map(main,port)
    for (region, room), (at, facing) in piers.items():
        path = Path(project_path(f"content/regions/{region}/maps/{room}.json"))
        data = json.loads(path.read_text())
        for warp in data["warps"]:
            to = warp["to"]
            if (to["region"],to["map"]) == ("kanto","kanto_main") and not warp.get("atlas"):
                to.update(at=at,facing="up")
        write_map(path,data)


if __name__ == "__main__":
    apply_transfer()
    apply_kanto_landings()
