"""Navigate the Distortion World on foot, carrying out the original ride/lift inputs."""
from collections import deque
from campaign_route import VECTORS

PREFIX='sinnoh_distortion_world_'
FACES={'up':'u','down':'d','left':'l','right':'r'}


def travel(p,goals,until_flag=None):
    denied=set();actors_by_map={}
    maps={mid:f for mid,f in p.routes.fields.items() if mid.startswith(PREFIX)}
    actions={}
    for mid,f in maps.items():
        for row in f.data['warps']:
            dest=row['to'];kind=row.get('mechanism','')
            if not dest['map'].startswith(PREFIX):continue
            target=dest['map'],*map(int,dest['at']);x,y=row['at']
            if kind=='distortion_lift':
                for key,(dx,dy,*_) in VECTORS.items():actions[mid,x-dx,y-dy,'A'+key]=target
            elif row['trigger'] in FACES:
                actions[mid,x,y,FACES[row['trigger']]]=target
    for _ in range(200):
        if p.pos in goals or until_flag in p.state['flags']:return
        actors_by_map[p.pos[0]]={(p.pos[0],*map(int,row[0])) for row in p.state['actors']}
        occupied=set().union(*actors_by_map.values())
        work=deque([p.pos]);prev={p.pos:None};end=None
        while work:
            at=work.popleft();mid,x,y=at;f=maps[mid]
            if at in goals:end=at;break
            for k,(dx,dy,*_) in VECTORS.items():
                for cmd in (k,'A'+k):
                    dst=actions.get((*at,cmd))
                    if dst is None:
                        if cmd!=k:continue
                        tx,ty=x+dx,y+dy
                        if not (0<=tx<f.w and 0<=ty<f.h) or f.get('collision',tx,ty):continue
                        dst=mid,tx,ty
                    if dst in prev or dst in occupied or (*at,cmd) in denied:continue
                    if dst[0]!=mid and not p.routes.flags.issuperset(p.routes.gates.get(dst[0],{}).get('require',[])):continue
                    prev[dst]=at,cmd;work.append(dst)
        if end is None:
            raise RuntimeError(('no Distortion World route',p.pos,list(goals)[:5],len(prev),sorted(denied)[-15:],sorted(set(i[0] for i in prev))))
        plan=[]
        while prev[end]:
            start,cmd=prev[end];plan.append((start,cmd,end));end=start
        legs=[]
        for start,cmd,end in plan[::-1]:
            if cmd.startswith('A'):
                if legs:break
                p.do('face',dir=cmd[1:])
                if p.pos==start:
                    denied.add((*start,cmd))
                break
            legs.append([cmd,end])
            if len(legs)==24:break
        if legs:
            p.do('walk',legs=legs)
            if p.state['obstruction']:
                start,cmd,expected=p.state['obstruction'];at=tuple(start);dx,dy,*_=VECTORS[cmd];x,y=at[1]+dx,at[2]+dy
                if p.pos==at and 0<=x<maps[at[0]].w and 0<=y<maps[at[0]].h and maps[at[0]].get('water',x,y):
                    p.do('face',dir=cmd)
                    for label in ('冲浪','好'):
                        if label in p.state['buttons']:p.do('click',label=label)
                    if p.pos==at:p.do('walk',legs=[[cmd,expected]])
                    if p.pos!=at:continue
                denied.add((*at,cmd))
    raise RuntimeError(('Distortion World unresolved input',p.pos))
