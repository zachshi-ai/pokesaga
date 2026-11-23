"""Import the four Gen VII releases from PokéAPI's CSVs, using move keys across dex revisions."""
import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSIONS = dict(zip(range(27, 31), ('sun', 'moon', 'ultra_sun', 'ultra_moon')))


def build(directory, move_file, showdown):
    def read(name):
        return csv.DictReader((directory / (name + '.csv')).open())

    catalog = json.loads((ROOT / 'content/dex_catalog.json').read_text())['species']
    pokemon = {}
    for species, entry in catalog.items():
        for form in entry['variants']:
            pokemon.setdefault(form['pokeapi_id'], (int(species), form['form']))
    symbols = {re.sub('[^a-z0-9]', '', m['key'].lower()): m['id']
               for m in json.loads((ROOT / 'content/moves.json').read_text())}
    moves = {int(m['id']): symbols.get(m['identifier'].replace('-', ''))
             for m in csv.DictReader(move_file.open())}
    levels = defaultdict(lambda: defaultdict(list))
    compatible = defaultdict(lambda: defaultdict(set))
    machines = defaultdict(dict)
    for r in read('machines'):
        group = r['version_group_id']
        if group in ('17','18'):
            machines[group][r['machine_number']] = moves[int(r['move_id'])]
    for r in read('pokemon_moves'):
        group = r['version_group_id']
        mon = pokemon.get(int(r['pokemon_id']))
        move = moves.get(int(r['move_id']))
        if group not in ('17','18') or not mon or not move:
            continue
        key = mon[1] or str(mon[0])
        if r['pokemon_move_method_id'] == '1':
            levels[group][key].append((int(r['level']), int(r['order'] or 0), move))
        elif r['pokemon_move_method_id'] == '4':
            compatible[group][key].add(move)

    slots = {r['id']:r for r in read('encounter_slots')}
    methods = {r['id']:r['identifier'] for r in read('encounter_methods')}
    areas = {r['id']:r for r in read('location_areas')}
    locations = {r['id']:r['identifier'] for r in read('locations')}
    conditions = defaultdict(list)
    for r in read('encounter_condition_value_map'):
        conditions[r['encounter_id']].append(int(r['encounter_condition_value_id']))
    wild = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for r in read('encounters'):
        version = VERSIONS.get(int(r['version_id']))
        if not version: continue
        slot = slots[r['encounter_slot_id']]
        method = methods[slot['encounter_method_id']]
        if method not in ('walk','surf','super-rod','bubbling-spots','sos','island-scan','berry-trees'): continue
        area = areas[r['location_area_id']]
        loc = locations[area['location_id']].removeprefix('alola-').replace('--','-')
        section = area['identifier']
        if section in ('hauoli-outskirts','trainers-school','aether-house','farthest-hollow','trial-site','totems-den',
                       'shopping-district','beachfront','marina','outer-cape','abandoned-site'):
            loc = loc + '-' + section
        species, form = pokemon[int(r['pokemon_id'])]
        row = [species, form, int(r['min_level']),int(r['max_level']),int(slot['rarity'] or 1), conditions[r['id']]]
        if row not in wild[version][loc][method]:
            wild[version][loc][method].append(row)

    effects = {}
    for key, block in re.findall(r'^\t(\w+): \{\n(.*?)^\t\},',showdown.read_text(),re.M|re.S):
        move = symbols.get(key)
        match = re.search(r'zMove: (\{[^\n]*\}),',block)
        if not move or not match:continue
        text = match[1]
        effect = {}
        if power := re.search(r'basePower: (\d+)',text):effect['power']=int(power[1])
        if name := re.search(r"effect: '([^']+)'",text):effect['effect']=name[1]
        if 'boost:' in text:effect['boost']={stat:int(value) for stat,value in re.findall(r'(\w+): (\d+)',text)}
        if effect:effects[move]=effect
    out = dict(levels={g:{s:[[lv,m] for lv,_,m in sorted(v)] for s,v in rows.items()} for g,rows in levels.items()},
               machines=machines,compatible={g:{s:sorted(v) for s,v in rows.items()} for g,rows in compatible.items()},
               national_moves=moves,wild=wild,z_effects=effects)
    assert all(len(machines[g])==100 and len(levels[g])>=800 for g in ('17','18'))
    assert len(wild)==4 and len(effects)>200
    (ROOT/'content/alola_field.json').write_text(json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n')


if __name__ == '__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    for key in ['directory','move_file','showdown']:ap.add_argument(key,type=Path)
    build(**vars(ap.parse_args()))
