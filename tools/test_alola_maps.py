#!/usr/bin/env python3
"""Verify every physical threshold, landing, field item and dialogue position against actual collision."""
from collections import defaultdict
from pathlib import Path
import json
import numpy as np
from scipy import ndimage
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_bytes())
def check_sandy_cave(m,access):
    assert set(access['alola_sandy_cave']['versions'])=={'ultra_sun','ultra_moon'}
    assert [w['to']['map'] for w in m['warps']]==['alola_big_wave_beach']
    tiles=m['physics'];start=m['spawn']
    treasure={o['alola_pickup']['key']:o['at'] for o in m['objects'] if o.get('alola_pickup')}
    assert set(treasure)=={'TM24','LIGHT_CLAY','BIG_PEARL'}
    obstacles={o['kind']:o['at'] for o in m['objects'] if o['kind'] in {'rock','boulder'}}
    rock=obstacles['boulder'];river=obstacles['rock']
    assert tiles['hole'][rock[1]-1][rock[0]] and tiles['water'][river[1]][river[0]]
    for modes,available in [
        ((),set()),
        (('surf',),{'BIG_PEARL'}),
        (('surf','sharpedo'),{'BIG_PEARL','LIGHT_CLAY'}),
        (('surf','machamp'),{'BIG_PEARL','TM24'}),
        (('surf','machamp','sharpedo'),set(treasure)),
    ]:
        blocked=np.array(tiles['collision'],bool)
        if 'surf' not in modes:blocked|=np.asarray(tiles['water'],bool)
        if 'machamp' not in modes:
            blocked|=np.asarray(tiles['hole'],bool);blocked[rock[1],rock[0]]=True
        if 'sharpedo' not in modes:blocked[river[1],river[0]]=True
        labels,_=ndimage.label(~blocked);connected=labels==labels[start[1],start[0]]
        got={key for key,(x,y) in treasure.items() if connected[y,x] or any(connected[y+dy,x+dx] for dx,dy in [(0,1),(0,-1),(1,0),(-1,0)])}
        assert got==available,(modes,got,available)

def main():
    maps={m['id']:m for p in (ROOT/'content/regions/alola/maps').glob('*.json') for m in [read(p)] if m.get('alola_native')}
    first='alola_home';pending=[first];seen=set();entries=defaultdict(set)
    while pending:
        mid=pending.pop()
        if mid in seen:continue
        seen.add(mid)
        for w in maps[mid]['warps']:
            t=w['to']
            if t['map'] in maps:entries[t['map']].add(tuple(t['at']));pending.append(t['map'])
    assert seen==maps.keys(),sorted(maps.keys()-seen)
    issues=[];checks=0
    for mid,m in maps.items():
        meta=m['physics'];walk=~np.array(meta['collision'],bool)
        if 'water' in meta:walk&=~np.array(meta['water'],bool)
        size=m['size'];assert walk.shape==tuple(reversed(size)),mid
        h,w=walk.shape
        for e in m['warps']:
            x,y=e['at'];walk[y,x]=False
        for n in m['npcs']:
            x,y=n['at'];walk[y,x]=False
        labels,_=ndimage.label(walk);x,y=m['spawn'];zone=labels[y,x];assert zone!=0,(mid,'spawn')
        for xy in entries[mid]:
            x,y=xy;checks+=1
            if labels[y,x]!=zone:issues.append((mid,'landing',xy))
        for what,xy in [*((e['alola_label'],e['at']) for e in m['warps']),*m['alola_anchors'].items(),*((t['item'],t['at']) for t in m['alola_item_tiles']),*((t['id'],t['at']) for t in m['alola_trainer_tiles'])]:
            x,y=xy;checks+=1
            if not any(0<=a<w and 0<=b<h and labels[b,a]==zone for a,b in [(x+1,y),(x-1,y),(x,y-1),(x,y+1)]):issues.append((mid,what,xy))
        assert Image.open(ROOT/m['hoenn_art']['scene'][0][6:]).width%w==0,mid
    rules=read(ROOT/'content/alola_map_access.json')
    assert rules.keys()<=maps.keys(), sorted(rules.keys()-maps.keys())
    check_sandy_cave(maps['alola_sandy_cave'],rules)
    if issues:print(issues[:50]);raise SystemExit(f'{len(issues)} unreachable Alola interactions')
    print('ALOLA MAPS PASS',len(maps),'maps',checks,'landing and interaction checks')
if __name__=='__main__':main()
