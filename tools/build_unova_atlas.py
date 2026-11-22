"""Build each Town Map from the entrances and corridors in its own era."""
from collections import deque
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "content"
# Percentage coordinates on the shared schematic. The same town keeps its place
# after the two-year transition. The new southwest peninsula is visible in B2.
POSITIONS = {
    "nuvema": (80,94), "1": (80,88), "accumula": (80,82), "2": (80,76),
    "striaton": (80,70), "dreamyard": (89,70), "3": (72,70), "wellspring": (72,63),
    "nacrene": (64,70), "museum": (63,66), "pinwheel": (57,70), "skyarrow_bridge": (55,76),
    "castelia": (50,81), "castelia_sewers": (56,82), "4": (50,69), "desert": (43,66),
    "relic": (40,62), "nimbasa": (50,57), "5": (43,54), "driftveil_bridge": (35,54),
    "driftveil": (27,54), "cold_storage": (27,61), "pwt": (27,61), "6": (22,46),
    "chargestone": (21,38), "mistralton": (20,31), "7": (25,26), "celestial": (24,18),
    "twist": (31,23), "icirrus": (38,22), "dragonspiral": (37,14), "8": (43,24),
    "tubeline_bridge": (48,23), "9": (53,22), "opelucid": (59,22), "10": (59,14),
    "victory": (63,10), "league": (63,4), "11": (65,24), "village": (71,25),
    "12": (76,24), "lacunosa": (82,23), "13": (88,25), "giant": (84,15),
    "undella": (90,39), "14": (84,46), "black_city": (76,51), "15": (68,52),
    "16": (57,54), "17": (72,89), "18": (65,90), "aspertia": (9,92),
    "19": (14,87), "floccesy": (20,83), "20": (26,79), "ranch": (23,72),
    "virbank": (32,77), "film": (32,70), "lentimas": (74,36), "reverse": (82,37),
    "marine_tube": (93,28), "humilau": (96,18), "seaside_cave": (94,33),
    "21": (97,24), "22": (91,15), "23": (73,11), "pass_blueberry_academy": (97,43),
    "pass_galar_wedgehurst": (32,14), "pass_alola_hauoli": (39,87),
    "pass_dream_village": (95,73),
}
COMMON_NAMES = {
    "wellspring":"地下水脉之穴", "cold_storage":"冷冻仓库", "tubeline_bridge":"圆筒桥",
    "driftveil_bridge":"帆巴吊桥", "pwt":"宝可梦世界锦标赛", "marine_tube":"海底隧道",
    "castelia_sewers":"飞云下水道", "seaside_cave":"海边洞穴",
}

LANDMARKS = {
    "liberty_garden":("自由庭园岛",(41,93)), "royal_unova":("皇家合众号",(55,88)),
    "p2_laboratory":("P2 实验室",(65,85)), "lostlorn_forest":("迷幻森林",(61,48)),
    "gear_station":("对战地铁",(50,61)), "anville_town":("金轮镇",(8,16)),
    "marvelous_bridge":("奇幻桥",(64,53)), "abundant_shrine":("丰收之祠",(78,44)),
    "moor_of_icirrus":("雪花湿地",(46,17)), "mistralton_cave":("吹寄洞穴",(28,40)),
    "challengers_cave":("修行岩屋",(54,28)), "abyssal_ruins":("海底遗迹",(96,39)),
    "underground_ruins":("地下遗迹",(18,49)), "nature_preserve":("自然保护区",(7,29)),
    "black_tower":("黑色摩天楼",(75,56)), "join_avenue":("加盟大道",(50,64)),
    "clay_tunnel":("菊老大之路",(28,48)), "strange_house":("陌生人之家",(76,40)),
    "relic_passage":("古代秘道",(42,72)), "cave_of_being":("心之空洞",(23,86)),
    "pledge_grove":("誓约之林",(20,89)), "virbank_complex":("立涌联合工业区",(32,84)),
}

def build(era, legacy):
    maps = {p.stem: json.loads(p.read_text()) for p in (ROOT/"unova_native"/era).glob("*.json")}
    for path in (ROOT/"regions/unova/maps").glob("unova_pass_*.json"):
        maps[path.stem] = json.loads(path.read_text())
    index = {p["id"].removeprefix("unova_"): p for p in legacy["locations"]}
    index["skyarrow_bridge"] = index["skyarrow"]
    places = []
    for name, pos in POSITIONS.items():
        mid = "unova_" + name
        room = maps.get(mid, {})
        if not room or not room.get("warps") or room.get("unova_technical"): continue
        origin = index.get(name, {})
        places.append({"id":mid, "map":mid, "name":origin.get("name", COMMON_NAMES.get(name,room["name"])),
                       "kind":origin.get("kind","landmark"),"at":room["spawn"],"pos":list(pos)})
    for mid, room in maps.items():
        zone = room.get("unova_zone")
        if zone not in LANDMARKS or room.get("unova_technical"):continue
        if not room.get("warps") and not room.get("unova_script_links"):continue
        name, pos = LANDMARKS[zone]
        places.append({"id":mid, "map":mid, "name":name, "kind":"landmark", "at":room["spawn"], "pos":list(pos)})
    places.sort(key=lambda p:(p["map"]!="unova_nuvema",p["map"]))
    ids = {p["id"] for p in places}
    edges = set()
    for start in ids:
        pending = deque([start])
        visited = {start}
        while pending:
            current = pending.popleft()
            room = maps[current]
            for target in room.get("unova_script_links",[]):
                if target in visited or target not in maps or maps[target].get("unova_technical"):continue
                visited.add(target)
                if target in ids: edges.add(tuple(sorted((start,target))))
                else: pending.append(target)
            for warp in room["warps"]:
                target = warp["to"]["map"]
                if warp["to"]["region"] != "unova": continue
                if era == "bw" and current.startswith("unova_pass_"):
                    target = {"unova_aspertia":"unova_nuvema","unova_virbank":"unova_castelia"}.get(target,target)
                if target in visited or target not in maps or maps[target].get("unova_technical"): continue
                visited.add(target)
                if target in ids: edges.add(tuple(sorted((start,target))))
                else: pending.append(target)
    hub = maps["unova_nuvema" if era=="bw" else "unova_aspertia"]["unova_hub"]
    return {"locations": places, "connections":sorted(edges), "hub": hub}

if __name__ == "__main__":
    legacy = json.loads((ROOT/"world_destinations.json").read_text())["regions"]["unova"]
    output = {era:build(era, legacy) for era in ("bw","b2")}
    (ROOT/"unova_atlas.json").write_text(json.dumps(output, ensure_ascii=False, separators=(",",":"))+"\n")
