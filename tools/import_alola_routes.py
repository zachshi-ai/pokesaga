"""Resolve ordinary trainer identities and physical SM pickup flags against the Alola source atlas."""
from pathlib import Path
import argparse,json,re
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[1]

def collect(atlas,rosters):
    def read(key):return json.loads((atlas/(key+'.json')).read_text())
    search=read('search')
    classic={t['id']:t for t in read('trainers')}
    classes={id:v for id,v in search['trainer_classes']}
    names={i:t for i,t in search['items']}
    ids={t['id'] for z in read('geometry')['zones'] for t in z.get('trainers',[])}
    trainers={}
    for id in ids:
        if id not in classic or classic[id].get('scripted'):continue
        t=classic[id]
        trainers[str(id)]={'class':classes[t['class']]['zh'],'name':t['name']['zh'],'versions':{}}
    for v in ['sun','moon','ultra_sun','ultra_moon']:
        text=(rosters/(v+'.js')).read_text()
        teams=json.JSONDecoder().raw_decode(text[text.index('{"meta"'):])[0]['trainers']
        for k,person in trainers.items():
            old=classic[int(k)]
            matches=[t for t in teams if t['name']==old['name']['en'] and t['trainerClassName']==classes[old['class']]['en']]
            row=next((t for t in matches if t['trainerId']==int(k)),matches[0] if len(matches)==1 else None)
            if row:person['versions'][v]=row['trainerId']
    items=defaultdict(dict)
    for r in read('field_items'):
        d=names.get(r['item'])
        if not d:continue
        code=d['en'].replace('é','e').upper().replace(' ','_').replace("'",'')
        items[str(r['zone'])][str(r['item'])]={'name':d['zh'],'key':code,'qty':r['quantity'],'medicine':int(17<=r['item']<=54),'note':r.get('note',{}).get('en','')}
    out={'trainers':trainers,'items':items}
    (ROOT/'content/alola_routes.json').write_text(json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('atlas',type=Path);p.add_argument('rosters',type=Path);collect(**vars(p.parse_args()))
