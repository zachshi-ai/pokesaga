"""Import the natural berry piles from each edition's Pokéarth location tables."""
from collections import defaultdict
from html import unescape
import json,re,argparse
from pathlib import Path
from import_alola_machines import ROOT,free_tiles

def load(pages):
    maps={p.stem[6:]:json.loads(p.read_text()) for p in (ROOT/'content/regions/alola/maps').glob('alola_*.json')}
    berries=json.loads((ROOT/'content/berries.json').read_text())
    result=defaultdict(dict)
    for page,mid in [('route2','2'),('route3','3'),('route4','4'),('route5','5'),('route8','8'),('route10','10'),('route16','16'),('route17','17'),('secludedshore','secluded_shore'),('berryfields','berry_fields'),('poniwilds','wilds'),('poniplains','poni_plains')]:
        doc=(pages/(page+'.shtml')).read_bytes().decode('utf8','replace')
        for edition,t in re.findall(r'Items - (Sun & Moon|Ultra Sun & Ultra Moon)</u>.*?<table[^>]*>(.*?)</table>',doc,re.S):
            groups=defaultdict(set)
            for tr in re.findall('<tr[^>]*>(.*?)</tr>',t,re.S|re.I):
                cells=[unescape(re.sub('<[^>]+>','',s)).strip() for s in re.findall('<td[^>]*class="fooinfo"[^>]*>(.*?)</td>',tr,re.S|re.I)]
                if len(cells)<2:continue
                key=cells[0].lower().removesuffix(' berry'); desc=cells[1].lower()
                if key not in berries or 'tree' not in desc:continue
                comparable=desc.replace('-',' ').replace('north east','northeast').replace('north west','northwest')
                part=next((w for w in ['northeast','northwest','east','west'] if w in comparable),'center') if mid in ('wilds','secluded_shore','poni_plains') else 'center'
                groups[part].add(key)
            if not groups:continue
            opts=free_tiles(maps[mid]);piles=[]
            # Use reachable open patches near the documented end of the map, leaving through paths clear.
            for i,(part,kinds) in enumerate(sorted(groups.items())):
                w,h=maps[mid]['size'];target=(w*(.8 if 'east' in part else .2 if 'west' in part else .54),h*(.2 if 'north' in part else .54))
                used=[p['at'] for p in piles]
                at=min((xy for xy in opts if all(abs(xy[0]-a[0])+abs(xy[1]-a[1])>3 for a in used)),key=lambda xy:(xy[0]-target[0])**2+(xy[1]-target[1])**2)
                piles.append({'kind':'berry_tree','name':'树果堆','at':at,'alola_pile':sorted(kinds),'pile_key':'a_berry_'+mid+'_'+part})
            result['17' if edition=='Sun & Moon' else '18']['alola_'+mid]=piles
    (ROOT/'content/alola_berries.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path);load(parser.parse_args().folder)
