"""Solve the active Platinum gym using only visible room state, walking and A."""
from collections import deque
from campaign_route import VECTORS

def around(at):
    return {(at[0]-a[0],at[1]-a[1]):k for k,a in VECTORS.items()}

def path(start,goals,neighbors):
    q=deque([start]);prev={start:None}
    while q:
        p=q.popleft()
        if goals(p):
            result=[]
            while prev[p]:
                p,key,end=prev[p];result.append((key,end))
            return result[::-1]
        for key,dest,end in neighbors(p):
            if dest not in prev:
                prev[dest]=(p,key,end);q.append(dest)
    return None

def walk(p,mid,plan):
    for i in range(0,len(plan),16):
        chunk=plan[i:i+16]
        p.do('walk',legs=[[k,[mid,*end]] for k,end in chunk])
        if tuple(p.pos[1:])!=tuple(chunk[-1][1]):return False
    return True

def move_to(p,mid,points):
    for attempt in range(20):
        coll=p.state['pl_gym_collision'] or p.routes.fields[mid].data['physics']['collision']
        occupied={tuple(r[0]) for r in p.state['actors']}
        h=len(coll);w=len(coll[0])
        def neighbors(cell):
            for k,(dx,dy,*_) in VECTORS.items():
                x,y=cell[0]+dx,cell[1]+dy
                if 0<=x<w and 0<=y<h and not coll[y][x] and (x,y) not in occupied:yield k,(x,y),(x,y)
        plan=path(p.pos[1:],lambda v:v in points,neighbors)
        if plan is None:return False
        if walk(p,mid,plan):return True
    raise RuntimeError(('gym blocked',mid,p.pos,points))

def prepare(p,event):
    key=event['id']
    if key not in ('s_lass_caroline','s_aroma_lady_jenna','s_aroma_lady_angela',*[f's_badge_{i}' for i in range(2,9)]): return
    mid=p.registry[event['map']]
    if key=='s_badge_3': solve_symbols(p)
    if key=='s_badge_8':solve_gears(p,mid)
    p.enter(mid)
    at=next((r[0] for r in p.state['actors'] if r[8]==event['trigger'].get('actor')),None)
    if not at and key=='s_badge_6':at=[16,3]
    if not at:raise RuntimeError(('missing gym trainer',key,p.pos))
    goals=around(at)
    if key in ['s_badge_4','s_badge_5','s_badge_6','s_badge_7','s_badge_8']: solve_local(p,mid,key,goals)
    if move_to(p,mid,goals):
        p.do('face',dir=goals[p.pos[1:]])
        if key not in p.state['flags']: raise RuntimeError(('gym trainer did not complete',key,p.pos,p.state['dialog']))
    else:raise RuntimeError(('gym access',key,p.pos,goals))

def neighbors_on(grid,xy,actors):
    x,y=xy
    for k,(dx,dy,*_) in VECTORS.items():
        a,b=x+dx,y+dy
        if 0<=b<len(grid) and 0<=a<len(grid[b]) and not grid[b][a] and (a,b) not in actors:
            yield k,(a,b),(a,b)

def engine_walk(p,mid,plan):
    if not walk(p,mid,plan): raise RuntimeError(('unexpected gym step',mid,p.pos,p.state['obstruction']))

def solve_symbols(p):
    for i in (1,2):
        mid='sinnoh_hearthome_city_gym_trainer_room_'+str(i)
        p.enter(mid)
        m=p.routes.fields[mid].data['platinum_gym'];state=p.state['pl_gym_state']
        # Each clue and its matching door display the same shape in the field.
        pos=m['doors'][int(state['choice'])][:2];stance=(pos[0],pos[1]+1)
        if not move_to(p,mid,{stance}): raise RuntimeError(('Hearthome clue door',mid,pos))
        target=next(w['to'] for w in p.routes.fields[mid].data['warps'] if w['at']==pos)
        p.do('walk',legs=[['u',[target['map'],*target['at']]]])
        if p.pos[0]!=target['map']: raise RuntimeError(('Hearthome door',p.pos,target))

def gear_water(p,mid,goals):
    f=p.routes.fields[mid].data;m=f['platinum_gym'];water=m['kind']=='water'
    actors={tuple(n[0]) for n in p.state['actors']}
    grid=f['physics']['collision'];layers={}
    buttons={(x,y):v for x,y,v in m['buttons']}
    for stage in range(3 if water else 4):
        layer=[r.copy() for r in grid]
        if water:
            for x,y,v in m['classes']:layer[y][x]=int(v!=stage)
        else:
            for i,(left,top,w,h) in enumerate(m['regions']):
                for y in range(top,top+h):
                    for x in range(left,left+w): layer[y][x]=int(i in m['states'][stage])
        for x,y in buttons:layer[y][x]=0
        layers[stage]=layer
    for _ in range(10):
        current=p.state['pl_gym_state'];start=int(current.get('level',1) if water else current.get('rotation',0))
        def edges(node):
            at,stage=node
            for k,end,_ in neighbors_on(layers[stage],at,actors):
                value=buttons.get(end)
                after=stage if value is None else value if water else (stage+value)%4
                yield k,(end,after),end
        plan=path((p.pos[1:],start),lambda d:d[0] in goals,edges)
        if plan is None:raise RuntimeError(('water or gear route',mid,p.pos,goals,start))
        if walk(p,mid,plan):return
    raise RuntimeError(('water/gear input',mid,p.pos))

def solve_gears(p,leader):
    for i in range(1,4):
        mid='sinnoh_sunyshore_city_gym_room_'+str(i)
        p.enter(mid)
        if mid==leader:return
        at=next(w['at'] for w in p.routes.fields[mid].data['warps'] if w['to']['map'].endswith('room_'+str(i+1)))
        gear_water(p,mid,{tuple(at)})
        w=next(w for w in p.routes.fields[mid].data['warps'] if w['at']==at)
        cmd=next(k for k,v in {'u':'up','r':'right','d':'down','l':'left'}.items() if v==w['trigger'])
        p.do('walk',legs=[[cmd,[w['to']['map'],*w['to']['at']]]])

def lift_plan(p,mid,goals,target_floor=3):
    m=p.routes.fields[mid].data['platinum_gym'];s=p.state['pl_gym_state'];rails=m['platforms']
    startmask=sum(int(s.get(str(i),r[6]))<<i for i,r in enumerate(rails))
    locs={}
    for i,(x,y,f,tx,ty,tf,_) in enumerate(rails):
        locs.setdefault((x,y,f),[]).append((i,0,(tx,ty,tf)))
        locs.setdefault((tx,ty,tf),[]).append((i,1,(x,y,f)))
    actors={(r['at'][0],r['at'][1],r['elevation']//10) for r in p.routes.fields[mid].data['npcs']}
    def explore(node):
        at,floor,mask=node
        for k,(dx,dy,*_) in VECTORS.items():
            x,y=at[0]+dx,at[1]+dy
            if not 0<=x<32 or not 0<=y<32 or (x,y,floor) in actors:continue
            active=next(((i,end) for i,side,end in locs.get((x,y,floor),[]) if mask>>i&1==side),None)
            if active:
                i,(tx,ty,tf)=active
                yield k,((tx,ty),tf,mask^(1<<i)),(tx,ty)
            elif not m['states'][floor][y*32+x]:
                yield k,((x,y),floor,mask),(x,y)
    plan=path((p.pos[1:],int(s.get('floor',0)),startmask),lambda node:node[1]==target_floor and node[0] in goals,explore)
    if plan is None:raise RuntimeError(('Canalave lifts',p.pos,s))
    engine_walk(p,mid,plan)

def bag_plan(p,mid,goals):
    data=p.routes.fields[mid].data;m=data['platinum_gym'];s=p.state['pl_gym_state']
    bags=tuple(map(tuple,s['bags']));tires=frozenset(map(tuple,s['tires']));static=data['physics']['collision'];rails=m['rails']
    actors={tuple(row[0]) for row in p.state['actors']}
    q=deque([(p.pos[1:],bags,tires,[])]);visited=set()
    while q:
        at,balls,wheels,schedule=q.popleft()
        blocked=actors|set(balls)|wheels
        neighborhood={at};work=[at]
        for here in work:
            for _,end,_ in neighbors_on(static,here,blocked):
                if end not in neighborhood:neighborhood.add(end);work.append(end)
        if goals.keys()&neighborhood:
            for stand,dir in schedule:
                if not move_to(p,mid,{stand}):raise RuntimeError(('bag stance',stand,p.pos))
                p.do('face',dir=dir)
            return
        key=min(neighborhood),balls,wheels
        if key in visited:continue
        visited.add(key)
        for i,pos in enumerate(balls):
            for stance,k in around(pos).items():
                if stance not in neighborhood:continue
                dx,dy,*_=VECTORS[k];x,y=pos;remain=wheels
                while True:
                    nx,ny=x+dx,y+dy;t=rails[y*32+x]
                    if not 0<=nx<32 or not 0<=ny<32 or t==2 and dy or t==3 and dx or t==5 and dx<0 or rails[ny*32+nx]==1 or (nx,ny) in balls:break
                    if (nx,ny) in remain:remain=remain-{(nx,ny)};break
                    x,y=nx,ny
                    if rails[y*32+x]==4:break
                if pos==(x,y) and remain==wheels:continue
                after=list(balls);after[i]=(x,y)
                q.append((stance,tuple(after),remain,schedule+[(stance,k)]))
    raise RuntimeError(('no punching-bag route',p.pos,goals,len(visited)))

def solve_local(p,mid,key,goals):
    if key=='s_badge_4':bag_plan(p,mid,goals)
    elif key in ('s_badge_5','s_badge_8'):gear_water(p,mid,goals)
    elif key=='s_badge_6':lift_plan(p,mid,goals)
    elif key=='s_badge_7':snow_route(p,mid,goals)

def snow_route(p,mid,goals):
    f=p.routes.fields[mid].data;g=f['physics'];grid=g['collision'];ice=g['slide']
    balls={tuple(n['at']):n['local_id'] for n in f['npcs'] if n['platinum_gfx']=='OBJ_EVENT_GFX_SNOWBALL'}
    live={tuple(r[0]) for r in p.state['actors'] if r[8] in balls.values()}
    other={tuple(r[0]) for r in p.state['actors'] if r[8] not in balls.values()}
    start=p.pos[1:],frozenset(live)
    def explore(node):
        at,solidballs=node
        for k,(dx,dy,mask,reverse) in VECTORS.items():
            x,y=at;remaining=solidballs;travel=False
            while True:
                nx,ny=x+dx,y+dy
                if not(0<=ny<len(grid) and 0<=nx<len(grid[ny])) or grid[ny][nx] or (nx,ny) in other:break
                sides=g.get('dirblock')
                if sides and (sides[y][x]&reverse or sides[ny][nx]&mask):break
                if (nx,ny) in remaining:
                    if not travel or not ice[y][x]:break
                    remaining=remaining-{(nx,ny)}
                x,y=nx,ny;travel=True
                if not ice[y][x]:break
            if travel:yield k,((x,y),remaining),(x,y)
    plan=path(start,lambda n:n[0] in goals,explore)
    if plan is None:raise RuntimeError(('Snowpoint ice',p.pos))
    engine_walk(p,mid,plan)
