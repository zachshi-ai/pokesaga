"""Compile Crystal's contact locations, appointment times and numbered rematch teams."""
from pathlib import Path
import argparse
import json
import re
from gen_johto import camel_to_id
from gen_johto_battles import sid, mid

ROOT=Path(__file__).resolve().parents[1]
DAYS='SUNDAY MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY'.split()

def program(text):
    ops=[];labels={};scope=""
    for line in text.splitlines():
        raw=line.split(';')[0].strip()
        if not raw:continue
        if not line[0].isspace():
            name=raw.rstrip(':')
            if not name.startswith('.'):scope=name
            labels[scope+name if name.startswith('.') else name]=len(ops)
            continue
        code,_,arguments=raw.partition(' ')
        args=[x.strip() for x in arguments.split(',')]
        if code in ("getlandmarkname","gettrainername","gettrainerclassname","getstring","getmonname","special","setval","swarm"):continue
        if code=="farscall":
            if args[0].startswith("PhoneScript_Random"):ops.append(["random",int(args[0].split('Random')[1])])
            continue
        if code in ("iftrue","iffalse","ifequal","ifnotequal","sjump"):
            if args[-1].startswith('.'):args[-1]=scope+args[-1]
        ops.append([code]+args)
    for op in ops:
        if op[0] in ("iftrue","iffalse","ifequal","ifnotequal","sjump"):op[-1]=labels[op[-1]]
    return {"in":next(v for k,v in labels.items() if k.endswith("PhoneCallerScript")),"out":next(v for k,v in labels.items() if k.endswith("PhoneCalleeScript")),"ops":ops}

def build(source):
    names={}
    for line in (source/'constants/trainer_constants.asm').read_text().splitlines():
        if match:=re.match(r'\s*trainerclass (\w+)',line):group=match[1];names[group]=[]
        elif match:=re.match(r'\s*const (\w+)(?:\s|$)',line):
            if 'group' in locals():names[group].append(match[1])
    parties={}
    raw=(source/'data/trainers/parties.asm').read_text()
    for group,num,kind,mons in re.findall(r'; (\w+) \((\d+)\)\s*\n\s*db "[^"]+@", (TRAINERTYPE_\w+)\s*\n(.*?)\n\s*db -1',raw,re.S):
        if group not in names or int(num)>len(names[group]):continue
        team=[]
        for ln in mons.splitlines():
            if not (m:=re.match(r'\s*db\s+(\d+),\s*(\w+)([^;]*)',ln)):continue
            row={'species':sid(m[2]),'level':int(m[1])}
            fields=[x.strip() for x in m[3].strip(' ,').split(',') if x.strip()]
            if 'ITEM' in kind and fields:
                item=fields.pop(0)
                if item!='NO_ITEM':row['held']=item
            if 'MOVES' in kind and fields:row['moves']=[mid(move) for move in fields if mid(move)]
            team.append(row)
        parties[(group,names[group][int(num)-1])]=team
    out={}
    contacts=(source/'data/phone/phone_contacts.asm').read_text()
    for group,trainer,target in re.findall(r'^\s*phone (?!TRAINER_NONE)(\w+),\s*(\w+),\s*(\w+),',contacts,re.M):
        key=trainer.rstrip('12345').lower()
        phone=(source/'engine/phone/scripts'/(key+'.asm')).read_text()
        neighborhood=next(p for p in (source/'maps').glob('*.asm') if re.search('askforphonenumber PHONE_.*_'+key.upper()+r'\b',p.read_text()))
        m='johto_'+camel_to_id(neighborhood.stem)
        lines=neighborhood.read_text()
        labels=list(re.finditer(r'^(\w+):',lines,re.M))
        script=next(lines[lab.start():labels[i+1].start()] for i,lab in enumerate(labels[:-1]) if re.search('askforphonenumber PHONE_.*_'+key.upper()+r'\b',lines[lab.start():labels[i+1].start()]))
        mapdata=json.loads((ROOT/'content/regions/johto/maps'/(m+'.json')).read_text())
        orig=next((n for n in mapdata['npcs'] if key==n['name'].lower().split()[-1]),None)
        location=orig['at'] if orig else None
        title=orig['name'] if orig else key.title()
        day=re.search(r'readvar VAR_WEEKDAY\s+ifnotequal (\w+)',phone)
        time=re.search(r'checktime (MORN|DAY|NITE)',phone)
        calls=[]
        for fclass,num in re.findall(r'loadtrainer (\w+), (\w+)',script):
            team=parties[(fclass,num)]
            if team:calls.append(team)
        gates={int(n):flag for n,flag in re.findall(r'\.Fight(\d+):\s*(?:checkevent|checkflag) (\w+)',script)}
        gifts=list(dict.fromkeys(re.findall(r'(?:verbosegiveitem|giveitem) (\w+)',script)))
        needed=re.search(r'checkpoke (\w+)',script)
        out[key]={'name':title,'map':m,'at':location,'weekday':DAYS.index(day[1]) if day else -1,'period':time[1] if time else '',
                  'rematches':calls,'gates':gates,'gifts':gifts,'incoming_gift':bool(re.search('setflag ENGINE_'+key.upper()+'_HAS_',phone)),
                  'show':sid(needed[1]) if needed else 0, 'program':program(phone)}
        if orig is None:print('unbound',key,m)
    return out

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path)
    data=build(p.parse_args().source)
    (ROOT/'content/regions/johto/phone.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
