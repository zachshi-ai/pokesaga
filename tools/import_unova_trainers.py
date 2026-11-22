#!/usr/bin/env python3
"""Compile ordinary field trainers from their map scripts and normal-mode parties in Black and Black 2."""
import argparse
import json
import struct
from pathlib import Path

import build_unova_campaign as records
from unova_source import UnovaSource, archive

CLASSES = dict(line.split("|") for line in """Ace Trainer|精英训练家
Artist|艺术家
Backers|球迷组合
Backpacker|背包客
Baker|面包师傅
Battle Girl|对战少女
Beauty|大姐姐
Biker|暴走族
Black Belt|空手道王
Clerk ♂|上班族
Clerk ♀|上班族
Cyclist|自行车手
Dancer|舞者
Depot Agent|车站员
Doctor|医生
Fisherman|垂钓者
Gentleman|绅士
Guitarist|吉他手
Harlequin|小丑
Hiker|登山男
Hooligans|不良组合
Hoopster|篮球选手
Infielder|棒球选手
Janitor|清洁工
Lady|大小姐
Lass|迷你裙
Linebacker|美式足球选手
Maid|女仆
Motorcyclist|摩托车手
Musician|音乐家
Nurse|护士训练家
Nursery Aide|幼儿园老师
Parasol Lady|阳伞姐姐
Pilot|飞行员
Pokéfan|宝可梦发烧友
Pokémon Breeder|饲育家
Pokémon Ranger|宝可梦巡护员
Policeman|警察
Preschooler|幼儿园儿童
Psychic|超能力者
Rich Boy|富家少爷
Roughneck|光头男
School Kid|补习班学生
Scientist|研究员
Smasher|网球选手
Socialite|贵妇人
Striker|足球选手
Swimmer ♂|泳裤小伙子
Swimmer ♀|比基尼姐姐
Team Plasma|等离子队
Twins|双胞胎
Veteran|资深训练家
Waiter|服务生
Waitress|女服务生
Worker|工人
Youngster|短裤小子""".splitlines())
VISUALS={"Lass":"lass","Youngster":"youngster","Parasol Lady":"woman","Black Belt":"blackbelt","Hiker":"hiker",
         "Fisherman":"fisherman","Nurse":"nurse","Doctor":"scientist","Scientist":"scientist","Battle Girl":"battle_girl",
         "Beauty":"beauty","Pokémon Breeder":"breeder","Biker":"fr_biker","Lady":"woman","Twins":"lass",
         "Clerk ♂":"clerk","Clerk ♀":"woman","Psychic":"psychic_m","Veteran":"expert_m","Ace Trainer":"cooltrainer_m",
         "Preschooler":"youngster","School Kid":"school_kid_m","Policeman":"fr_policeman"}
FORMS={"Wormadam (Trash)":"WORMADAM_TRASH","Wormadam (Sandy)":"WORMADAM_SANDY","Rotom (Wash)":"ROTOM_WASH","Basculin (Blue Striped)":"BASCULIN_BLUE_STRIPED"}

def train(row):
    party=[]
    for m in row["party"]:
        unit=records.mon(m["species"],m["level"],m["moves"],m["held_item"],m["ability"])
        if m["species"] in FORMS: unit["form"]=FORMS[m["species"]]
        party.append(unit)
    kind=row['trainer_class']
    gfx=VISUALS.get(kind,"man")
    if not (records.ROOT/'assets/npc'/(gfx+'.png')).exists():gfx='man'
    return {"name":CLASSES.get(kind,kind)+" "+row['name'],"class":kind,"gfx":gfx,"team":party,
            "battle_type":row['battle_type'],"prize":4*int(row['money'])*party[-1]['level']}

# These Trainers run short story scripts instead of the global 3000-series scripts.
# Local IDs, opponent records and the two musician roles come from their field scripts.
SCRIPTED = {('bw',18):{0:88,2:87}, ('b2',489):{1:171,2:172}, ('b2',502):{1:178,2:179}, ('b2',63):{2:207,3:208,0:209}}

def original_rows(bw, zones, period):
    if period=='bw':
        events=archive(bw,'1/2/5')
    for z in zones:
        for row in z['npcs']:
            tid=SCRIPTED.get((period,z['i']),{}).get(row['id'])
            if tid:yield z['i'],row['id'],3000+tid,0,'down'
        if period=='b2':
            for row in z['npcs']:
                if 'grid' in row and str(row['type']).startswith('ACTOR_EVENT_TYPE_TRAINER'):
                    yield z['i'],row['id'],row['script'],row['params'][0],row['direction'].removeprefix('DIR_').lower()
        else:
            raw=events[z['bank']]
            if len(raw)<8: continue
            bg,npc=raw[4:6]
            for i in range(npc):
                r=struct.unpack_from('<12HI8s',raw,8+20*bg+36*i)
                if r[3] and not r[12]:
                    yield z['i'],r[0],r[5],r[7],('up','down','left','right')[r[6]%4]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('black','black2','trainer_data'):parser.add_argument(name,type=Path)
    args=parser.parse_args()
    for key,filename in [('species_ids','species'),('ability_ids','abilities'),('move_ids','moves')]:
        setattr(records,key,{records.norm(r['key']):r['id'] for r in records.read(filename+'.json')})
    records.species_ids.update(burmy=412,wormadam=413,mothim=414,cherrim=421,gastrodon=423,castform=351,basculin=550,darmanitan=555,deerling=585,sawsbuck=586,tornadus=641,thundurus=642)
    result={}
    for period,filename in [('bw','black_white'),('b2','black2_white2')]:
        source=UnovaSource(args.black,args.black2,period)
        rosters=records.trainer_file(args.trainer_data,period,filename)
        people={}
        locations={}
        for zone,local,script,sight,face in original_rows(args.black,source.zones,period):
            if not (3000<=script<4000 or 5000<=script<6000): continue
            tid=str(script%1000)
            if not rosters.get(tid,{}).get('party'): continue
            if tid not in people: people[tid]=train(rosters[tid])
            locations.setdefault(str(zone),{})[str(local)]=[int(tid),sight,face]
        result[period]=dict(trainers=people,locations=locations)
        print(period,len(people),'parties;',sum(map(len,locations.values())),'field actors')
    (records.ROOT/'content/unova_trainers.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')

if __name__=='__main__':main()
