"""Complete Turffield by approaching each flock on the field and tapping real battle commands."""
from collections import deque
from campaign_route import VECTORS

LOBBY="galar_turffield_pitch_room"
FIELD="galar_turffield_mission"
PITCH="galar_turffield_pitch"

def herd(p):
    p.enter(LOBBY)
    if "g_gym_registered" not in p.state["flags"]:
        clerk = next(row[0] for row in p.state["actors"] if row[1]=="g_gym_reception")
        p.use_at(LOBBY,clerk)
    assert "g_gym_registered" in p.state["flags"],p.state["dialog"]
    if "g_gym_mission" not in p.state["flags"]:
        p.enter(FIELD)
        play_pastures(p)
        assert all("g_pen_%d"%i in p.state["flags"] for i in range(1,5))
    p.enter(PITCH)
    leader=next(row[0] for row in p.state["actors"] if row[1]=="galar_milo")
    p.use_at(PITCH,leader)
    assert "g_badge_1" in p.state["flags"],(p.pos,p.state["dialog"],p.state["fights"])
    assert p.state["bag"]["伽勒尔招式学习器10·魔法叶"]==1 and p.state["bag"]["草之套装"]==1
    print("MILO",p.state["fights"],p.state["galar_dynamax_inputs"],flush=True)

def play_pastures(p):
    field=p.routes.fields[FIELD]
    target_role=None
    for turn in range(700):
        flags=set(p.state["flags"])
        if "g_gym_mission" in flags:return
        actors={row[1]:tuple(row[0]) for row in p.state["actors"]}
        occupied={tuple(row[0]) for row in p.state["actors"]}
        here=p.pos[1:]
        paths={here:None}
        queue=deque([here])
        while queue:
            x,y=queue.popleft()
            for key,(dx,dy,*_) in VECTORS.items():
                to=x+dx,y+dy
                if to in paths or to in occupied or to in field.doors:continue
                if not (0<to[0]<field.w-1 and 0<to[1]<field.h-1) or field.get("collision",*to):continue
                paths[to]=(key,to) if (x,y)==here else paths[x,y]
                queue.append(to)
        trainer=next((r for r in actors if r.startswith("g_grass_trainer_") and
                     "g_grass_win_"+r.rsplit("_",1)[1] not in flags),None)
        if trainer:
            tx,ty=actors[trainer]
            goals={(tx-dx,ty-dy):k for k,(dx,dy,*_) in VECTORS.items()}
            if here in goals:
                p.do("face",dir=goals[here])
                assert "g_grass_win_"+trainer.rsplit("_",1)[1] in p.state["flags"],(trainer,p.state["dialog"])
                continue
            dest=next(pos for pos in paths if pos in goals)
        else:
            flocks={role:pos for role,pos in actors.items() if role.startswith("g_flock_")}
            if target_role not in flocks:
                target_role=min(flocks,key=lambda r: abs(here[0]-flocks[r][0])+abs(here[1]-flocks[r][1]))
            sx,sy=flocks[target_role]
            # Pressure from the rear. Step along the back of the group to keep it moving.
            options=[pos for pos in paths if pos!=here and abs(pos[0]-sx)<=2 and 1<=pos[1]-sy<=3]
            if not options:
                raise AssertionError(("unreachable flock",p.pos,actors))
            dest=options[0]
        key,pos=paths[dest]
        before=p.pos
        p.do("walk",legs=[[key,[FIELD,*pos]]])
        assert p.pos!=before,("blocked herder",before,key,p.state["actors"],p.state["dialog"])
        newly=set(p.state["flags"])-flags
        if any(f.startswith("g_pen_") for f in newly):print("WOOLLOO PEN",sorted(newly),turn+1,p.pos,flush=True)
    raise AssertionError(("herding did not finish",p.pos,p.state["actors"]))
