#!/usr/bin/env python3
"""Compile Black and Black 2 zones, transitions, permissions and Emerald field art."""
import argparse
from collections import defaultdict
from functools import lru_cache
import json
from pathlib import Path
import re
import numpy as np
from scipy import ndimage
from unova_source import UnovaSource, names, read
from unova_locations import assign, LABELS
from unova_art import ROOT, Emerald, atlas, paint, encode

RAILS={28:1,249:17,30:2,214:15,338:20,339:21,340:22,341:23,114:5,209:13,211:14,66:4,121:6,
       241:16,242:16,243:16,244:16,36:3,255:18,137:7,140:8,141:9,142:10,143:11,144:12,464:19,424:24,0:0}
HOME={('bw',391):(5,6),('b2',428):(4,6)}
DIRECTIONS=[(-1,0),(1,0),(0,-1),(0,1)]
def tolist(at):return [int(at[0]),int(at[1])]
def nearest(cells,at):
    return cells[np.argmin(np.abs(cells-np.asarray(at)).sum(axis=1))]
def rail_data(src,z):
    from unova_rails import BW_IDS
    ids=BW_IDS if src.era=='bw' else RAILS
    if z['i'] not in ids:return None
    return src.rails[ids[z['i']]]
def rail_point(rail,index,front,side):
    if not rail or not rail['lines']:return None
    if index>=len(rail['lines']):return None
    line=rail['lines'][index]
    if line['point_a'] is None or line['point_b'] is None:return None
    pts=[rail['points'][p]['position'] for p in (line['point_a'],line['point_b'])]
    points=np.asarray([[p['x'],p['z']] for p in pts],float)/65536
    d=points[1]-points[0]
    norm=np.linalg.norm(d)
    if norm<.1:return None
    t=d/norm
    pos=points[0]+d*(front/max(1,line['length']))+np.array([-t[1],t[0]])*side
    return np.floor(pos).astype(int)

def event_point(rail,event,warp=False):
    if 'grid' in event:
        g=event['grid'];unit=16 if warp else 1
        return np.array((g['x']//unit,g['z']//unit),int)
    if 'rail' in event:
        r=event['rail']
        return rail_point(rail,r['component'],r['front'],r['side'])
    return None

def initialize(src,z):
    blocks=src.blocks(z['i'])
    if not blocks:return None
    blockpos=np.array(list(blocks))
    origin=blockpos.min(axis=0)*32
    edge=(blockpos.max(axis=0)+1)*32
    rail=rail_data(src,z)
    if rail:
        points=np.array([[q['position']['x'],q['position']['z']] for q in rail['points']])/65536
        origin=np.minimum(origin,np.floor(points.min(axis=0)-5).astype(int))
        edge=np.maximum(edge,np.ceil(points.max(axis=0)+6).astype(int))
    for (bx,by),model in blocks.items():
        t=src.terrain(model)
        if t is not None:edge=np.maximum(edge,np.array((bx*32+t.shape[1],by*32+t.shape[0])))
    w,h=edge-origin
    env=np.full((h,w),0x810001,np.uint32)
    for (bx,by),model in blocks.items():
        t=src.terrain(model)
        if t is None:continue
        x,y=(bx*32,by*32)-origin
        th,tw=t.shape
        env[y:y+th,x:x+tw]=t
    rail=rail_data(src,z)
    if rail:
        for index,line in enumerate(rail['lines']):
            for front,row in enumerate(line['tiles']):
                for i,flag in enumerate(row):
                    if int(flag,16)&0x10000:continue
                    side=i-len(row)//2
                    start=rail_point(rail,index,front,side)
                    stop=rail_point(rail,index,front+1,side)
                    if start is None or stop is None:continue
                    x,y=start-origin;ex,ey=stop-origin
                    # DS rail motion is continuous. Rasterize cardinal steps between
                    # its vertices so a diagonal rail never breaks into isolated cells.
                    distance=max(abs(ex-x),abs(ey-y),1)
                    lastx,lasty=x,y
                    for step in range(distance+1):
                        xx=round(x+(ex-x)*step/distance);yy=round(y+(ey-y)*step/distance)
                        for wx,wy in [(xx,yy),(xx,lasty)]:
                            if 0<=wx<w and 0<=wy<h:env[wy,wx]=int(flag,16)
                        lastx,lasty=xx,yy
    cp=env&65535
    water=((env&0x20000)!=0)|np.isin(cp,[0x3f,0x40,0x41,0x42,0x43,0x44])
    collision=((env&0x10000)!=0)|(cp==255)
    collision[water]=False
    grass=((env&0x40000)!=0)|((env&0x200000)!=0)
    clear=~(collision|water)
    coords=np.argwhere(clear)[:,::-1]
    if not len(coords):
        coords=np.argwhere(water)[:,::-1]
        if not len(coords):return None
        clear=water
    labels,count=ndimage.label(clear);counts=np.bincount(labels.ravel());counts[0]=0
    group=int(np.argmax(counts));main=np.argwhere(labels==group)[:,::-1]
    spawn=tolist(nearest(main,HOME.get((src.era,z['i']),tuple(np.array(z['fly'])-origin))))
    # Choose anchors with at least three neighboring walkable tiles to keep narrow passages clear.
    capacity=ndimage.convolve((labels==group).astype('uint8'),np.ones((3,3),'uint8'),mode='constant')
    spots=np.argwhere(capacity>=6)[:,::-1]
    if not len(spots):spots=main
    center=nearest(spots,main.mean(axis=0));anchors={}
    for tag,offset in zip(('story','guest1','guest2','side1','side2','side3'),[(0,0),(-2,0),(2,0),(-3,2),(3,2),(0,3)]):
        unused=spots[[tolist(a) not in anchors.values() and tolist(a)!=spawn for a in spots]]
        anchors[tag]=tolist(nearest(unused if len(unused) else spots,center+offset))
    entries=[]
    for event in z['warps']:
        raw=event_point(rail,event,True)
        if raw is None:entries.append(None);continue
        p=raw-origin
        if not (0<=p[0]<w and 0<=p[1]<h):entries.append(None);continue
        entries.append(tolist(p))
    if src.era=='b2' and z['i']==144:
        spawn=tolist(nearest(main,(16,40)))
    if z['mid']=='unova_ns_castle':
        spawn=tolist(nearest(main,(16,20)))
    return dict(z=z,blocks=blocks,origin=origin,size=[int(w),int(h)],env=env,collision=collision,water=water,grass=grass,main=main,coords=coords,anchors=anchors,spawn=spawn,entries=entries,rail=rail,warps=[],doors=[])

def append_warp(a,at,b,landing,trigger='step',source='scripted',**extra):
    a['warps'].append(dict(at=tolist(at),trigger=trigger,source_warp=source,to=dict(region='unova',map=b['z']['mid'],at=tolist(landing),unova_native=True,**extra)))

def source_links(data):
    for i,a in data.items():
        for k,(p,row) in enumerate(zip(a['entries'],a['z']['warps'])):
            b=data.get(row['zone']);end=row['warp']
            if not b or p is None:continue
            q=b['entries'][end] if end<len(b['entries']) else None
            if not q:q=b['spawn']
            # Some DS thresholds are blocked; approach them from a valid adjacent tile.
            x,y=p
            close=nearest(a['coords'],p)
            if np.abs(close-np.array(p)).sum()>1: p=tolist(close)
            x,y=p;a['collision'][y,x]=False
            landing=nearest(b['coords'],q)
            if b['z']['mid']=='unova_9' and a['z']['mid']=='unova_bw_zone_352' and tolist(landing)==[26,26]:
                landing=nearest(b['coords'],[26,27])
            if b['z']['mid']=='unova_b2_zone_568' and a['z']['mid']=='unova_b2_zone_586' and tolist(landing)==[2,6]:
                landing=nearest(b['coords'],[3,6])
            g=row.get('grid',{})
            horizontal=min(max(1,g.get('width',1)),7);vertical=min(max(1,g.get('height',1)),7)
            for dx in range(horizontal):
                for dy in range(vertical):
                    tx=x+dx;ty=y+dy
                    if tx>=a['size'][0] or ty>=a['size'][1]:continue
                    if (dx or dy) and a['collision'][ty,tx]:continue
                    append_warp(a,(tx,ty),b,landing,source='native_'+str(k))
            a['doors'].append(((x,y),b['z']))
    for a in data.values():
        code=a['env']&65535
        # The four original map behaviors are one-way ledges east, west, north, south.
        # Expose the approaches as directional edges to the route/atlas graph as well.
        for kind,dx,dy,side in [(114,1,0,'right'),(115,-1,0,'left'),(116,0,-1,'up'),(117,0,1,'down')]:
            for y,x in np.argwhere(code==kind):
                sx,sy=x-dx,y-dy;tx,ty=x+dx,y+dy
                w,h=a['size']
                if not (0<=sx<w and 0<=tx<w and 0<=sy<h and 0<=ty<h):continue
                if a['collision'][sy,sx] or a['collision'][ty,tx]:continue
                append_warp(a,(sx,sy),a,(tx,ty),side,'ledge_'+side)
    # Original overworld matrices connect neighboring chunks along each walkable edge.
    neighbors={}
    for i,a in data.items():
        if a['z']['matrix'] not in (0,1):continue
        for key in a['blocks']:neighbors[(a['z']['matrix'],)+key]=i
    for (mat,bx,by),i in neighbors.items():
        for dx,dy,front,back in [(1,0,'right','left'),(0,1,'down','up')]:
            j=neighbors.get((mat,bx+dx,by+dy))
            if j is None or i==j:continue
            a,b=data[i],data[j]
            for offset in range(32):
                glob=np.asarray([bx*32+(31 if dx else offset),by*32+(31 if dy else offset)])
                p=glob-a['origin'];q=glob+np.asarray((dx,dy))-b['origin']
                if a['collision'][p[1],p[0]] or b['collision'][q[1],q[0]]:continue
                wet=a['water'][p[1],p[0]]
                if wet!=b['water'][q[1],q[0]]:continue
                append_warp(a,p,b,q,front,'matrix',surf_arrival=bool(wet))
                append_warp(b,q,a,p,back,'matrix',surf_arrival=bool(wet))

def scripted(a,b,pa=None,pb=None,source='scripted'):
    def point(m,pos):
        existing={tuple(w['at']) for w in m['warps']}
        existing.update(tuple(p) for p in m['anchors'].values())
        options=m['main'][[tuple(p) not in existing and tolist(p)!=m['spawn'] for p in m['main']]]
        return nearest(options if len(options) else m['main'],pos if pos is not None else np.array(m['spawn'])+[2,0])
    p=point(a,pa);q=point(b,pb)
    append_warp(a,p,b,q,source=source);append_warp(b,q,a,p,source=source)

def actors(src,a):
    actors=[];ambient=[];blocked={tuple(p) for p in a['anchors'].values()}|{tuple(w['at']) for w in a['warps']}|{tuple(a['spawn'])}
    z=a['z']
    for row in z['npcs']:
        raw=event_point(a['rail'],row)
        obj=row['model'];model=src.model_codes.get(obj,-1) if isinstance(obj,str) else obj
        staged=raw is not None and tuple(raw)!=(0,0)
        at=raw-a['origin'] if raw is not None else np.array([-1,-1])
        valid=staged and 0<=at[0]<a['size'][0] and 0<=at[1]<a['size'][1]
        if valid:
            near=nearest(a['coords'],at)
            if np.abs(near-at).sum()>4:valid=False
        face=str(row.get('direction','DIR_DOWN')).removeprefix('DIR_').lower()
        cast=dict(local_id=row['id'],model=model,obj_code=str(obj),script=row.get('script',0),flag=row.get('flag',0),facing=face,
                  at=tolist(near) if valid else [],source_at=tolist(raw) if raw is not None else [])
        actors.append(cast)
        if not valid or cast['flag'] or cast['script']>=2000 or tuple(near) in blocked:continue
        if not 15<=model<=140 or model in (56,57,58):continue
        # Nurse, clerk and trainer handling is attached by the field system.
        if row.get('type','ACTOR_EVENT_TYPE_NONE')!='ACTOR_EVENT_TYPE_NONE' or len(ambient)>=8:continue
        ambient.append(dict(local_id='unova_ambient_'+str(row['id']),unova_local_id=row['id'],unova_gfx=model,at=tolist(near),name='居民',facing=face,lines=['这里是'+z['name']+'。']))
        blocked.add(tuple(near))
    return actors,ambient

def build(era,src,args):
    assign(src);r=src.field/'rails'
    from unova_rails import black_rails
    src.rails=black_rails(src) if src.era=='bw' else [read(r/('%03d.json'%h['rail'])) for h in read(r/'headers.json')['headers']]
    src.model_codes={'OBJ_CODE_'+key.upper():i for i,key in enumerate(names(src.b2,'obj_codes','OBJ_CODE_'))}
    data={}
    for z in src.zones:
        a=initialize(src,z)
        if a is not None:data[z['i']]=a
    source_links(data)
    from unova_transitions import scripted_fields
    scripted_fields(src,data,append_warp)
    from unova_transport import annotate
    annotate(src,data,append_warp)
    from unova_mechanisms import platforms
    for a in data.values():
        a['mechanisms']=platforms(a)
        for station in a['mechanisms']:
            x,y=station['from'],station['to']
            tag='mechanism_%s_%d'%(station['kind'],station['index'])
            append_warp(a,x,a,y,source=tag)
            append_warp(a,y,a,x,source=tag)
    # DS scripts control ferries, plane travel, elevators and League chamber withdrawals.
    links=[(137,138),(136,137),(97,98)]
    if era=='bw':links += [(144,264)]
    else:links += [(448,28),(107,458)]
    for i,j in links:
        if i in data and j in data:scripted(data[i],data[j])
    if era=='b2':
        import copy
        for clone,original,mid in [(1000,427,'aspertia_lookout'),(1001,552,'frigate_seaside'),(1002,552,'frigate_p2')]:
            if original not in data:continue
            m=copy.deepcopy(data[original]);m['z']['mid']='unova_'+mid;m['z']['name']=LABELS[mid];m['warps']=[];data[clone]=m
            if clone==1000:
                # Bianca waits on the actual lookout above the city at original grid (38,713).
                pos=np.asarray((38,713))-m['origin']
                # This narrative view shares Aspertia's coordinate system. Keep
                # the lookout platform and the top of its stair, not the whole city.
                px,py=pos
                mask=np.ones(m['collision'].shape,dtype=bool)
                mask[max(0,py-5):py+2,max(0,px-6):px+2]=False
                m['collision']|=mask
                m['coords']=np.argwhere(~(m['collision']|m['water']))[:,::-1]
                m['main']=m['coords']
                m['spawn']=tolist(nearest(m['coords'],pos+[-2,-3]))
                for tag,offset in zip(m['anchors'],[(-2,-4),(-3,-3),(-1,-3),(-4,-2),(-1,-1),(-3,-2)]):
                    m['anchors'][tag]=tolist(nearest(m['coords'],pos+offset))
                scripted(data[original],m,pos,pos,'lookout_stairs')
            else:
                coast=data[463 if clone==1001 else 238]
                for link in coast['warps']:
                    if link['to']['map']==data[original]['z']['mid']:link['to']['map']=m['z']['mid']
                m['warps']=copy.deepcopy(data[original]['warps'])
                if clone==1001:scripted(coast,m,source='gangplank')
    from unova_transport import scheduled_exits
    scheduled_exits(era,data)
    out=ROOT/'content/unova_native'/era;out.mkdir(parents=True,exist_ok=True)
    for i in sorted(data,key=lambda i:0 if i in (389,390,391,427,428) else i+1):
        a=data[i];z=a['z'];cast,npcs=actors(src,a)
        physics={'size':a['size'],'collision':a['collision'].astype('uint8').tolist()}
        types=a['env']&65535
        ledges=np.zeros(types.shape,'uint8')
        for kind,bit in [(114,4),(115,8),(116,1),(117,2)]:ledges[types==kind]=bit
        if ledges.any():physics['ledge']=ledges.tolist()
        objects=[];holes=types==29
        rocks=[v for v in z['npcs'] if v.get('script')==10000 and 'grid' in v]
        if rocks and holes.any():
            labels,num=ndimage.label(holes)
            physics['hole']=holes.astype('uint8').tolist()
            passable=a['collision'].copy();passable[holes]=False;physics['collision']=passable.astype('uint8').tolist()
            physics['strength_pits']=[np.argwhere(labels==k)[:,::-1].tolist() for k in range(1,num+1)]
            for v in rocks:
                if v.get('flag') in ('EVENT_FLAG_0x036b',):continue
                at=np.asarray((v['grid']['x'],v['grid']['z']))-a['origin']
                if not (0<=at[0]<a['size'][0] and 0<=at[1]<a['size'][1]):continue
                objects.append({'at':tolist(at),'legacy_at':tolist(at),'kind':'boulder','native_fixture':True,'sprite':'boulder','unova_gfx':v['model'],'flag':'unova_%s_%d_rock_%d'%(era,z['i'],v['id'])})
        for name,val in [('water',a['water']),('grass',a['grass']),('dark_grass',np.isin(a['env']&0xffff,[6,7,9,0x22]))]:
            if val.any():physics[name]=val.astype('uint8').tolist()
        existing=out/(z['mid']+'.json')
        geometry_only=args.geometry_only and existing.exists()
        art=read(existing)['hoenn_art'] if geometry_only else paint(src,z,a['blocks'],a['origin'],a['env'],a['collision'],a['water'],a['grass'],a['doors'])
        from unova_interiors import bake
        picture=None if geometry_only else bake(src,a)
        if picture:
            art['scene']=picture
        if art.get('scene'):
            art['t']=encode(np.zeros(a['collision'].shape,dtype='uint16'))
            art['p']=a.get('street_facades',art.get('p',[]) if geometry_only else [])
        enc=z['encounters']
        if era=='b2' and enc:enc='ENCOUNTERS_'+enc.upper()
        doc=dict(id=z['mid'],region='unova',name=z['name'],unova_native=True,unova_zone=z['key'],unova_zone_id=z['i'],unova_event_bank=z['bank'],unova_encounter=enc,unova_era=era,unova_origin=tolist(a['origin']),unova_mechanisms=a.get('mechanisms',[]),unova_script_links=a.get('script_links',[]),unova_dynamic_exits=bool(a.get('dynamic_exits')),unova_technical=bool(a.get('technical')),unova_technical_reason=a.get('technical',''),unova_anchors=a['anchors'],unova_cast=cast,spawn=a['spawn'],size=a['size'],physics=physics,warps=a['warps'],npcs=npcs,objects=objects,allow_fly=z['fly_from'],allow_cycling=z['cycling'],allow_running=True,hoenn_art=art)
        if 241<=i<=248:doc['map_type']='MAP_TYPE_UNDERWATER'
        from unova_services import decorate, add_phenomena
        decorate(doc)
        add_phenomena(doc,a['env'])
        (out/(z['mid']+'.json')).write_text(json.dumps(doc,default=int,ensure_ascii=False,separators=(',',':'))+'\n')
    registered={a['z']['mid'] for a in data.values()}
    for file in out.glob('*.json'):
        if file.stem not in registered and read(file).get('unova_native'):file.unlink()
    print(era,len(data),'zones',sum(len(a['warps']) for a in data.values()),'transitions',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--bw',type=Path,required=True);p.add_argument('--b2',type=Path,required=True);p.add_argument('--emerald',type=Path,required=True);p.add_argument('--geometry-only',action='store_true');p.add_argument('--apicula',type=Path);p.add_argument('--cache',type=Path,default=Path('/tmp/pokesaga-unova-models'));p.add_argument('--era',choices=['bw','b2','both'],default='both');args=p.parse_args()
    atlas(Emerald(args.emerald))
    sequel=UnovaSource(args.bw,args.b2,'b2')
    for era in (['bw','b2'] if args.era=='both' else [args.era]):
        src=sequel if era=='b2' else UnovaSource(args.bw,args.b2,era)
        src.companion=sequel
        if era=='bw' and args.apicula:
            from unova_black_models import convert
            convert(src,args.apicula,args.cache)
        build(era,src,args)
