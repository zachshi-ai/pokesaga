"""Import dynamic gym collision tables, rail positions and switch scripts from Platinum."""
import re
import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import ROOM,TOWN

def symbols(art):
    ids={}
    for label in ('circle','square','triangle','sun','donut','moon','star','heart','bag','tires','yellow','green','blue','lift'):
        image=art.e.metatile('MossdeepCity_Gym',0x20a).copy();d=ImageDraw.Draw(image)
        cream='#f0f4db';navy='#37455b';cyan='#5ad8e0'
        if label=='bag':
            d.line((7,0,7,4),fill=navy,width=2);d.rounded_rectangle((4,3,11,14),radius=3,fill='#c65e4b',outline=navy);d.line((6,5,6,11),fill='#ec9774')
        elif label=='tires':
            for y in (7,3): d.ellipse((2,y,13,y+6),fill='#333d50',outline='#343343');d.ellipse((5,y+1,10,y+3),fill='#969eaa')
        elif label in ('yellow','green','blue','lift'):
            d.rectangle((1,4,14,13),fill=navy);d.rectangle((2,3,13,10),fill={'yellow':'#ebbc54','green':'#73ad6c','blue':'#578dd6','lift':'#cc6e64'}[label],outline=cream);d.line((4,5,10,5),fill=cream)
        else:
            d.rounded_rectangle((1,1,14,14),2,fill=navy,outline=cream)
            if label in ('circle','donut','sun','moon'):
                d.ellipse((4,4,11,11),fill=cyan)
                if label=='donut':d.ellipse((6,6,9,9),fill=navy)
                if label=='moon':d.ellipse((7,2,13,9),fill=navy)
                if label=='sun':
                    for x,y in [(7,2),(7,13),(2,7),(13,7)]:d.point((x,y),fill=cyan)
            elif label=='square': d.rectangle((4,4,11,11),fill=cyan)
            elif label=='triangle': d.polygon([(7,3),(3,11),(12,11)],fill=cyan)
            elif label=='star':d.polygon([(8,2),(9,6),(13,6),(10,9),(11,13),(8,10),(4,13),(5,9),(2,6),(6,6)],fill=cyan)
            else:d.polygon([(3,5),(5,3),(8,5),(11,3),(13,5),(13,7),(8,12),(3,7)],fill=cyan)
        ids[label]=len(art.images);art.images.append(image)
    ids.update(open=art.tile('MossdeepCity_Gym',0x20a),closed=art.tile('MossdeepCity_Gym',0x208),water=art.tile(TOWN,0xa1),plank=art.tile('PetalburgCity_Gym',0x201),ice=art.tile('ShoalCave_LowTideIceRoom',0x38d))
    return ids

def config(src,art,fields):
    text=(src/'src/overlay008/gym_features.c').read_text()
    def body(k):return re.search(r'\b'+k+r'[^;]*?=\s*\{(.*?)\n\};',text,re.S).group(1)
    def nums(s):return [int(i) for i in re.findall(r'\b\d+\b',s)]
    def arrays(k):return [nums(s) for s in re.findall(r'\{([^{}]+)\}',body(k))]
    def pts(k):return [list(map(int,p)) for p in re.findall(r'\.x = (\d+), \.z = (\d+)',body(k))]
    data={}
    data['canalave_city_gym']={'kind':'lift','states':arrays('sCanalaveGymCollisionMaps'),'platforms':[]}
    for x,y,z,tx,ty,tz,fa,fb,start in re.findall(r'\.positionA = \{ \.x = (\d+), \.y = (\d+), \.z = (\d+) \},\s*\.positionB = \{ \.x = (\d+), \.y = (\d+), \.z = (\d+) \},\s*\.floorA = (\d+),\s*\.floorB = (\d+),\s*\.startInPositionB = (\w+)',body('sCanalavePlatformPaths')):
        data['canalave_city_gym']['platforms'].append([int(x),int(z),int(fa),int(tx),int(tz),int(fb),int(start=='TRUE')])
    g=fields['MAP_HEADER_PASTORIA_CITY_GYM']
    data['pastoria_city_gym']={'kind':'water','classes':[[int(x),int(y),int(g['words'][y,x]&255)-85] for y,x in zip(*np.nonzero(np.isin(g['words']&255,[85,86,87])))],
        'buttons':[[e['x'],e['z'],next(i for i,k in enumerate(['Yellow','Green','Blue']) if k in e['script'])] for e in g['bank']['coord_events']]}
    data['eterna_city_gym']={'kind':'clock','states':arrays('sEternaGymClockCollision'),'fountain':arrays('sEternaGymFountainCollision')}
    data['veilstone_city_gym']={'kind':'bags','rails':nums(body('sVeilstoneTileBehaviors')),'bags':pts('sPunchingBagPositions'),'tires':pts('sTireStackPositions')}
    data['snowpoint_city_gym']={'kind':'snow'}
    for i in range(1,4):
        key=f'sunyshore_city_gym_room_{i}'
        ev=fields['MAP_HEADER_'+key.upper()]['bank']['coord_events'];scripts=(src/f'res/field/maps/{key}/scripts.s').read_text()
        buttons=[]
        for e in ev:
            v=re.search(re.escape(e['script'])+r':\s+PressSunyshoreGymButton SUNYSHORE_GYM_BUTTON_(\w+)',scripts).group(1)
            buttons.append([e['x'],e['z'],{'NORMAL':1,'REVERSE':-1,'DOUBLE':2}[v]])
        data[key]={'kind':'gear','buttons':buttons,'regions':arrays(f'sSunyshoreRoom{i}CollisionRegions'),
            'states':[nums(body(f'sSunyshoreRoom{i}State{k}Collisions')) for k in range(4)]}
    for i,shapes in enumerate((['circle','square','triangle'],['sun','donut','moon','star','heart']),1):
        raw=nums(body(f'sTrainerRoom{i}CluePositions'));sx=15 if i==1 else 27
        data[f'hearthome_city_gym_trainer_room_{i}']={'kind':'symbols','doors':[list(p)+[s] for p,s in zip(pts(f'sTrainerRoom{i}Doors'),shapes)],
            'clues':[[j%sx+1,j//sx+3] for j,t in enumerate(raw) if t==0]}
    tiles=symbols(art)
    for k,m in data.items():
        fields['MAP_HEADER_'+k.upper()]['gym']={**m,'tiles':tiles}
