"""Match X/Y ROM trainer parties to the Kalos routes listed in Pokéarth's location guide.

Run with the locally downloaded Serebii Kalos location HTML directory and the XY zone index.
Only identifiers and party references are stored. Optional rematches use their own scripts.
"""
import argparse
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
CAVES = {"santaluneforest":"Santalune Forest","connectingcave":"Connecting Cave","glitteringcave":"Glittering Cave",
         "reflectioncave":"Reflection Cave","frostcavern":"Frost Cavern","victoryroad":"Victory Road",
         "terminuscave":"Terminus Cave","losthotel":"Lost Hotel","azurebay":"Azure Bay"}
GYMS = {"santalunecity":"santalune","cyllagecity":"cyllage","shalourcity":"shalour","coumarinecity":"coumarine",
        "laverrecity":"laverre","anistarcity":"anistar","snowbellecity":"snowbelle"}


def normalize(s):
    return re.sub('[^a-z0-9]', '', unicodedata.normalize('NFKD', s).lower())


def run(pages, atlas):
    trainers = json.loads((ROOT / 'content/kalos_trainers.json').read_bytes())
    zones = json.loads(atlas.read_bytes())['zones']
    parties = defaultdict(list)
    for key, team in trainers['teams'].items():
        fingerprint = tuple((m['species'], m['level']) for m in team)
        parties[fingerprint].append(key)
    locations = {f'route{i}':f'Route {i}' for i in range(2,23)} | CAVES
    output = defaultdict(list)
    for stem in list(locations) + list(GYMS):
        if stem in GYMS:
            destinations = ['kalos_gym_'+GYMS[stem]]
        else:
            areas = [(int(z), row) for z, row in zones.items() if row['name'] == locations[stem]]
            # Prefer the occupied outdoor or dungeon floors over gates and empty connectors.
            core = [z for z, row in areas if 'wild' in row]
            destinations = list(map(str, sorted(core or [min(z for z, _ in areas)])))
        path = pages / (stem+'.html')
        if not path.exists():raise FileNotFoundError(path)
        html = BeautifulSoup(path.read_bytes(), 'html.parser', from_encoding='windows-1252')
        matched = []
        for block in html.select('table.trainer'):
            lines = block.find_all('tr', recursive=False)
            names = lines[1].find_all('td', recursive=False)
            displayed = normalize(names[0].get_text(' ',strip=True))
            if ('leader' in displayed or 'teamflare' in displayed or displayed.startswith('pokemontrainer')
                    or displayed in ('professorsycamore','lysandre','trainerrinka')):
                continue
            ids = [int(a['href'].rsplit('/',1)[1].split('.')[0]) for a in lines[0].select('a[href*="/pokedex-xy/"]')]
            levels = [int(re.search(r'\d+',c.get_text()).group()) for c in block.select('td.level')]
            if len(levels)!=len(ids): continue
            candidates=[k for k in parties[tuple(zip(ids,levels))]
                        if normalize(trainers['people'][k][0]) in displayed and trainers['people'][k][0]]
            if not candidates:continue
            key=candidates[0]
            if key in matched:continue
            matched.append(key)
        for index, key in enumerate(matched):
            dest=destinations[min(len(destinations)-1,index*len(destinations)//len(matched))]
            if stem=='santalunecity' and trainers['people'][key][0]=='Rinka':continue  # opening skates belong to the main story
            output[dest].append(int(key))
    # These source tables contain spelling differences between the ROM and the guide.
    # Use the original trainer IDs on the gym floors, including the underground web.
    output.pop('kalos_gym_santalune',None)
    output.update({
        'kalos_gym_santalune_web':[39,40,48],
        'kalos_gym_cyllage':[64,106,63,105],
        'kalos_gym_shalour':[83,147,146,84],
        'kalos_gym_coumarine':[123,124,121,122],
    })
    (ROOT/'content/kalos_route_trainers.json').write_text(json.dumps(output, separators=(',',':'))+'\n')
    print('Matched',sum(map(len,output.values())),'trainer parties across',len(output),'route, cave and Gym zones')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pages',type=Path)
    parser.add_argument('atlas',type=Path)
    args=parser.parse_args()
    run(args.pages,args.atlas)
