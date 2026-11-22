"""Replay the Emerald Gym mechanisms with ordinary directional inputs and A."""
from collections import deque
from campaign_route import VECTORS

DIRS={k:(v[0],v[1]) for k,v in VECTORS.items()}

def walk(p,route):
    while route:
        block,route=route[:30],route[30:]
        p.do("walk",legs=[[k,(p.pos[0],*xy)] for k,xy in block])
        if p.pos[1:]!=block[-1][1]:
            raise AssertionError(("gym input",p.pos,block,p.state["obstruction"]))

def search(start,goal,edges):
    q=deque([start]);seen={start:None}
    while q:
        node=q.popleft()
        if goal(node):
            result=[]
            while seen[node]:
                prev,k=seen[node];result.append((k,node[:2]));node=prev
            return result[::-1]
        for k,n in edges(node):
            if n not in seen:seen[n]=node,k;q.append(n)
    raise ValueError(("no puzzle path",start))

def mauville(p):
    mid=p.pos[0]; f=p.routes.fields[mid];m=f.data["mechanisms"];base=f.data["physics"]["collision"]
    cells={(x,y):c for x,y,_,_,c in m['alt']};buttons={(x,y):i for x,y,i in m['buttons']}
    actors={tuple(a[0]) for a in p.state["actors"]}
    def edges(s):
        x,y,alt,press=s
        for k,(dx,dy) in DIRS.items():
            a,b=x+dx,y+dy
            if not (0<=a<f.w and 0<=b<f.h) or (a,b) in actors:continue
            if (cells.get((a,b),base[b][a]) if alt else base[b][a]):continue
            n=buttons.get((a,b),press)
            yield k,(a,b,alt^(n!=press),n)
    leader=next(n for n in f.data['npcs'] if 'Wattson' in n['source_script'])
    lx,ly=leader['at']
    alt=int('h_wattson_alt' in p.state['flags'])
    press=p.state.get('gym_button',0)
    steps=search((*p.pos[1:],alt,press),lambda n:abs(n[0]-lx)+abs(n[1]-ly)==1,edges)
    walk(p,steps)
    for x,y,_,_,c in m['off']:f.grid['collision'][y*f.w+x]=c
    p.routes.edges.cache_clear()

def petalburg(p):
    mid=p.pos[0]; f=p.routes.fields[mid]
    for trainer in ('TRAINER_RANDALL','TRAINER_PARKER','TRAINER_JODY'):
        if 'h_trainer_'+trainer in p.state['flags']:continue
        n=next(n for n in f.data['npcs'] if n.get('source_trainer')==trainer)
        p.use_at(mid,n['at'])
        if 'h_trainer_'+trainer not in p.state['flags']:raise AssertionError(('gym room',trainer,p.pos,p.state['dialog']))
    for changes in f.data['mechanisms']['doors'].values():
        for x,y,_,_,c in changes:f.grid['collision'][y*f.w+x]=c
    p.routes.edges.cache_clear()

def prepare(p,event):
    if event['id'] not in ('h_badge_3','h_badge_5','h_badge_6','h_badge_7','h_badge_8'):return
    p.enter(event['map_id'])
    if event['id']=='h_badge_3':mauville(p)
    elif event['id']=='h_badge_5':petalburg(p)
    elif event['id']=='h_badge_6':fortree(p)
    elif event['id']=='h_badge_7':mossdeep(p)
    elif event['id']=='h_badge_8':sootopolis(p)

SHAPES={"l1":(1,1,0,0),"l2":(2,1,0,0),"l3":(1,2,0,0),"l4":(2,2,0,0),"t1":(1,1,1,0),"t2":(2,1,1,0),"t3":(1,2,1,0),"t4":(1,1,2,0)}
CW=((0,-1),(1,-2),(0,0),(1,0),(-1,0),(-1,1),(-1,-1),(-2,-1))
CCW=((-1,-1),(-1,-2),(0,-1),(1,-1),(0,0),(0,1),(-1,0),(-2,0))
FACES={"u":"up","d":"down","l":"left","r":"right"}

def fortree(p,target=None):
    mid=p.pos[0];f=p.routes.fields[mid];m=f.data["mechanisms"]
    other={tuple(a[0]) for a in p.state["actors"]}
    doors={tuple(w["at"]) for w in f.data['warps']}
    if target is None:lx,ly=next(n['at'] for n in f.data['npcs'] if 'Winona' in n['source_script'])
    def edges(s):
        x,y,state=s
        for k,(dx,dy) in DIRS.items():
            a,b=x+dx,y+dy
            if not (0<=a<f.w and 0<=b<f.h) or (a,b) in other or ((a,b) in doors and (a,b)!=target) or f.get('collision',a,b):continue
            after=state;blocked=False
            for i,(gx,gy,shape,_) in enumerate(m['gates']):
                rx,ry=a-gx+2,b-gy+2
                if not(0<=rx<4 and 0<=ry<4):continue
                info=m['rotation'][FACES[k]][ry*4+rx]
                if not info:continue
                turn,side,off=info;angle=state[i];arms=SHAPES[shape]
                if arms[(side-angle)%4]<=off:continue
                sweep=CW if turn==1 else CCW
                blocked=any(f.get('collision',gx+sweep[2*((angle+arm)%4)+r][0],gy+sweep[2*((angle+arm)%4)+r][1]) for arm,sz in enumerate(arms) for r in range(sz))
                if not blocked: after=(*state[:i],(angle+turn)%4,*state[i+1:])
                break
            if not blocked:yield k,(a,b,after)
    angles=tuple(int(p.state.get('gym_local',{}).get(str(i),g[3])) for i,g in enumerate(m['gates']))
    goals=(lambda n:n[:2]==target) if target else (lambda n:abs(n[0]-lx)+abs(n[1]-ly)==1)
    walk(p,search((*p.pos[1:],angles),goals,edges))

def mossdeep(p,target=None):
    mid=p.pos[0];f=p.routes.fields[mid];m=f.data["mechanisms"]
    raw={tuple(map(int,xy.split(','))):int(v) for xy,v in m['arrows'].items()}
    switches={tuple(map(int,xy.split(','))):v for xy,v in m['switches'].items()}
    offsets=((1,0),(0,1),(-1,0),(0,-1))
    start=tuple(tuple(a[0]) for a in p.state['actors'])
    warps={tuple(w['at']):w for w in f.data['warps']}
    if target is None:lx,ly=next(n['at'] for n in f.data['npcs'] if 'TateAndLiza' in n['source_script'])
    def edges(s):
        x,y,positions=s
        for k,(dx,dy) in DIRS.items():
            a,b=x+dx,y+dy
            if not (0<=a<f.w and 0<=b<f.h) or f.get('collision',a,b) or (a,b) in positions:continue
            w=warps.get((a,b))
            if w and w.get('trigger')=='step':a,b=w['to']['at']
            color=switches.get((a,b));updated=positions
            if color is not None:
                moved=[]
                for xy in positions:
                    t=raw.get(xy,-1)
                    if t>=0 and t>>3==color and (t%8)<4:
                        mx,my=offsets[t%8];xy=(xy[0]+mx,xy[1]+my)
                    moved.append(xy)
                updated=tuple(moved)
            yield k,(a,b,updated)
    goals=(lambda n:n[:2]==target) if target else (lambda n:abs(n[0]-lx)+abs(n[1]-ly)==1)
    walk(p,search((*p.pos[1:],start),goals,edges))

def ice_panel(points,start,end):
    def visit(here,unused):
        if not unused:return [] if here==end else None
        if here==end:return None
        # Any internal vertex with fewer than two reachable neighbours is a dead end.
        allowed=unused|{here}
        for x,y in unused-{end}:
            if sum((x+dx,y+dy) in allowed for dx,dy in DIRS.values())<2:return None
        for k,(dx,dy) in DIRS.items():
            nxt=(here[0]+dx,here[1]+dy)
            if nxt not in unused:continue
            tail=visit(nxt,unused-{nxt})
            if tail is not None:return [(k,nxt),*tail]
        return None
    result=visit(start,points-{start})
    if result is None:raise ValueError(('no thin ice solution',start,end))
    return result

def sootopolis(p):
    mid=p.pos[0];f=p.routes.fields[mid];ph=f.data['physics'];m=f.data["mechanisms"]
    for level,(bottom,top) in enumerate([(19,17),(14,12),(9,6)]):
        p.go({(mid,8,bottom+1)})
        points={(x,y) for y in range(top,bottom+1) for x,b in enumerate(ph['behavior'][y]) if b==0x26}
        walk(p,[('u',(8,bottom)),*ice_panel(points,(8,bottom),(8,top)),('u',(8,top-1)),('u',(8,top-2))])
        for x,y,_,_,c in m['stairs'][level*2:level*2+2]:
            f.grid['collision'][y*f.w+x]=c
            if 'slide' in f.grid:f.grid['slide'][y*f.w+x]=0
        p.routes.edges.cache_clear()
