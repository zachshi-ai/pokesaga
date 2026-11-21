"""Walk the mansion's three statue switches, left-hand drop, basement and southeast exit."""
from campaign_route import VECTORS, NAMES

import json
from pathlib import Path

TRAVERSALS = json.loads(Path(__file__).with_name("kanto_traversals.json").read_text())
TO_KEY, TO_EXIT = TRAVERSALS["mansion"]


def trace(routes, pos, key):
    mid, x, y = pos
    dx, dy, _, _ = VECTORS[key]
    doors = routes.fields[mid].doors
    foot = doors.get((x, y), {})
    ahead = doors.get((x+dx, y+dy), {})
    if NAMES.get(foot.get("trigger")) == key:
        return routes.projection(foot["to"])
    if ahead and (ahead.get("trigger", "step") == "step" or (ahead.get("trigger") == "door" and key == "u")):
        return routes.projection(ahead["to"])
    return (mid, x+dx, y+dy)


def replay(p, sequence):
    for segment in sequence.split():
        if segment.startswith("A"):
            p.do("face", dir=segment[1])
            p.do("click", label="按下")
            continue
        if segment.startswith("P"):
            p.do("face", dir=segment[1])
            continue
        key, length = segment[0], int(segment[1:])
        planned = []
        end = p.pos
        for _ in range(length):
            end = trace(p.routes, end, key)
            planned.append([key, end])
        p.do("walk", legs=planned)
        if p.pos != end:
            raise RuntimeError(f"Field route stopped at {p.pos}, expected {end}: {p.state['obstruction']}")


def acquire_key(p):
    if "secret_key" in p.state["flags"]:
        return
    p.visit("pokemon_mansion_1f", (8,33))
    if "mansion_secret_switch" in p.state["flags"]:
        p.interact("pokemon_mansion_1f", (5,5))
        p.do("click", label="按下")
        p.visit("pokemon_mansion_1f", (8,33))
    replay(p, TO_KEY)
    p.milestone("secret_key")
    replay(p, TO_EXIT+" d1")
    assert p.pos[0] == "kanto_main", p.pos
