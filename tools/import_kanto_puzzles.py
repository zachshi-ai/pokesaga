"""Bake the changing FireRed puzzle cells from the source used by firered_fields.py."""
import json
import re
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

from bake_emerald_field import Atlas
from firered_fields import FireRedFields


def build(source, project):
    atlas = Atlas()
    atlas.add(Image.new('RGBA', (16, 16)))
    field = FireRedFields(source, project, atlas)
    labels = dict(re.findall(r'#define (METATILE_\w+)\s+(0x[0-9A-Fa-f]+)', (source/'include/constants/metatile_labels.h').read_text()))
    maps = {}

    def puzzle(mid, native, code, states, triggers=None):
        map_info = json.loads((source/'data/maps'/native/'map.json').read_text())
        layout = field.layouts[map_info['layout']]
        block = np.fromfile(source/layout['blockdata_filepath'], '<u2').reshape(layout['height'], layout['width'])
        primary, secondary = layout['primary_tileset'], layout['secondary_tileset']

        def tile(x, y, number, solid):
            bg, fg, _ = field.metatile(primary, secondary, number)
            return [x, y, bg, fg, solid]

        variants = []
        touched = set()
        for flags, label in states:
            body = re.split(r'\n\s*(?:return|end)\b', code.split(label+'::', 1)[1], maxsplit=1)[0]
            cells = []
            for x, y, name, solid in re.findall(r'setmetatile\s+(\d+),\s*(\d+),\s*(\w+),\s*([01])',body):
                x, y = int(x), int(y)
                cells.append(tile(x, y, int(labels[name], 16), int(solid)))
                touched.add((x,y))
            assert cells, label
            variants.append({'flags':flags, 'cells':cells})
        base = [tile(x, y, int(block[y,x]) & 1023, int((int(block[y,x]) >> 10) & 3 != 0)) for x,y in sorted(touched)]
        maps.setdefault(mid, []).append({'base':base, 'variants':variants, 'controls':triggers or []})

    def script(native):
        return (source/'data/maps'/native/'scripts.inc').read_text()

    def controls(native, suffix):
        bg = json.loads((source/'data/maps'/native/'map.json').read_text())['bg_events']
        return [[r['x'],r['y']] for r in bg if re.search(suffix+'$',r.get('script',''))]

    place = 'CeladonCity_GameCorner'
    puzzle('celadon_city_game_corner',place,script(place),[([],place+'_EventScript_HideRocketHideout'),(['hideout_stairs'],place+'_EventScript_OpenRocketHideout')])
    place = 'RocketHideout_B4F'
    puzzle('rocket_hideout_b4f',place,script(place),[([],place+'_EventScript_SetBarrier'),(['hideout_guard_1_win','hideout_guard_2_win'],place+'_EventScript_RemoveBarrier')])
    place = 'VermilionCity_Gym'
    puzzle('vermilioncity_gym',place,script(place),[(['surge_first'],place+'_EventScript_SetOneBeamOff'),(['surge_open'],place+'_EventScript_SetBeamsOff')],controls(place,'TrashCan[0-9]+'))
    place = 'CinnabarIsland_Gym'
    for n in range(1,7):
        puzzle('cinnabarisland_gym',place,script(place),[(['cinnabar_quiz_'+str(n)],place+'_EventScript_OpenDoor'+str(n))],controls(place,'Quiz'+str(n)+'(Left|Right)'))
    code = (source/'data/scripts/silphco_doors.inc').read_text()
    for n, suffix in re.findall(r'^EventScript_Close(\d+)FDoor(\d*)::',code,re.M):
        place = 'SilphCo_'+n+'F'
        flag = 'silph_door_'+n+'_'+(suffix or '1')
        door = n+'FDoor'+suffix
        puzzle('silph_co_'+n+'f',place,code,[([],'EventScript_Close'+door),([flag],'EventScript_Open'+door)],controls(place,'Door'+suffix))
    for floor, suffix, point in [(1,'',(20,16)),(2,'1',(2,19)),(2,'2',(14,19)),(3,'',(7,7))]:
        place='VictoryRoad_'+str(floor)+'F'
        mid='victoryroad_'+str(floor)+'f'
        flag=f'btn:{mid}:{point[0]},{point[1]}'
        puzzle(mid,place,script(place),[([],place+'_EventScript_SetRockBarrier'+suffix),
                                          ([flag],place+'_EventScript_FloorSwitch'+suffix)])
    code = (source/'data/scripts/pokemon_league.inc').read_text()
    for room in ['Loreleis','Brunos','Agathas','Lances']:
        mid = 'pokemon_league_'+room.lower()+'_room'
        puzzle(mid,'PokemonLeague_'+room+'Room',code,[(['kanto_'+room.lower()+'_win'],'PokemonLeague_EventScript_SetDoorOpen'+('Lance' if room=='Lances' else ''))])
    ice_map = 'FourIsland_IcefallCave_1F'
    native_map = json.loads((source/'data/maps'/ice_map/'map.json').read_text())
    layout = field.layouts[native_map['layout']]
    bg, fg, _ = field.metatile(layout['primary_tileset'],layout['secondary_tileset'],
                                int(labels['METATILE_SeafoamIslands_CrackedIce'],16))
    callbacks = (source/'src/field_tasks.c').read_text()
    ice_table = callbacks.split('sIcefallCaveIceCoords[][2] =',1)[1].split('};',1)[0]
    rules = []
    for col,row in re.findall(r'\{\s*(\d+)\s*,\s*(\d+)\s*\}',ice_table):
        x,y=int(col),int(row)
        rules.append({'thin_ice':[x,y],'base':[],'controls':[],
                      'variants':[{'flags':[f'icefall_crack_{x}_{y}'],'cells':[[x,y,bg,fg,0]]}]})
    assert len(rules) == 9
    maps['four_island_icefall_cave_1f'] = rules
    lobby='TrainerTower_Lobby'
    puzzle('trainer_tower_lobby',lobby,script(lobby),[(['fr_tower_lobby_exit'],'TrainerTower_Lobby_OpenCounterBarrier')])
    tunnel = 'LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL'
    snapshots = []
    for layout_id in [tunnel, tunnel+'_DUG_OUT']:
        layout = field.layouts[layout_id]
        blocks = np.fromfile(source/layout['blockdata_filepath'], '<u2').reshape(layout['height'], layout['width'])
        snapshots.append(blocks)
    before, after = snapshots
    changed = np.argwhere(before != after)
    def tunnel_cells(blocks):
        cells = []
        for y, x in changed:
            value = int(blocks[y,x])
            bg, fg, _ = field.metatile(layout['primary_tileset'],layout['secondary_tileset'],value & 1023)
            cells.append([int(x),int(y),bg,fg,int(bool((value >> 10) & 3))])
        return cells
    maps['three_island_dunsparce_tunnel'] = [{'base':tunnel_cells(before), 'controls':[],
        'variants':[{'flags':['national_dex'],'cells':tunnel_cells(after)}]}]
    # The ROM defines 24 floor layouts. Mixed selects one of the same three
    # floor plans per floor through the native challengeType table.
    from frlg_tower_tables import compile_tower
    species = {r['key']:r['id'] for r in json.loads((project/'content/species.json').read_text())}
    moves = dict(re.findall(r'^#define MOVE_(\w+)\s+(\d+)\b',(source/'include/constants/moves.h').read_text(),re.M))
    mixed = compile_tower(source,species,moves)['mixed']
    for number in range(1,9):
        tower = f'LAYOUT_TRAINER_TOWER_{number}F'
        layouts = [field.layouts[tower+suffix] for suffix in ['', '_DOUBLES', '_KNOCKOUT']]
        blocks = [np.fromfile(source/r['blockdata_filepath'],'<u2').reshape(r['height'],r['width']) for r in layouts]
        diff = np.argwhere((blocks[0]!=blocks[1]) | (blocks[0]!=blocks[2]))
        def floor_tiles(k):
            cells = []
            for y,x in diff:
                val=int(blocks[k][y,x])
                bg,fg,_=field.metatile(layouts[k]['primary_tileset'],layouts[k]['secondary_tileset'],val & 1023)
                cells.append([int(x),int(y),bg,fg,int(bool((val >> 10) & 3))])
            return cells
        variants = []
        for k,kind in [(1,'double'),(2,'knockout')]:
            modes=[kind]+(['mixed'] if mixed[number-1]['kind']==kind else [])
            variants.append({'flags':[], 'tower_modes':modes, 'cells':floor_tiles(k)})
        maps[f'trainer_tower_{number}f']=[{'base':floor_tiles(0), 'controls':[], 'variants':variants}]
    output = Image.new('RGBA',(16*16, ((len(atlas.images)+15)//16)*16))
    for n,img in enumerate(atlas.images):
        output.paste(img,(n%16*16,n//16*16))
    output.save(project/'assets/emerald/field/kanto_puzzles.png',optimize=True)
    (project/'content/regions/kanto/puzzles.json').write_text(json.dumps(maps,ensure_ascii=False,separators=(',',':'))+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("firered", type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    build(args.firered, args.project)
