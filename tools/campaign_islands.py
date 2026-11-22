"""Play the two Sevii visits using field movement, the passenger ferry and normal conversations."""
from collections import deque

from campaign_route import VECTORS

CENTER = "one_island_pokemon_center_1f"
HARBOR = "_island_harbor"
ISLANDS = {"one":"一之岛","two":"二之岛","three":"三之岛","four":"四之岛","five":"五之岛","six":"六之岛"}


def ferry(p, origin, destination):
    p.interact(origin + HARBOR, (8, 6))
    p.do("click", label=ISLANDS[destination])
    assert p.pos[0] == destination + HARBOR, (origin, destination, p.state)


def heal(p, island):
    p.visit(island + "_island_pokemon_center_1f", (5 if island == "one" else 7, 4), "u")


def teach(p, move_name, move_id):
    if any(move_id in mon[5] for mon in p.state["party"]):
        return
    p.do("hm")
    p.do("click", label=move_name)
    choices = p.state["buttons"]
    eligible = [(len(mon[5]) >= 4, sum(move in (15,57,70,127,249) for move in mon[5]), name)
                for name in choices if "学不会" not in name
                for mon in p.state["party"] if name == mon[0]]
    student = min(eligible)[-1] if eligible else None
    if student is None:
        raise RuntimeError((move_name, choices, p.state["party"]))
    p.do("click", label=student)
    if not any(move_id in mon[5] for mon in p.state["party"]):
        # Preserve the strongest attacks and the other field moves when replacing a move.
        choices = [x for x in p.state["buttons"] if x not in ("返回","取消","关闭","算了，不学") and not any(
            existing in x for existing in ("冲浪","居合斩","飞翔","怪力","攀瀑","碎岩"))]
        if choices:
            p.do("click",label=choices[-1])
    assert any(move_id in mon[5] for mon in p.state["party"]), (move_name,p.state)


def detour(p):
    if "sevii_visit_started" not in p.state["flags"]:
        if "sevii_bill_waits" in p.state["flags"]:
            p.interact("cinnabarisland_pokemoncenter_1f",(11,5))
        else:
            p.go({("kanto_main",80,386),(CENTER,14,7)})
            if "sevii_visit_started" not in p.state["flags"]:
                p.interact("kanto_main",(80,387))
    p.interact(CENTER,(15,6))
    p.milestone("sevii_meteorite_errand")
    assert p.state["bag"].get("陨石") == 1 and p.state["bag"].get("三岛通行证") == 1
    heal(p,"one")
    teach(p,"冲浪",57)
    teach(p,"居合斩",15)
    ferry(p,"one","two")
    p.interact("two_island_joyful_game_corner",(5,5))
    p.milestone("sevii_lostelle_missing")
    ferry(p,"two","three")
    p.interact("three_island",(7,24))
    p.milestone("sevii_bikers_left")
    heal(p,"three")
    forest = "three_island_berry_forest"
    p.go({(forest,4,9),(forest,5,8),(forest,3,8),(forest,4,7)})
    p.do("mode",value="train")
    try:
        p.interact("three_island_berry_forest",(4,8))
    finally:
        p.do("mode",value="travel")
    p.milestone("sevii_lostelle_rescued")
    p.interact("two_island_joyful_game_corner",(5,5))
    p.milestone("sevii_delivered_meteorite")
    ferry(p,"two","one")
    p.interact(CENTER,(14,6))
    p.milestone("sevii_detour_finished")
    assert p.pos[0] == "cinnabarisland_pokemoncenter_1f"


def boulder_passage(p, room, entrance, exit_tile):
    """Solve the Strength room on entry. A push needs a vacant square beyond the boulder."""
    p.visit(room, entrance)
    field = p.routes.fields[room]
    stones = frozenset(tile for tile, kind in field.blockers.items() if kind == "boulder")
    rocks = {tile for tile, kind in field.blockers.items() if kind == "rock"}
    floor = {(x,y) for y in range(field.h) for x in range(field.w) if not field.get("collision",x,y)}
    floor -= rocks | (set(field.doors) - {entrance, exit_tile})
    start = (entrance, stones)
    previous = {start: None}
    queue = deque([start])
    while queue:
        state = queue.popleft()
        (x,y), stones = state
        if (x,y) == exit_tile: break
        for key,(dx,dy,_,_) in VECTORS.items():
            ahead = x+dx,y+dy
            if ahead not in floor: continue
            pushed = ahead in stones
            new_stones = stones
            if pushed:
                beyond = ahead[0]+dx,ahead[1]+dy
                if beyond not in floor or beyond in stones: continue
                new_stones = (stones - {ahead}) | {beyond}
            following = (ahead,new_stones)
            if following not in previous:
                previous[following] = state,key,pushed
                queue.append(following)
    else:
        raise ValueError(("Strength puzzle has no solution",room,entrance,exit_tile))
    moves = []
    while previous[state]:
        before,key,pushed = previous[state]
        moves.append((key,pushed,state[0]))
        state = before
    for key,push,tile in reversed(moves):
        if push: p.do("face",dir=key)
        dest = (room,*tile) if tile != exit_tile else p.routes.projection(field.doors[tile]["to"])
        p.do("walk",legs=[[key,dest]])
        assert p.pos == dest, ("Mt Ember Strength step",p.pos,dest,key,push)


def icefall_path(routes, puzzles, start, finish):
    main = "four_island_icefall_cave_1f"
    basement = "four_island_icefall_cave_b1f"
    entry = "four_island_icefall_cave_entrance"
    thin = {tuple(r["thin_ice"]) for r in puzzles[main]}
    state = (start, frozenset())
    queue = deque([state])
    previous = {state: None}

    def step(loc, key):
        for direction, candidate in routes.edges(loc):
            if direction == key:
                return routes.projection(candidate) if isinstance(candidate, dict) else candidate

    while queue:
        state = queue.popleft()
        loc, cracked = state
        if loc == finish:
            path = []
            while previous[state]:
                state, key, landing = previous[state]
                path.append((key, landing))
            return list(reversed(path))
        for key in VECTORS:
            end = step(loc, key)
            if not end or end[0] not in (main, basement, entry):
                continue
            # The player cannot turn or stop before the end of a sheet of ice.
            while end[0] == basement and routes.fields[basement].get("slide", *end[1:]) == 255:
                following = step(end, key)
                if not following or following == end:
                    break
                end = following
            marked = cracked
            if end[0] == main and loc[0] == main and end[1:] in thin:
                if end[1:] in cracked:
                    end = (basement, *end[1:])
                    marked = frozenset()
                else:
                    marked = marked | {end[1:]}
            if end[0] != main:
                marked = frozenset()
            candidate = (end, marked)
            if candidate not in previous:
                previous[candidate] = (state, key, end)
                queue.append(candidate)
    raise ValueError(("No route across Icefall Cave", start, finish))


def climb_icefall(p):
    main = "four_island_icefall_cave_1f"
    entrance = "four_island_icefall_cave_entrance"
    if not p.state["bag"].get("秘传学习器 07", 0):
        p.visit(main, (3,17))
        for finish in [(main, 12, 16), (entrance, 10, 22)]:
            for key, landing in icefall_path(p.routes, p.puzzles, p.pos, finish):
                here = p.pos
                p.do("walk", legs=[[key, landing]])
                assert p.pos == landing, ("Icefall Cave", here, key, landing, p.pos)
        assert p.state["bag"].get("秘传学习器 07", 0)
    teach(p,"攀瀑",127)
    p.visit(entrance, (17,21), "u")
    assert p.pos == (entrance,17,13), ("Waterfall",p.pos,p.state["dialog"])


def postgame(p):
    if "national_dex" not in p.state["flags"]:
        p.interact("pallettown_professoroakslab",(6,3))
    p.milestone("national_dex")
    teach(p,"冲浪",57)
    teach(p,"居合斩",15)
    teach(p,"怪力",70)
    if not p.state["bag"].get("秘传学习器 06",0):
        p.interact("one_island_kindle_road_ember_spa",(10,5))
    assert p.state["bag"].get("秘传学习器 06",0)
    teach(p,"碎岩",249)
    p.interact(CENTER,(15,6))
    p.milestone("ember_ruby_requested")
    heal(p,"one")
    mountain = "mt_ember_exterior"
    p.interact(mountain,(41,40))
    p.milestone("sevii_password_one")
    if "beat_ember_grunt_1" not in p.state["flags"]: p.interact(mountain,(41,40))
    p.interact(mountain,(42,40))
    p.milestone("beat_ember_grunt_2")
    p.routes.cleared.add((mountain,42,39))
    p.routes.edges.cache_clear()
    boulder_passage(p,"mt_ember_ruby_path_b2f",(1,7),(13,9))
    boulder_passage(p,"mt_ember_ruby_path_b3f",(1,4),(5,19))
    p.interact("mt_ember_ruby_path_b5f",(7,7))
    p.milestone("got_ember_ruby")
    boulder_passage(p,"mt_ember_ruby_path_b3f",(5,19),(19,19))
    p.interact(CENTER,(15,6))
    p.milestone("delivered_ember_ruby")
    assert p.state["bag"].get("彩虹通行证") == 1 and "三岛通行证" not in p.state["bag"]
    heal(p,"one")
    ferry(p,"one","four")
    climb_icefall(p)
    p.interact("four_island_icefall_cave_back",(12,16))
    p.milestone("rescued_icefall")
    ferry(p,"four","six")
    p.visit("six_island_ruin_valley",(24,25),"u")
    p.do("click",label="使用居合斩")
    p.milestone("ruin_valley_cut_door")
    p.routes.cleared.add(("six_island_ruin_valley",24,24))
    p.routes.edges.cache_clear()
    # Step down each correct hole. The other holes return the player to the first floor.
    for floor,xy in (("b1f",(6,7)),("b2f",(6,7)),("b3f",(6,7)),("b4f",(6,7))):
        p.visit("six_island_dotted_hole_"+floor,xy)
    p.interact("six_island_dotted_hole_sapphire_room",(7,7))
    p.milestone("sevii_password_two")
    ferry(p,"six","five")
    heal(p,"five")
    warehouse = "five_island_rocket_warehouse"
    for name,xy in (("grunt1",(6,6)),("grunt2",(15,11)),("grunt3",(17,15)),
                    ("admin1",(27,16)),("admin2",(25,11))):
        p.interact(warehouse,xy)
        p.milestone("sevii_warehouse_"+name)
    p.interact(warehouse,(27,4))
    p.milestone("sevii_recovered_sapphire")
    ferry(p,"five","one")
    p.interact(CENTER,(15,6))
    p.milestone("sevii_network_online")
    assert "蓝宝石" not in p.state["bag"]
