"""Read Team Rocket Elite's Sun/Moon Battle Tree and Battle Royal data workbook.

Input: docs.google.com/spreadsheets/d/1D7T0jCHBkDppjTB0_rJyK0houk8zE3wLmZ1DlVXEkXg
The USUM set table also includes the three rental-battle opponents at Festival Plaza.
"""
import argparse
import json
import re
from pathlib import Path
from openpyxl import load_workbook
from import_kalos_maison import slug

ROOT = Path(__file__).resolve().parents[1] / 'content'


def convert(workbook):
    tables = load_workbook(workbook, read_only=True)
    mons = {}
    for entry in json.loads((ROOT/'species.json').read_text()):
        base = entry['key']
        mons[slug(base)] = (entry['id'], '')
        mons.setdefault(slug(base.split('_')[0]), (entry['id'], ''))
        for variant in entry.get('forms',[]):
            key = variant['key']
            mons[slug(key)] = (entry['id'], key)
    moves = {slug(e['key']):e['id'] for e in json.loads((ROOT/'moves.json').read_text())}
    aliases = {'oricoriopaustyle':'oricoriopau'}
    def species(label):
        raw = re.sub(r'-\d+$', '', label)
        if raw.startswith('Alolan '):raw = raw[7:]+' Alola'
        if raw.endswith(' Rotom'):raw = 'Rotom '+raw.split()[0]
        if raw.endswith('-T'):raw = raw[:-2]+' therian'
        key = slug(raw)
        return mons[aliases.get(key,key)]
    result = {}
    pool = []
    pool_index = {}
    for mode, first in [('sm',0),('royal',2),('usum',4)]:
        refs = {}
        for row in list(tables.worksheets[first].values)[1:]:
            if not isinstance(row[0], (float,int)):continue
            label,nature,held,*tail=row[1:]
            sid,form=species(label)
            stats=tail[4].split('/')
            ev=[min(252,510//len(stats)) if k in stats else 0 for k in ('HP','Atk','Def','SpA','SpD','Spd')]
            item=held.replace("'",'').replace('-','_').replace(' ','_').upper()
            data=[sid,[moves[slug(m)] for m in tail[:4] if m not in ('-',None)],item,nature,form,ev]
            handle=json.dumps(data,ensure_ascii=False)
            if handle not in pool_index:
                pool_index[handle]=len(pool)
                pool.append(data)
            refs[label]=pool_index[handle]
        trainers=[]
        for row in tables.worksheets[first+1].values:
            if ' - ' not in str(row[0]):continue
            name,roster=row[0].split(' - ',1)
            trainers.append([name,[refs[s.strip()] for s in roster.split(',') if s.strip()]])
        result[mode]=trainers
    result['sets']=pool
    (ROOT/'alola_side_tree.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workbook',type=Path)
    convert(parser.parse_args().workbook)
