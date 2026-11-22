"""Controller inputs for Emerald's field items. Every pickup, machine and crossing is played in-game."""
import json
from functools import lru_cache

from campaign_route import ROOT, VECTORS


@lru_cache(maxsize=1)
def moves():
    return {int(m["id"]): m for m in json.loads((ROOT / "content/moves.json").read_text())}


@lru_cache(maxsize=1)
def compatible():
    return {int(k): set(v) for k, v in json.loads((ROOT / "content/hoenn_field_items.json").read_text())["learn"].items()}


def click(p, label):
    assert any(label in b for b in p.state["buttons"]), (label, p.pos, p.state["buttons"], p.state["dialog"])
    p.do("click", label=next(b for b in p.state["buttons"] if label in b))


def back(p):
    while p.state["buttons"]:
        p.do("back")


def machine(p, move, keep=(57, 249, 70)):
    if any(move in m[5] for m in p.state["party"]):
        back(p)
        return
    candidates = [m for m in p.state["party"] if m[1] in compatible()[move]]
    assert candidates, ("no compatible party member", move, p.state["party"])
    # Reserve Swampert's STAB attack for battles. Use another compatible partner if available.
    mon = next((m for m in candidates[1:] if len(set(m[5]) & set(keep))<3),candidates[0])
    if mon[0] not in p.state["buttons"]:
        back(p)
        p.do("hm")
        click(p,moves()[move]["name"])
    click(p, mon[0])
    if move not in next(m[5] for m in p.state["party"] if m[0]==mon[0]):
        options = [i for i in mon[5] if i not in keep]
        assert options, (mon, move, keep)
        old = min(options, key=lambda mid:moves()[mid].get("power",0))
        click(p, "（%d）" % old)
    assert any(move in m[5] for m in p.state["party"]), ("could not teach",move,p.state["dialog"])
    back(p)


def gift(p,mid,script,item):
    if item in p.state["flags"]: return
    npc=next(n for n in p.routes.fields[mid].data["npcs"] if n.get("source_script")==script)
    p.use_at(mid,npc["at"])
    assert item in p.state["flags"], (item,p.pos,p.state["dialog"],p.state["buttons"])


def dive(p,mid,xy,choice,dest):
    p.go({(mid,*xy)})
    p.do("face",dir="u")
    click(p,choice)
    assert p.pos[0]==dest,(choice,mid,xy,dest,p.pos,p.state["dialog"])


def from_sea(p,city=False):
    """Enter the visible opening, then surface inside the underwater chamber."""
    route = "126" if city else "128"
    start = (45,66) if city else (38,27)
    submarine = "em_underwater_sootopolis_city" if city else "em_underwater_seafloor_cavern"
    inside = "hoenn_sootopolis" if city else "hoenn_seafloor"
    if p.pos[0]==inside: return
    if not p.pos[0].startswith("em_underwater_"):
        dive(p,"hoenn_"+route,start,"下潜","em_underwater_route"+route)
    dive(p,submarine,(9,6) if city else (6,5),"上浮",inside)


def leave_sootopolis(p):
    if p.pos[0].startswith("em_sootopolis_city_"):
        if "h_badge_8" in p.state["flags"]:
            f=p.routes.fields["em_sootopolis_city_gym_1f"]
            for x,y,*values in f.data.get("mechanisms",{}).get("stairs",[]):
                f.grid["collision"][y*f.w+x]=values[-1]
            p.routes.edges.cache_clear()
        p.enter("hoenn_sootopolis")
    if p.pos[0]!="hoenn_sootopolis": return
    dive(p,"hoenn_sootopolis",(29,53),"下潜","em_underwater_sootopolis_city")
    dive(p,"em_underwater_route126",(45,66),"上浮","hoenn_126")


def prepare(p,event):
    key=event["id"]
    clean = "h_peace" not in p.state["flags"]
    if getattr(p.routes, "pillar_clean", None) != clean:
        for field in p.routes.fields.values():
            patches=field.data.get("mechanisms",{}).get("clean",[])
            field.repaired_floor={(x,y) for x,y,*_ in patches}
            for x,y,*values in patches:
                field.grid["collision"][y*field.w+x] = values[-1] if clean else field.data["physics"]["collision"][y][x]
        p.routes.pillar_clean=clean
        p.routes.edges.cache_clear()
    opened = "h_pillar" in p.state["flags"]
    if getattr(p.routes, "pillar_open", None) != opened:
        outside = p.routes.fields["em_sky_pillar_outside"]
        for x,y,*values in outside.data.get("mechanisms",{}).get("pillar_door",[]):
            outside.grid["collision"][y*outside.w+x] = values[-1] if opened else outside.data["physics"]["collision"][y][x]
        p.routes.pillar_open=opened
        p.routes.edges.cache_clear()
    legends = "h_kyogre" in p.state["flags"] and "h_peace" not in p.state["flags"]
    if getattr(p.routes,"sootopolis_legends",None) != legends:
        lake=p.routes.fields["hoenn_sootopolis"]
        model=lake.data.get("mechanisms",{})
        for x,y,*values in model.get("legends",[]):
            lake.grid["collision"][y*lake.w+x]=values[-1] if legends else lake.data["physics"]["collision"][y][x]
        for x,y,water,elevation in model.get("lake_terrain",[]):
            for prop,value in (("water",water),("elevation",elevation)):
                lake.grid[prop][y*lake.w+x]=value if legends else lake.data["physics"][prop][y][x]
        p.routes.sootopolis_legends=legends
        p.routes.edges.cache_clear()
    if key=="h_badge_2" and "h_item_hm_flash" not in p.state["flags"]:
        gift(p,"hoenn_granite","GraniteCave_1F_EventScript_Hiker","h_item_hm_flash")
        back(p)
    if key=="h_cozmo_report":
        gift(p,"em_mauville_city_house1","MauvilleCity_House1_EventScript_RockSmashDude","h_item_hm_rock_smash")
        machine(p,249)
        if "h_item_hm_strength" not in p.state["flags"]:
            p.use_at("hoenn_rusturf",[24,5])
            assert "h_item_hm_strength" in p.state["flags"],("Rusturf rocks",p.pos,p.state["dialog"])
        machine(p,70)
    if key=="h_steven118":
        machine(p,57)
    if key=="h_weather":
        # The northern overpass is at elevation 4. Ascend its eastern stairs,
        # then walk west along the deck; approaching from below stays on level 3.
        for xy in [(30,98),(30,97),(30,96),(35,86),(34,85),(27,85),(25,85),(21,85),(18,85),(12,85),(5,85)]:
            p.visit("hoenn_119",xy)
    if key=="h_scope": p.do("mode",value="train")  # Steven's invisible Kecleon must be fought.
    if key=="h_fortree_clear": p.do("mode",value="travel")
    if key=="h_kyogre":
        for traversal in (57,70,249): machine(p,traversal)
        machine(p,291,keep=(57,70,249))
        from_sea(p)
        cavern(p)
    if key in ("h_duel","h_peace"):
        from_sea(p,city=True)
    if key=="h_pillar":
        if p.pos[0].startswith("em_cave_of_origin"): p.enter("hoenn_sootopolis")
        leave_sootopolis(p)
    if key=="h_league":
        for traversal in (57,70,249,127): machine(p,traversal)
        victory_road(p)
    if key=="h_wally_road":
        leave_sootopolis(p)
        machine(p,127,keep=(57,70,249))
        # Reach the foaming lip by surfing, face it, then trigger the climb with A.
        field=p.routes.fields["hoenn_ever_grande"]
        banks={("hoenn_ever_grande",x,y+1) for y in range(1,field.h-1) for x in range(field.w)
               if field.get("waterfall",x,y) and not field.get("waterfall",x,y+1)
               and field.get("water",x,y+1) and not field.get("collision",x,y+1)}
        p.go(banks)
        before=p.pos
        p.do("face",dir="u")
        assert p.pos[0]==before[0] and p.pos[2]<before[2]-1,("Ever Grande waterfall",before,p.pos,p.state["dialog"])


def cavern_plan(field, start, exit_at, occupied=()):
    """Search movable boulder states. Paths between pushes use native collision, height and walls."""
    from collections import deque
    rocks=frozenset((int(o['at'][0]),int(o['at'][1])) for o in field.data['objects'] if o['kind']=='rock')
    initial=frozenset(tuple(map(int,o['at'])) for o in field.data['objects'] if o['kind']=='boulder')
    occupied=set(occupied)
    other_doors={cell for cell in field.doors if cell!=exit_at and cell!=start}
    def walkable(src,dst):
        x,y=dst
        if not (0<=x<field.w and 0<=y<field.h) or field.get('collision',x,y):return False
        if dst in occupied or dst in other_doors:return False
        h,k=field.get('elevation',*src),field.get('elevation',x,y)
        return h in (0,15) or k in (0,15,h)
    def reach(pos,boxes):
        parents={pos:None}
        queue=deque([pos])
        pushes=[]
        while queue:
            here=queue.popleft()
            if here==exit_at: break
            for k,(dx,dy,*_) in VECTORS.items():
                nxt=here[0]+dx,here[1]+dy
                if not walkable(here,nxt):continue
                if nxt in boxes:
                    dest=nxt[0]+dx,nxt[1]+dy
                    if dest not in boxes and dest not in rocks and dest not in field.doors and walkable(nxt,dest):
                        pushes.append((here,k,nxt,dest))
                elif nxt not in parents:
                    parents[nxt]=(here,k)
                    queue.append(nxt)
        return parents,pushes
    def trace(parents,cell):
        order=[]
        while parents[cell]:
            before,k=parents[cell]
            order.append(('rock' if cell in rocks else 'walk',k,cell))
            cell=before
        return order[::-1]
    queue=deque([(start,initial,[])])
    visited=set()
    while queue:
        pos,boxes,history=queue.popleft()
        paths,pushes=reach(pos,boxes)
        if exit_at in paths:return history+trace(paths,exit_at)
        fingerprint=min(paths),boxes
        if fingerprint in visited:continue
        visited.add(fingerprint)
        for here,k,block,dest in pushes:
            changed=(boxes-{block})|{dest}
            prefix=history+trace(paths,here)+[('push',k,block)]
            queue.append((block,changed,prefix))
    raise ValueError(('no boulder route',field.data['id'],start,exit_at))


def cavern(p):
    stages=[(1,2),(2,7),(7,3),(3,8),(8,9)]
    def room(n):return 'em_seafloor_cavern_room'+str(n)
    if p.pos[0]=='hoenn_seafloor':p.enter(room(1))
    for source,dest in stages:
        if p.pos[0]!=room(source): continue
        if source==7:
            p.enter(room(dest))
            continue
        door=next(w for w in p.routes.fields[p.pos[0]].data['warps'] if w['to']['map']==room(dest))
        walk_puzzle_room(p,door)
    assert p.pos[0]==room(9),('cavern exit',p.pos)



def walk_puzzle_room(p,door):
    mid=p.pos[0]
    field=p.routes.fields[mid]
    path=cavern_plan(field,p.pos[1:],tuple(door['at']),p.routes.occupied.get(mid,()))
    removed=set()
    for kind,k,pos in path:
        if (kind=='rock' and pos not in removed) or kind=='push':
            p.do('face',dir=k)
            removed.add(pos)
        end=(door['to']['map'],*door['to']['at']) if pos==tuple(door['at']) else (mid,*pos)
        p.do('walk',legs=[[k,end]])
        assert p.pos==end,('cavern walk',kind,mid,pos,k,p.pos,p.state['dialog'],p.state['obstruction'])


def victory_road(p):
    b1='em_victory_road_b1f'
    b2='em_victory_road_b2f'
    field=p.routes.fields[b1]
    # Western stairs below the first encounter with Wally.
    p.go({(b1,8,3)})
    walk_puzzle_room(p,field.doors[30,25])
    # Surf across B2F and scale the northbound fall before taking the inner staircase.
    p.go({(b1,17,16)})
    walk_puzzle_room(p,field.doors[20,21])
    p.enter('hoenn_league')
