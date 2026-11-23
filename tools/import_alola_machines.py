"""Map the 100 Sun/Moon and Ultra Sun/Ultra Moon TMs onto the shared 2D maps.

Input: cached *-tms.html from pokemondb.net/{sun-moon,ultra-sun-ultra-moon}/tms.
Original physical item coordinates take precedence over adapted positions.
"""
import argparse
from collections import defaultdict, deque
import json
from pathlib import Path
import re
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
NAMES = {"Aether Paradise":"aether_lab","Akala Outskirts":"akala_outskirts","Ancient Poni Path":"ancient_path","Blush Mountain":"blush_mountain","Brooklet Hill":"brooklet","Diglett's Tunnel":"diglett_tunnel","Haina Desert":"haina","Hano Grand Resort":"hano","Hau'oli Cemetery":"cemetery","Hau'oli City":"hauoli","Heahea City":"heahea","Hokulani Observatory":"observatory","Iki Town":"iki","Kala'e Bay":"kalae_bay","Konikoni City":"konikoni","Lake of the Sunne":"lake_sunne","Lush Jungle":"lush","Malie City":"malie","Malie Garden":"malie_garden","Melemele Sea":"melemele_sea","Mount Hokulani":"hokulani","Mount Lanakila":"lanakila","Paniola Ranch":"paniola_ranch","Paniola Town":"paniola","Poni Breaker Coast":"poni_breaker_coast","Poni Coast":"poni_coast","Poni Meadow":"poni_meadow","Poni Plains":"poni_plains","Resolution Cave":"resolution_cave","Royal Avenue":"royal","Sandy Cave":"sandy_cave","Seafolk Village":"seafolk","Seaward Cave":"seaward_cave","Shady House":"shady_house","Ten Carat Hill":"hill","Vast Poni Canyon":"canyon","Verdant Cavern":"cavern","Wela Volcano Park":"wela"}
DIRECTIONS = [(0,1),(1,0),(-1,0),(0,-1)]

def free_tiles(m):
    obstacles = set(tuple(x['at']) for key in ('objects','npcs','warps','alola_item_tiles','alola_trainer_tiles') for x in m.get(key,[]))
    obstacles.update(map(tuple,m['alola_anchors'].values()))
    p=m['physics']; collision=p['collision'];water=p.get('water')
    seen={tuple(m['spawn'])}; queue=deque(seen); result=[]
    while queue:
        x,y=queue.popleft()
        if (x,y) not in obstacles and sum((x+dx,y+dy) not in obstacles for dx,dy in DIRECTIONS)>=3:result.append([x,y])
        for dx,dy in DIRECTIONS:
            xx,yy=x+dx,y+dy
            if 0<=yy<len(collision) and 0<=xx<len(collision[yy]) and not collision[yy][xx] and not (water and water[yy][xx]) and (xx,yy) not in seen:
                queue.append((xx,yy));seen.add((xx,yy))
    return result

def build(folder):
    maps={p.stem[6:]:json.loads(p.read_text()) for p in (ROOT/'content/regions/alola/maps').glob('alola_*.json')}
    routes=json.loads((ROOT/'content/alola_routes.json').read_text())
    spots=defaultdict(list)
    for mid,m in maps.items():
        for s in m.get('alola_item_tiles',[]):
            item=routes['items'].get(str(s['zone']),{}).get(str(s['item']),{})
            if item.get('key','').startswith('TM'):spots[int(item['key'][2:])].append((mid,s['at']))
    allrows={}
    for v,file in [('17','sun-moon'),('18','ultra-sun-ultra-moon')]:
        taken=defaultdict(set);tm={}
        for tr in BeautifulSoup((folder/(file+'-tms.html')).read_bytes(),'html.parser').select('table')[0].select('tbody tr'):
            cells=[td.get_text(' ',strip=True) for td in tr.select('td')]
            n=int(cells[0]);loc=cells[-1];place=loc.split(' (')[0];detail=loc[len(place):].lower()
            mid=place[6:] if place.startswith('Route ') else NAMES[place]
            if n==1:mid='school'
            if n==10:mid='nursery'
            if n==29:mid='aether_conservation'
            if n==44:mid='thrifty_mart'
            if n==46:mid='cavern_den'
            if n==48:mid='hauoli_mall'
            if n==90:mid='lab'
            if 'farthest hollow' in detail:mid='farthest_hollow'
            shop='pokémart' in detail or 'tm shop' in detail
            gift=(n in (1,10,12,21,27,29,43,44,45,48,54,56,58,60,63,67,76,87,90,92,94,95,96,98) or (v=='17' and n==77) or (v=='18' and n in (8,19,66,75,82))) and not shop
            row={'map':'alola_'+mid,'kind':'shop' if shop else 'gift' if gift else 'field'}
            if shop:
                price=re.search(r'\$([\d,]+)',detail);row['price']=int(price[1].replace(',','')) if price else 50000
            if n==44:row['price']=1000
            row['require']={1:'a_school',29:'a_nihilego',54:'a_hala',67:'a_grass',90:'a_champion',92:'a_champion'}.get(n,'')
            if v=='18' and n==87:row['require']='a_champion'
            for ride,code in [('tauros','tauros'),('machamp shove','machamp'),('sharpedo jet','sharpedo')]:
                if ride in detail:row['require']='a_ride_'+code
            if n in (48,56):row['night']=True
            if 'defeat all trainers' in detail or 'beat trial guide' in detail or n in (58,60,94,96,98) or (v=='18' and n in (19,82,95)):
                row['route_challenge']=True
            if n in (12,43,54,67,87,90,92):row['speaker']={12:'骷髅队成员',43:'阿克罗玛',54:'库库伊博士',67:'库库伊博士',87:'古兹马的妈妈',90:'库库伊博士',92:'卡希丽'}[n]
            if n==29:row['speaker']='碧珂'
            if n==44:row['speaker']='引梦貘人'
            if n==48:row['speaker']='清洁员';row['require']='a_hala'
            if n==75 and v=='18':row['speaker']='剧团演员'
            if n in (8,66) and v=='18':row['speaker']='黑带训练家'
            if n==63 and v=='18':row['next_day']=True
            if row['kind']=='field':
                original=next(((m,xy) for m,xy in spots[n] if m==mid or m.startswith(mid+'_')),None)
                if original:row['map'],row['at']='alola_'+original[0],original[1]
                elif n==24 and v=='18':row['native']=True
                else:
                    options=[xy for xy in free_tiles(maps[mid]) if tuple(xy) not in taken[mid]]
                    pos=options[(n*149)%len(options)];taken[mid].add(tuple(pos));row['at']=pos
            tm[str(n)]=row
        assert set(tm)==set(map(str,range(1,101)))
        allrows[v]=tm
    (ROOT/'content/alola_machines.json').write_text(json.dumps(allrows,ensure_ascii=False,separators=(',',':'))+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('folder',type=Path);build(parser.parse_args().folder)
