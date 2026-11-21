"""Resolve FireRed's warp index and metatile behavior in the project's map coordinates."""
import argparse
import json
import re
import struct
from collections import defaultdict
from pathlib import Path

from asset_paths import project_path, source_path


def read(path):
    return json.loads(path.read_bytes())


def norm(name):
    return re.sub(r'[^a-z0-9]', '', name.lower())


# field_control_avatar.c checks arrows/stairs underfoot, and an animated door
# one tile ahead to the north. Non-warp neighbors in warp_events are anchors for
# scripts / link players. They are not alternative entrances when walked across.
DIRECTION = {0x62: 'right', 0x63: 'left', 0x64: 'up', 0x65: 'down',
             0x6C: 'right', 0x6D: 'left', 0x6E: 'right', 0x6F: 'left'}
OPPOSITE = {'up': 'down', 'down': 'up', 'left': 'right', 'right': 'left'}
STEP = {0x60, 0x61, 0x66, 0x67, 0x68, 0x6A, 0x6B, 0x71}
# These doors change metatile / are fired by a map script rather than the
# default layout. The study world's postgame areas are already open.
SCRIPT_DOORS = {('MAP_MT_EMBER_EXTERIOR',42,39), ('MAP_SIX_ISLAND_RUIN_VALLEY',24,24),
                ('MAP_SEVEN_ISLAND_HOUSE_ROOM1',4,1), ('MAP_FIVE_ISLAND_MEADOW',12,21),
                ('MAP_POKEMON_LEAGUE_LANCES_ROOM',6,5)}
LEAGUE_HALLS = {'MAP_POKEMON_LEAGUE_LORELEIS_ROOM', 'MAP_POKEMON_LEAGUE_BRUNOS_ROOM',
                'MAP_POKEMON_LEAGUE_AGATHAS_ROOM'}
LIFTS = {'MAP_SILPH_CO_ELEVATOR', 'MAP_CELADON_CITY_DEPARTMENT_STORE_ELEVATOR',
         'MAP_ROCKET_HIDEOUT_ELEVATOR', 'MAP_TRAINER_TOWER_ELEVATOR'}


def build(source, root):
    native = {m['id']: m for p in (source/'data/maps').glob('*/map.json') if (m := read(p))}
    layouts = {l['id']: l for l in read(source/'data/layouts/layouts.json')['layouts'] if 'id' in l}
    attrs = {norm('gTileset_'+p.parent.name): [v[0] for v in struct.iter_unpack('<I', p.read_bytes())]
             for p in (source/'data/tilesets').glob('*/*/metatile_attributes.bin')}
    files, locations = {}, {}
    ids = {norm(k[4:]): k for k in native}
    for r in ('kanto', 'sevii'):
        for p in sorted((root/'content/regions'/r/'maps').glob('*.json')):
            room = (r, p.stem)
            files[room] = p
            data = read(p)
            key = ids.get(norm(p.stem)) or ids.get(norm(data.get('emerald', '')))
            if key:
                locations[key] = (room, (0, 0))
    for name, offset in read(root/'content/emerald_maps/kanto_main.json')['member_maps'].items():
        locations['MAP_'+name] = (('kanto','kanto_main'), offset)

    blocks = {}
    def point(key, event):
        room, (x, y) = locations[key]
        return [x + event['x'], y + event['y']]

    def behavior(key, event):
        if (key, event['x'], event['y']) in SCRIPT_DOORS:
            return 0x69
        if key in LEAGUE_HALLS:
            if (event['x'],event['y']) == (6,2): return 0x69
            if (event['x'],event['y']) == (6,12): return 0x65
        if key == 'MAP_POKEMON_LEAGUE_LANCES_ROOM' and event['x'] == 23:
            return 0x65
        layout_id = native[key]['layout']
        if key == 'MAP_THREE_ISLAND_DUNSPARCE_TUNNEL':
            layout_id = 'LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL_DUG_OUT'
        layout = layouts[layout_id]
        lid = layout['id']
        if lid not in blocks:
            blocks[lid] = (source/layout['blockdata_filepath']).read_bytes()
        offset = (event['y'] * layout['width'] + event['x']) * 2
        mid = struct.unpack_from('<H', blocks[lid], offset)[0] & 1023
        if mid < 640:
            return attrs[norm(layout['primary_tileset'])][mid] & 0x1ff
        return attrs[norm(layout['secondary_tileset'])][mid-640] & 0x1ff

    def landing(key, event):
        (r, mid), _ = locations[key]
        x, y = point(key, event)
        mode = behavior(key, event)
        out = {'region': r, 'map': mid, 'at': [x, y]}
        if key in LEAGUE_HALLS and (x,y) == (6,12):
            # PokemonLeague_EventScript_EnterRoom actually walks five tiles north.
            out.update(at=[6,7], arrival_from=[6,12], facing='up')
        elif mode in (0x69, 0x60):
            out.update(at=[x,y+1], arrival_from=[x,y], facing='down')
        elif mode in DIRECTION:
            out['facing'] = OPPOSITE[DIRECTION[mode]]
        return out

    exits, points = defaultdict(dict), defaultdict(set)
    floors = defaultdict(list)
    for key in sorted(locations):
        room, _ = locations[key]
        for event in native[key]['warp_events']:
            at = point(key, event)
            points[room].add(tuple(at))
            if key in LEAGUE_HALLS and at == [6,12]:
                # In exploration mode the closed gate can be used from the last
                # walkable tile. The original one-way challenge is scripted.
                at = [6,10]
            target = event['dest_map']
            tile = behavior(key, event)
            if target not in locations or tile not in STEP | DIRECTION.keys() | {0x69}:
                continue
            dest_event = native[target]['warp_events'][int(event['dest_warp_id'])]
            to = landing(target, dest_event)
            row = {'at': at, 'to': to}
            if tile == 0x69:
                row['trigger'] = 'door'
            elif tile in DIRECTION:
                row['trigger'] = DIRECTION[tile]
            else:
                row['trigger'] = 'step'
            if target in LIFTS:
                origin = landing(key, event)
                slot = 'sevii_lift' if target == 'MAP_TRAINER_TOWER_ELEVATOR' else to['map']
                to['remember_passage'] = {'key':slot, 'destination':origin}
                if origin not in floors[target]:
                    floors[target].append(origin)
            exits[room][tuple(at)] = row

    for key, stops in floors.items():
        room, _ = locations[key]
        event = next(e for e in native[key]['warp_events'] if behavior(key,e) == 0x65)
        slot = 'sevii_lift' if key == 'MAP_TRAINER_TOWER_ELEVATOR' else room[1]
        base_floor = next(t for t in stops if t['map'].endswith(('_1f','_b1f','_lobby')))
        at = point(key,event)
        exits[room][tuple(at)] = {'at':at,'to':{**base_floor, 'recall_passage':slot}, 'trigger':'down'}

    count = 0
    for room, triggers in exits.items():
        p = files[room]
        data = read(p)
        # Keep project-only ferries, causeways and border connections. Replace
        # old guessed interior shortcuts to a room already linked by a native door.
        native_dest = {row['to']['map'] for row in triggers.values()}
        is_lift = next((k for k in floors if locations[k][0] == room), None)
        kept = []
        for row in data['warps']:
            if tuple(row['at']) in points[room]:
                continue
            if not row.get('atlas') and room[0]=='kanto' and row['to']['region']=='kanto' and (
                row['to']['map'] in native_dest or is_lift):
                continue
            kept.append(row)
        if room[0] == 'sevii' and room[1].endswith('_harbor'):
            for row in kept:
                dest = row['to']
                if dest['region'] == 'sevii' and dest['map'].endswith('_harbor'):
                    row.update(at=[7,5], trigger='left')
                    dest.update(at=[8,3],facing='up')
                elif dest['region'] == 'kanto' and dest['map']=='kanto_main':
                    row.update(at=[9,5],trigger='right')
                    dest.update(at=[286,231],facing='up')
        data['warps'] = list(triggers.values()) + kept
        if is_lift == 'MAP_TRAINER_TOWER_ELEVATOR':
            for row in kept:
                if row['at'] == [0,2]:
                    row['trigger'] = 'panel'
            data['objects'] = [o for o in data.get('objects',[]) if o['at'] != [1,2] or o.get('kind') != 'sign']
        if room == ('kanto','ceruleancity_house2'):
            for obj in data.get('objects',[]):
                if obj['at'] == [4,1] and obj['kind'] == 'sign':
                    obj['text'] = '墙上被撞出了一个能钻过去的大洞。'
        if is_lift and room[0]=='kanto':
            data['lift_stops'] = sorted(floors[is_lift], key=lambda t: floor_sort(t['map']))
            panels = [e for e in native[is_lift]['bg_events'] if 'FloorSelect' in e['script']]
            panels_at = [point(is_lift, e) for e in panels]
            data['objects'] = [o for o in data.get('objects',[]) if o['at'] not in panels_at]
            data['objects'] += [{'at':at,'kind':'elevator','name':'电梯操作盘'} for at in panels_at]
        if data != read(p):
            original = p.read_text()
            style = {'indent':1} if original.startswith('{\n') else {'separators':(',',':')}
            p.write_text(json.dumps(data,ensure_ascii=False,**style)+ ('\n' if original.endswith('\n') else ''))
            count += 1
    print(f'{len(locations)} FireRed map identities, {sum(map(len,exits.values()))} active warp events, {count} changed game maps')


def floor_sort(name):
    tail = name.split('_')[-1]
    if tail == 'roof': return 100
    n = re.search(r'(\d+)f$', tail)
    return (-1 if tail.startswith('b') else 1)*int(n[1]) if n else 0


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--firered',type=Path,default=Path(source_path('firered')))
    parser.add_argument('--project',type=Path,default=Path(project_path()))
    args=parser.parse_args()
    build(args.firered,args.project)
