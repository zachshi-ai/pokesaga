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
def approaches(warp):
    x, y = warp['at']
    trigger = warp.get('trigger')
    if trigger == 'door':
        return [(x, y + 1)]
    if trigger in ('up', 'down', 'left', 'right'):
        return [(x, y)]
    return [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]


def connected_floor(room, allow_surf=False):
    phy = room['physics']
    dry = ~np.array(phy['collision'], bool)
    water = np.array(phy.get('water', np.zeros_like(dry)), bool)
    # World.can_enter permits a mounted rider on a water cell including a
    # colliding water mesh, and dismounts on the adjoining walkable shore.
    walk = dry | water if allow_surf else dry & ~water
    for warp in room['warps']:
        if warp.get('trigger') in ('door', 'step'):
            x, y = warp['at']
            walk[y, x] = False
    for npc in room['npcs']:
        x, y = npc['at']
        walk[y, x] = False
    labels, _ = ndimage.label(walk)
    height, width = labels.shape
    x, y = room['spawn']
    components = {labels[y, x]}
    assert 0 not in components, (room['id'], 'spawn', room['spawn'])

    def reached(point):
        x, y = point
        return 0 <= x < width and 0 <= y < height and labels[y, x] in components

    portals = [w for w in room['warps'] if w['to']['map'] == room['id'] and not w['to'].get('kalos_requires')]
    while True:
        before = len(components)
        for warp in portals:
            if any(map(reached, approaches(warp))):
                x, y = warp['to']['at']
                assert labels[y, x], (room['id'], 'self warp into solid tile', [x, y])
                components.add(labels[y, x])
        if len(components) == before:
            return reached


fail=[]
for k, m in maps.items():
    reached = connected_floor(m)
    seawater_entries = set()
    seawater_doors = []
    if k in ('kalos_12', 'kalos_azure'):
        wet = np.array(m['physics']['water'], bool)
        def at_sea(point):
            x, y = point
            return wet[y, x]
        seawater_doors = [w for w in m['warps'] if at_sea(w['at'])]
        assert len(seawater_doors) == 1 and seawater_doors[0].get('trigger') in ('up','down'), k
        seawater_entries.update(point for point in entries[k] if at_sea(point))
        assert len(seawater_entries) == 1, (k, seawater_entries)
        if k == 'kalos_azure':
            # The den itself is on dry ground but its island is surrounded by sea.
            den_gate = next(w for w in m['warps'] if w.get('source_warp') == 'xy_0')
            seawater_doors.append(den_gate)
            cave = maps[den_gate['to']['map']]
            seawater_entries.update(tuple(w['to']['at']) for w in cave['warps'] if w['to']['map'] == k)
        afloat = connected_floor(m, allow_surf=True)
        for warp in seawater_doors:
            if any(map(reached, approaches(warp))):
                fail.append((k, 'water passage accessible without Surf', warp['at']))
        for point in seawater_entries:
            if reached(point):
                fail.append((k, 'water arrival accessible without Surf', point))
    for point in entries[k]:
        available = afloat if point in seawater_entries else reached
        if not available(point):
            fail.append((k, 'arrival', point))
        checks += 1
    for warp in m['warps']:
        available = afloat if warp in seawater_doors else reached
        if not any(map(available, approaches(warp))):
            fail.append((k, 'no approach', warp['at']))
        checks += 1
    for point in m['kalos_anchors'].values():
        if not any(map(reached, approaches({'at': point}))):
            fail.append((k, 'no actor approach', point))
        checks += 1
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
# Model 122 has a curving front desk, separate seats and a west stair flight.
# Its furniture collisions used to punch both lower corners out of the lobby.
with Image.open(ROOT/'assets/kalos/maps/field_17.png') as picture:
    lobby = np.asarray(picture.convert('RGB'))
def lobby_tile(x,y):
    return lobby[y*16:(y+1)*16,x*16:(x+1)*16]
assert all(np.array_equal(lobby_tile(x,y),lobby_tile(9,11)) for x,y in [(8,16),(25,15)])
assert np.array_equal(lobby_tile(4,3),lobby_tile(5,3))
assert not np.array_equal(lobby_tile(4,3),lobby_tile(9,11))
assert not np.array_equal(lobby_tile(13,8),lobby_tile(9,11))
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
