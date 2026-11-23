"""Place ordinary X/Y field items on accessible cells of their mapped route or dungeon.

TMs, character gifts, timed stones and version events have separate scripts. Pokéarth's
location and direction descriptions are used here; these are not original object coordinates.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import zlib

import numpy as np
from bs4 import BeautifulSoup
from scipy.ndimage import label
from import_kalos_routes import CAVES, ROOT

HEAL = {'Potion':'伤药','Super Potion':'好伤药','Hyper Potion':'厉害伤药','Max Potion':'全满药',
        'Full Restore':'全复药','Antidote':'解毒药','Paralyze Heal':'解麻药','Full Heal':'万灵药',
        'Awakening':'解眠药','Revive':'活力碎片','Max Revive':'活力块','Burn Heal':'灼伤药',
        'Ice Heal':'解冻药','Ether':'PP 单项小补剂','Elixir':'PP 多项小补剂','Max Ether':'PP 单项全补剂',
        'Max Elixir':'PP 多项全补剂','Rare Candy':'神奇糖果'}
BALLS = {'Poke Ball':'精灵球','Great Ball':'超级球','Ultra Ball':'高级球','Timer Ball':'计时球',
         'Luxury Ball':'豪华球','Repeat Ball':'重复球','Nest Ball':'巢穴球','Net Ball':'捕网球',
         'Dive Ball':'潜水球','Heal Ball':'治愈球','Quick Ball':'先机球','Dusk Ball':'黑暗球'}
REP = {'Repel':'除虫喷雾','Super Repel':'白银喷雾','Max Repel':'黄金喷雾','Escape Rope':'离洞绳'}
TREASURE = {'Tiny Mushroom':'小蘑菇','Big Mushroom':'大蘑菇','Nugget':'金珠','Pearl':'珍珠',
            'Big Pearl':'大珍珠','Stardust':'星砂','Star Piece':'星之碎片','Pretty Wing':'美丽之羽'}

def item_record(name, evo, held, berries):
    key=name.upper().replace(' ','_').replace("'",'')
    if key in evo:return [evo[key],'evo']
    if key in held:return [held[key],'held',key]
    if key.endswith('_BERRY') and key[:-6].lower() in berries:
        return [berries[key[:-6].lower()]['name'],'berry',key[:-6].lower()]
    for book,category in [(HEAL,'heal'),(BALLS,'ball'),(REP,'other'),(TREASURE,'other')]:
        if name in book:return [book[name],category]
    return []

def location(rows, desc, seed):
    coords=np.array(rows)
    low=coords.min(0); high=coords.max(0)
    target=low+(high-low)*[.16+((seed>>8)&255)/375,.16+(seed&255)/375]
    if 'north' in desc:target[1]=np.quantile(coords[:,1],.15)
    if 'south' in desc:target[1]=np.quantile(coords[:,1],.85)
    if 'west' in desc:target[0]=np.quantile(coords[:,0],.15)
    if 'east' in desc:target[0]=np.quantile(coords[:,0],.85)
    return tuple(coords[np.argmin(((coords-target)**2).sum(1))])

def run(pages):
    data=ROOT/'content'
    evo=json.loads((data/'evo_items.json').read_text())
    held={i['key']:i['name'] for i in json.loads((data/'items.json').read_text())}
    berries=json.loads((data/'berries.json').read_text())
    areas={f'route{i}':'kalos_'+str(i) for i in range(2,23)}
    areas.update(dict(zip(CAVES, ('kalos_forest','kalos_cave','kalos_glitter','kalos_reflection','kalos_frost','kalos_victory','kalos_terminus_cave','kalos_lost_hotel','kalos_azure'))))
    output=defaultdict(list)
    for stem,mid_name in areas.items():
        md=json.loads((data/'regions/kalos/maps'/(mid_name+'.json')).read_text())
        physics=md['physics']; grid=np.array(physics['collision'])==0
        if 'water' in physics:grid &= np.array(physics['water'])==0
        blocked={tuple(x['at']) for group in ('objects','warps','npcs') for x in md[group]}|{tuple(a) for a in md['kalos_anchors'].values()}|{tuple(md['spawn'])}
        groups,_=label(grid)
        counts=np.bincount(groups.ravel());counts[0]=0
        rows=[tuple(x) for x in np.argwhere(groups==counts.argmax())[:,::-1] if tuple(x) not in blocked]
        soup=BeautifulSoup((pages/(stem+'.html')).read_bytes(),'html.parser',from_encoding='windows-1252')
        section=soup.find('a',attrs={'name':'items'})
        if not section:continue
        for n,tr in enumerate(section.find_next('table').select('tr')[1:]):
            cols=tr.find_all('td',recursive=False)
            if len(cols)<3 or not rows:continue
            name=cols[1].get_text(' ',strip=True)
            desc=cols[2].get_text(' ',strip=True).lower()
            if any(word in desc for word in ('given',' gift','trade','purchase','after defeat','after beating','from ','hotel guest','daily','sold','shop','berry tree')):continue
            record=item_record(name,evo,held,berries)
            if not record:continue
            point=location(rows,desc,zlib.crc32((stem+str(n)+name).encode()));rows.remove(point)
            gates=[k for k in ('cut','strength','waterfall','surf','rock smash') if k in desc]
            kind='hidden' if 'dowsing' in desc or 'hidden' in desc else 'item'
            output[mid_name].append({'kind':kind,'at':list(map(int,point)),'flag':f'k_pick_{stem}_{n}',
                                     'kalos_item':record,'requires_moves':[k.upper().replace(' ','_') for k in gates]})
    (data/'kalos_pickups.json').write_text(json.dumps(output,ensure_ascii=False,separators=(',',':'))+'\n')
    print('Placed',sum(map(len,output.values())),'items across',len(output),'locations')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pages',type=Path)
    run(parser.parse_args().pages)
