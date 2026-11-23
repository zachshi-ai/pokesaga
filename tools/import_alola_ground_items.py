"""Build Ultra Sun/Ultra Moon ground pickup differences from the Serebii Alola location tables.
Usage: import_alola_ground_items.py <native atlas cache> <cached Pokéarth location pages>.
Translations and numeric item ids come from the native atlas search index.
"""
import argparse
from collections import Counter,defaultdict
from html import unescape
import json
from pathlib import Path
import re
from import_alola_machines import ROOT,free_tiles

def clean(s):return unescape(re.sub('<[^>]*>','',s)).strip()
def token(s):return re.sub('[^a-z0-9]','',s.lower().replace('é','e'))
def page_for(s):return s.split(' (')[0].lower().replace(' ','').replace('’',"'").replace('é','e')+'.shtml'
def build(atlas,pages):
    look=json.loads((atlas/'search.json').read_text())
    items={token(v['en']):(i,v) for i,v in look['items']}
    locations={i:n['en'] for i,n,_ in look['locations']}
    zone={r['zone']:page_for(locations[r['location']]) for r in json.loads((atlas/'field_items.json').read_text())}
    table={}
    for file in pages.glob('*.shtml'):
        for version,body in re.findall(r'Items - (Sun & Moon|Ultra Sun & Ultra Moon)</u>.*?<table[^>]*>(.*?)</table>',file.read_bytes().decode('utf8','replace'),re.I|re.S):
            counts,ground=table.setdefault(file.name,{}).setdefault(version,(Counter(),[]))
            for tr in re.findall('<tr[^>]*>(.*?)</tr>',body,re.S|re.I):
                td=[clean(x) for x in re.findall('<td[^>]*class="fooinfo"[^>]*>(.*?)</td>',tr,re.I|re.S)]
                if len(td)<2:continue
                key=token(td[0]);note=td[1].lower();counts[key]+=1
                if key not in items or re.search(r'\b(from|gift|give|defeat|battle|purchase|win|sell|buy|daily|receive|awarded|after|show|tree|obtain|totem|trade|reward|handed|return|speaking)\b',note):continue
                if not re.search('hidden|south|north|east|west|ledge|grass|behind|floor|beach|platform|rock|corner|entrance|path|near|beside|under|next to|end of',note):continue
                if not (items[key][0]<327 or items[key][0]>=492) or re.search(r'berry$|iumz$|ite$|memory$|^tm\d|^hm\d|^zygarde',key):continue
                ground.append((key,'hidden' if 'hidden' in note else 'item'))
    maps=[json.loads(p.read_text()) for p in sorted((ROOT/'content/regions/alola/maps').glob('*.json'))]
    files=defaultdict(list)
    source=json.loads((ROOT/'content/alola_routes.json').read_text())['items']
    out=defaultdict(lambda:{'omit':[],'add':[]});used=defaultdict(Counter)
    for m in maps:
        for s in m.get('alola_item_tiles',[]):
            page=zone.get(s['zone']); item=source.get(str(s['zone']),{}).get(str(s['item']))
            if not item or page not in table or 'Ultra Sun & Ultra Moon' not in table[page]:continue
            if m not in files[page]:files[page].append(m)
            key=token(item['key']);flag='a_pick_%d_%d_%d'%(s['zone'],*s['at'])
            if key.startswith('tm'):continue
            if used[page][key]>=table[page]['Ultra Sun & Ultra Moon'][0][key]:
                out[m['id']]['omit'].append(flag)
            else:used[page][key]+=1
    for page,group in files.items():
        # Place new pickups in the same named locality, preserving existing geometry where available.
        ultra=table[page]['Ultra Sun & Ultra Moon'][1];counter=Counter()
        group.sort(key=lambda m:(len(m['id']),m['id']))
        for i,(key,kind) in enumerate(ultra):
            counter[key]+=1
            if counter[key]<=used[page][key]:continue
            item_id,entry=items[key]
            if item_id>=700 and not (key.endswith('ball') or key in ('adrenalineorb','icememory','icestone','terrainextender','protectivepads','maxmalasada','bigmalasada')):continue
            m=group[i%len(group)];candidates=free_tiles(m)
            if not candidates:continue
            used_at={tuple(o['at']) for o in out[m['id']]['add']};candidates=[xy for xy in candidates if tuple(xy) not in used_at]
            if not candidates:continue
            xy=candidates[(i*193+item_id)%len(candidates)]
            symbol=entry['en'].replace('é','e').replace(' ','_').replace("'",'').upper()
            item={'key':symbol,'name':entry['zh'],'qty':1,'medicine':int(17<=item_id<=54),'note':''}
            out[m['id']]['add'].append({'kind':kind,'name':item['name'],'at':xy,'alola_pickup':item,'flag':'a_ultra_pick_%d_%d_%d'%(item_id,*xy)})
    (ROOT/'content/alola_ground.json').write_text(json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n')
    print(sum(len(v['omit']) for v in out.values()),sum(len(v['add']) for v in out.values()))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('atlas',type=Path);p.add_argument('pages',type=Path);build(**vars(p.parse_args()))
