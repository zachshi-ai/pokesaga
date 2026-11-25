"""The shop in Konikoni, Malie library, Paniola's eatery and Heahea's visitor office."""

from copy import deepcopy
import numpy as np
from scipy import ndimage

# Pick entrances along the actual connected street nearest these surveyed quarters.
ROOMS = [
    (
        "konikoni",
        "konikoni_gems",
        "可霓可市・丽姿的宝石店",
        (-8, 2),
        "店员",
        "丽姿收集各地的矿石。橱窗中半透明的晶簇来自阿卡拉岛。",
        "woman",
    ),
    (
        "malie",
        "malie_library",
        "马利埃图书馆",
        (-7, -2),
        "图书管理员",
        "有关阿罗拉的古书放在馆内。请轻声阅读。",
        "scientist",
    ),
    (
        "heahea",
        "heahea_office",
        "慷待市・观光服务处",
        (8, -4),
        "接待员",
        "西边是港口。沿东边的大道出城，可以走上四号道路。",
        "woman",
    ),
    (
        "paniola",
        "paniola_salon",
        "欧哈纳镇・餐厅",
        (8, 2),
        "牧场主",
        "牧场就在镇外。走累了可以先在这里歇歇脚。",
        "man",
    ),
]


def attach(maps, arrivals, source):
    for parent, key, title, offset, name, line, gfx in ROOMS:
        parent_id = "alola_" + parent
        mid = "alola_" + key
        town = maps["alola", parent_id]
        # On a full upstream rebuild the previous output room can still be in the directory.
        # Always derive its door from the newly generated town and replace our previous pair.
        for warp in list(town["warps"]):
            if warp.get("source_warp") == "island_door" and warp["to"]["map"] == mid:
                town["warps"].remove(warp)
                arrivals.get(("alola", mid), set()).discard(tuple(warp["to"]["at"]))
        prior = maps.get(("alola", mid), {})
        for warp in prior.get("warps", []):
            if (
                warp.get("source_warp") == "island_door"
                and warp["to"]["map"] == parent_id
            ):
                arrivals.get(("alola", parent_id), set()).discard(
                    tuple(warp["to"]["at"])
                )
        old = np.asarray(town["physics"]["collision"], bool)
        walk = ~old & ~np.array(town["physics"].get("water", np.zeros_like(old)), bool)
        protect = {tuple(town["spawn"]), *arrivals.get(("alola", parent_id), ())}
        for row in (
            town["warps"]
            + town["npcs"]
            + town["objects"]
            + town["alola_item_tiles"]
            + town["alola_trainer_tiles"]
        ):
            protect.add(tuple(row["at"]))
        protect.update(tuple(v) for v in town["alola_anchors"].values())
        for x, y in protect:
            walk[y, x] = False
        # Work in the component reached from the town centre. A doorway also needs a clear
        # return tile and an unobstructed facade immediately north of the street.
        sx, sy = town["spawn"]
        base = ~old & ~np.array(town["physics"].get("water", np.zeros_like(old)), bool)
        for row in town["warps"] + town["npcs"]:
            x, y = row["at"]
            base[y, x] = False
        labels, _ = ndimage.label(base)
        connected = labels == labels[sy, sx]
        target = (sx + offset[0], sy + offset[1])
        best = None
        h, w = old.shape
        water = np.array(town["physics"].get("water", np.zeros_like(old)), bool)
        for y, x in np.argwhere(walk & connected):
            x, y = int(x), int(y)
            if not 4 <= x < w - 4 or not 5 <= y < h - 2 or not walk[y + 1, x]:
                continue
            rect = {(u, v) for u in range(x - 2, x + 3) for v in range(y - 3, y)}
            if rect & protect or water[y - 3 : y, x - 2 : x + 3].any():
                continue
            candidate = base.copy()
            candidate[y - 3 : y, x - 2 : x + 3] = False
            candidate[y, x] = False
            label, _ = ndimage.label(candidate)
            region = label == label[sy, sx]
            if not region[y + 1, x] or any(
                not region[yy, xx] for xx, yy in protect if base[yy, xx]
            ):
                continue
            score = (
                abs(x - target[0])
                + abs(y - target[1])
                - old[y - 3 : y, x - 2 : x + 3].sum() * 0.24
            )
            if best is None or score < best[0]:
                best = (score, x, y)
        if best is None:
            raise ValueError((parent_id, "no accessible shopfront"))
        _, x, y = best
        room = deepcopy(maps["alola", "alola_motel_2"])
        room.update(
            id=mid,
            name=title,
            alola_image=key,
            alola_location="",
            alola_zones=[],
            alola_zone=-1,
            alola_item_tiles=[],
            alola_trainer_tiles=[],
            objects=[],
            npcs=[{"at": [6, 5], "name": name, "gfx": gfx, "lines": [line]}],
        )
        if key == "konikoni_gems":
            room["npcs"][0].update(
                shop=True,
                gfx="clerk",
                counter_goods=[
                    {"name": item, "category": "other", "price": 3000}
                    for item in ("火之石", "雷之石", "水之石", "叶之石")
                ],
            )
        door = tuple(room["warps"][0]["at"])
        landing = [door[0], door[1] - 1]
        room["warps"] = [
            {
                "at": list(door),
                "trigger": "step",
                "source_warp": "island_door",
                "alola_label": town["name"],
                "to": {
                    "region": "alola",
                    "map": parent_id,
                    "at": [x, y + 1],
                    "alola_native": True,
                },
            }
        ]
        town["warps"].append(
            {
                "at": [x, y],
                "trigger": "step",
                "source_warp": "island_door",
                "alola_label": title,
                "to": {
                    "region": "alola",
                    "map": mid,
                    "at": landing,
                    "alola_native": True,
                },
            }
        )
        arrivals.setdefault(("alola", mid), set()).add(tuple(landing))
        arrivals.setdefault(("alola", parent_id), set()).add((x, y + 1))
        maps["alola", mid] = room
        if key == "malie_library":
            upstairs = "alola_malie_library_2f"
            stair = [3,4]
            foot = [3,5]
            def stairs(dest, label):
                return {"at": stair, "trigger": "step", "source_warp": "library_stairs",
                        "alola_label": label, "to": {"region": "alola", "map": dest,
                                                    "at": foot, "alola_native": True}}
            upper = deepcopy(room)
            upper.update(id=upstairs, name="马利埃图书馆・二楼", alola_image="malie_library_2f",
                         spawn=foot, alola_anchors={"story": [11,8]}, npcs=[], objects=[],
                         warps=[stairs(mid, "马利埃图书馆・一楼")])
            room["warps"].append(stairs(upstairs,upper["name"]))
            maps["alola",upstairs]=upper
            for floor in (mid,upstairs):
                arrivals.setdefault(("alola",floor),set()).add(tuple(foot))
