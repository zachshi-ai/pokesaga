"""Compile X/Y game trainer parties from PokeFeur at 012259145f9f29fb33d64ecc218dff1c966bb1fd.

Pass vanilla_exports/pokemon_{x,y}_europe_en_ja_fr_de_es_it_ko.js in that order.
No game image or external data service is required at run time.
"""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def tables(path):
    raw = path.read_text()
    game = json.JSONDecoder().raw_decode(raw[raw.index('{"meta"'):])[0]
    teams, people = {}, {}
    for trainer in game['trainers']:
        key = str(trainer['trainerId'])
        people[key] = [trainer['name'], trainer['trainerClassName']]
        team = []
        for row in trainer['party']:
            mon = {'species': row['speciesId'], 'level': row['level'],
                   'moves': [move for move in row['movesetIds'] if move]}
            if row['heldItem']:
                mon['held'] = re.sub(r'[^A-Z0-9]+', '_', row['heldItem'].upper()).strip('_')
            if row['abilityIds']:
                mon['ability'] = row['abilityIds'][0]
            if row['formId']:
                mon['xy_form'] = row['formId']
            team.append(mon)
        teams[key] = team
    return teams, people


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('x', type=Path)
    parser.add_argument('y', type=Path)
    args = parser.parse_args()
    teams, people = tables(args.x)
    y, yp = tables(args.y)
    assert len(teams) == len(y) == 784 and people.keys() == yp.keys()
    changes = {key: value for key, value in y.items() if teams[key] != value}
    out = {'teams': teams, 'y': changes, 'people': people}
    (ROOT/'content/kalos_trainers.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':'))+'\n')
    print(len(teams), 'trainers;', len(changes), 'Y party differences')
