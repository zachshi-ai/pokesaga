"""Match Serebii's restaurant course order to the exact X/Y trainer party records."""
import argparse
import json
import re
from pathlib import Path
from bs4 import BeautifulSoup

ROOT=Path(__file__).resolve().parents[1]

def run(page):
    data=json.loads((ROOT/'content/kalos_trainers.json').read_text())
    mode={'Double Battle':'double','Triple Battle':'triple','Rotation Battle':'rotation'}
    out={}
    for table in BeautifulSoup(page.read_bytes(),'html.parser').select('table.dextable')[1:]:
        room=table.find_previous('a',attrs={'name':True})['name']
        style=mode[table.find_previous('b').get_text(strip=True)]
        course=[]
        for row in table.find_all('tr')[1:]:
            cells=row.find_all('td',recursive=False)
            name=cells[0].get_text(strip=True)
            team=[int(m.group(1)) for a in cells[1].find_all('a') if (m:=re.search(r'(\d+)\.shtml',a.get('href','')))]
            turns=int(cells[2].get_text(strip=True).split()[0])
            matches=[i for i,party in data['teams'].items() if data['people'][i][0] in name and sorted(m['species'] for m in party)==sorted(team)]
            if not matches:
                # The guide calls Georges’ Pidgeot a Pidgeotto. Use the ROM party.
                names=[i for i,p in data['people'].items() if p[0] in name and
                       len(data['teams'][i])==len(team) and
                       len(set(team)&{m['species'] for m in data['teams'][i]})>=len(team)-1]
                matches=names
            if not matches:
                matches=[i for i,party in data['teams'].items() if
                         data['people'][i][1] in name and sorted(m['species'] for m in party)==sorted(team)]
            if not matches:raise ValueError((room,style,name,team))
            course.append([int(matches[0]),turns])
        out.setdefault(room,{})[style]=course
    (ROOT/'content/kalos_restaurants.json').write_text(json.dumps(out,separators=(',',':'))+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('page',type=Path)
    run(parser.parse_args().page)
