"""Attach the study project's interregional walking routes to the playable Unova shoreline."""
from collections import deque
from functools import lru_cache
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DIRECTIONS={'left':(-1,0),'right':(1,0),'up':(0,-1),'down':(0,1)}
BW_PORTS={'unova_aspertia':'unova_nuvema','unova_virbank':'unova_castelia'}

@lru_cache(None)
def crossings(era):
    ports={}
    world=json.loads((ROOT/'content/world_destinations.json').read_text())
    for link in world['passages']:
        if 'unova' not in (link['a'],link['b']):continue
        old=next(p for p in (link['from'],link['to']) if p['region']=='unova')['map']
        original=json.loads((ROOT/f'content/regions/unova/maps/{old}.json').read_text())
        road=next(w for w in original['warps'] if w['to']['map']==link['via']['map'])
        w,h=original['size'];x,y=road['at']
        side=min(zip([x,w-1-x,y,h-1-y],DIRECTIONS))[1]
        mid=BW_PORTS.get(old,old) if era=='bw' else old
        ports.setdefault(mid,[]).append((side,road['to'],link['name']))
    return ports

def attach(data):
    era,mid=data['unova_era'],data['id']
    ports=crossings(era).get(mid,[])
    hub=mid==('unova_nuvema' if era=='bw' else 'unova_aspertia')
    if not (ports or hub):return
    w,h=data['size']
    physics=data['physics']
    blocked=physics['collision'];wet=physics.get('water')
    occupied={tuple(a['at']) for a in data['npcs']+data['warps']+data['objects'] if a.get('at')}
    occupied.update(tuple(x) for x in data['unova_anchors'].values())
    start=tuple(data['spawn'])
    def clear(x,y):
        return 0<=x<w and 0<=y<h and not int(blocked[y][x]) and not (wet and int(wet[y][x]))
    # Flood-fill from the real fly landing. Existing doors cannot be used as paths through a wall.
    visited={start:0};todo=deque([start])
    while todo:
        x,y=todo.popleft()
        for dx,dy in DIRECTIONS.values():
            pos=x+dx,y+dy
            if pos not in visited and clear(*pos) and pos not in occupied:
                visited[pos]=visited[(x,y)]+1;todo.append(pos)
    if hub:
        for dx,dy in DIRECTIONS.values():
            npc=start[0]+dx,start[1]+dy
            if npc in visited and npc not in occupied:
                data['npcs'].append({'at':list(npc),'local_id':'unova_navigator','name':'地区向导','gfx':'ranger','transit':True,'lines':['要前往哪个地区？']})
                data['unova_hub']={'region':'unova','map':mid,'at':list(start),'npc_at':list(npc)}
                occupied.add(npc)
                break
    for side,dest,label in ports:
        dx,dy=DIRECTIONS[side]
        candidates=[p for p in visited if p not in occupied and p!=start and (p[0]-dx,p[1]-dy) in visited]
        if not candidates:continue
        def score(p):
            x,y=p
            return (not clear(x+dx,y+dy), x*dx+y*dy, -visited[p])
        pos=max(candidates,key=score);occupied.add(pos)
        data['warps'].append({'at':list(pos),'trigger':side,'to':dest,'atlas':'world','name':label})
        # Place a direction sign beside the exit where it cannot block the corridor.
        for tx,ty in ((pos[0]-dy,pos[1]+dx),(pos[0]+dy,pos[1]-dx)):
            if 0<=tx<w and 0<=ty<h and (tx,ty) not in occupied and not clear(tx,ty):
                data['objects'].append({'kind':'sign','at':[tx,ty],'text':label+'　'+{'left':'←','right':'→','up':'↑','down':'↓'}[side]});break
