"""Extract HGSS Azalea's four switch configurations and all native ride paths."""
import json
import re
import sys
from pathlib import Path

root=Path(__file__).resolve().parents[1]
source=(Path(sys.argv[1])/'src/field/gymmick/azalea.c').read_text()
paths={}
for name,table in re.findall(r'RouteNode sSpinarak(Route_\w+|InitialPositions)\[\] = \{(.*?)\};',source,re.S):
    paths[name]=[[int(x),int(z)] for x,z in re.findall(r'\{\s*(\d+),\s*(\d+)\s*\}',table)]
routes=[]
for num,table in re.findall(r'sSpinarakRoutes_From(\d+)\[\] = \{(.*?)\};',source,re.S):
    states=[]
    for line in re.findall(r'\{(.*?)\}',table):
        match=re.search(r',\s*(\d+),\s*sSpinarak(Route_\w+)',line)
        states.append([int(match[1]),match[2]] if match else [])
    routes.append(states)
data=json.loads((root/'content/hgss/events.json').read_text())
bank=data['banks'][str(data['headers']['MAP_AZALEA_GYM']['event_bank'])]
result={'stops':paths.pop('InitialPositions'),'pads':[[p['x'],p['z']] for p in bank['coords']],
        'switches':[[p['x'],p['z'],int('015' in p['scriptId'])] for p in bank['bgs']],
        'routes':routes,'paths':paths}
assert len(routes)==12 and all(len(r)==4 for r in routes) and len(paths)==8
(root/'content/hgss/azalea.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
