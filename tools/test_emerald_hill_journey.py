"""Walk four timed Trainer Hill courses with a real player party, starting from a champion save."""
import argparse,json,os,tempfile,heapq,math
from pathlib import Path
from test_hoenn_journey import EmeraldPlayer,Routes,ROOT
from hoenn_field_route import click
from test_kanto_journey import league_heal

ENTRY='em_trainer_hill_entrance'
ROOF='em_trainer_hill_roof'
MOVES={v['id']:v for v in json.loads((ROOT/'content/moves.json').read_text())}
SPECIES={v['id']:v for v in json.loads((ROOT/'content/species.json').read_text())}
TYPES=json.loads((ROOT/'content/types.json').read_text())

def attack_score(attacker,moves,defender):
    best=0.0
    for move_id in moves:
        mv=MOVES[move_id]
        if mv['key'] in ('SELF_DESTRUCT','EXPLOSION','MISTY_EXPLOSION'):continue
        special=mv['category']=='special';typ=mv['type']
        score=mv['power']*min(100,mv['accuracy'] or 100)/100
        score*=attacker['base']['spa' if special else 'atk']/max(1,defender['base']['spd' if special else 'def'])
        score*=math.prod(TYPES[typ].get(t,1) for t in defender['types'])
        score*=1.5 if typ in attacker['types'] else 1
        if mv['key'] in ('SUCKER_PUNCH','FUTURE_SIGHT'):score*=.5
        best=max(best,score)
    return best

def choose_leads(p,foes):
    roster=[]
    for m in p.state['party']:
        if not m[3]:continue
        sp=SPECIES[int(m[1])];powers=[]
        for mon in foes:
            opposing=SPECIES[int(mon['species'])]
            hit=attack_score(sp,[int(i) for i,pp in zip(m[5],m[6]) if pp],opposing)
            risk=attack_score(opposing,mon['moves'],sp)
            powers.append((hit+1)/(risk+30)*(1.3 if sp['base']['spe']>opposing['base']['spe'] else 1))
        score=(sum(powers)/len(powers)+powers[0])*m[3]/m[4]
        roster.append((score,int(m[1])))
    if not roster:return
    roster.sort(reverse=True);targets=[v[1] for v in roster[:2]]
    def lead(sid):
        index=next(i for i,m in enumerate(p.state['party']) if int(m[1])==sid)
        if index:p.do('lead',slot=index)
    if len(targets)>1 and int(p.state['party'][1][1])!=targets[1]:
        lead(targets[1])
        p.do('lead',slot=1)
    lead(targets[0])

def earn_supplies(p,target):
    """Defeat previously unchallenged route trainers before returning to the timed course."""
    budget=lambda:p.state['money']+1500*p.state['bag'].get('活力碎片',0)+1200*p.state['bag'].get('厉害伤药',0)
    if budget()>=target:return
    if p.pos[0]==ENTRY and p.pos[2]<=6:
        p.go({(ENTRY,9,6)})
        if '退出' in p.state['buttons']:click(p,'退出')
        p.go({(ENTRY,9,7)})
    for route in (117,118,110,111,112,116,119,120,121,123,104,109):
        mid='hoenn_'+str(route)
        p.enter(mid)
        candidates=[n for n in p.routes.fields[mid].data['npcs'] if n.get('source_trainer')]
        while candidates:
            if budget()>=target:return
            candidates.sort(key=lambda n:abs(n['at'][0]-p.pos[1])+abs(n['at'][1]-p.pos[2]))
            person=candidates.pop(0)
            if 'h_trainer_'+person['source_trainer'] in p.state['flags']:continue
            if not any(tuple(a[0])==tuple(person['at']) for a in p.state['actors']):continue
            try:p.use_at(mid,person['at'])
            except (AssertionError,ValueError,RuntimeError) as error:
                if p.process.poll() is not None:raise
                print('DETOUR',mid,person['at'],str(error)[:100],flush=True)
        print('PURSE',mid,p.state['money'],flush=True)
    if budget()<target:print('PURSE available',budget(),flush=True)

def cross(p,mode,floor):
    """Minimize avoidable sightings while following native ledges and forced arrows."""
    mid=p.pos[0]; f=p.routes.fields[mid]; course=f.data['mechanisms']['hill'][mode]
    dirs={'u':(0,-1,1),'d':(0,1,2),'r':(1,0,4),'l':(-1,0,8)}
    faces={'up':'u','down':'d','left':'l','right':'r'}
    costs_per_trainer=[900 if actor['name']=='THEODORE' else 240 for actor in course['actors']]
    seen={}; occupied={tuple(n['at']) for n in course['actors']}
    for i,n in enumerate(course['actors']):
        x,y=n['at'];dx,dy,_=dirs[faces[n['facing']]]
        for _ in range(n['sight']):
            x+=dx;y+=dy
            if not (0<=x<f.w and 0<=y<f.h) or f.get('collision',x,y):break
            seen[x,y]=seen.get((x,y),0) | 1<<i
    def step(x,y,d):
        dx,dy,b=dirs[d];a=x+dx;c=y+dy
        if not (0<=a<f.w and 0<=c<f.h):return
        if f.get('ledge',a,c)&b:a+=dx;c+=dy
        if 0<=a<f.w and 0<=c<f.h and (a,c) not in occupied and not f.get('collision',a,c):return a,c
    start=(*p.pos[1:],0); q=[(0,start)]; costs={start:0}; back={}
    while q:
        cost,state=heapq.heappop(q); x,y,mask=state
        if costs[state]!=cost:continue
        if (x,y)==(12,1):break
        for i,n in enumerate(course['actors']):
            ax,ay=n['at']
            if mask & (1<<i):continue
            for k,(dx,dy,_) in dirs.items():
                if (x+dx,y+dy)!=(ax,ay):continue
                node=(x,y,mask|1<<i);value=cost+costs_per_trainer[i]
                if value<costs.get(node,10**8):
                    costs[node]=value;back[node]=(state,'talk'+k);heapq.heappush(q,(value,node))
        for d in dirs:
            at=step(x,y,d); force=d; walked=set(); next_mask=mask
            while at and (at,force) not in walked:
                walked.add((at,force));next_mask |= seen.get(at,0)
                slide=f.get('slide',*at)
                if not slide:break
                force=force if slide==255 else {1:'u',2:'d',4:'r',8:'l'}[slide]
                following=step(*at,force)
                if not following:break
                at=following
            if not at or at==(2,1):continue
            node=(*at,next_mask)
            value=cost+1+sum(costs_per_trainer[i]+10 for i in range(len(costs_per_trainer)) if (next_mask^mask)&(1<<i))+(500 if next_mask^mask==3 else 0)
            if value<costs.get(node,10**8):
                costs[node]=value;back[node]=(state,d);heapq.heappush(q,(value,node))
    else:raise ValueError(('unreachable original hill exit',mode,floor,p.pos))
    journey=[]
    while state!=start:
        prev,d=back[state];journey.append((d,state[:2],state[2]^prev[2]));state=prev
    for d,at,new in reversed(journey):
        if new:
            foes=[mon for i,n in enumerate(course['actors']) if new&(1<<i) for mon in n['team']]
            league_heal(p)
            choose_leads(p,foes)
        if d.startswith('talk'):
            p.do('face',dir=d[-1]);league_heal(p)
            assert p.pos[0]==mid,('lost hill trainer',mode,floor,p.pos)
            continue
        dest=(mid,*at) if at!=(12,1) else ((ROOF,9,5) if floor==4 else (f'em_trainer_hill_{floor+1}f',2,1))
        p.do('walk',legs=[[d,list(dest)]])
        for _ in range(32):
            if p.pos==dest or p.pos[0]!=mid:break
            slide=f.get('slide',*p.pos[1:])
            if not slide:
                if mid!=dest[0]:break
                remaining=(dest[1]-p.pos[1],dest[2]-p.pos[2])
                if sum(abs(v) for v in remaining)!=1:break
                d=next(k for k,v in dirs.items() if v[:2]==remaining)
            elif slide!=255:d={1:'u',2:'d',4:'r',8:'l'}[slide]
            before=p.pos
            p.do('walk',legs=[[d,list(dest)]])
            if p.pos==before:break
        if p.pos!=dest:raise AssertionError(('hill walk',mode,floor,d,dest,p.pos,p.state['dialog']))
        if any(m[3]<m[4]*.8 for m in p.state['party']):league_heal(p)

def run():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--pack',type=Path)
    parser.add_argument('--entry-save',required=True,type=Path)
    parser.add_argument('--result-save',type=Path)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        save=Path(tmp)/'save.json';save.write_bytes(args.entry_save.read_bytes())
        launch=[args.godot,'--headless','--fixed-fps','60','--path',str(ROOT)]
        if args.pack:launch+=['--main-pack',str(args.pack)]
        p=EmeraldPlayer(Routes(('hoenn',)),launch,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp),tmp)
        try:
            if p.pos[0]==ROOF:
                p.enter('em_trainer_hill_elevator')
                p.use_at('em_trainer_hill_elevator',(0,6))
                click(p,'一楼')
            for mode,label in zip(('Normal','Variety','Unique','Expert'),('普通','变化','独特','专家')):
                if mode in json.loads(save.read_text())['flags'].get('h_hill_times',{}):continue
                earn_supplies(p,{'Normal':33000,'Variety':16000,'Unique':17500,'Expert':43500}[mode])
                p.enter(ENTRY)
                # Place the Water and Dark attackers in the two starting lanes.
                for sid in (262,260):
                    slot=next((i for i,m in enumerate(p.state['party']) if m[1]==sid),None)
                    if slot is not None:p.do('lead',slot=slot)
                if p.state['money']>1200:
                    p.use_at(ENTRY,(14,9))
                    for name,target,price in [('活力碎片',13 if mode=='Expert' else 10,1500),('厉害伤药',20,1200)]:
                        amount=min(target-int(p.state['bag'].get(name,0)),int(p.state['money'])//price)
                        if amount>0:p.do('shop',item=name,amount=amount)
                    p.do('back')
                    print('SUPPLIES',p.state['bag'].get('活力碎片',0),p.state['bag'].get('厉害伤药',0),flush=True)
                # Talking to the clerk is also possible from behind the counter.
                p.use_at(ENTRY,(11,6))
                click(p,label)
                for floor in range(1,5):
                    mid=f'em_trainer_hill_{floor}f'
                    field=p.routes.fields[mid]
                    course=field.data['mechanisms']['hill'][mode]
                    for key in ('ledge','slide'):
                        field.grid[key]=[int(v) for line in course[key] for v in line]
                    for x,y,_,_,solid in course['tiles']:
                        index=y*field.w+x
                        field.grid['collision'][index]=solid
                        field.grid['elevation'][index]=3
                p.routes.edges.cache_clear()
                for floor in range(1,5):
                    p.enter(f'em_trainer_hill_{floor}f')
                    league_heal(p)
                    cross(p,mode,floor)
                    print('HILL',mode,floor,p.pos,[(m[0],m[3],m[4]) for m in p.state['party']],flush=True)
                p.use_at(ROOF,(12,7))
                p.do('save')
                flags=json.loads(save.read_text())['flags']
                assert mode in flags.get('h_hill_times',{}), (mode,p.pos,p.state['dialog'])
                print('ROOF',mode,flags['h_hill_times'][mode],flush=True)
                if args.result_save:args.result_save.write_bytes(save.read_bytes())
                p.enter('em_trainer_hill_elevator')
                p.use_at('em_trainer_hill_elevator',(0,6))
                click(p,'一楼')
        finally:p.finish()
if __name__=='__main__':run()
