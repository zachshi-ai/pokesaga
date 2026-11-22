"""Project original field-model materials and props onto Emerald's 16 px tile vocabulary."""
import base64
import json
import re
import struct
import zlib
from functools import lru_cache
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import Emerald, ROOM, CLINIC, CAVE, TOWN
from johto_gba_outdoor import TILES, AUTOTILES

TERRAIN = dict(TILES, water=(TOWN,0x170), ground=(TOWN,0x121), floor=(ROOM,0x201),
               wall=(ROOM,0x216), clinic=(CLINIC,0x202), wallcap=(ROOM,0x254),
               tiles=("MossdeepCity_Gym",0x20a), carpet=(ROOM,0x205), stairs=(CAVE,0x20b),
               sea=(TOWN,0x170), wood=(ROOM,0x201), verge=(TOWN,0x07), darkgrass=(TOWN,0x15),
               rock=("FallarborTown",0x265), stone=("RustboroCity",0x2bd))
KEYS=['void']+list(TERRAIN)
KEYS += ['trail_'+str(y)+str(x) for y in range(3) for x in range(3)]+['shore_'+str(n) for n in range(16)]
K={key:i for i,key in enumerate(KEYS)}
ROOT=Path(__file__).resolve().parents[1]
def atlas(emerald):
    out=ROOT/'assets/unova'
    out.mkdir(parents=True,exist_ok=True)
    a=Image.new('RGBA',(256,((len(KEYS)+15)//16)*16))
    for key,(layout,cell) in TERRAIN.items():
        idx=K[key];a.paste(emerald.metatile(layout,cell),(idx%16*16,idx//16*16))
    from platinum_art import Art
    shore=Art(emerald.source,None)
    for y in range(3):
        for x in range(3):
            idx=K['trail_'+str(y)+str(x)];a.paste(emerald.metatile(TOWN,AUTOTILES['trail'][y][x]),(idx%16*16,idx//16*16))
    for mask in range(16):
        idx=K['shore_'+str(mask)];a.paste(shore.images[shore.shore(mask)],(idx%16*16,idx//16*16))
    a.save(out/'tiles.png',optimize=True)

def encode(grid):
    return base64.b64encode(zlib.compress(grid.astype('<u2').tobytes(),9)).decode()

def glb(path):
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+length]),raw[28+length:]

def accessor(doc,binary,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    dt=np.dtype({5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']])
    dims={'SCALAR':1,'VEC3':3}[a['type']]
    return np.ndarray((a['count'],dims),dtype=dt,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*dims),dt.itemsize))

def material(name):
    s=name.lower()
    if re.search(r'kage|shadow|hikari|yuki|simi|alpha|hlight|lambert|cloud|hikari|tesuri',s):return ''
    if re.search(r'(?:^|_)ki\d|(?:^|_)tuki|leaf|mori',s):return 'canopy'
    if re.search(r'mizu|water|nami|river|umi|sea_jimen',s):return 'water'
    if re.search(r'gake|iwa|rock|stonewall',s):return 'cliff'
    if re.search(r'grass|shiba|kusa',s):return 'grass'
    if re.search(r'hana|flower|kadan',s):return 'flowers'
    if re.search(r'doro|michi|jimen|dirt',s):return 'ground'
    if re.search(r'suna|sand',s):return 'sand'
    if re.search(r'bridge|hashi|hasi|^t01wd',s):return 'bridge'
    if re.search(r'kaida|stair|step',s):return 'stairs'
    if re.search(r'renga|tile|ishi|isi|pave|asfalt',s):return 'pave'
    if re.search(r'yuka|floor',s):return 'floor'
    if re.search(r'kabe|wall|heki',s):return 'wall'
    if re.search(r'carpet|rag|mat0|shiki',s):return 'carpet'
    if re.search(r'saku|fence',s):return 'fence'
    return ''

def prop_name(s):
    for expr,kind in [('^ki[0-9]|tree','tree'),('streetlamp|lightpole|gaito','streetlamp'),('sign|kanban','sign'),('fountain|funsui','fountain'),
                      ('^bed|_bed','ceilingbed'),('^tv','tv'),('^pc(desk)?[0-9]','pc'),('^wii|console','console'),('shelf|books','bookshelf_home'),
                      ('plant|^vase','plant_indoor'),('^table|^desk','desk'),('^stair|^d0stair','woodstairs'),('rock|^iwa','rock')]:
        if re.search(expr,s):return kind
    return ''

@lru_cache(None)
def projected(path):
    doc,binary=glb(path);p=Image.new('L',(128,128));draw=ImageDraw.Draw(p)
    alltri=[];objects=[]
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            if 'indices' not in prim or 'material' not in prim:continue
            mat=doc['materials'][prim['material']].get('name','')
            kind=material(mat)
            if not kind:continue
            xyz=accessor(doc,binary,prim['attributes']['POSITION'])
            inds=accessor(doc,binary,prim['indices']).reshape(-1)
            if len(inds)%3:continue
            v=xyz[inds].reshape(-1,3,3)
            for tri in v:
                points=(tri[:,[0,2]]/4+64).astype(int)
                a,b,c=points
                if abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))<4:continue
                alltri.append((float(tri[:,1].mean()),tuple(map(tuple,points.tolist())),250 if kind=='canopy' else K[kind]))
    for _,triangle,col in sorted(alltri,key=lambda t:t[0]):draw.polygon(triangle,col)
    for n in doc['nodes']:
        m=re.match(r'bw2_prop_\d+_id_(\d+)',n.get('name',''))
        if m:
            x,_,z=n['translation'];objects.append((int(m[1]),int((x+256)//16),int((z+256)//16)))
    return np.asarray(p)[2::4,2::4],objects

@lru_cache(None)
def prop_catalog(folder):
    return {json.loads(p.read_bytes())['res_id']:p.parent.name for p in folder.glob('*/data.json')}

def paint(src,z,blocks,origin,env,collision,water,grass,warps):
    w,h=env.shape[1],env.shape[0]
    outdoor=z['matrix'] in (0,1) or z['fly_from']
    cave=any(s in z['place'] for s in ('cave','chasm','mountain','castle','sewers','ruins','tunnel','passage','victory_road','tower')) and not outdoor
    city='city' in z['place'] or 'league' in z['place']
    clinical='pokemon_center' in z['key'] or z['bgm']==1060
    gym='gym' in z['mid']
    ground='pave' if outdoor and city else 'grass' if outdoor else 'rockfloor' if cave else 'clinic' if clinical or gym else 'floor'
    tiles=np.full(env.shape,K[ground],np.uint16)
    tiles[collision]=K['cliff' if cave or outdoor else 'wall']
    semantic=np.zeros(env.shape,'uint8');props=[];indoor_fixtures=[]
    for (bx,by),model in blocks.items():
        localx=bx*32-origin[0];localy=by*32-origin[1]
        reference=src.visual_model(z,bx,by,model)
        if not reference:continue
        surface,objects=projected(reference)
        s=semantic[localy:localy+32,localx:localx+32];s[:]=surface
        if src.era=='bw':objects=src.model_props(model)
        bundle=src.prop_bundle(z)
        for pid,x,y in objects:
            kind=prop_name(bundle.get(pid,''))
            x+=localx;y+=localy
            if not kind or not (0<=x<w and 0<=y<h):continue
            if kind=='tree' and not collision[y,x]:continue
            if kind=='woodstairs' and not any(abs(wx-x)+abs(wy-y)<3 for (wx,wy),_ in warps):continue
            (props if outdoor else indoor_fixtures).append((kind,x,y))
    known=(semantic!=0)&(semantic!=250)
    tiles[known]=semantic[known]
    if not outdoor and not cave:
        from scipy.ndimage import binary_dilation
        furniture_area=binary_dilation(~collision,iterations=2)
        tiles[~furniture_area]=0
        if clinical or gym: tiles[(~collision)&(semantic==K['floor'])]=K['clinic']
    if outdoor:
        tiles[semantic==250]=K['grass']
        if np.any(semantic==250):
            from scipy.ndimage import maximum_filter
            candidates=(semantic==250)&collision
            for y in range(1,h,2):
                for x in range(1,w,2):
                    if candidates[y,x] and np.count_nonzero(candidates[max(0,y-1):y+1,max(0,x-1):x+1])>=3:props.append(('tree',x,y))
    tiles[water]=K['water'];tiles[grass & ~water]=K['rockfloor' if cave else 'tall']
    occupied=set()
    for (x,y),dest in warps:
        if not outdoor or dest['parent']==dest['i'] or dest['matrix'] in (0,1):continue
        if not (0<y<h and 0<x<w):continue
        if (x,y) in occupied or water[y,x]:continue
        if dest['place']!=z['place'] and dest['i'] not in (396,489,502):continue
        if any(re.search(k,dest['key']) for k in ('gate','bridge','cave','frigate')):continue
        if not collision[max(0,y-1),x]:continue
        occupied.add((x,y))
        kind='center' if ('pokemon_center' in dest['key'] or dest['bgm']==1060) else 'gym' if 'gym' in dest['mid'] else 'lab' if 'lab' in dest['mid'] else ('home_red','home_blue','home_green','home_city')[(x+y)%4]
        use=kind
        # Only occupy solid source cells. Choose the small facade in a tight city block.
        for yy in range(max(0,y-3),y):
            if not np.all(collision[yy,max(0,x-1):min(w,x+2)]):use=kind+'_compact';break
        props.append((use,x,y-1))
        tiles[y,x]=K['ground' if not city else 'pave']
    if z['mid'] in ['unova_bw_home_2f','unova_b2_home']:
        preset={'unova_bw_home_2f':[('ceilingbed',2,4),('pc',4,3),('bookshelf_home',7,2),('woodstairs',9,2)],'unova_b2_home':[('ceilingbed',2,5),('bookshelf_home',6,2),('tv',10,3),('plant_indoor',12,4)]}
        for k,x,y in preset[z['mid']]:
            if not any(q[0]==k for q in indoor_fixtures):indoor_fixtures.append((k,x,y))
    props.extend(indoor_fixtures)
    if outdoor:
        mask=tiles==K['ground'];pad=np.pad(mask,1,constant_values=True)
        dx=np.where(~pad[1:-1,:-2],0,np.where(~pad[1:-1,2:],2,1))
        dy=np.where(~pad[:-2,1:-1],0,np.where(~pad[2:,1:-1],2,1))
        for iy in range(3):
            for ix in range(3):
                tiles[mask&(dx==ix)&(dy==iy)]=K['trail_'+str(iy)+str(ix)]
    mask=tiles==K['water']
    pad=np.pad(mask,1,constant_values=True)
    edges=(~pad[:-2,1:-1]).astype('uint8')+2*(~pad[2:,1:-1])+4*(~pad[1:-1,2:])+8*(~pad[1:-1,:-2])
    for n in range(16):tiles[mask&(edges==n)]=K['shore_'+str(n)]
    return {'s':[w,h],'t':encode(tiles),'p':sorted(set(props),key=lambda p:(p[2],p[1],p[0]))}
