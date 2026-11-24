#!/usr/bin/env python3
"""Build playable X/Y fields from original zone matrices, meshes, and warp targets."""
import argparse
import base64
import zlib
from collections import defaultdict, deque
from pathlib import Path
import json
import math
import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from kalos_rooms import SPECIAL,physics as room_physics
from kalos_locations import ALIAS,CENTERS,CN,GYMS,NAMED,SCRIPT_LINKS,SEAMS,TECH,TOWNS,mid,name
from kalos_surfaces import (BLOCK,BRIDGE,FLOOR,GRASS,ICE,LAND,PURPLE,RED,ROAD,ROUGH,SAND,
                           SNOW,STAIR,STONE,VOID,WATER,WOOD,YELLOW)

ROOT=Path(__file__).resolve().parents[1]
MAPS=ROOT/'content/regions/kalos/maps'
VEC=[(0,-1),(1,0),(0,1),(-1,0)]
DIR=['up','right','down','left']
def ints(v):return [int(x) for x in v]
def save(p,data):
    p.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
def native_point(w):
    return None if w[0] is None else np.floor(np.array([w[0],w[2]])/18).astype(int)
def cells_of(mask):return np.argwhere(mask)[:,::-1]
def mode_component(collision,kind,targets):
    walk=(~collision)&(kind!=WATER)
    label,total=ndimage.label(walk)
    if not total:return walk
    counts=np.bincount(label.ravel())[1:]
    score=counts.astype(float)**.65
    viable=(counts>=max(5,counts.max()*.12))
    coords=cells_of(walk)
    tree=cKDTree(coords)
    for p in targets:
        distance,index=tree.query(p);x,y=coords[index]
        if distance<9:score[label[y,x]-1]+=15/(1+distance/5)
    return label==int(np.argmax(np.where(viable,score,0))+1)

class Area:
    def __init__(self,raw,number,z,slug=None):
        f=np.load(raw/'planes'/f'{number}.npz')
        self.number=number;self.zone=z;self.mid=slug or mid(number)
        self.origin=f['origin'];self.kind=f['kind'];self.solid=f['collision'].copy()
        self.floor=f['height'];self.img=str(f['art']);self.outdoor=bool(f['outdoor'])
        if number in SPECIAL:
            self.kind,self.solid=room_physics(number,self.kind.shape)
            self.img={1:'gba_bedroom',2:'gba_living'}.get(number,'gba_center')
        self.warps=[];self.objects=[];self.npcs=[];self.anchors={}
        self.used=set();self.arrivals=set();self.sources=[]
        ys,xs=np.indices(self.kind.shape)
        if number==264:
            boundary=self.origin[0]+157
            self.solid|=(xs+self.origin[0]<boundary if self.mid=='kalos_7' else xs+self.origin[0]>=boundary)
        # Source exterior models contain large, uniform backdrops beyond the playable edge.
        # Keep the lawn around real paths and façades, instead of treating that backdrop as a road.
        paths=np.isin(self.kind,[ROAD,STONE,GRASS,YELLOW,RED,PURPLE,SAND,WOOD,STAIR,BRIDGE])
        if self.outdoor and number not in (357,318) and paths.sum()>24:
            beyond=ndimage.distance_transform_edt(~paths)>10
            self.solid|=beyond & (self.kind==LAND)
        self.set_walk()
        if number==1:
            self.spawn=[14,11]
            self.objects.append({'at':[14,5],'kind':'wall_map','native_fixture':True})
    def set_walk(self):
        targets=[native_point(w)-self.origin for w in self.zone['warps'] if native_point(w) is not None]
        self.walk=mode_component(self.solid,self.kind,targets)
        if not self.walk.any():
            raise ValueError(('no traversable source floor',self.mid))
        self.spots=cells_of(self.walk)
        self.tree=cKDTree(self.spots)
        # Source label is a town-map hint that can be outside the actual room; choose a clear interior tile.
        pt=np.median(self.spots,axis=0)
        label=self.zone['label']
        if self.outdoor and label:
            center=np.asarray(label)/18-self.origin
            if self.tree.query(center)[0]<12:pt=center
        self.spawn=ints(self.nearest(pt))
    def nearest(self,xy):
        return self.spots[self.tree.query(xy)[1]]
    def allocate(self,xy,avoid_near=0,safe=False):
        # Keep nonessential doors and actors away from a one-tile corridor, which a standing NPC would obstruct.
        order=np.argsort(np.sum((self.spots-xy)**2,axis=1))
        forbidden=self.used|self.arrivals
        if safe:
            forbidden|={tuple(self.spawn)}
        h,w=self.walk.shape
        for i in order:
            p=tuple(self.spots[i]);x,y=p
            if p in forbidden:continue
            if avoid_near and any(abs(x-q[0])+abs(y-q[1])<=avoid_near for q in forbidden):continue
            if safe and sum(0<=x+dx<w and 0<=y+dy<h and self.walk[y+dy,x+dx] for dx,dy in VEC)<3:continue
            return ints(p)
        if avoid_near or safe:return self.allocate(xy)
        raise ValueError(('no available field tile',self.mid,len(self.spots)))
    def add(self,p,other,arrival,source,trigger='step',atlas=False,caption=None,return_cell=None):
        key=tuple(p)
        if any(tuple(w['at'])==key for w in self.warps):return False
        row={'at':ints(p),'trigger':trigger,'source_warp':source,
             'to':{'region':'kalos','map':other.mid,'at':ints(arrival),'kalos_native':True}}
        if return_cell is not None:row['_return_cell']=ints(return_cell)
        if atlas:row['atlas']='world'
        self.warps.append(row); self.used.add(key)
        if caption:row['kalos_label']=caption
        return True
    def landing(self,key):
        # Door targets stand one tile inside the destination. Prefer the southern approach to a house,
        # and the northern approach when leaving the bottom door of an interior.
        h,w=self.walk.shape;x,y=key
        order=[(0,1),(0,-1),(-1,0),(1,0)] if self.outdoor else [(0,-1),(0,1),(-1,0),(1,0)]
        candidates=[(x+dx,y+dy) for dx,dy in order if 0<=x+dx<w and 0<=y+dy<h and self.walk[y+dy,x+dx] and (x+dx,y+dy) not in self.used]
        return ints(candidates[0]) if candidates else ints(self.nearest(key))
    def finish_anchors(self):
        self.used|={tuple(self.spawn)}
        # Reserve the table on the west terrace, rather than the bridge or an indoor counter.
        focus=self.spawn
        if self.number==8:focus=ints(np.array([8118,9468])//18-self.origin)
        if self.number in GYMS or self.number in [251,252,253,254,256]:
            candidates=self.spots[self.spots[:,1]<=np.quantile(self.spots[:,1],.22)]
            focus=ints(np.median(candidates,axis=0))
        if self.number==1:focus=[8,7]
        if self.number==2:focus=[31,33]
        if self.number in (21,22):focus=[77,81]
        if self.number==264 and self.mid=='kalos_7':focus=[158,80]
        if self.number in CENTERS:focus=ints(np.median(self.spots,axis=0)+[0,-2])
        keep=set(self.used)
        keys=['story','guest1','guest2','guest3','guest4','guest5']+[f'side{i}' for i in range(1,13)]+[f'trainer{i}' for i in range(1,21)]
        if self.number in CENTERS:keys=['nurse','mart','pc']+keys
        radius=np.percentile(self.spots,85,axis=0)-np.percentile(self.spots,15,axis=0)
        for i,key in enumerate(keys):
            if len(self.used)>=len(self.spots)-2:break
            if i==0 or key=='story':target=focus
            elif key.startswith('guest') or key in ('mart','pc'):
                offsets=[(-2,1),(2,1),(-3,2),(3,2),(0,3),(0,5)]
                target=np.array(focus)+offsets[(i-1)%len(offsets)]
            else:
                theta=i*2.39996
                target=np.array(self.spawn)+radius*np.array([np.cos(theta),np.sin(theta)])*.47
            if self.number in CENTERS and key in ('nurse','mart','pc'):
                target={'nurse':[10,8],'mart':[19,10],'pc':[15,8]}[key]
                p=self.allocate(target)
            else:p=self.allocate(target,avoid_near=1,safe=True)
            self.anchors[key]=p; self.used.add(tuple(p))
        self.used=keep
    def data(self):
        h,w=self.kind.shape
        # Water is traversable only in the surfing state. Solid props and cliffs always keep their collision.
        physics={'size':[w,h],'collision':self.solid.astype('uint8').tolist()}
        water=(self.kind==WATER)&~self.solid
        grass=np.isin(self.kind,[GRASS,YELLOW,RED,PURPLE,ROUGH]) & ~self.solid
        if water.any():physics['water']=water.astype('uint8').tolist()
        if grass.any():physics['grass']=grass.astype('uint8').tolist()
        wild=self.zone.get('wild',{})
        if wild and not self.outdoor:physics['wild_any']=True
        out={'id':self.mid,'region':'kalos','name':name(self.number,self.zone),'kalos_native':True,
             'kalos_zone':self.number,'kalos_matrix':self.zone['view'],'kalos_origin':ints(self.origin),
             'kalos_image':self.img,'kalos_anchors':self.anchors,'size':[w,h],'physics':physics,
             'spawn':self.spawn,'warps':self.warps,'objects':self.objects,'npcs':self.npcs,
             'allow_fly':self.outdoor,'allow_cycling':self.outdoor,'allow_running':True}
        from unova_art import K
        tiles=np.zeros_like(self.kind,dtype='<u2')
        for code,key in [(LAND,'grass'),(ROAD,'ground'),(STONE,'stone'),(GRASS,'tall'),(WATER,'water'),(YELLOW,'flowers'),(RED,'flowers'),(PURPLE,'flowers'),(FLOOR,'floor'),(ICE,'ice'),(SNOW,'snow'),(SAND,'sand'),(BRIDGE,'bridge'),(WOOD,'wood'),(STAIR,'stairs')]:
            tiles[self.kind==code]=K[key]
        out['hoenn_art']={'s':[w,h],'t':base64.b64encode(zlib.compress(tiles.tobytes(),9)).decode(),'p':[],
                          'scene':['res://assets/kalos/maps/'+self.img+'.png',0,0]}
        if self.number in CENTERS:out['kalos_center']=True
        if self.mid=='kalos_7_west':out['name']='7号道路・西段'
        categories={YELLOW:'yellow_flowers',RED:'red_flowers',PURPLE:'purple_flowers',ROUGH:'rough_terrain'}
        for color,key in categories.items():
            mask=(self.kind==color)&grass
            if mask.any():physics[key]=mask.astype('uint8').tolist()
        return out

def connect(a,b,s,t,source,caption=None):
    pa=a.allocate(s,avoid_near=1);pb=b.allocate(t,avoid_near=1)
    a.used.add(tuple(pa));b.used.add(tuple(pb))
    la=a.landing(pa);lb=b.landing(pb);a.arrivals.add(tuple(la));b.arrivals.add(tuple(lb))
    a.add(pa,b,lb,source,caption=caption,return_cell=pb);b.add(pb,a,la,source,caption=caption,return_cell=pa)
    return pa,pb

def unit_approach(a,k,count):
    # An indexed warp can be script-positioned (no X/Z in the atlas). Place it along an unobstructed
    # frontage of the original zone, preserving the source door association and its reciprocal target.
    center=np.median(a.spots,axis=0);extent=np.percentile(a.spots,82,axis=0)-center
    angle=k*2.399963
    return center+extent*np.array([math.cos(angle),math.sin(angle)])*.84

def build(raw, streets_only=False):
    source=json.loads((raw/'map.json').read_text())
    zones={int(n):z for n,z in source['zones'].items()}
    areas={n:Area(raw,n,z) for n,z in zones.items() if n not in TECH}
    west=Area(raw,264,zones[264],'kalos_7_west')
    all_areas=[*areas.values(),west]
    def area_for(n,idx):
        if n==264 and idx in (0,1,2,5):return west
        return areas.get(n)
    pairs={}
    for n,z in zones.items():
        if n not in areas:continue
        for idx,raw_w in enumerate(z['warps']):
            dest,didx=raw_w[3:]
            a=area_for(n,idx); b=area_for(dest,didx)
            if b is None:continue
            # Multiple identical edge triggers around a circular plaza all lead to the same street.
            p=native_point(raw_w)
            anchor=(a.mid,idx)
            if p is None:
                previous=next((v for (source_num,j),v in pairs.items() if source_num==a.mid and z['warps'][j][3]==dest and z['warps'][j][0] is None),None)
                if previous is not None:pairs[anchor]=previous;continue
                p=unit_approach(a,idx,len(z['warps']))
            else:p=p-a.origin
            tile=a.allocate(p)
            a.used.add(tuple(tile));pairs[anchor]=tile
    for n,z in zones.items():
        if n not in areas:continue
        for i,r in enumerate(z['warps']):
            dest,didx=r[3:];a=area_for(n,i);b=area_for(dest,didx)
            if b is None or (a.mid,i) not in pairs:continue
            t=pairs.get((b.mid,didx),b.spawn)
            arrival=b.landing(t);b.arrivals.add(tuple(arrival))
            a.add(pairs[(a.mid,i)],b,arrival,'xy_'+str(i),caption=name(dest,zones[dest]) if r[0] is None or (pnt:=native_point(r)) is not None and np.linalg.norm(np.array(pairs[(a.mid,i)])+a.origin-pnt)>3.5 else None,return_cell=t)
    def seam(a,b):
        aa=a.spots+a.origin;bb=b.spots+b.origin
        distances,neighbors=cKDTree(bb).query(aa)
        best=distances.min()
        candidates=np.where(distances<=best+.05)[0]
        # Prefer the center of a traversable cross-section, rather than a tile behind a border tree.
        centroid=np.median(aa[candidates],axis=0)
        pick=candidates[np.argmin(((aa[candidates]-centroid)**2).sum(1))]
        return connect(a,b,aa[pick]-a.origin,bb[neighbors[pick]]-b.origin,'matrix')
    for n,t in SEAMS:
        seam(areas[n],areas[t])
        if (n,t) in ((0,258),(258,8)):
            for src,dest in ((areas[n],areas[t]),(areas[t],areas[n])):
                next(w for w in src.warps if w['to']['map']==dest.mid)['atlas']='world'
    seam(areas[264],west)
    for n,t,caption in SCRIPT_LINKS:
        a=areas[n];b=areas[t];pa=unit_approach(a,t,4);pb=unit_approach(b,n,4)
        if n==1:pa=[21,6];pb=[38,26]
        if (n,t)==(256,257):pa=ints(np.median(a.spots,axis=0)+[0,-6])
        connect(a,b,pa,pb,'script_'+str(n)+'_'+str(t),caption)
    # Geosenge's pre/post-weapon matrices occupy the same physical town. This old map id was
    # already a location in earlier saves and connects back to the town rather than opening a shortcut.
    seam(areas[21],areas[22])
    # Natural exits from a previous region stay reciprocal after the native map changes dimensions.
    for n,source_mid,region,at,face in [(157,'galar_pass_kalos_cyllage','galar',[33,11],'left'),(38,'kalos_pass_paldea_n3','kalos',[15,1],'up')]:
        a=areas[n]; p=a.allocate(unit_approach(a,n,1),avoid_near=2)
        a.warps.append({'at':p,'trigger':face,'atlas':'world','source_warp':'interregional','to':{'region':region,'map':source_mid,'at':at}})
        a.used.add(tuple(p))
    # A step trigger fires immediately. Find the connected room interior WITH all those tiles
    # removed, and put every reciprocal arrival on that side of the sill. This also handles
    # bridge ends, narrow corridors and clustered lift buttons.
    lookup={a.mid:a for a in all_areas}
    for a in all_areas:
        free=a.walk.copy()
        for w in a.warps:
            x,y=w['at'];free[y,x]=False
        groups,total=ndimage.label(free)
        counts=np.bincount(groups.ravel());counts[0]=0
        core=groups==np.argmax(counts)
        if not core.any():raise ValueError(('no room interior between doors',a.mid))
        touching=ndimage.binary_dilation(core)&~core
        rim=cells_of(touching)
        occupied={tuple(w['at']) for w in a.warps}
        a.lips={}
        for w in a.warps:
            key=tuple(w['at']);x,y=key
            if not touching[y,x]:
                options=[p for p in rim if tuple(p) not in occupied]
                pos=min(options,key=lambda p:abs(p[0]-x)+abs(p[1]-y)); occupied.remove(key)
                w['at']=ints(pos); x,y=pos;occupied.add(tuple(pos));a.solid[y,x]=False
            land=[(x+dx,y+dy) for dx,dy in VEC if 0<=y+dy<core.shape[0] and 0<=x+dx<core.shape[1] and core[y+dy,x+dx]]
            facing=(x,y+1 if a.outdoor else y-1)
            a.lips[key]=ints(min(land,key=lambda p:(abs(p[0]-facing[0])+abs(p[1]-facing[1]),p)))
        a.walk=core;a.spots=cells_of(core);a.tree=cKDTree(a.spots)
        a.spawn=ints(a.nearest(a.spawn));a.used=occupied;a.arrivals=set(tuple(p) for p in a.lips.values())
    for a in all_areas:
        for w in a.warps:
            target=w['to']
            if a.number==109 and target['map']==mid(236):target['kalos_requires']=['k_train_pass']
            if target['map'] in (mid(319),mid(346)) and a.number not in (319,346):target['kalos_requires']=['k_parade']
            key=w.pop('_return_cell',None)
            if key is not None:
                dest=lookup[w['to']['map']];w['to']['at']=dest.lips.get(tuple(key),dest.spawn)
    for a in all_areas:
        # Source script lifts may be the only entrance to a room. Make every sign and landing reachable in ordinary input.
        a.arrivals.update(tuple(w['at']) for w in a.warps)
        if tuple(a.spawn) in a.used:a.spawn=a.allocate(a.spawn,avoid_near=2,safe=True)
        if a.number==0:
            npc=a.allocate(np.array(a.spawn)+[1,0],safe=True)
            a.npcs.append({'at':npc,'name':'地区领航员','gfx':'sailor','transit':True})
            a.used.add(tuple(npc))
            adj=[(npc[0]+dx,npc[1]+dy) for dx,dy in VEC if (npc[0]+dx,npc[1]+dy) in map(tuple,a.spots)]
            a.spawn=ints(next(c for c in adj if c not in a.used))
        a.finish_anchors()
    from kalos_streets import draw as streets
    if streets_only:
        for n in range(63,70):streets(areas[n])
        return
    from kalos_gym_rooms import install
    install(all_areas)
    for n in (0,63,64,65,66,67,68,69):streets(areas[n])
    for a in all_areas:save(MAPS/(a.mid+'.json'),a.data())
    phases={}
    town=areas[21]
    for tag,number in [('stones',21),('weapon',22),('crater',23)]:
        variant=town if number==21 else areas.get(number) or Area(raw,number,zones[number])
        mask=variant.solid.copy()
        # The original plaza changes at its center. Keep the unchanged doorways, actor access
        # and approach roads from the normal town at all three stages.
        yy,xx=np.indices(mask.shape)
        plaza=(abs(xx-77)<21)&(abs(yy-62)<22)
        mask=np.where(plaza,mask,town.solid)
        for a in (areas[21],areas[22]):
            for x,y in [*a.lips.values(),a.spawn,*a.anchors.values(),*[w['at'] for w in a.warps]]:mask[y,x]=False
        phases[tag]={'art':variant.img,'collision':mask.astype('uint8').tolist()}
    save(ROOT/'content/kalos_geosenge.json',phases)
    used_images={a.img for a in all_areas}|{state['art'] for state in phases.values()}
    for png in (ROOT/'assets/kalos/maps').glob('xy_*.png'):
        if png.stem not in used_images:
            png.unlink()
            png.with_suffix('.png.import').unlink(missing_ok=True)
    for p in MAPS.glob('kalos_zone_*.json'):
        if p.stem not in lookup and json.loads(p.read_text()).get('kalos_native'):p.unlink()
    return zones,all_areas

def atlas(raw,zones,areas):
    old_path=ROOT/'content/world_destinations.json';d=json.loads(old_path.read_text());reg=d['regions']['kalos']
    townmap=json.loads((raw/'map.json').read_text())['townmap']; tw,th=townmap['size']
    positions={k:[round(x/tw*100),round(y/th*100)] for k,x,y in townmap['spots']}
    maps={a.mid:a for a in areas};locations=[]
    for n in [*TOWNS,258,259,260,261,262,263,264,266,267,268,269,270,272,273,275,276,278,279,281,282,283,285,286,287,334,304,22,305,181,357,310,317,318,320,77,329,336,343,349,351,352]:
        if n in TECH:continue
        a=maps[mid(n)];en=zones[n]['name'];old=next((v for v in reg['locations'] if v['map']==a.mid),{})
        nearby={181:[15,32],329:[34,56],352:[32,60],22:[10,49],77:[52,36]}
        pos=nearby.get(n,positions.get(en,old.get('pos',[50,50])))
        locations.append({'id':a.mid,'name':name(n,zones[n]),'map':a.mid,'at':a.spawn,
                          'kind':old.get('kind','landmark'),'pos':pos})
    old=[i for i in reg['locations'] if '_pass_' in i['map']];reg['locations']=locations+old
    a=maps['kalos_vaniville'];reg['hub']={'region':'kalos','map':a.mid,'at':a.spawn,'npc_at':a.npcs[0]['at']}
    chains=[
        'vaniville 1 aquacorde 2 forest 3 santalune 4 lumiose 5 camphrier 7 cave 8 ambrette 9 glitter',
        '7 6 palace_approach','7 battle_chateau','7 berry_fields','8 cyllage 10 geosenge 11 reflection shalour 12 coumarine 13 lumiose 14 laverre 15 dendemille 17 anistar 18 couriway 19 snowbelle 20 village',
        'geosenge crystals','shalour mastery','12 azure sea_spirits_den','13 power_plant','laverre factory','15 lost_hotel 16 lumiose','15 16','dendemille frost','18 terminus_entrance','snowbelle 21 victory league','santalune 22 victory','lumiose tower','lumiose kiloude','couriway pass_paldea_n3']
    reg['connections']=sorted({tuple(sorted(('kalos_'+left,'kalos_'+right))) for chain in chains
                               for left,right in zip(chain.split(),chain.split()[1:])})
    chart=raw/'townmap.webp'
    if chart.is_file():
        from PIL import Image
        background=Image.open(chart).convert('RGB').resize((240,168),Image.Resampling.LANCZOS)
        background.quantize(64).convert('RGB').save(ROOT/'assets/atlas/kalos.webp',lossless=True,method=6)
    save(old_path,d)
    path=MAPS.parent/'region.json';j=json.loads(path.read_text());j['maps']=sorted([*maps,'kalos_pass_paldea_n3'])
    j['start']={'map':a.mid,'at':a.spawn};save(path,j)
    # Update the landing used by roads coming from other regions. Directional exits start one tile clear of the edge.
    for n,path in [(157,'galar/galar_pass_kalos_cyllage'),(38,'kalos/kalos_pass_paldea_n3')]:
        reg,rm=path.split('/');p=ROOT/'content/regions'/reg/'maps'/(rm+'.json');j=json.loads(p.read_text())
        native=maps[mid(n)]
        warp=next(w for w in native.warps if w.get('source_warp')=='interregional')
        for w in j['warps']:
            if w['to']['map']==native.mid:
                w['to'].update({'at':native.landing(warp['at']),'kalos_native':True})
        save(p,j)
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path)
    from asset_paths import source_path
    from kalos_opening import install
    parser.add_argument("--emerald-source",type=Path,default=Path(source_path("emerald")))
    parser.add_argument("--streets-only",action="store_true",help="Redraw only the seven Lumiose streets and plazas")
    args=parser.parse_args()
    if args.streets_only:
        build(args.source, streets_only=True)
        raise SystemExit(0)
    zs,ms=build(args.source);atlas(args.source,zs,ms)
    install(args.emerald_source)
    import subprocess, sys
    subprocess.run([sys.executable,str(ROOT/'tools/kalos_field_art.py'),str(args.source)],check=True)
    print('Kalos maps',len(ms),'warps',sum(len(a.warps) for a in ms),'anchors',sum(len(a.anchors) for a in ms))
