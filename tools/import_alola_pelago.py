"""Import versioned Pelago visitor weights and berry growth/yield from the two in-game guide tables."""
import json,re,sys
from pathlib import Path
from bs4 import BeautifulSoup
ROOT=Path(__file__).resolve().parents[1]
def read_page(path):
    visitors=[];berries={}
    for table in BeautifulSoup(path.read_bytes(),'html.parser').find_all('table'):
        rows=table.find_all('tr',recursive=False)
        if not rows:continue
        head=rows[0].get_text(' ',strip=True)
        if head.startswith('No. Pic Name') and 'Rarity' in head:
            for row in rows[2:]:
                text=row.get_text(' ',strip=True)
                sid=re.match(r'#(\d+)',text)
                if not sid:continue
                weights=[round(float(q)*100) for q in re.findall(r'([.\d]+)%',text)]
                assert len(weights)==5,(sid,weights)
                visitors.append([int(sid.group(1)),weights])
        if head.startswith('Picture Berry Time'):
            for row in rows[1:]:
                match=re.fullmatch(r'(.+) Berry (\d+) (\d+)-(\d+)',row.get_text(' ',strip=True))
                if match:berries[match[1].lower()]=[int(n) for n in match.groups()[1:]]
    return visitors,berries
if __name__=='__main__':
    folder=Path(sys.argv[1]);v={};berries={}
    for tag,src in [('sm','sunmoon'),('us','ultrasunultramoon')]:
        p=folder/('pelago-'+tag+'.html')
        if not p.exists():
            import subprocess
            subprocess.run(['curl','--fail','--location','--silent','--retry','3','https://www.serebii.net/'+src+'/pokepelago.shtml','-o',str(p)],check=True)
        v[tag],b=read_page(p);berries.update(b)
    assert min(map(len,v.values()))>=20 and len(berries)>=50
    (ROOT/'content/alola_pelago.json').write_text(json.dumps({'visitors':v,'berries':berries},indent=1)+'\n')
