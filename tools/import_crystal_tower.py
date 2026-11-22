"""Compile the ten original Crystal Battle Tower pools, fixed stats/items/PP and trainer names."""
import argparse
import json
from pathlib import Path
import re
from gen_johto_battles import sid, mid

ROOT=Path(__file__).resolve().parents[1]

def build(source):
    folder=source/'data/battle_tower'
    trainers=re.findall(r'^\s*bt_trainer (\w+),\s*"([^"]+)"',(folder/'classes.asm').read_text(),re.M)
    groups={}
    for block in re.split(r'\bdname "[^"]+", MON_NAME_LENGTH',(folder/'parties.asm').read_text()):
        m=re.search(r'^\s*db (\w+)\n\s*db (\w+)\n\s*db ([A-Z_, 0-9]+)\n',block,re.M)
        if not m:continue
        level=int(re.search(r'db (\d+) ; Level',block)[1])
        species=sid(m[1])
        moves=[mid(v.strip()) for v in m[3].split(',')]
        pp=[int(v.strip()) for v in re.search(r'db ([0-9, ]+) ; PP',block)[1].split(',')]
        stats=[int(v) for v in re.findall(r'bigdw (\d+) ; (?:Max HP|Atk|Def|Spd|SAtk|SDef)\b',block)]
        assert len(stats)==6 and any(moves) and species and len(pp)==4,(m[1],moves,stats)
        groups.setdefault(level,[]).append(dict(species=species,level=level,moves=[v for v in moves if v],held=m[2],stats=stats,pp=pp[:len([v for v in moves if v])]))
    assert len(trainers)==70 and len(groups)==10 and all(len(t)==21 for t in groups.values()),(len(trainers),[(k,len(v)) for k,v in groups.items()])
    return {'trainers':trainers,'groups':groups}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path)
    (ROOT/'content/regions/johto/tower.json').write_text(json.dumps(build(p.parse_args().source),ensure_ascii=False,separators=(',',':'))+'\n')
