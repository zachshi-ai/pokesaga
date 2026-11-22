"""Coordinate spaces and stable field IDs shared by the Platinum map compiler."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'content/platinum_native'

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n')

ALIASES = dict(twinleaf_town='twinleaf', sandgem_town='sandgem', solaceon_town='solaceon',
    floaroma_town='floaroma', celestic_town='celestic', pokemon_league='league',
    oreburgh_gate_1f='gate', oreburgh_mine_b1f='mine',
    canalave_library_1f='library', great_marsh_5='marsh', vista_lighthouse='lighthouse',
    mt_coronet_1f_south='coronet', route_209_lost_tower_1f='tower', iron_island='iron_island',
    spear_pillar='spear', sendoff_spring='spring', stark_mountain_outside='stark',
    snowpoint_temple_1f='temple', solaceon_ruins_room_1='ruins', lake_verity='verity',
    lake_valor='valor', lake_acuity='acuity', valley_windworks_outside='windworks',
    victory_road_1f='victory', fight_area='fight', survival_area='survival', resort_area='resort')
ALIASES.update({name+'_city':name for name in 'jubilife oreburgh eterna hearthome veilstone pastoria canalave snowpoint sunyshore'.split()})
ALIASES.update({f'route_{i}':str(i) for i in range(201,231)})
ALIASES.update(route_204_south='204',route_205_south='205',route_210_south='210',route_211_west='211',route_212_north='212',eterna_forest='forest')

# MapMatrix_RevealSeabreakPath (src/map_matrix.c) swaps these four Route 224 blocks.
SEABREAK = {(28,15):119,(27,16):120,(28,16):121,(27,17):122}
BLOOM_FIELDS = {'sinnoh_224','sinnoh_seabreak_path','sinnoh_league'}

def catalog(src):
    maps=src/'res/field/maps'
    groups={g['id']:g for g in json.loads((maps/'groups.json').read_text())}
    result={}
    for p in sorted(maps.glob('*/header.json')):
        key=p.parent.name
        if key in ('nothing','everywhere') or key.startswith('unused_'): continue
        header=json.loads(p.read_text())
        group=groups[header['mapGroup']]
        hid='MAP_HEADER_'+key.upper()
        rows={ (x,y):int(v[4:]) for y,row in enumerate(group['maps']) for x,v in enumerate(row)
            if v!='MAP_NONE' and (not group['headers'] or group['headers'][y][x]==hid) }
        if not rows: continue
        ox=min(x for x,y in rows); oy=min(y for x,y in rows)
        if not group['headers']: ox=oy=0
        size=[32*(max(x for x,y in rows)-ox+1),32*(max(y for x,y in rows)-oy+1)]
        origin=[ox*32,oy*32]
        if key.startswith('distortion_world_'):
            # The overlay uses a second global 3-D coordinate system in its own archives.
            # Preserve those script coordinates for flat floor masks, lifts, NPCs and rocks.
            size=[128,128]
        events=p.with_name('events.json')
        result[hid]=dict(id='sinnoh_'+ALIASES.get(key,key),source_id=hid,origin=origin,size=size,
            rows=rows,area=int(header['areaData'].split('_')[-1]),header=header,
            bank=json.loads(events.read_text()) if events.exists() else {})
    return result

if __name__=='__main__':
    import sys
    src=Path(sys.argv[1])
    fields=catalog(src)
    write(OUT/'index.json',{hid:row['id'] for hid,row in fields.items()})
    jobs={(land,row['area']) for row in fields.values() for land in row['rows'].values()}
    jobs.update((land,fields['MAP_HEADER_ROUTE_224']['area']) for land in SEABREAK.values())
    write(Path(sys.argv[2]),sorted(jobs))
    print(len(fields),'Platinum headers')
