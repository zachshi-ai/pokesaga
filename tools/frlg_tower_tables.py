"""Compile the FireRed tower's per-floor challenge roster and original party selection."""
import re


def compile_tower(source,species,moves):
    code=(source/'src/trainer_tower_sets.c').read_text()
    engine=(source/'src/trainer_tower.c').read_text()
    solo_gfx={cls:[gfx] for gfx,cls in re.findall(r'\{OBJ_EVENT_GFX_(\w+),\s*FACILITY_CLASS_(\w+),',engine)}
    pair_gfx={cls:[first,second] for first,second,cls in re.findall(r'\{OBJ_EVENT_GFX_(\w+),\s*OBJ_EVENT_GFX_(\w+),\s*FACILITY_CLASS_(\w+),',engine)}
    picked={}
    for k,table in [('single','SingleBattle'),('double','DoubleBattle'),('knockout','Knockout')]:
        block=re.search('static const u8 s'+table+r'ChallengeMonIdxs.*?= \{(.*?)\};',engine,re.S)[1]
        picked[k]=[[int(n) for n in re.findall(r'\d+',r)] for r in re.findall(r'\{(.*?)\}',block)]
    sets={}
    for name,body in re.findall(r'static const struct TrainerTowerFloor sTrainerTowerFloor_(\w+) = \{(.*?)\n\};',code,re.S):
        trainers=[]
        for section in re.split(r'\.name = _\("',body)[1:]:
            label=section.split('"')[0]
            if not label:continue
            mons=[]
            for mon in re.finditer(r'\.species = SPECIES_(\w+),\s*\.heldItem = ITEM_(\w+),\s*\.moves = \{([^}]+)\}',section):
                mons.append({'species':species[mon[1]],'held':mon[2] if mon[2]!='NONE' else '',
                             'moves':[moves[s] for s in re.findall(r'MOVE_(\w+)',mon[3]) if s!='NONE']})
            if mons:
                cls=re.search(r'\.facilityClass = FACILITY_CLASS_(\w+)',section)[1]
                trainers.append((label,mons,cls))
        sets[name]=(re.search(r'\.challengeType = CHALLENGE_TYPE_(\w+)',body)[1].lower(),trainers)
    links=code.split('gTrainerTowerFloors')[1]
    catalog={}
    for mode,refs in zip(('single','double','knockout','mixed'),[r for r in re.findall(r'\{([^{}]+)\}',links,re.S) if '&' in r]):
        path=[]
        for i,n in enumerate(re.findall(r'&sTrainerTowerFloor_(\w+)',refs)):
            kind,trainers=sets[n];choices=picked[kind][i]
            if kind=='single':
                fights=[{'name':trainers[0][0],'team':[trainers[0][1][j] for j in choices]}]
            elif kind=='double':
                fights=[{'name':' / '.join(q[0] for q in trainers),'team':[trainers[t][1][j] for t,j in enumerate(choices)]}]
            else:
                fights=[{'name':trainers[t][0],'team':[trainers[t][1][j]]} for t,j in enumerate(choices)]
            art=pair_gfx.get(trainers[0][2],['YOUNGSTER','LASS']) if kind=='double' else [solo_gfx.get(tr[2],['YOUNGSTER'])[0] for tr in trainers]
            path.append({'kind':kind,'fights':fights,'actors':[[tr[0],art[j].lower()] for j,tr in enumerate(trainers)]})
        assert len(path)==8
        catalog[mode]=path
    assert len(catalog)==4
    return catalog
