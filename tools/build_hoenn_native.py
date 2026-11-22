#!/usr/bin/env python3
"""Compile the native Hoenn maps from pret/pokeemerald 9103e529."""
import argparse
import base64
import json
import re
import zlib
from collections import Counter
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image
from hoenn_passages import record
from hoenn_mechanisms import compile_mechanisms
from hoenn_water_tiles import WaterTiles
from bake_emerald_field import Atlas, Emerald, normalized

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "content/hoenn_native"
ART = ROOT / "assets/hoenn_native"
ALIASES = {
    "LittlerootTown": "littleroot_town", "Route101":"route101",
    "LittlerootTown_ProfessorBirchsLab":"littleroot_birch_lab",
    **{f"LittlerootTown_{character}House_{floor}F":f"littleroot_{side}_home_{floor}f"
       for character,side in (("Brendans","west"),("Mays","east")) for floor in (1,2)},
    **{f"Route{n}": f"hoenn_{n}" for n in range(102,135)},
    **{name:"hoenn_"+alias for name,alias in (("OldaleTown","oldale"),("DewfordTown","dewford"),
       ("LavaridgeTown","lavaridge"),("FallarborTown","fallarbor"),("VerdanturfTown","verdanturf"),
       ("PacifidlogTown","pacifidlog"),("PetalburgCity","petalburg"),("SlateportCity","slateport"),
       ("MauvilleCity","mauville"),("RustboroCity","rustboro"),("FortreeCity","fortree"),
       ("LilycoveCity","lilycove"),("MossdeepCity","mossdeep"),("SootopolisCity","sootopolis"),
       ("EverGrandeCity","ever_grande"),("MtChimney","chimney"),("DesertRuins","desert_ruins"),
       ("RustboroCity_DevonCorp_1F","devon"),("FieryPath","fiery"),
       ("EverGrandeCity_PokemonLeague_1F","league"),("GraniteCave_1F","granite"),
       ("MeteorFalls_1F_1R","meteor"),("SlateportCity_OceanicMuseum_1F","museum"),
       ("CaveOfOrigin_Entrance","origin"),("MtPyre_1F","pyre"),("RusturfTunnel","rusturf"),
       ("SeafloorCavern_Entrance","seafloor"),("ShoalCave_HighTideEntranceRoom","shoal"),
       ("SkyPillar_Entrance","sky_pillar"),("MossdeepCity_SpaceCenter_1F","space_center"),
       ("VictoryRoad_1F","victory"),("Route119_WeatherInstitute_1F","weather"),
       ("PetalburgWoods","woods"))}
}

def write(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")

def read(path):
    return json.loads(path.read_text())

def raw_index(source):
    # The old Ruby/Sapphire-only maps have no reachable entrance in Emerald.
    maps = {m["id"]:m for p in sorted((source / "data/maps").glob("*/map.json"))
            if (m:=read(p)) and "Unused" not in m["name"] and "Prototype" not in m["name"]}
    # Emerald always replaces the unused pre-release Route 131 on transition.
    maps['MAP_ROUTE131']['layout']='LAYOUT_ROUTE131_SKY_PILLAR'
    by_name={m['name']:m for m in maps.values()}
    for m in maps.values():
        shared=m.get('shared_events_map')
        if not shared and m['name'].startswith('ShoalCave_HighTide'):
            shared=m['name'].replace('HighTide','LowTide')
        if shared:
            for typ in ('object_events','warp_events','bg_events','coord_events'):
                if typ not in m or not m[typ]:m[typ]=by_name[shared].get(typ) or []
    ids = {key:ALIASES.get(m["name"],"em_"+key[4:].lower()) for key,m in maps.items()}
    missing=set(ALIASES)-{m["name"] for m in maps.values()}
    assert not missing,missing
    write(DEST/"index.json",ids)
    return maps,ids

def pack(array):
    return base64.b64encode(zlib.compress(array.astype("<u2").tobytes(),9)).decode()

def source_scripts(source):
    paths=[*source.glob("data/maps/*/scripts.inc"),*source.glob("data/scripts/*.inc")]
    text="\n".join(p.read_text() for p in paths)
    return dict(re.findall(r"^(\w+)::?[^\n]*\n((?:[ \t][^\n]*\n)*)",text,re.M))

class FieldArt:
    def __init__(self,source):
        self.e=Emerald(source)
        self.animations=WaterTiles(self.e)
        sec=source/'data/tilesets/secondary/secret_base'
        self.e.dirs['secretbase']=source/'data/tilesets/primary/secret_base'
        for d in sec.iterdir():
            if d.is_dir():self.e.dirs['secretbase'+normalized(d.name)]=sec
        self.layouts={l['id']:l for l in self.e.layouts.values()}
        enum=(source/'include/constants/metatile_behaviors.h').read_text()
        names=re.findall(r'^\s*(MB_[A-Z_0-9]+)\s*,',enum,re.M)
        table=(source/'src/metatile_behavior.c').read_text()
        attrs=dict(re.findall(r'\[(MB_\w+)\]\s*=\s*([^,]+),',table))
        self.water=[i for i,n in enumerate(names) if 'TILE_FLAG_SURFABLE' in attrs.get(n,'')]
        self.grass=[i for i,n in enumerate(names) if 'TILE_FLAG_HAS_ENCOUNTERS' in attrs.get(n,'') and i not in self.water]
        self.atlas=Atlas()
        self.atlas.add(Image.new('RGBA',(16,16)))
    @lru_cache(None)
    def rows(self,key):
        l=self.layouts[key]
        w,h=l['width'],l['height']
        raw=np.fromfile(self.e.source/l['blockdata_filepath'],dtype='<u2',count=w*h).reshape(h,w)
        blocks=raw&1023
        primary,secondary=l['primary_tileset'],l['secondary_tileset']
        attr=np.zeros(1024,np.uint16)
        for off,ts in [(0,primary),(512,secondary)]:
            folder=self.e.dirs[normalized(ts.removeprefix('gTileset_'))]
            a=np.fromfile(folder/'metatile_attributes.bin',dtype='<u2')
            attr[off:off+len(a)]=a
        behavior=attr[blocks]&255
        solid=(raw>>10)&3
        elevation=raw>>12
        phys={'size':[w,h],'behavior':behavior.tolist(),'collision':solid.tolist(),'elevation':elevation.tolist()}
        for name,nums in [('water',self.water),('grass',self.grass),('counter',[0x80]),('waterfall',[0x13]),('deep',[0x11,0x12,0x14])]:
            layer=np.isin(behavior,nums)
            if np.any(layer): phys[name]=layer.astype('B').tolist()
        for name,start,bits in [('ledge',0x38,[4,8,1,2,16,32,64,128]),('dirblock',0x30,[8,4,2,1,10,6,9,5]),('slide',0x44,[4,8,1,2]),('current',0x50,[4,8,1,2])]:
            mask=np.zeros(256,np.uint8)
            mask[start:start+len(bits)]=bits
            if np.any(mask[behavior]): phys[name]=mask[behavior].tolist()
        return phys,blocks,attr,primary,secondary
    @lru_cache(None)
    def tile_id(self,primary,secondary,mid,above=False):
        original = self.atlas.add(self.e.tile(primary,secondary,mid,above))
        return self.animations.tile(primary,secondary,mid,above) or original

    @lru_cache(None)
    def art(self,key):
        phys,blocks,attr,primary,secondary=self.rows(key)
        ground=np.zeros(1024,np.uint16)
        top=np.zeros(1024,np.uint16)
        for i in np.unique(blocks):
            i=int(i)
            ground[i]=self.tile_id(primary,secondary,i)
            if (attr[i]>>12) in (0,2):
                top[i]=self.tile_id(primary,secondary,i,True)
        plan=dict(s=phys['size'],t=pack(ground[blocks]),p=[],source="pokeemerald")
        if np.any(top[blocks]):plan['a']=pack(top[blocks])
        return plan

def events(x,y):
    return [int(x),int(y)]

def xy(e):
    return events(e['x'],e['y'])

def to(mid,at,**kw):
    return dict(region='hoenn',map=mid,at=at,hoenn_native=True,**kw)

def trigger(value):
    return {0x69:'door',0x62:'right',0x63:'left',0x64:'up',0x65:'down',0x6d:'down',0x1c:'down'}.get(value,'step')

def inside(p,phys):
    x,y=p
    return 0<=x<phys['size'][0] and 0<=y<phys['size'][1]

def connect(phys,destination,d,offset):
    w,h=phys['size']; tw,th=destination['size']
    for i in range(w if d in ('up','down') else h):
        if d=='up': a,b=[i,0],[i-offset,th-1]
        elif d=='down':a,b=[i,h-1],[i-offset,0]
        elif d=='left':a,b=[0,i],[tw-1,i-offset]
        else:a,b=[w-1,i],[0,i-offset]
        if not inside(b,destination):continue
        x,y=a;tx,ty=b
        if phys['collision'][y][x] or destination['collision'][ty][tx]:continue
        se=phys['elevation'][y][x];de=destination['elevation'][ty][tx]
        if se not in (0,15,de) and de not in (0,15):continue
        yield a,b

def landing(phys,e):
    x,y=xy(e)
    kind=trigger(phys['behavior'][y][x])
    if kind=='door' and y+1<phys['size'][1]:
        return [x,y+1],{'arrival_from':[x,y],'facing':'down'}
    return [x,y],{}

def safe_arrivals(maps):
    """Step out of solid doorframes and occupied sand traps onto their adjacent floor."""
    def occupied_tiles(row):
        return {tuple(n["at"]) for n in row["npcs"] if not n.get("initially_hidden", False)}
    occupied = {mid: occupied_tiles(row) for mid, row in maps.items()}
    def resolve(target):
        mid = target.get("map")
        if target.get("region") != "hoenn" or mid not in maps:
            return
        field = maps[mid]
        grid = field["physics"]["collision"]
        x, y = map(int, target["at"])
        w, h = field["size"]
        def free(i,j):
            return 0 <= i < w and 0 <= j < h and not grid[j][i] and (i,j) not in occupied[mid]
        if free(x,y):
            return
        for distance in (1,2):
            for dx,dy in ((0,1),(0,-1),(-1,0),(1,0)):
                i,j = x+dx*distance,y+dy*distance
                if free(i,j):
                    target["at"] = [i,j]
                    target.pop("arrival_from",None)
                    return
        # The unused e-Reader basement points inside a solid wall on the ground floor.
        target["at"] = field["spawn"].copy()
        target.pop("arrival_from",None)
    for row in maps.values():
        for warp in row["warps"]:
            dest = warp["to"]
            resolve(dest)
            if "remember_passage" in dest:
                resolve(dest["remember_passage"]["destination"])


def source_text(script,scripts,depth=0):
    if depth>2:return ''
    body=scripts.get(script,'')
    match=re.search(r'\bmsgbox (\w+)|\bmessage (\w+)',body)
    if match:
        label=next(s for s in match.groups() if s)
        raw=scripts.get(label,'')
        value=''.join(re.findall(r'\.string "([^"]*)"',raw))
        return value.replace('\\p','\n').replace('\\n',' ').replace('\\l',' ').replace('$','').replace('{PLAYER}','小悠').replace('{RIVAL}','小遥').replace('{KUN}','')
    jump=re.search(r'^\s*goto (\w+)',body,re.M)
    return source_text(jump[1],scripts,depth+1) if jump else ''

def native_wild(source):
    species={r['key']:r['id'] for r in read(ROOT/'content/species.json')}
    group=read(source/'src/data/wild_encounters.json')['wild_encounter_groups'][0]
    rates={r['type']:r['encounter_rates'] for r in group['fields']}
    result={}
    for m in group['encounters']:
        if not m.get('map') or m['map'] in result: continue
        row={}
        for key,name in [('land_mons','encounters'),('water_mons','water_encounters'),('fishing_mons','fishing_encounters'),('rock_smash_mons','rock_encounters')]:
            if key not in m:continue
            mons=m[key]['mons']
            row[name]=[dict(species=species[e['species'][8:]],min=e['min_level'],max=e['max_level'],weight=rates[key][i]) for i,e in enumerate(mons) if e['species'][8:] in species]
            if key=='land_mons':row['encounter_rate']=min(0.35,m[key]['encounter_rate']/100)
        result[m['map']]=row
    return result
def trainers(source):
    species={r['key']:r['id'] for r in read(ROOT/'content/species.json')}
    parties={}
    for k,body in re.findall(r'(sParty_\w+)\[\] = \{(.*?)\n\};',(source/'src/data/trainer_parties.h').read_text(),re.S):
        team=[]
        for lv,sp in re.findall(r'\.lvl\s*=\s*(\d+),\s*\.species\s*=\s*SPECIES_(\w+)',body):
            if sp in species: team.append(dict(species=species[sp],level=int(lv)))
        parties[k]=team
    result={}
    for k,body in re.findall(r'\[(TRAINER_\w+)\]\s*=\s*\{(.*?)\n    \},',(source/'src/data/trainers.h').read_text(),re.S):
        p=re.search(r'\.party = \w+\((sParty_\w+)\)',body)
        n=re.search(r'trainerName = _\("([^"]+)"\)',body)
        if p and n and parties.get(p[1]):result[k]=(n[1].title(),parties[p[1]])
    return result

class Inhabitants:
    def __init__(self,source,scripts):
        self.scripts=scripts
        self.trainers=trainers(source)
        self.hidden=set(re.findall(r'\bsetflag (FLAG_\w+)',(source/'data/scripts/new_game.inc').read_text()))
        self.hidden.update(re.findall(r'\bsetflag (FLAG_\w+)',scripts.get('InsideOfTruck_EventScript_SetIntroFlagsMale','')))
        self.gfx_used=set()
        self.berries=dict(re.findall(r'setberrytree\s+(\w+),\s+ITEM_TO_BERRY\(ITEM_(\w+)_BERRY\)',(source/'data/scripts/new_game.inc').read_text()))
    def item(self,key):
        from gen_world_extras import ITEM_ZH
        name,category,_=ITEM_ZH.get(key,(key.removeprefix("ITEM_").replace("_"," ").title(),"other",0))
        return dict(item=key,name=name,category=category)
    def rows(self,m):
        npcs=[]; objects=[]
        for ix,e in enumerate(m.get('object_events') or [],1):
            if 'graphics_id' not in e: continue
            gfx=e['graphics_id'];script=e['script'];flag=e['flag'];ty=e['movement_type']
            face=next((d for d in ('up','left','right','down') if ty.endswith('_'+d.upper())),'down')
            row=dict(at=xy(e),source_script=script,source_flag=flag,source_gfx=gfx,source_id=ix,local_id=ix,
                     source_local=e.get('local_id',''),facing=face,movement=ty,elevation=e['elevation'],initially_hidden=flag in self.hidden)
            code=self.scripts.get(script,''); item=re.search(r'\bfinditem (ITEM_\w+)',code)
            if item:
                row.update(kind='item',flag=flag,**self.item(item[1]));objects.append(row);continue
            kind={'OBJ_EVENT_GFX_CUTTABLE_TREE':'cut','OBJ_EVENT_GFX_BREAKABLE_ROCK':'rock','OBJ_EVENT_GFX_PUSHABLE_BOULDER':'boulder','OBJ_EVENT_GFX_BERRY_TREE':'berry_tree'}.get(gfx)
            if kind:
                row['kind']=kind
                if kind=='berry_tree':
                    row['berry']=self.berries.get(e['trainer_sight_or_berry_tree_id'],'ORAN')
                objects.append(row);continue
            key=gfx.removeprefix('OBJ_EVENT_GFX_')
            row['name']={'MOM':'妈妈','MOM_1':'妈妈','PROF_BIRCH':'小田卷博士','BIRCHS_BAG':'博士的背包','MAY_NORMAL':'小遥','RIVAL_MAY_NORMAL':'小遥','MAN_1':'镇民','WOMAN_1':'镇民','YOUNGSTER':'短裤小子','NURSE':'护士','MART_EMPLOYEE':'店员','NORMAN':'千里','ARCHIE':'水梧桐','MAXIE':'赤焰松','STEVEN':'大吾','WALLACE':'米可利','WALLY':'满充','ROXANNE':'杜鹃','BRAWLY':'藤树','WATTSON':'铁旋','FLANNERY':'亚莎','WINONA':'娜琪','TATE':'枫','LIZA':'南','JUAN':'亚当','RAYQUAZA':'烈空坐','GROUDON_1':'固拉多','KYOGRE_1':'盖欧卡','MOVING_BOX':'搬家纸箱','ZIGZAGOON_1':'蛇纹熊','ITEM_BALL':'精灵球'}.get(key,'训练家' if 'TRAINER_TYPE_NORMAL' in e['trainer_type'] else '居民')
            if (key=='NURSE' and ('PokemonCenter' in m['name'] or 'PokemonLeague' in m['name'] or 'BattleFrontier' in m['name'])) or 'PkmnCenterNurse' in code:row.update(name='护士',heal=True)
            if 'pokemart' in code or (key=='MART_EMPLOYEE' and ('Mart' in m['name'] or 'DepartmentStore' in m['name'])): row.update(name='店员',shop=True)
            msg=source_text(script,self.scripts)
            if msg:row['lines']=[msg]
            match=re.search(r'\btrainerbattle_\w+\s+(TRAINER_\w+)',code)
            if match and match[1] in self.trainers and not match[1].startswith("TRAINER_GABBY_AND_TY_"):
                name,team=self.trainers[match[1]]
                row.update(name=name,source_trainer=match[1],battle=dict(team=team))
            npcs.append(row);self.gfx_used.add(gfx)
        for e in m.get('bg_events') or []:
            row=dict(at=xy(e),source_script=e.get('script',''),kind='sign',native_fixture=True)
            if e['type']=='hidden_item':
                row.update(kind='hidden',flag=e.get('flag',''),**self.item(e['item']))
            elif e['type']=='secret_base':
                site=e['secret_base_id']
                row.update(source_script='EmeraldBaseSite',secret_site=site,room='em_'+site.rsplit('_',1)[0].lower())
            elif e['type']=='sign':
                row['text']=source_text(e.get('script',''),self.scripts) or ''
            else: continue
            objects.append(row)
        return npcs,objects

def actors(source,used):
    root=source/'src/data/object_events'
    graphics=(root/'object_event_graphics.h').read_text()
    ptr=dict(re.findall(r'\[(OBJ_EVENT_GFX_\w+)\]\s*=\s*&(gObjectEventGraphicsInfo_\w+)',(root/'object_event_graphics_info_pointers.h').read_text()))
    infos=dict(re.findall(r'\b(gObjectEventGraphicsInfo_\w+) = \{(.*?)\n\};',(root/'object_event_graphics_info.h').read_text(),re.S))
    frame={name:re.findall(r'\b(?:overworld_frame|obj_frame_tiles)\((\w+)(?:, \d+, \d+, (\d+))?\)',body)[:9] for name,body in re.findall(r'\b(sPicTable_\w+)\[\] = \{(.*?)\n\};',(root/'object_event_pic_tables.h').read_text(),re.S)}
    image_files=dict(re.findall(r'(gObjectEventPic_\w+)\[.*?\] = INCGFX_U32\("([^"]+)"',graphics))
    pal_files=dict(re.findall(r'(gObjectEventPal_\w+)\[.*?\] = INCGFX_U16\("([^"]+)"',graphics))
    palettes={tag:pal_files.get(pal) for pal,tag in re.findall(r'\{(gObjectEventPal_\w+),\s*(OBJ_EVENT_PAL_TAG_\w+)\}',(source/'src/event_object_movement.c').read_text())}
    catalog={}; sprites={}
    for gfx in sorted(used|{'OBJ_EVENT_GFX_RIVAL_MAY_NORMAL','OBJ_EVENT_GFX_MAY_NORMAL','OBJ_EVENT_GFX_BRENDAN_NORMAL','OBJ_EVENT_GFX_VIGOROTH_CARRYING_BOX','OBJ_EVENT_GFX_RAYQUAZA','OBJ_EVENT_GFX_GROUDON_FRONT','OBJ_EVENT_GFX_KYOGRE_FRONT'}):
        body=infos.get(ptr.get(gfx),'')
        if not body:continue
        pic=re.search(r'\.images = (\w+)',body)
        poses=frame.get(pic[1],[]) if pic else []
        filename=image_files.get(poses[0][0]) if poses else None
        if not filename or not (source/filename).exists():continue
        img=Image.open(source/filename)
        w=int(re.search(r'\.width = (\d+)',body)[1]);h=int(re.search(r'\.height = (\d+)',body)[1])
        tag=re.search(r'\.paletteTag = (\w+)',body)[1];pal=palettes.get(tag)
        if pal and (source/pal).exists():
            colors=[int(v) for line in (source/pal).read_text().splitlines()[3:19] for v in line.split()]
            img.putpalette(colors+[0]*(768-len(colors)))
        # The lake encounter uses rendered cutscene palettes and side profiles.
        # The overworld sheets otherwise share two muted palettes with town NPCs.
        legendary = {'OBJ_EVENT_GFX_KYOGRE_SIDE':('kyogre',(0,1,1,1,4,12,13,5,7,8,6,10,2,4,10,15)),
                     'OBJ_EVENT_GFX_GROUDON_SIDE':('groudon',(0,9,9,13,14,10,3,14,1,8,6,7,8,6,11,15))}.get(gfx)
        if legendary:
            species,order=legendary
            palette=Image.open(source/'graphics/rayquaza_scene/scene_1'/(species+'.png')).getpalette()
            colors=[v for i in order for v in palette[i*3:i*3+3]]
            img.putpalette(colors+[0]*(768-len(colors)))
        frames=[int(index or 0) for symbol,index in poses if symbol==poses[0][0]]
        cols=len(frames)
        source_cols=max(1,img.width//w)
        sheet=Image.new('P',(cols*w,h));sheet.putpalette(img.getpalette())
        for col,index in enumerate(frames):
            x,y=index%source_cols*w,index//source_cols*h
            sheet.paste(img.crop((x,y,x+w,y+h)),(col*w,0))
        img=sheet
        alpha=np.where(np.array(img)==0,0,255).astype(np.uint8)
        out=img.convert('RGBA');out.putalpha(Image.fromarray(alpha))
        name=ptr[gfx].removeprefix('gObjectEventGraphicsInfo_')
        sprites[name]=out
        catalog[gfx]=dict(sheet=name,w=w,h=h,frames=cols,inanimate='.inanimate = TRUE' in body)
    (ART/'actors').mkdir(parents=True,exist_ok=True)
    for name,img in sprites.items():img.save(ART/'actors'/f'{name}.png',optimize=True)
    write(DEST/'actors.json',catalog)
    return catalog

def native_name(m,legacy,region_names):
    if legacy:return legacy['name']
    section=region_names.get(m['region_map_section'],'')
    name=m['name']
    if name=='InsideOfTruck':return '搬家卡车'
    subs={'PokemonCenter':'宝可梦中心','Mart':'友好商店','Gym':'道馆','ChampionsRoom':'冠军房间','HallOfFame':'名人堂','SidneysRoom':'花月的房间','PhoebesRoom':'芙蓉的房间','GlaciasRoom':'波妮的房间','DrakesRoom':'源治的房间','Entrance':'入口','Summit':'山顶','Top':'塔顶','Outside':'外部','Exterior':'外侧','StevensRoom':'大吾的房间','CableCarStation':'缆车站','WallysHouse':'满充家','MrBrineysHouse':'哈奇家','PokemonFanClub':'宝可梦发烧友俱乐部','DevonCorp':'得文公司','OceanicMuseum':'海洋科学博物馆','WeatherInstitute':'天气研究所','SpaceCenter':'宇宙中心','MagmaHideout':'熔岩队基地','AquaHideout':'海洋队基地','JaggedPass':'凹凸山道','NewMauville':'新紫堇','SeafloorCavern':'海底洞窟','SkyPillar':'天空之柱','CaveOfOrigin':'觉醒祠堂','VictoryRoad':'冠军之路','MtPyre':'送神山','SSTidal':'破浪号','Underwater':'水下'}
    parts=[subs.get(v,re.sub(r'Room(\d+)',r'房间\1',v)) for v in name.split('_')]
    if section and len(parts)>1 and parts[0] not in subs.values():parts[0]=section
    return '·'.join(parts)
def compile_maps(source,maps,ids):
    art=FieldArt(source)
    scripts=source_scripts(source)
    from hoenn_base import side_tables
    write(DEST/'side.json',side_tables(source,scripts))
    cast=Inhabitants(source,scripts)
    wild=native_wild(source)
    legacy_dir=ROOT/'content/regions/hoenn/maps'
    legacy={p.stem:read(p) for p in legacy_dir.glob('*.json')}
    region_names={m['region_map_section']:legacy[ids[k]]['name'] for k,m in maps.items() if ids[k] in legacy and '_' not in m['name']}
    atlas=read(ROOT/'content/world_destinations.json')['regions']['hoenn']
    destinations={loc['map']:loc for loc in atlas['locations']}
    sources={};result={}
    def phys(k):return art.rows(maps[k]['layout'])[0]
    for k,m in maps.items():
        for ix,e in enumerate(m.get('warp_events') or []):
            if e.get('dest_map') in maps: sources.setdefault(e['dest_map'],[]).append((k,ix))
    for k,m in maps.items():
        mid=ids[k];ph=phys(k);beh=ph['behavior'];wid,hei=ph['size']
        npcs,objects=cast.rows(m)
        scripts_path=source/'data/maps'/m['name']/'scripts.inc'
        code=scripts_path.read_text() if scripts_path.exists() else ''
        for n in npcs:
            if '_VAR_' not in n['source_gfx']:continue
            var=n['source_gfx'].split('_')[-1]
            possible=re.findall(r'setvar VAR_OBJ_GFX_ID_'+var+r', (OBJ_EVENT_GFX_\w+)',code)
            role=n['source_local']+" "+n["source_script"]
            if 'RIVAL' in role.upper(): n['native_gfx']='OBJ_EVENT_GFX_RIVAL_MAY_NORMAL'
            elif 'MauvilleOldMan' in role:n['native_gfx']='OBJ_EVENT_GFX_BARD'
            elif 'LilycoveLady' in role:n['native_gfx']='OBJ_EVENT_GFX_WOMAN_2'
            elif possible:n['native_gfx']=next((s for s in possible if '_MAY' in s),possible[0])
            if n.get('native_gfx'):cast.gfx_used.add(n['native_gfx'])
        warps=[]
        for ix,e in enumerate(m.get('warp_events') or []):
            x,y=xy(e)
            if not inside([x,y],ph):continue
            target=e['dest_map'];wi=e['dest_warp_id']
            # These are coordinates reserved for the post-League abnormal-weather special.
            # On the standard map they are solid rock or open sea, with no active entrance.
            if target in ('MAP_TERRA_CAVE_ENTRANCE','MAP_UNDERWATER_MARINE_CAVE') and m['map_type'] in ('MAP_TYPE_ROUTE','MAP_TYPE_UNDERWATER') and not ('MarineCave' in m['name'] or 'TerraCave' in m['name']):continue
            wi=int(wi) if str(wi).isdigit() else wi
            trig=trigger(beh[y][x])
            if k=='MAP_INSIDE_OF_TRUCK':dest=to(ids['MAP_LITTLEROOT_TOWN'],[3,10],facing='right')
            elif target in maps and isinstance(wi,int) and 0<=wi<len(maps[target].get('warp_events') or []):
                remote=maps[target]['warp_events'][wi]
                if not inside(xy(remote),phys(target)):continue
                p,extras=landing(phys(target),remote);dest=to(ids[target],p,**extras)
                if remote['dest_map']=='MAP_DYNAMIC':
                    p,extras=landing(ph,e);dest['remember_passage']=dict(key='hoenn:'+ids[target],destination=to(mid,p,**extras))
            elif target=='MAP_DYNAMIC' and sources.get(k):
                prev,wi=sources[k][0]
                remote=maps[prev]['warp_events'][wi]
                p,extras=landing(phys(prev),remote);dest=to(ids[prev],p,recall_passage='hoenn:'+mid,**extras)
            else:continue
            if m['name'].startswith('ShoalCave_HighTide') and target.startswith('MAP_SHOAL_CAVE_LOW_TIDE') and target.replace('LOW_TIDE','HIGH_TIDE') in ids:
                dest['map']=ids[target.replace('LOW_TIDE','HIGH_TIDE')]
            warps.append(dict(at=[x,y],trigger=trig,to=dest,source_warp=ix))
        dive={}
        for c in m.get('connections') or []:
            if c['map'] not in ids:continue
            d=c['direction'];offset=int(c['offset'])
            if d in ('dive','emerge'):
                dive=dict(region='hoenn',map=ids[c['map']],direction=d,offset=offset)
                continue
            for a,b in connect(ph,phys(c['map']),d,offset):
                warps.append(dict(at=a,trigger=d,to=to(ids[c['map']],b,facing=d)))
        dive_script=re.search(r'^\s*setdivewarp (MAP_\w+),\s*(\d+),\s*(\d+)',code,re.M)
        if not dive and dive_script and dive_script[1] in ids:
            dive=dict(region='hoenn',map=ids[dive_script[1]],direction='emerge' if m['map_type']=='MAP_TYPE_UNDERWATER' else 'dive',offset=0,at=events(*dive_script.groups()[1:]))
        old=legacy.get(mid,{})
        ports={'hoenn_dewford':([18,11],[17,11],[18,10]),'hoenn_fallarbor':([12,8],[12,9],[13,8]),'hoenn_pacifidlog':([17,14],[16,14],[18,14])}
        for w in old.get('warps',[]):
            if mid in ports and w['to']['region']!='hoenn':
                gate,arrival,sailor=ports[mid]
                warps.append(dict(at=gate,trigger='step',to=w['to'],atlas='world'))
                npcs.append(dict(at=sailor,name='接驳员',gfx='sailor',lines=['从我身旁的路口出发，可以步行前往其他地区。']))
                dest=w['to']; port_file=ROOT/'content/regions'/dest['region']/'maps'/(dest['map']+'.json')
                port=read(port_file)
                for back in port['warps']:
                    if back['to']['region']=='hoenn' and back['to']['map']==mid:
                        back['to'].update(at=arrival,hoenn_native=True)
                write(port_file,port)
            if (w['to']['region']!='hoenn' or w['to']['map']=='demo_town') and mid=='littleroot_town':
                warps.append(dict(w,atlas='world') if w['to']['region']=='frontier' else w)
        if mid=='littleroot_town':
            npcs.extend(n for n in old['npcs'] if n.get('transit') or n.get('gfx')=='sailor')
            if not any(n.get('transit') for n in npcs):
                npcs.append(dict(at=atlas['hub']['npc_at'],name='地区领航员',transit=True,gfx='sailor'))
        occupied={tuple(n['at']) for n in npcs+objects}|{tuple(w['at']) for w in warps}
        def free(x,y):
            return not ph['collision'][y][x] and tuple([x,y]) not in occupied and (m['map_type']=='MAP_TYPE_UNDERWATER' or not ph.get('water') or not ph['water'][y][x])
        around=[(x,y) for y in range(hei) for x in range(wid) if free(x,y)]
        anchor=old.get('spawn',[wid//2,hei//2])
        if mid=='em_inside_of_truck': anchor=[2,2]
        if mid=='littleroot_town':anchor=atlas['hub']['at']
        spawn=list(min(around,key=lambda pos:(pos[0]-anchor[0])**2+(pos[1]-anchor[1])**2)) if around else [0,0]
        row=dict(id=mid,region='hoenn',name=native_name(m,old,region_names),emerald='native_'+mid,emerald_original=m['name'],source_id=k,
                 size=ph['size'],spawn=spawn,physics=ph,hoenn_art=art.art(m['layout']),map_type=m['map_type'],dark=m['requires_flash'],
                 npcs=npcs,objects=objects,warps=warps,coord_events=m.get('coord_events') or [],
                 allow_running=m['allow_running'],allow_cycling=m['allow_cycling'])
        if dive:row['dive_connection']=dive
        if m['name']=='Underwater_SealedChamber':
            row['dive_at']={'12,44':dict(map=ids['MAP_SEALED_CHAMBER_OUTER_ROOM'],region='hoenn',direction='emerge',at=[10,19],offset=0)}
        row.update(wild.get(k,{}))
        if old:row['legacy_size']=old['size']
        if m['name'] in ('InsideOfTruck','MauvilleCity_Gym','PetalburgCity_Gym','SootopolisCity_Gym_1F','MossdeepCity_Gym','FortreeCity_Gym','Route110_TrickHousePuzzle6') or m['name'].startswith('SkyPillar'):
            compile_mechanisms(art,m,row,scripts,source,ART)
        result[mid]=row
    safe_arrivals(result)
    for mid,row in result.items():
        write(DEST/'maps'/f'{mid}.json',row)
    # Add the endgame entrance variants after the shared atlas has stable base indices.
    for label in ("SIDNEYS","PHOEBES","GLACIAS","DRAKES"):
        key="MAP_EVER_GRANDE_CITY_"+label+"_ROOM"
        mid=ids[key]
        compile_mechanisms(art,maps[key],result[mid],scripts,source,ART)
        write(DEST/'maps'/f'{mid}.json',result[mid])
    for key in ('MAP_SOOTOPOLIS_CITY','MAP_NEW_MAUVILLE_INSIDE','MAP_ABANDONED_SHIP_CORRIDORS_B1F','MAP_ABANDONED_SHIP_HIDDEN_FLOOR_CORRIDORS'):
        mid=ids[key]
        compile_mechanisms(art,maps[key],result[mid],scripts,source,ART)
        write(DEST/'maps'/f'{mid}.json',result[mid])
    from hoenn_legends import MAPS as LEGEND_MAPS
    extra=list(LEGEND_MAPS)+['MeteorFalls_1F_1R','Route110_TrickHouseEntrance']+['Route110_TrickHousePuzzle'+str(i) for i in (1,2,3,4,5,7,8)]
    extra.extend(m['name'] for m in maps.values() if m['name'].startswith('SecretBase_') or any(e['type']=='secret_base' for e in (m.get('bg_events') or [])))
    extra.extend('TrainerHill_'+str(i)+'F' for i in range(1,5))
    for name in dict.fromkeys(extra):
        k=next(key for key,m in maps.items() if m['name']==name)
        mid=ids[k]
        compile_mechanisms(art,maps[k],result[mid],scripts,source,ART)
        write(DEST/'maps'/f'{mid}.json',result[mid])
    write(DEST/'travel.json',record(result,ids,read(ROOT/'content/hoenn_campaign.json')))
    for d in result['em_secret_base_red_cave1']['mechanisms']['base']['furniture'].values():
        if d.get('gfx'):cast.gfx_used.add(d['gfx'])
    for n in range(1,5):
        for course in result[f'em_trainer_hill_{n}f']['mechanisms']['hill'].values():
            cast.gfx_used.update(a['source_gfx'] for a in course['actors'])
    catalog=actors(source,cast.gfx_used)
    from hoenn_base import effect_tiles
    write(DEST/'base_effects.json',effect_tiles(art,source,ART))
    atlas_img=Image.new('RGBA',(64*16,((len(art.atlas.images)+63)//64)*16))
    for i,im in enumerate(art.atlas.images):atlas_img.paste(im,(i%64*16,i//64*16))
    ART.mkdir(parents=True,exist_ok=True)
    # The editor may import while regions are being generated.
    import tempfile
    with tempfile.NamedTemporaryFile(dir=ART, suffix='.tmp', delete=False) as pending:
        pending_path = Path(pending.name)
    try:
        atlas_img.save(pending_path, format='PNG', optimize=True)
        pending_path.replace(ART/'tiles.png')
    finally:
        pending_path.unlink(missing_ok=True)
    art.animations.save(ART/'water.png')
    write(DEST/'atlas.json',dict(tiles=len(art.atlas.images),animated=len(art.animations.sequences)))
    print(f"{len(maps)} maps, {len(catalog)} actor identities, {len(art.atlas.images)} metatiles")

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("--index",action="store_true")
    args=parser.parse_args()
    maps,ids=raw_index(args.source)
    if not args.index: compile_maps(args.source,maps,ids)
