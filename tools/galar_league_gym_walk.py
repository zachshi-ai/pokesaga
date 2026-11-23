"""Play the seven later Gym Challenges through floor movement, conversations and battle choices."""
from collections import deque
from campaign_route import VECTORS

def _paths(p,avoid=()):
    mid,x,y=p.pos;field=p.routes.fields[mid]
    blocked={tuple(a[0]) for a in p.state["actors"]}|set(avoid)
    start=(x,y);paths={start:[]};q=deque([start])
    while q:
        pos=q.popleft()
        for k,(dx,dy,*_) in VECTORS.items():
            dest=pos[0]+dx,pos[1]+dy
            if dest in paths or dest in blocked or dest in field.doors:continue
            if not (0<=dest[0]<field.w and 0<=dest[1]<field.h) or field.get("collision",*dest):continue
            paths[dest]=paths[pos]+[[k,[mid,*dest]]];q.append(dest)
    return paths

def _go(p,targets,avoid=()):
    paths=_paths(p,avoid)
    tile=next((pos for pos in paths if pos in targets),None)
    if tile is None:raise AssertionError(("unreachable gym station",p.pos,targets,p.state["actors"]))
    if paths[tile]:p.do("walk",legs=paths[tile])
    assert p.pos[1:]==tile,("field puzzle obstructed",tile,p.pos,p.state["dialog"])
    return tile

def _touch(p,role,avoid=(),stand=None):
    xy=next(row[0] for row in p.state["actors"] if row[1]==role)
    goals={(xy[0]-dx,xy[1]-dy):k for k,(dx,dy,*_) in VECTORS.items()}
    if stand is not None:goals={stand:goals[stand]}
    at=_go(p,goals,avoid)
    p.do("face",dir=goals[at])

def _exit_north(p,num,avoid=()):
    mid=p.pos[0];f=p.routes.fields[mid];door=next(w for w in f.data['warps'] if w['to']['map']==f'galar_gym_{num}_pitch')
    x,y=door['at'];_go(p,{(x,y+1)},avoid);p.do('walk',legs=[['u',[door['to']['map'],*door['to']['at']]]])
    assert p.pos[0]==door['to']['map'],(num,p.pos,p.state['dialog'])

def challenge(p,number):
    n=int(number);mission=f'galar_gym_{n}_mission';pitch=f'galar_gym_{n}_pitch';f=p.routes.fields[mission];m=f.data['galar_facility']
    assert f'g_gym_{n}_ready' in p.state['flags'] and f'g_badge_{n-1}' in p.state['flags'],(n,p.pos)
    p.enter(mission)
    avoid=set()
    def train(i):
        if f'g_gym_{n}_trainer_{i}' in p.state['flags']:return
        _touch(p,'g_fac_trainer_'+str(i),avoid)
        assert f'g_gym_{n}_trainer_{i}' in p.state['flags'],(n,i,p.pos,p.state['dialog'],p.state['fights'])
    if n==2:
        for i in range(4):
            if i<3:train(i)
            _touch(p,'g_fac_valve_'+str(i))
    elif n==3:
        ri=0
        for turn in range(12):
            if int(p.saved()['flags'].get('g_gym_3_field',{}).get('points',0))>=5:break
            row=next(a for a in p.state['actors'] if a[1].startswith('g_fac_wild_'))
            if turn==0 and p.state['bag'].get('精灵球',0):
                p.do('throw_with',item='精灵球',species=0)
            else:p.do('mode',value='train')
            _touch(p,row[1]);ri+=1
        p.do('mode',value='travel')
        assert p.saved()['flags']['g_gym_3_field']['points']>=5,(p.pos,ri)
    elif n==4:
        for i,cup in enumerate(m['cups']):
            x,y=cup['at'];goal=int(cup['goal']);role='g_fac_cup_'+str(i)
            value=int(p.saved()['flags'].get('g_gym_4_field',{}).get('cup_'+str(i),0))
            for _ in range((goal-value)%4):
                _touch(p,role,stand=(x-1,y))
            _touch(p,role,stand=(x,y+1))
            for _ in range(120):
                if not p.state['panels']:break
                p.do('save')
            assert p.pos[1:]==tuple(cup['landing']),(n,i,p.pos)
            train(i)
    elif n==6:
        version=p.saved()['flags']['g_version']
        avoid={tuple(xy) for xy in m['traps_shield' if version=='shield' else 'traps']}
        # Trigger a real unmarked pit, return to the official checkpoint, then use the safe passages.
        paths=_paths(p);trap=next(pos for pos in paths if pos in avoid)
        p.do('walk',legs=paths[trap])
        assert p.pos[1:]==tuple(m['checkpoints'][0]) and p.saved()['flags']['g_gym_6_field']['revealed']
        for i in range(len(m['trainers'])):train(i)
    else:
        for i in range(len(m['trainers'])):train(i)
    _exit_north(p,n,avoid)
    _touch(p,'g_fac_leader')
    assert f'g_badge_{n}' in p.state['flags'],(n,p.pos,p.state['dialog'],p.state['fights'])
    print("GALAR GYM WON",n,p.pos,p.state["steps"],p.state["turns"],flush=True)
