#!/usr/bin/env python3
"""Compile pret/pokeplatinum's map matrices, paired entrances, terrain and event banks.

Run platinum_layout.py SOURCE jobs.json, then hgss_render platinum SOURCE jobs.json SAMPLES.
Run this script with SOURCE, pret/pokeemerald, SAMPLES. No ROM or network is required.
"""
from pathlib import Path
from collections import defaultdict
from functools import lru_cache
import argparse, json, re
import numpy as np
from scipy import ndimage
from platinum_layout import catalog, write, ROOT, OUT, SEABREAK, BLOOM_FIELDS
from platinum_art import Art
from platinum_map_names import map_name
import platinum_first_routes
import platinum_travel
import platinum_cycling
import platinum_league_art
from platinum_gyms import config as configure_gyms
from platinum_distortion import load as distortion_maps, install as distortion_install
DIR=[(0,-1,'up'),(0,1,'down'),(-1,0,'left'),(1,0,'right')]
FACING={'NORTH':'up','SOUTH':'down','EAST':'right','WEST':'left'}
TRIG={94:'right',95:'left',98:'right',99:'left',100:'up',101:'down',105:'door',108:'right',109:'left',110:'up',111:'down'}
SURF={16,17,18,19,20,21,25,34,42}
def local(r,e):return [e['x']-r['origin'][0],e['z']-r['origin'][1]]
def within(r,p):return 0<=p[0]<r['size'][0] and 0<=p[1]<r['size'][1]
def word(r,p):return int(r['words'][p[1],p[0]]) if within(r,p) else 32768
def ground(r,p):return not word(r,p)&32768 and (word(r,p)&255) not in SURF
def nearest(r,p,occupied=()):
    coords=np.argwhere((r['words']&32768==0)&~np.isin(r['words']&255,list(SURF)))
    if not coords.size:return [0,0]
    ids=np.argsort(abs(coords[:,0]-p[1])+abs(coords[:,1]-p[0]),kind='stable')
    for i in ids:
        y,x=map(int,coords[i])
        if (x,y) not in occupied:return [x,y]
    return [int(coords[ids[0],1]),int(coords[ids[0],0])]
def target(r,p,**extra):return {'region':'sinnoh','map':r['id'],'at':p,'platinum_native':True,**extra}
def actors(r):
    npcs=[];objects=[];coords=[]
    for o in r['bank'].get('object_events',[]):
        if 'clone' in o:
            copy=o['clone'];dest=META.get(copy['map'],{})
            original=next((v for v in dest.get('bank',{}).get('object_events',[]) if v.get('id')==copy['id']),{})
            o={**original,**o,'id':copy['id']}
        p=local(r,o); name=o['id'];trainer=o.get('trainer',{})
        npc={'at':p,'platinum_at':[o['x'],o['z']],'source_id':name,'local_id':name,
             'source_flag':o.get('hidden_flag','0'),'platinum_gfx':o['graphics_id'],'source_gfx':o['graphics_id'],
             'source_script':o.get('script',trainer.get('id','')),'facing':FACING.get(o['initial_dir'].replace('DIR_',''),'down'),
             'movement':o['movement_type'],'elevation':o['y'],'source_data':o.get('data',[]),
             'source_trainer':trainer,'trainer_type':o['trainer_type']}
        for field in ('berry_tree','signpost','clone'):
            if field in o: npc[field]=o[field]
        # Off-map actors can be moved onto the map by script later. Keep them in the roster.
        if r['source_id']=='MAP_HEADER_ETERNA_CITY_GYM':
            trainers={'LOCALID_LASS_CAROLINE':'TRAINER_LASS_CAROLINE','LOCALID_AROMA_LADY_JENNA':'TRAINER_AROMA_LADY_JENNA','LOCALID_AROMA_LADY_ANGELA':'TRAINER_AROMA_LADY_ANGELA'}
            if name in trainers:npc['source_trainer']={'id':trainers[name],'sight_range':0}
        npcs.append(npc)
    for o in r['bank'].get('bg_events',[]):
        p=local(r,o);script=o.get('script',o.get('hidden_item',''))
        obj={'at':p,'platinum_at':[o['x'],o['z']],'source_script':script,
             'source_flag':o.get('hidden_item','0'),'source_type':o.get('type','hidden_item'),
             'kind':'sign','baked':True,'source_facing':o.get('player_facing_dir','BG_EVENT_DIR_ALL')}
        if 'hidden_item' in o:obj['hidden_item']=o['hidden_item']
        objects.append(obj)
    for o in r['bank'].get('coord_events',[]):
        p=local(r,o);coords.append({**o,'platinum_at':[o['x'],o['z']],'elevation':o.get('y',0),
                                   'at':p,'x':p[0],'y':p[1],'source_script':o['script']})
    return npcs,objects,coords

def compile_maps(src,emerald,samples):
    art=Art(emerald,samples)
    compile_fields(src,samples,art,False)
    compile_fields(src,samples,art,True)
    art.save()
    platinum_league_art.dress(emerald)

def compile_fields(src,samples,art,bloom):
    global META
    META=catalog(src); old={p.stem:json.loads(p.read_text()) for p in (ROOT/'content/regions/sinnoh/maps').glob('*.json')}
    if bloom:META['MAP_HEADER_ROUTE_224']['rows'].update(SEABREAK)
    dist=distortion_maps(src,META,samples);owners=defaultdict(dict)
    @lru_cache(None)
    def chunk(n):
        b=(src/f'res/field/mapmodels/data/map_data_{n:03}.bin').read_bytes()
        return np.frombuffer(b,'<u2',1024,offset=16).reshape(32,32)
    for hid,r in META.items():
        w,h=r['size'];phys=np.full((h,w),32768,np.uint16);ox,oy=r.get('land_offset',[0,0])
        for (x,y),land in r['rows'].items():
            if r['header']['mapGroup'] in ('TownsAndRoutes','GreatMarsh'):owners[r['header']['mapGroup']][x,y]=hid
            sx=x*32-r['origin'][0]+ox; sy=y*32-r['origin'][1]+oy; phys[sy:sy+32,sx:sx+32]=chunk(land)
        if r['header']['mapType']=='MAP_TYPE_INDOORS' and hid not in dist:
            # Zero-filled cells outside the model are unused DS memory. Do not let a
            # transfer select those unbounded cells as a legal destination or spawn.
            present=np.zeros_like(phys,dtype=bool)
            for (x,y),land in r['rows'].items():
                cx=x*32-r['origin'][0]; cy=y*32-r['origin'][1]
                sec=art.section(land,r['area'])
                present[cy:cy+32,cx:cx+32]=np.array([a[0]!=0 for a in sec['surface']]).reshape(32,32)
            if present.any():
                supported=ndimage.binary_dilation(present,iterations=2)
                phys[(phys==0)&~supported]=32768
        r['words']=phys
        r['anchors']={e['id']:e for e in r['bank'].get('warp_events',[])}
    configure_gyms(src,art,META)
    for hid,r in META.items():
        r['warps']=distortion_install(hid,r,META,dist) if hid in dist else []
    for hid,r in META.items():
        warps=r['warps'];ox,oy=r['origin'];grp=r['header']['mapGroup']
        for e in r['bank'].get('warp_events',[]):
            d=META.get(e['dest_header_id']);p=local(r,e)
            if platinum_travel.landing_only(hid,e):continue
            if d is None or e.get('dest_warp_id') not in d['anchors'] or not within(r,p): continue
            anchor=d['anchors'][e['dest_warp_id']];q=local(d,anchor)
            if not within(d,q): continue
            behavior=word(r,p)&255; dest_behavior=word(d,q)&255; trigger=TRIG.get(behavior,'step')
            out=target(d,q)
            if d['id']=='sinnoh_206' and ('CYCLING_ROAD_NORTH_GATE' in hid or ('CYCLING_ROAD_SOUTH_GATE' in hid and q[1]==105)):
                out['cycling_deck']=True
            if dest_behavior==105 and ground(d,[q[0],q[1]+1]):
                out.update(at=[q[0],q[1]+1],arrival_from=q,facing='down')
            elif not ground(d,q) and (word(d,q)&255) not in SURF:
                out['at']=nearest(d,q)
            # Source stair entrances are directional and must be standable to activate.
            if trigger!='door':r['words'][p[1],p[0]]&=32767
            warps.append({'at':p,'trigger':trigger,'to':out,'source_warp':e['id'],'dest_warp':e['dest_warp_id']})
        for (bx,by),land in r['rows'].items():
            for dx,dy,side in DIR:
                other=owners[grp].get((bx+dx,by+dy))
                if other is None or other==hid:continue
                d=META[other]
                for i in range(32):
                    ax=bx*32+(31 if dx==1 else 0 if dx==-1 else i);ay=by*32+(31 if dy==1 else 0 if dy==-1 else i)
                    p=[ax-ox,ay-oy];q=[ax+dx-d['origin'][0],ay+dy-d['origin'][1]]
                    a,b=word(r,p),word(d,q)
                    if (a|b)&32768 or ((a&255) in SURF)!=((b&255) in SURF):continue
                    out=target(d,q,connection=True)
                    if (a&255) in SURF:out['sea_connection']=True
                    warps.append({'at':p,'trigger':side,'to':out})
    platinum_travel.prepare(META)
    occupied_by_map={r['id']:{tuple(local(r,n)) for n in r['bank'].get('object_events',[])} for r in META.values()}
    fields_by_id={r['id']:r for r in META.values()}
    for r in META.values():
        for wrow in r['warps']:
            to=wrow['to']; dest=fields_by_id.get(to['map'])
            if dest is None or not to.get('platinum_native') or wrow.get('mechanism'):continue
            occupied=occupied_by_map[to['map']]
            if to['map']=='sinnoh_206' and r['id']=='sinnoh_wayward_cave_1f':
                # Megan is eight levels above the hidden cave's actual entrance.
                continue
            if tuple(to['at']) in occupied:
                x,y=to['at']
                to['at']=next(([x+dx,y+dy] for dx,dy in ((0,1),(-1,0),(1,0),(0,-1))
                    if ground(dest,[x+dx,y+dy]) and (x+dx,y+dy) not in occupied),nearest(dest,to['at'],occupied))
        if bloom and r['id'] not in BLOOM_FIELDS:continue
        platinum_travel.lake_tables(r)
        w,h=r['size'];phys=r['words'];b=phys&255; col=(phys>>15).astype('uint8')
        detail={'size':[w,h],'collision':col.tolist()}
        for key,mask in [('water',np.isin(b,list(SURF))),('grass',np.isin(b,[2,3,5,6,8,11,24,36,37])),('slide',b==32),
                ('climb',np.isin(b,[75,76])),('waterfall',b==19),('counter',b==128)]:
            if mask.any():
                values=mask.astype('uint8')
                if key=='slide': values*=255
                if key=='climb': values*=b.astype('uint8')
                detail[key]=values.tolist()
        for key,lookup in [('ledge',{56:4,57:8,58:1,59:2,90:1,91:2,92:8,93:4}),
                    ('dirblock',{48:4,49:8,50:1,51:2,52:5,53:9,54:6,55:10,73:3,74:12})]:
            result=np.zeros_like(col)
            for beh,v in lookup.items():result[b==beh]=v
            if result.any():detail[key]=result.tolist()
        warps=r['warps'];npcs,objects,coords=actors(r); types=r['header']['mapType'];name=r['id']
        if name=='sinnoh_twinleaf':
            navigator=next(a for a in old[name]['npcs'] if a.get('atlas')=='world')
            hub=json.loads((ROOT/'content/world_destinations.json').read_text()).get('regions',{}).get('sinnoh',{}).get('hub',{})
            npcs.append(dict(navigator,at=hub['npc_at'],facing='left'))
        if name in ('sinnoh_spear','sinnoh_spear_pillar_dialga','sinnoh_spear_pillar_palkia'):
            objects.append({'kind':'sign','baked':True,'at':[31,52],'platinum_at':[31,52],'source_script':'Platinum_AzureFlute'})
        if name=='sinnoh_distortion_world_turnback_cave_room':
            for xy,script in [([116,74],'DistortionWorldTurnbackCaveRoom_Portal'),([89,55],'VisibleItems_Unused7321_GriseousOrb')]:
                objects.append({'kind':'sign' if 'Portal' in script else 'platinum_pickup','source_script':script,'at':xy,'platinum_at':xy,'baked':True})
        for (bx,by),land in r['rows'].items():
            for model,_,px,py in art.section(land,r['area'])['props']:
                if model!=26:continue
                gx=bx*32+int(px);gy=by*32+int(py)
                x,y=gx-r['origin'][0],gy-r['origin'][1]
                objects.append({'kind':'sign','at':[x,y],'platinum_at':[gx,gy],'source_script':'Platinum_HoneyTree','baked':True})
        objects.extend(platinum_travel.fixtures(r,art))
        if r.get('lift_stops'):
            switch=next((o for o in objects if 'Elevator' in o['source_script']),None)
            if switch is None:objects.append({'kind':'elevator','baked':True,'at':[1,5]})
            else:switch['kind']='elevator'
        occupied={tuple(a['at']) for a in npcs+objects+warps}
        sp=[w//2,h//2]
        if name=='sinnoh_twinleaf_town_player_house_2f':sp=[4,6]
        elif name=='sinnoh_twinleaf':sp=[20,22]
        else:
            for warp in warps:
                if 'pokecenter_1f' in warp['to']['map'] or (sp==[w//2,h//2] and warp.get('source_warp')):
                    sp=[warp['at'][0],warp['at'][1]+1]
        sp=nearest(r,sp,occupied)
        atlas_props=[]
        for passage in old.get(name,{}).get('warps',[]):
            if passage.get('atlas')!='world' or (passage['to']['region']=='sinnoh' and not passage['to']['map'].startswith('sinnoh_pass_')):continue
            # Integrate the cross-era walking trails at signed junctions on the
            # exterior's actual footprint, staying clear of urban lots and lakes.
            ow,oh=old[name]['size'];px,py=passage['at']
            hint=[round(px*(w-1)/max(1,ow-1)),round(py*(h-1)/max(1,oh-1))]
            labels,n=ndimage.label((col==0)&~np.isin(b,list(SURF))); sizes=np.bincount(labels.ravel())
            if n==0:continue
            component=labels[sp[1],sp[0]]
            if not component:continue
            candidates=[]
            for yy,xx in np.argwhere(labels==component):
                x,y=int(xx),int(yy)
                if (x,y) in occupied:continue
                for dx,dy,direction in DIR:
                    q=(x+dx,y+dy)
                    if not within(r,q) or not word(r,q)&32768 or (word(r,q)&255) in SURF or q in occupied:continue
                    candidates.append((abs(x-hint[0])+abs(y-hint[1]),y,x,q[1],q[0],direction));break
            if candidates:
                _,y,x,sy,sx,direction=min(candidates);atlas_props.append(['sign',sx,sy])
                warps.append({'at':[x,y],'trigger':direction,'atlas':'world','to':passage['to']})
                occupied.add((x,y))
        compiled={'id':name,'region':'sinnoh','name':map_name(r['source_id']),'platinum_native':True,'source_id':r['source_id'],
                'platinum_origin':r['origin'],'map_type':types,'spawn':sp,'size':[w,h],'physics':detail,
                'warps':warps,'npcs':npcs,'objects':objects,'coord_events':coords,
                'allow_cycling':r['header']['isBikeAllowed'],'allow_running':r['header']['isRunningAllowed'],
                'allow_fly':r['header']['isFlyAllowed'],'hoenn_art':art.make(r,phys,warps)}
        compiled['hoenn_art']['p'].extend(atlas_props)
        platinum_first_routes.dress(compiled)
        links=platinum_travel.links(r,META)
        if links:compiled['platinum_script_links']=links
        if platinum_travel.technical(name):compiled['platinum_technical']=True
        if 'lift_stops' in r:compiled['lift_stops']=r['lift_stops']
        if 'gym' in r:compiled['platinum_gym']=r['gym']
        if name.startswith('sinnoh_distortion_world_'):compiled['platinum_ride_tile']=art.shelf(15,True)
        if name=='sinnoh_206':compiled['platinum_cycling']=dict(platinum_cycling.layer(src,r))
        if name in BLOOM_FIELDS:compiled['platinum_flower']='open' if bloom else 'closed'
        write(OUT/('flower' if bloom else 'maps')/f'{name}.json',compiled)
    write(OUT/'index.json',{k:r['id'] for k,r in META.items()})
    print(f'{len(META)} Platinum fields, {sum(len(r["warps"]) for r in META.values())} passages, {len(art.images)} Emerald tiles')
if __name__=='__main__':
    import sys
    compile_maps(*map(Path,sys.argv[1:4]))
