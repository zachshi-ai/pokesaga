#!/usr/bin/env python3
"""Fit the four Alola islands and their attached rooms to the shared four-way field engine."""
import argparse,hashlib,json,math,re
from pathlib import Path
from collections import defaultdict
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree
from alola_locations import LOCS,PATHS,EXTRAS,SUBS,CENTERS
from alola_interiors import design,theme
import alola_sandy_cave,alola_pelago_art,alola_towns
from build_alola_surfaces import UNIT,PX
from kalos_gym_rooms import tile,sprite
from kalos_surfaces import LAND,GRASS,WATER,ROAD,WOOD,STAIR,BLOCK
from unova_art import K,encode
ROOT=Path(__file__).resolve().parents[1]
MAPS=ROOT/'content/regions/alola/maps';ART=ROOT/'assets/alola/maps'
DIRS=[(0,1),(1,0),(0,-1),(-1,0)]
ISLANDS={0:'melemele',49:'akala',97:'ulaula',168:'poni'}
def load(p):return json.loads(p.read_bytes())
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,separators=(',',':'))+'\n')
def ints(v):return [int(x) for x in v]
def pts(g):
    return [np.array(v['position'])[::2] for k in ['trainers','items'] for v in g[k]]+[np.array(e['shape']['center'])[::2] for e in g['encounters'] if e.get('shape')]
def flat(p):return np.array([p['x'],p['z']],float)
def largest(mask):
    counts,k=ndimage.label(mask)
    if not k:return mask
    return counts==(np.argmax(np.bincount(counts.ravel())[1:])+1)
def allocate_walk(k,solid,focus):
    valid=(~solid)&(k!=WATER)
    groups,n=ndimage.label(valid)
    if not n:return valid
    score=np.bincount(groups.ravel()).astype(float);score[0]=0
    dist=np.sum((np.argwhere(valid)[:,::-1]-focus)**2,axis=1)
    for p in np.argwhere(valid)[np.argsort(dist)[:20]]:score[groups[tuple(p)]]+=4
    return groups==int(np.argmax(score))
class Area:
    def __init__(self,mid,name,kind,solid,pic,focus=None,origin=None,geo=(),out=False,location='',zones=(),scene=''):
        self.mid=mid;self.name=name;self.k=kind;self.s=solid.copy();self.pic=pic.convert('RGB');self.origin=origin;self.location=location;self.zones=zones;self.scene=scene
        self.out=out;self.geo=list(geo);self.warps=[];self.anchors={};self.fixed=[];self.items=[];self.trainers=[];self.npcs=[];self.objects=[]
        self.h,self.w=self.k.shape;self.px=self.pic.width//self.w
        self.used=set();self.arrivals=set()
        self.set_walk(np.array([self.w//2,self.h//2]) if focus is None else focus)
    def set_walk(self,focus):
        self.walk=allocate_walk(self.k,self.s,focus)
        if self.walk.sum()<40:
            raise ValueError(('no supported floor',self.mid,int(self.walk.sum())))
        self.spots=np.argwhere(self.walk)[:,::-1];self.tree=cKDTree(self.spots)
        self.spawn=ints(self.spots[self.tree.query(focus)[1]])
        self.dist=ndimage.distance_transform_edt(self.walk)
    def position(self,p):
        return np.array(p)/UNIT-self.origin if self.origin is not None else np.array(self.spawn)
    def reserve(self,p,access=False,spacing=0):
        pts=self.spots;diff=pts-p;order=np.argsort(np.einsum('ij,ij->i',diff,diff))
        avoid=self.used|self.arrivals|{tuple(self.spawn)}
        for idx in order:
            x,y=map(int,pts[idx])
            if (x,y) in avoid:continue
            if access and self.dist[y,x]<1.9:continue
            if spacing and any(abs(x-a)+abs(y-b)<=spacing for a,b in avoid):continue
            self.used.add((x,y));return [x,y]
        if spacing:return self.reserve(p,access)
        if access:return self.reserve(p)
        raise ValueError(('out of cells',self.mid,len(avoid)))
    def edge(self,direction,inside=False):
        pts=self.spots
        if inside:
            return self.reserve(np.array([self.w//2,self.h-3]),True)
        diff=pts-np.array(self.spawn)
        n=np.array(direction);n=n/(np.linalg.norm(n)+.001)
        projection=diff[:,0]*n[0]+diff[:,1]*n[1]-abs(-diff[:,0]*n[1]+diff[:,1]*n[0])*.35
        chosen=pts[projection>=np.percentile(projection,93)]
        return self.reserve(np.median(chosen,axis=0),True,3)
    def landing(self,pt):
        opts=[(pt[0]+dx,pt[1]+dy) for dx,dy in DIRS]
        for x,y in opts:
            if 0<=x<self.w and 0<=y<self.h and self.walk[y,x] and (x,y) not in self.used:
                self.arrivals.add((x,y));return [x,y]
        return self.reserve(pt)
    def stamp(self,k,p):
        x,y=p;tx=tile(k).resize((self.px,self.px),Image.Resampling.NEAREST)
        self.pic.paste(tx,(x*self.px,y*self.px))
    def label_door(self,p):
        x,y=p
        # Small directional brass markers distinguish a transfer tile from the adjacent arrival tile.
        l=x*self.px;t=y*self.px;w=self.px
        d=ImageDraw.Draw(self.pic);d.polygon([(l+1,t+w-3),(l+w//2,t+w//2),(l+w-2,t+w-3)],fill='#ffeba0',outline='#6c6655')
    def anchors_and_encounters(self):
        focus=np.array(self.spawn)
        if self.mid=='home':self.spawn=[8,7];focus=np.array([10,4])
        elif self.mid.startswith('e4_') or self.mid in ['champion_room','megalo_tower']:focus=np.array([self.w//2,5])
        if self.mid.startswith('center_'):
            for key,p in [('nurse',[10,8]),('mart',[19,10]),('pc',[15,8])]:
                self.anchors[key]=self.reserve(np.array(p))
        ks=['story']+[f'guest{i}' for i in range(1,6)]+[f'side{i}' for i in range(1,13)]+[f'trainer{i}' for i in range(1,11)]
        extent=np.maximum(3,(np.percentile(self.spots,85,axis=0)-np.percentile(self.spots,15,axis=0))*.4)
        for i,key in enumerate(ks):
            if i==0:target=focus
            elif i<6:target=focus+np.array([(-2,1),(2,1),(-3,2),(3,2),(0,3)][i-1])
            else:target=np.array(self.spawn)+np.array([math.cos(i*2.4),math.sin(i*2.4)])*extent
            self.anchors[key]=self.reserve(target,True,1)
        for group in self.geo:
            for src,dst,idx in [('items',self.items,'item'),('trainers',self.trainers,'id')]:
                for record in group[src]:
                    p=self.reserve(self.position(np.array(record['position'])[::2]),True)
                    dst.append({**{key:record[key] for key in [idx,'kind'] if key in record},'zone':group['zone'],'at':p})
            for e in group['encounters']:
                if not e.get('shape') or e['method'] not in ['grass','cave','flowers','ambush']:continue
                shape=e['shape'];p=self.position(np.array(shape['center'])[::2])
                yy,xx=np.indices(self.k.shape);dx,dy=xx+.5-p[0],yy+.5-p[1];a=shape.get('rotation',[0,0,0,1]);angle=2*math.atan2(a[1],a[3])
                width,height=np.array(shape.get('size',[shape.get('radius',150)*2,100,shape.get('radius',150)*2]))[::2]/(UNIT*2)
                patch=self.walk&(abs(dx*math.cos(angle)+dy*math.sin(angle))<=width)&(abs(dy*math.cos(angle)-dx*math.sin(angle))<=height)
                if not patch.any():
                    near=self.spots[self.tree.query(p)[1]];patch=self.walk&((xx-near[0])**2+(yy-near[1])**2<=3)
                self.k[patch]=GRASS
        grass=self.k==GRASS
        if grass.any() and self.out:
            for y,x in np.argwhere(grass):self.stamp('tall',(x,y))
        for w in self.warps:self.label_door(w['at'])
    def data(self):
        size=[self.w,self.h]
        physics={'size':size,'collision':self.s.astype('uint8').tolist()}
        for code,key in [(WATER,'water'),(GRASS,'grass')]:
            bits=(self.k==code)&(~self.s)
            if bits.any():physics[key]=bits.astype('uint8').tolist()
        if self.mid=="sandy_cave":
            hole=np.zeros_like(self.s,dtype=np.uint8);x,y=alola_sandy_cave.PIT;hole[y,x]=1
            physics.update(hole=hole.tolist(),wild_any=True)
        if not self.out and self.geo and any(c['method']=='cave' for g in self.geo for c in g['encounters']):physics['wild_any']=True
        name='center' if self.mid.startswith('center_') else self.mid
        path=ART/(name+'.png')
        if name!='center' or not path.exists():self.pic.quantize(128,dither=Image.Dither.NONE).save(path,optimize=True)
        tiles=np.where(self.s,K['wall'],K['grass' if self.out else 'floor']).astype('<u2')
        tiles[self.k==WATER]=K['water'];tiles[self.k==GRASS]=K['tall']
        import base64,zlib
        return {'id':'alola_'+self.mid,'region':'alola','name':self.name,'alola_native':True,'alola_zone':self.zones[0] if self.zones else -1,'alola_zones':self.zones,'alola_location':self.location,'alola_image':name,'alola_anchors':self.anchors,'alola_center':self.mid.startswith('center_'),'alola_item_tiles':self.items,'alola_trainer_tiles':self.trainers,'size':size,'physics':physics,'spawn':self.spawn,'npcs':self.npcs,'objects':self.objects,'warps':self.warps,'allow_fly':self.out,'allow_running':True,'allow_cycling':self.out,'hoenn_art':{'s':size,'t':base64.b64encode(zlib.compress(tiles.tobytes())).decode(),'p':[],'scene':['res://assets/alola/maps/'+name+'.png',0,0]}}
def materials(cache):
    locations={r['id']:r for r in load(cache/'locations.json')}
    geos=load(cache/'geometry.json')['zones']
    native=load(cache/'scenes.json')['scenes']
    assigned={};zone_owner={}
    for row in native:
        world=row['world']
        if world in SUBS:assigned[world]=SUBS[world][0]+'_'+str(world)
        else:assigned[world]={34:'school',86:'aether_base_8',88:'paniola_ranch',89:'nursery',196:'aether_docks',199:'aether_conservation',200:'aether_lab',201:'aether_lab_b',204:'aether_mansion'}.get(world,LOCS[row['locations'][0]])
    for row in native:
        for z in row['zones']:zone_owner[z]=assigned[row['world']]
    # School, shopping mall, and other interior objects use their own coordinate spaces.
    for z,k in [(26,'home_1f'),(37,'lab'),(53,'school'),(40,'motel_2'),(57,'hauoli_mall'),(109,'tide_song'),(129,'aether_base_8'),(131,'paniola_ranch'),(132,'nursery'),(209,'motel_13'),(206,'aether_house'),(212,'zygarde_lab'),(256,'mina_house')]:zone_owner.setdefault(z,k)
    for g in geos:zone_owner.setdefault(g['zone'],LOCS[g['location']])
    cache_fields={}
    def plane(n):
        if n not in cache_fields:
            raw=np.load(cache/'planes'/(n+'.npz'))
            cache_fields[n]=(raw['origin'],raw['kind'],raw['solid'],Image.open(cache/'planes'/(n+'.png')))
        return cache_fields[n]
    active={}
    fields={}
    for n,l in locations.items():
        m=LOCS[n]; matches=[q for q in native if assigned[q['world']]==m]
        if matches:fields[m]=matches[0]['file']
        elif l.get('map') and l['map']['kind']=='overworld':fields[m]=l['island']
        elif m=='mahalo':fields[m]='melemele'
    for q in native:fields[assigned[q['world']]]=q['file']
    names={LOCS[n]:l['name']['zh'].translate(str.maketrans('０１２３４５６７８９','0123456789')) for n,l in locations.items()}
    names.update(EXTRAS)
    names.update(aether_base_8='8号道路・以太基地',nursery='宝可梦寄放屋')
    for p in CENTERS:names['center_'+p]=names.get(p,p)+'・宝可梦中心'
    for w,(p,cn) in SUBS.items():names[p+'_'+str(w)]=names[p]+'・'+cn
    for mid,name in names.items():
        parent=next((q for q,l in LOCS.items() if l==mid),None)
        scene=fields.get(mid)
        zone=[g for g in geos if zone_owner[g['zone']]==mid]
        out=mid in ('big_wave_beach','heahea_beach','ulaula_beach','poni_beach','megalopolis','poni_wilds_beach','festival_plaza','pikachu_valley','poni_wormhole') or bool(scene and scene in ISLANDS.values())
        if not scene:
            k,s,img=(alola_pelago_art.design(mid) if mid.startswith("pelago_") else alola_sandy_cave.design() if mid=="sandy_cave" else design(mid))
            slug=locations[parent]["slug"] if parent else "sandy-cave" if mid=="sandy_cave" else ""
            active[mid]=Area(mid,name,k,s,img,geo=zone,out=out,location=slug,zones=[z["zone"] for z in zone])
            continue
        src=next((q for q in native if q['file']==scene),None)
        parent=parent or src['locations'][0]
        l=locations[parent];o,k,s,img=plane(scene);yn,xn=k.shape
        valid=(~s)&(k!=WATER)&(k!=0)
        samples=[p for z in zone for p in pts(z) if ISLANDS.get(z['world'],'scene-'+str(z['world']))==scene]
        ws=np.array(samples)/UNIT if samples else np.empty((0,2))
        pt=flat(l['map'])/UNIT if scene in ISLANDS.values() else np.median(ws,axis=0) if len(ws) else None
        if scene in ISLANDS.values():
            coord=np.vstack([ws,pt])
            left,top=np.maximum(0,np.floor(coord.min(0)-o-13).astype(int));right,bottom=np.minimum([xn,yn],np.ceil(coord.max(0)-o+14).astype(int))
        else:
            counts,n=ndimage.label(valid);ar=np.bincount(counts.ravel());ar[0]=0
            pts0=np.argwhere(counts==int(np.argmax(ar)))[:,::-1]
            # Remove a model's distant ocean sphere/skybox, retaining its traversable component and source landmarks.
            if len(pts0) and np.ptp(pts0,axis=0).max()<250:
                coord=np.vstack([ws-o,pts0]) if len(ws) else pts0;lo=np.maximum(0,coord.min(0).astype(int)-5);hi=np.minimum([xn,yn],coord.max(0).astype(int)+6)
            elif len(ws):
                lo=np.maximum(0,(ws-o).min(0).astype(int)-10);hi=np.minimum([xn,yn],(ws-o).max(0).astype(int)+11)
            else:
                good=np.argwhere((k!=WATER)&(k!=0))[:,::-1]
                ctr=np.median(good,axis=0) if len(good) else np.array([xn/2,yn/2])
                lo=np.maximum(0,(ctr-[45,45]).astype(int));hi=np.minimum([xn,yn],(ctr+[46,46]).astype(int))
            left,top=lo;right,bottom=hi
        o=o+[left,top]; k=k[top:bottom,left:right].copy();s=s[top:bottom,left:right].copy();pic=img.crop((left*PX,top*PX,right*PX,bottom*PX))
        if min(k.shape)<1:raise RuntimeError(mid)
        s[[0,-1],:]=True;s[:,[0,-1]]=True
        source_zones=([z for z in l['zones'] if z not in zone_owner or zone_owner[z]==mid] if mid==LOCS[parent] else [])+[g['zone'] for g in zone]+(src['zones'] if src else [])
        zones=list(dict.fromkeys(source_zones))
        if largest((~s)&(k!=WATER)).sum()<60:
            # Pure ocean maps need a shore from which to call a riding Pokémon.
            if k.shape[0]<15 or k.shape[1]<17:
                k,s,pic=design('poni_beach');o=None;pt=None
            else:
                ctr=np.array([k.shape[1]//2,k.shape[0]//2]);x,y=ctr; x0,x1=x-6,x+7;y0,y1=y-5,y+6
                k[y0:y1,x0:x1]=WOOD;s[y0:y1,x0:x1]=False;tx=tile('bridge').resize((PX,PX),Image.Resampling.NEAREST)
                for yy in range(y0,y1):
                    for xx in range(x0,x1):pic.paste(tx,(xx*PX,yy*PX))
        if mid=="seafolk":alola_towns.decks(k,s);pt=o+[22,11]
        active[mid]=Area(mid,name,k,s,pic,None if pt is None or o is None else pt-o,o,zone,out,l['slug'],zones,scene)
    for index,l in locations.items():
        active[LOCS[index]].pin=l.get('map')
    return active,locations
def link(a,b,path,graph):
    if tuple(sorted([a.mid,b.mid])) in graph:return
    graph.add(tuple(sorted([a.mid,b.mid])))
    if a.scene and a.scene==b.scene and a.origin is not None and b.origin is not None:
        direction=b.origin+np.array(b.spawn)-a.origin-np.array(a.spawn)
    else:
        # Fitted entrances leave at the edge facing adjacent outdoor terrain; indoors favour the front threshold.
        direction=np.array([1,0]) if path.index(a.mid)<path.index(b.mid) else np.array([-1,0])
    def choose(p,other,d):
        if p.mid=='sandy_cave':return p.reserve(np.array([3,16]))
        if p.mid=='big_wave_beach' and other.mid=='sandy_cave':return p.reserve(np.array([4,13]))
        if p.mid.startswith('center_'):
            return p.reserve(np.array([12,20]))
        if p.mid=='home':return p.reserve(np.array([13,9]),True)
        if other.mid=='home':return p.reserve(np.array([3,4]),True)
        if p.mid=='home_1f':return p.reserve(np.array([p.w//2,p.h-2]))
        destination=getattr(other,'pin',None)
        if p.scene in ISLANDS.values() and destination and ISLANDS.get(destination['world'])==p.scene and other.scene!=p.scene:
            return p.reserve(p.position(flat(destination)),True,3)
        if p.out and not other.out and not other.scene:
            # Fit entrances at the boundary between traversable ground and architecture.
            rim=p.walk&ndimage.binary_dilation(p.s)&~(p.k==WATER)
            pts=np.argwhere(rim)[:,::-1]
            if len(pts):
                key=int.from_bytes(hashlib.sha256(other.mid.encode()).digest()[:3],'little');angle=key*2.39996
                profile=np.array(p.spawn)+[math.cos(angle)*p.w*.22,math.sin(angle)*p.h*.22]
                target=pts[np.argmin(np.sum((pts-profile)**2,axis=1))]
                return p.reserve(target,True,2)
        return p.edge(d,inside=not p.scene and not p.out)
    pa=choose(a,b,direction);pb=choose(b,a,-direction)
    x,y=a.landing(pa),b.landing(pb)
    for src,dest,door,to in [(a,b,pa,y),(b,a,pb,x)]:
        row={'at':door,'trigger':'step','alola_label':dest.name,'source_warp':'adapted_route','to':{'region':'alola','map':'alola_'+dest.mid,'at':to,'alola_native':True}}
        src.warps.append(row)
def main(cache):
    ART.mkdir(parents=True,exist_ok=True)
    maps,places=materials(cache)
    paths=list(PATHS)+['8 aether_base_8','paniola_ranch nursery']
    for n,(base,_) in SUBS.items():
        sub=base+'_'+str(n)
        prev=next((base+'_'+str(q) for q in reversed(sorted(SUBS)) if q<n and SUBS[q][0]==base),base)
        paths.append(prev+' '+sub)
    # The original dungeon is traversed before reaching its destination.
    for base,deep,destination in [('lanakila','lanakila_119','league'),('canyon','canyon_175','altar'),('canyon','canyon_175','moone')]:
        revised=[]
        for p in paths:
            words=p.split()
            if base in words and destination in words and abs(words.index(base)-words.index(destination))==1:
                pos=words.index(destination);revised+=[' '.join(words[:pos]),deep+' '+destination]
            else:revised.append(p)
        paths=revised
    edges=set()
    for path in paths:
        tokens=path.split()
        for a,b in zip(tokens,tokens[1:]):link(maps[a],maps[b],tokens,edges)
    # Retain the four cross-region entrances and update their reciprocal landing coordinates.
    for mid,reg,remote in [('seafolk','alola','alola_pass_hoenn_pacifidlog'),('hano','alola','alola_pass_aether_dock'),('altar','alola','alola_pass_ultra_megalopolis'),('hauoli','unova','unova_pass_alola_hauoli')]:
        a=maps[mid];src=ROOT/'content/regions'/reg/'maps'/(remote+'.json');d=load(src);w=next(w for w in d['warps'] if w['to']['map']=='alola_'+mid)
        door=a.edge((1,0));return_to=a.landing(door);w['to'].update({'alola_native':True,'at':return_to});save(src,d)
        at=w['at'];ww,hh=d['size'];inside=[min(max(1,at[0]),ww-2),min(max(1,at[1]),hh-2)]
        a.warps.append({'at':door,'trigger':'step','atlas':'world','alola_label':d['name'],'to':{'region':reg,'map':remote,'at':inside}})
    for a in maps.values():
        if a.mid.startswith('pelago_'):
            a.objects.append({'kind':'sign','native_fixture':True,'at':list(alola_pelago_art.OFFICE),'alola_pelago':a.mid[7:]})
        if a.mid=='sandy_cave':a.objects.extend(alola_sandy_cave.objects())
        if a.mid=='home':
            a.spawn=[8,7];a.objects.append({'at':[7,3],'kind':'wall_map','native_fixture':True})
        if a.mid=='hauoli':
            x,y=a.spawn
            for dx,dy in DIRS:
                if 0<=x+dx<a.w and 0<=y+dy<a.h and a.walk[y+dy,x+dx] and (x+dx,y+dy) not in a.used:
                    a.npcs.append({'at':[x+dx,y+dy],'name':'地区领航员','gfx':'sailor','transit':True});a.used.add((x+dx,y+dy));break
        if not a.warps:raise ValueError(('unlinked',a.mid))
        from alola_streets import frontage
        frontage(a)
        a.anchors_and_encounters()
        if a.mid in ['photo_hauoli','photo_konikoni']:
            a.objects.append({'at':[a.w//2,9],'kind':'sign','alola_club':'photo','native_fixture':True})
        if a.mid=='observatory_151':
            a.objects.append({'at':a.anchors['trainer10'],'kind':'sign','alola_club':'roller','sprite':'sign'})
            tx=sprite('console');x,y=a.anchors['trainer10'];tx=tx.resize((a.px,a.px),Image.Resampling.NEAREST)
            a.pic.paste(tx,(x*a.px,y*a.px),tx)
        save(MAPS/('alola_'+a.mid+'.json'),a.data())
    reg=load(MAPS.parent/'region.json');reg['maps']=sorted(p.stem for p in MAPS.glob('*.json'));reg['start']={'map':'alola_hauoli','at':maps['hauoli'].spawn};save(MAPS.parent/'region.json',reg)
    dest=ROOT/'content/world_destinations.json';all_data=load(dest);alola=all_data['regions']['alola']
    alola['hub']={'region':'alola','map':'alola_hauoli','at':maps['hauoli'].spawn,'npc_at':maps['hauoli'].npcs[0]['at']}
    old=[r for r in alola['locations'] if '_pass_' in r['map']]
    viewport={'melemele':(2,2,42,39),'akala':(43,27,39,44),'ulaula':(59,0,40,38),'poni':(4,52,38,43)}
    positions={}
    for island,(x,y,w,h) in viewport.items():
        island_locs=[r for r in places.values() if r['island']==island and r.get('map')]
        arr=np.array([flat(r['map']) for r in island_locs]);mn=arr.min(0);ext=np.maximum(1,arr.max(0)-mn)
        for r in island_locs:positions[LOCS[r['id']]]=ints([x,y]+(flat(r['map'])-mn)/ext*[w,h])
    locs=[]
    for n,l in places.items():
        key=LOCS[n];m=maps[key];tag='town' if key in ['iki','hauoli','heahea','konikoni','paniola','malie','po','tapu','seafolk'] else 'route' if key.isdigit() else 'landmark'
        locs.append({'id':'alola_'+key,'name':m.name,'kind':tag,'map':'alola_'+key,'at':m.spawn,'pos':positions.get(key,[49,46])})
    from alola_streets import chart
    chart(cache,places,locs,ROOT/'assets/atlas/alola.webp')
    alola['locations']=locs+old
    allowed={r['map'] for r in locs+old};alola['connections']=sorted([['alola_'+a,'alola_'+b] for a,b in edges if {'alola_'+a,'alola_'+b}<=allowed]);save(dest,all_data)
    print('Alola maps',len(maps),'native meshes or sectors',sum(bool(a.scene) for a in maps.values()),'links',sum(len(a.warps) for a in maps.values()),'items',sum(len(a.items) for a in maps.values()),'trainers',sum(len(a.trainers) for a in maps.values()))
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('atlas',type=Path);main(ap.parse_args().atlas)
