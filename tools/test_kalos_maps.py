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

# Prevent a rebuild from silently shipping the old scene projections or missing a
# story phase. Every furniture base and every occupied store/house footprint is
# checked independently of the renderer, as are the two interregional road gates.
from PIL import Image
from kalos_field_fixtures import furniture_sprite
scenes={m['kalos_image'] for m in maps.values()}
assert not any(name.startswith('xy_') for name in scenes)
phases=json.loads((ROOT/'content/kalos_geosenge.json').read_text())
phase_names={phase['art'] for phase in phases.values()}
assert len(phase_names)==3 and phase_names<=scenes|{'field_23'}
objects=0
for mid,m in maps.items():
    image_path=ROOT/'assets/kalos/maps'/(m['kalos_image']+'.png')
    with Image.open(image_path) as pic:
        w,h=m['size'];assert pic.width*h==pic.height*w,mid
    gates={tuple(w['at']) for w in m['warps']}
    occupied=gates|set(entries[mid])|{tuple(m['spawn'])}|set(map(tuple,m['kalos_anchors'].values()))
    feet=m.get('kalos_furniture_feet',[])
    for x,y in feet:
        assert m['physics']['collision'][y][x] and (x,y) not in occupied,(mid,x,y)
    for kind,x,y,scale in m.get('kalos_furnishings',[]):
        assert furniture_sprite(kind).getbbox() and m['physics']['collision'][y][x],(mid,kind,x,y)
        objects+=1
assert objects>0
for art in phase_names:assert (ROOT/'assets/kalos/maps'/(art+'.png')).is_file()
for mid,kinds in {
    'kalos_factory':{'kalos_conveyor','kalos_packer'}, 'kalos_ambrette_aquarium':{'kalos_tanks'},
    'kalos_sycamore_lab':{'kalos_samples','kalos_workbench'}, 'kalos_e4_malva':{'kalos_brazier'},
    'kalos_e4_siebold':{'kalos_sluice'},'kalos_e4_wikstrom':{'kalos_swordrack'},
    'kalos_e4_drasna':{'kalos_dragonpillar'},'kalos_champion_room':{'kalos_rosette'}}.items():
    assert kinds<={f[0] for f in maps[mid].get('kalos_furnishings',[])},mid
cross=json.loads((ROOT/'content/regions/kalos/maps/kalos_pass_paldea_n3.json').read_text())
assert (ROOT/cross['hoenn_art']['scene'][0].removeprefix('res://')).is_file()
walk=~np.isin(cross['tiles'],[1,2,6,7]);x,y=cross['npcs'][0]['at'];walk[y,x]=False
labels,_=ndimage.label(walk);sx,sy=cross['spawn'];land=labels[sy,sx];assert land>0
for w in cross['warps']:
    x,y=w['at'];assert labels[y,x]==land,(cross['name'],w)
print('KALOS ART PASS',len(maps)+1,'fields, three Geosenge phases,',objects,'pieces of fitted furniture')
