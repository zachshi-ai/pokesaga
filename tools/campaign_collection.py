"""Use Kanto's encounter maps, field items, shops and nurses to prepare a campaign save."""
from collections import Counter
from dataclasses import dataclass
from functools import lru_cache

from campaign_route import ROOT, VECTORS, read

REGION = ROOT / "content/regions/kanto/maps"
BALLS = ("精灵球", "超级球", "高级球")


@dataclass
class Habitat:
    name: str
    mid: str
    grass: set
    odds: Counter
    level: int


@lru_cache(maxsize=1)
def habitats():
    all_patches = []
    for path in sorted(REGION.glob("*.json")):
        data = read(path)
        zones = data.get("zones") or [dict(encounters=data.get("encounters", []), name=path.stem,
                                            rect=[0, 0, *data["size"]])]
        if not any(z.get("encounters") for z in zones):
            continue
        meta_path = ROOT / "content/emerald_maps" / (data.get("emerald", "") + ".json")
        if not meta_path.exists():
            continue
        meta = read(meta_path)
        grass = meta.get("grass", [])
        if not grass:
            continue
        objects = {tuple(o["at"]) for o in data.get("objects", []) if o.get("kind") != "hidden"}
        doors = {tuple(o["at"]) for o in data.get("warps", [])}
        for zone in zones:
            slots = zone.get("encounters", [])
            if not slots:
                continue
            x, y, width, height = map(int, zone["rect"])
            free = {(i, j) for j in range(max(0, y), min(len(grass), y + height))
                    for i in range(max(0, x), min(len(grass[j]), x + width))
                    if grass[j][i] and not meta["collision"][j][i]} - objects - doors
            pairs = {point for point in free
                     if any((point[0] + dx, point[1] + dy) in free for dx, dy, *_ in VECTORS.values())}
            if not pairs:
                continue
            odds = Counter()
            for slot in slots:
                odds[int(slot["species"])] += int(slot["weight"])
            level = max(int(slot["max"]) for slot in slots)
            all_patches.append(Habitat(zone.get("name", path.stem), path.stem, pairs, odds, level))
    return all_patches


def mode(p, name):
    p.do("mode", value=name)


def heal(p):
    mode(p, "travel")
    goals = {(mid, 7, 4) for mid, f in p.routes.fields.items()
             if any(n.get("heal") and n["at"] == [7, 2] for n in f.data.get("npcs", []))}
    goals = {g for g in goals if (REGION / (g[0] + ".json")).is_file()}
    plateau = "indigo_plateau_pokemon_center_1f"
    if any(n.get("heal") and n["at"] == [13, 10] for n in p.routes.fields[plateau].data["npcs"]):
        goals.add((plateau, 13, 12))
    p.go(goals)
    p.do("face", dir="u")
    if any(m[3] != m[4] for m in p.state["party"]):
        raise RuntimeError(f"Nurse failed to restore party at {p.pos}")


def earn_ball_money(p):
    """Fight unbeaten outdoor trainers using the same A-to-talk interaction as the campaign."""
    mode(p, "travel")
    if weak_party(p):
        heal(p)
    mid = "kanto_main"
    field = p.routes.fields[mid]
    defeated = set(p.state.get("defeated", {}).get("kanto/kanto_main", []))
    approaches = {}
    level = max(m[2] for m in p.state["party"])
    for trainer in field.data["npcs"]:
        team = trainer.get("battle", {}).get("party", [])
        if not team or not trainer.get("sight") or trainer["name"] in defeated:
            continue
        if max(int(mon["level"]) for mon in team) > level + 2:
            continue
        x, y = trainer["at"]
        for key, (dx, dy, *_) in VECTORS.items():
            nx, ny = x - dx, y - dy
            if 0 <= nx < field.w and 0 <= ny < field.h and not field.get("collision", nx, ny):
                approaches[(mid, nx, ny)] = (key, trainer["name"])
    initial = p.state["money"]
    while approaches and p.state["money"] <= initial:
        try:
            p.go(set(approaches))
        except ValueError:
            break
        key, name = approaches[p.pos]
        p.do("face", dir=key)
        approaches = {pos: value for pos, value in approaches.items() if value[1] != name}
    return p.state["money"] > initial


def supplies(p, target):
    have = sum(p.state["bag"].get(k, 0) for k in BALLS)
    budget = int(p.state["money"])
    buy = min(target - have, budget // 200)
    if buy <= 0:
        return have
    mode(p, "travel")
    goals = {(mid, 4, 3) for mid, field in p.routes.fields.items() if mid.endswith("_mart") and
             any(n.get("shop") and n["at"] == [2, 3] for n in field.data.get("npcs", []))}
    p.go(goals)
    p.do("face", dir="l")
    p.do("shop", item="精灵球", amount=buy)
    p.do("back")
    if sum(p.state["bag"].get(k, 0) for k in BALLS) != have + buy:
        raise RuntimeError(f"Failed to buy {buy} balls at {p.pos}")
    return have + buy


def enter_patch(p, habitat):
    mode(p, "travel")
    p.go({(habitat.mid, *xy) for xy in habitat.grass})


def pace(p, patch, purpose, steps=48):
    mode(p, purpose)
    start = p.pos
    for key, (dx, dy, *_) in VECTORS.items():
        neighbor = (patch.mid, start[1] + dx, start[2] + dy)
        if neighbor[1:] not in patch.grass or neighbor[1:] in p.routes.occupied.get(patch.mid, set()):
            continue
        if (key, neighbor) not in p.routes.edges(start):
            continue
        reverse = {"u":"d", "d":"u", "l":"r", "r":"l"}[key]
        if (reverse, start) not in p.routes.edges(neighbor):
            continue
        legs = [[key, neighbor], [reverse, start]] * (steps // 2)
        p.do("walk", legs=legs)
        if p.pos[0] == "safarizone_entrance" and patch.mid.startswith("safarizone_"):
            return  # Admission ends immediately at zero Safari Balls or steps.
        if p.pos != start:
            break
        return
    raise RuntimeError(f"Cannot pace an encounter pair at {p.pos}")


def weak_party(p):
    party = p.state["party"]
    return not party or not any(m[3] > m[4] * 0.45 and sum(m[6]) > 3 for m in party)


def kanto_caught(p):
    return {int(n) for n in p.state["dex"] if 1 <= int(n) <= 151}


def collect_kanto(p, target=60):
    """Visit productive grass patches until the caught national numbers reach the target."""
    stalled = Counter()
    unavailable = set()
    while len(kanto_caught(p)) < target:
        owned = kanto_caught(p)
        balls = sum(p.state["bag"].get(k, 0) for k in BALLS)
        if balls < 5:
            balls = supplies(p, min(100, 5 * (target - len(owned)) + 5))
        if not balls and earn_ball_money(p):
            balls = supplies(p, 30)
        if not balls:
            raise RuntimeError(f"No affordable balls or remaining reachable trainers at {len(owned)}/{target}")
        if weak_party(p):
            heal(p)
        candidates = []
        for patch in habitats():
            if patch.mid.startswith("ceruleancave_") and not p.state.get("hall"):
                continue
            missing = patch.odds.keys() - owned
            if not missing or patch.name in unavailable:
                continue
            chance = sum(patch.odds[k] for k in missing) / sum(patch.odds.values())
            score = chance * (1 + min(4, len(missing)) / 4) / (1 + stalled[patch.name] / 3)
            if p.pos[0] == patch.mid and p.pos[1:] in patch.grass:
                score *= 1.4
            if patch.level > max(m[2] for m in p.state["party"]) + 8:
                score *= 0.2
            candidates.append((score, patch))
        if not candidates:
            raise RuntimeError(f"Reachable encounters exhausted at {len(owned)}/{target}")
        _, patch = max(candidates, key=lambda pair: pair[0])
        try:
            enter_patch(p, patch)
            pace(p, patch, "collect")
        except ValueError as exc:
            print("Unreachable habitat", patch.name, exc.args[0][:130], flush=True)
            unavailable.add(patch.name)
            continue
        print("POKEDEX", len(kanto_caught(p)), "/", target, patch.name, flush=True)
        if owned == kanto_caught(p):
            stalled[patch.name] += 1
            if stalled[patch.name] >= 16:
                unavailable.add(patch.name)
    mode(p, "travel")


def collect_candies(p, needed):
    mode(p, "travel")
    approaches = {}
    for mid, field in p.routes.fields.items():
        if not (REGION / (mid + ".json")).is_file():
            continue
        for item in field.data.get("objects", []):
            if item.get("name") != "神奇糖果":
                continue
            x, y = item["at"]
            if f"{mid}:{x},{y}" in p.state["flags"] or item.get("flag") in p.state["flags"]:
                continue
            for key, (dx, dy, *_) in VECTORS.items():
                nx, ny = x - dx, y - dy
                if 0 <= nx < field.w and 0 <= ny < field.h and not field.get("collision", nx, ny):
                    approaches[(mid, nx, ny)] = (key, mid, x, y)
    while approaches and p.state["bag"].get("神奇糖果", 0) < needed:
        try:
            p.go(set(approaches))
        except ValueError:
            break
        key, mid, x, y = approaches[p.pos]
        p.do("face", dir=key)
        approaches = {pos: v for pos, v in approaches.items() if v[1:] != (mid, x, y)}


def prepare_party(p, target_level=60):
    """Prepare for the Kanto League after eight badges. Every level comes from battle or a collected candy."""
    heal(p)
    supplies(p, 45)
    # The postgame Cerulean Cave is deliberately excluded from League preparation.
    patches = {h.name: h for h in habitats()}
    training_ground = patches["ROUTE23"]
    while len(p.state["party"]) > 8 and sum(m[2] >= 40 for m in p.state["party"]) < 3:
        weakest = min(range(1, len(p.state["party"])), key=lambda i: p.state["party"][i][2])
        size = len(p.state["party"])
        p.do("deposit", slot=weakest)
        if len(p.state["party"]) >= size:
            raise RuntimeError("PC did not accept the selected party member")
    enter_patch(p, training_ground)
    for _ in range(12):
        if not sum(p.state["bag"].get(k, 0) for k in BALLS) or len(p.state["party"]) >= 12: break
        if sum(m[2] >= 40 for m in p.state["party"]) >= 3: break
        pace(p, training_ground, "collect", 32)
        if weak_party(p):
            heal(p)
            enter_patch(p, training_ground)
    collect_candies(p, max(0, target_level - max(m[2] for m in p.state["party"])))
    best = max(range(len(p.state["party"])), key=lambda i: p.state["party"][i][2])
    if best: p.do("lead", slot=best)
    while p.state["bag"].get("神奇糖果", 0) and p.state["party"][0][2] < target_level:
        before = p.state["bag"]["神奇糖果"]
        p.do("use", item="神奇糖果", slot=0)
        if p.state["bag"].get("神奇糖果", 0) >= before:
            raise RuntimeError("Rare Candy was not consumed")
    heal(p)
    enter_patch(p, training_ground)
    for batch in range(4000):
        levels = sorted((m[2] for m in p.state["party"]), reverse=True)
        if levels[0] >= target_level and len(levels) >= 3 and levels[2] >= target_level - 12:
            break
        if weak_party(p) or p.state["party"][0][3] < p.state["party"][0][4] // 3 or sum(p.state["party"][0][6]) < 4:
            heal(p)
            enter_patch(p, training_ground)
        pace(p, training_ground, "train", 64)
        if not batch % 25:
            print("LEAGUE PREPARATION", levels[:6], batch, flush=True)
    else:
        raise RuntimeError(f"League preparation did not reach Lv{target_level} in Victory Road")
    heal(p)
    mode(p, "travel")
