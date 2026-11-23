#!/usr/bin/env python3
"""Audit the signed-in map data: players must be able to leave every origin after a real step warp."""
from collections import defaultdict
import json
from pathlib import Path
import numpy as np
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[1]
maps={m['id']:m for file in (ROOT/'content/regions/kalos/maps').glob('*.json')
      for m in [json.loads(file.read_text())] if m.get('kalos_native')}
entries=defaultdict(set)
checks=0
for m in maps.values():
    for warp in m['warps']:
        dest=warp['to']
        if dest['map'] in maps:entries[dest['map']].add(tuple(dest['at']))
seen={'kalos_home_2f'};pending=list(seen)
while pending:
    for warp in maps[pending.pop()]['warps']:
        dest=warp['to']['map']
        if dest in maps and dest not in seen:seen.add(dest);pending.append(dest)
assert seen==maps.keys(),sorted(maps.keys()-seen)
fail=[]
for k,m in maps.items():
    size=m['size'];phys=m['physics'];walk=~np.array(phys['collision'],bool)
    if 'water'in phys:walk&=~np.array(phys['water'],bool)
    doors=[]
    for warp in m['warps']:
        x,y=warp['at'];doors.append((x,y))
        if warp['trigger']=='step':walk[y,x]=False
    for npc in m['npcs']:
        x,y=npc['at'];walk[y,x]=False
    labels,num=ndimage.label(walk)
    x,y=m['spawn'];area=labels[y,x];assert area>0,(k,m['spawn'])
    accessible={area}
    portals=[w for w in m['warps'] if w['to']['map']==k and not w['to'].get('kalos_requires')]
    for iteration in range(len(portals)+1):
        old=len(accessible)
        for w in portals:
            x,y=w['at']
            if any(labels[b,a] in accessible for a,b in ((x+1,y),(x-1,y),(x,y+1),(x,y-1))):
                xx,yy=w['to']['at'];accessible.add(labels[yy,xx])
        if len(accessible)==old:break
    assert 0 not in accessible,(k,'self warp into solid tile')
    for x,y in entries[k]:
        if labels[y,x] not in accessible:fail.append((k,'arrival',[x,y]))
        checks+=1
    for x,y in doors+[tuple(p) for p in m['kalos_anchors'].values()]:
        if not any(0<=xx<size[0] and 0<=yy<size[1] and labels[yy,xx] in accessible for xx,yy in ((x+1,y),(x-1,y),(x,y+1),(x,y-1))):
            fail.append((k,'no approach',[x,y]))
        checks+=1
    img=m['hoenn_art']['scene'][0].replace('res://','')
    assert (ROOT/img).is_file(),img
assert not fail,fail[:20]
print('KALOS MAPS PASS',len(maps),'reachable rooms;',checks,'doorway, arrival and actor approaches.')
