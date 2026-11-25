#!/usr/bin/env python3
"""Compile native HGSS map connections, door pairs and terrain into playable Godot fields."""
import base64
import json
import struct
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'content/hgss'
DIRS = [(0,-1,'up'),(0,1,'down'),(-1,0,'left'),(1,0,'right')]
WHIRL_1F = {
    'johto_whirl_island_nw': ((0,0,30,29), {(2,3):(11,20),(2,1):(8,16)}),
    'johto_whirl_island_ne': ((32,0,63,29), {(1,6):(37,25),(8,1):(56,9),(6,5):(51,22),(5,5):(48,21)}),
    'johto_whirl_island_sw': ((0,32,31,63), {(2,3):(8,54),(8,1):(27,49),(1,1):(6,49),(7,1):(22,47)}),
    'johto_whirl_island_se': ((32,32,63,63), {(2,6):(52,59),(2,1):(52,49)}),
}
ICE_B2 = {
    'johto_ice_path_b2_f_mahogany_side': ((0,0,31,31), {(8,0):(26,11),(4,5):(16,17),(4,4):(15,15),(0,1):(5,12),(0,8):(26,26),(5,1):(19,10),(1,2):(12,13),(1,6):(11,21),(5,5):(20,22)}),
    'johto_ice_path_b2_f_blackthorn_side': ((32,0,63,31), {(1,7):(43,22),(1,1):(50,5),(4,7):(57,24),(1,5):(44,16)}),
}
# D39R0102 scripts 000–003 specify the player's B2 landings. The B2 event
# bank lists the matching four resting rocks, which stop the ice slide.
ICE_PITS = [((11,10),(12,12),(12,13)),((10,18),(10,21),(11,21)),((18,7),(20,10),(19,10)),((19,19),(21,23),(20,22))]


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n')


def compile_fields():
    source = json.loads((DATA/'events.json').read_text())
    headers, banks = source['headers'], source['banks']
    old_maps = {p.stem:json.loads(p.read_text()) for p in (ROOT/'content/regions/johto/maps').glob('*.json')}
    terrain = (DATA/'terrain.bin').read_bytes()
    native_ids = {}
    for mid,hid in source['aliases'].items():
        if headers[hid]['entries']:
            native_ids.setdefault(hid,mid)
    for mid, alternatives in source['split_maps'].items():
        hid = alternatives[0]
        if headers[hid]['entries']:
            native_ids.setdefault(hid,mid)
    # Native passages can lead through a room that did not exist in the earlier games.
    for hid,h in headers.items():
        if h['entries'] and h['header_id'] > 1:
            native_ids.setdefault(hid,'hgss_'+hid[4:].lower())
    owners = {}
    for hid,mid in native_ids.items():
        for e in headers[hid]['entries']:
            if headers[hid]['matrix_id'] == 0:
                owners[e['column'],e['row']] = hid

    def word(hid,x,y):
        h = headers[hid]
        e = cells[hid].get((x//32,y//32))
        if e is None: return 32768
        value = struct.unpack_from('<H', terrain, e['land_id']*2048+2*(y%32*32+x%32))[0]
        # The Elite Four scripts walk the player through the gate centre and
        # animate its closure afterwards. Its unloaded model has a blocked tile.
        if hid in league_gates and (x,y)==league_gates[hid]: value &= 0x7fff
        return value

    def local(hid,event):
        ox,oy = headers[hid]['origin']
        return event['x']-ox,event['z']-oy

    def ident(hid): return banks[str(headers[hid]['event_bank'])]
    league_gates={'MAP_POKEMON_LEAGUE_'+name+'_ROOM':(6,19) for name in ('WILL','KOGA','BRUNO','KAREN')}
    league_gates['MAP_POKEMON_LEAGUE_LANCE_ROOM']=(6,25)
    cells = {}
    for hid in native_ids:
        h = headers[hid]
        ox,oy = h['origin']
        cells[hid] = {(e['column']-ox//32,e['row']-oy//32):e for e in h['entries']}
    out = DATA/'maps'
    out.mkdir(exist_ok=True)
    fields = {}
    index = {}
    merged = {}
    surf = set(source['permissions']['surfable'])
    for hid,mid in native_ids.items():
        h,bank = headers[hid],ident(hid)
        width,height = h['size']
        ox,oy = h['origin']
        old = old_maps.get(mid,{})
        def walkable(p):
            x,y = p
            return 0 <= x < width and 0 <= y < height and not word(hid,x,y)&32768
        parts = [[x*32,y*32,f"{e['land_id']}:{h['area_data_id']}"] for (x,y),e in cells[hid].items()]
        passages = {}
        reference = []
        for w in bank['warps']:
            dest = w['header']
            if dest not in native_ids: continue
            # The National Park gatehouse survives only as out-of-bounds events in the DS archive.
            if dest=='MAP_NATIONAL_PARK_UNUSED_GATEHOUSE': continue
            other = ident(dest)['warps']
            if not 0 <= w['anchor'] < len(other): continue
            p = local(hid,w)
            if not (0 <= p[0] < width and 0 <= p[1] < height): continue
            q = local(dest,other[w['anchor']])
            dw,dh = headers[dest]['size']
            if not (0 <= q[0] < dw and 0 <= q[1] < dh): continue
            # Pal Park's transfer rectangles sit beyond the south edge. The
            # actual threshold above them has DS south-exit behavior 111.
            if hid=='MAP_PAL_PARK' and word(hid,p[0],p[1]-1)&255==111:
                p=(p[0],p[1]-1)
            if dest=='MAP_PAL_PARK' and word(dest,q[0],q[1]-1)&255==111:
                q=(q[0],q[1]-2)
            behavior = word(hid,*p) & 255
            dest_behavior = word(dest,*q)&255
            trigger = {98:'right',99:'left',100:'up',101:'down',105:'door',108:'right',109:'left',110:'up',111:'down'}.get(behavior,'step')
            t = {'region':'johto','map':native_ids[dest],'at':list(q),'hgss':True}
            if dest_behavior == 105:
                if not word(dest,q[0],q[1]+1)&32768:
                    t.update(at=[q[0],q[1]+1],arrival_from=list(q),facing='down')
            passages.setdefault(p, {'at':list(p),'trigger':trigger,'to':t})
        if hid == 'MAP_MOUNT_MOON_SQUARE_ENTRANCE':
            # D02R0102 moves the two alternate destinations onto the real exits during Clefairy's dance.
            for inactive,live in [((9,7),(5,6)),((9,26),(5,25))]:
                alternate=passages.pop(inactive)['to']
                passages[live]['to']['clefairy_night']=alternate
        if hid == 'MAP_OLIVINE_LIGHTHOUSE_4F':
            # The two halves of this staircase share a transfer; only its lower half is walkable.
            assert passages[3,4]['to']==passages[3,5]['to'] and word(hid,3,4)&32768
            del passages[3,4]
        # These transfers run inside field scripts instead of the zone's warp bank.
        # D27R0105_000 jumps through the east window to the outer balcony.
        if hid == 'MAP_OLIVINE_LIGHTHOUSE_4F':
            scene = next(r for r in bank['coords'] if 'D27R0105_000' in r['scriptId'])
            x,y = local(hid,scene)
            passages[x,y] = {'at':[x,y],'trigger':'step','to':{'region':'johto','map':native_ids['MAP_OLIVINE_LIGHTHOUSE_EXTERIOR'],'at':[15,3],'facing':'down','hgss':True}}
        if hid == 'MAP_VICTORY_ROAD_3F':
            # D43R0103_002–006 pass five different landings to the common fall script.
            holes = {'002':[57,42], '003':[28,38], '004':[31,44], '005':[22,17], '006':[58,28]}
            for scene in bank['coords']:
                number = scene['scriptId'].split('D43R0103_')[-1].split()[0]
                if number in holes:
                    point = local(hid,scene)
                    passages[point] = {'at':list(point),'trigger':'step','field_drop':True,'to':{
                        'region':'johto','map':native_ids['MAP_VICTORY_ROAD_2F'],'at':holes[number],'hgss':True}}
        # The lighthouse (D27R0108) and Radio Tower (D23R0107) use a two-stop
        # lift. The entering floor chooses the destination of the dynamic exit.
        lifts = [
            ('OLIVINE_LIGHTHOUSE_ELEVATOR','OLIVINE_LIGHTHOUSE_1F','OLIVINE_LIGHTHOUSE_LIGHT_ROOM',[8,5],[8,5]),
            ('GOLDENROD_RADIO_TOWER_ELEVATOR','GOLDENROD_RADIO_TOWER_5F','GOLDENROD_RADIO_TOWER_OBSERVATION_DECK',[13,3],[8,13]),
        ]
        for cab,base,top,base_exit,top_exit in lifts:
            cab,base,top = ('MAP_'+n for n in (cab,base,top))
            key=cab.lower()
            if hid in (base,top):
                other = top if hid==base else base
                other_exit = top_exit if hid==base else base_exit
                for passage in passages.values():
                    dest=passage['to']
                    if dest['map']==native_ids[cab]:
                        dest['at']=[3,4]
                        dest['remember_passage']={'key':key,'destination':{'region':'johto','map':native_ids[other],'at':other_exit,'hgss':True}}
            elif hid==cab:
                passages[3,6]={'at':[3,6],'trigger':'down','to':{'region':'johto','map':native_ids[base],'at':base_exit,'hgss':True,'recall_passage':key}}
        if hid=='MAP_ROUTE_10':
            # The default warp is the restored building. R10's scene script
            # intercepts this doorway and sends the player to the broken plant.
            for passage in passages.values():
                dest=passage['to']
                repaired=native_ids['MAP_ROUTE_10_POWER_PLANT_REPAIRED']
                if dest['map']==repaired:
                    dest['until_power']={'region':'johto','map':native_ids['MAP_ROUTE_10_POWER_PLANT_BROKEN'],'at':[7,20],'hgss':True}
        # The badge-era ticket gates check power and the Magnet Train Pass.
        # The train cutscene returns the player to the other city's 1F (3,3).
        stations = {'MAP_GOLDENROD_MAGNET_TRAIN_STATION_1F':('MAP_SAFFRON_MAGNET_TRAIN_STATION_1F',6,6),
                    'MAP_SAFFRON_MAGNET_TRAIN_STATION_1F':('MAP_GOLDENROD_MAGNET_TRAIN_STATION_1F',14,7)}
        if hid in stations:
            other,x,y=stations[hid]
            passages[x,y]={'at':[x,y],'trigger':'up','to':{'region':'johto','map':native_ids[other],'at':[3,3],'facing':'right','hgss':True}}
        if h['matrix_id']==0:
            for (cx,cy),e in cells[hid].items():
                for dx,dy,direction in DIRS:
                    neighbor=owners.get((e['column']+dx,e['row']+dy))
                    if not neighbor or neighbor==hid: continue
                    nox,noy=headers[neighbor]['origin']
                    for i in range(32):
                        x=cx*32+(31 if dx==1 else 0 if dx==-1 else i)
                        y=cy*32+(31 if dy==1 else 0 if dy==-1 else i)
                        nx,ny=x+ox+dx-nox,y+oy+dy-noy
                        source_word,target_word=word(hid,x,y),word(neighbor,nx,ny)
                        if (source_word|target_word)&32768: continue
                        if ((source_word&255) in surf) != ((target_word&255) in surf): continue
                        target={'region':'johto','map':native_ids[neighbor],'at':[nx,ny],'connection':True,'hgss':True}
                        if (source_word&255) in surf: target['sea_connection']=True
                        passages.setdefault((x,y),{'at':[x,y],'to':target,'trigger':direction,'edge':True})
        for op in old.get('warps',[]):
            matched = [p for p,row in passages.items() if row['to']['map']==op['to']['map']]
            if matched:
                size = old['size']
                sx,sy = op['at']
                estimate=(sx*width/max(1,size[0]),sy*height/max(1,size[1]))
                near=min(matched,key=lambda p:(p[0]-estimate[0])**2+(p[1]-estimate[1])**2)
                reference.append((sx,sy,*near))
        # Isolate accessible room surfaces from the unused zero-filled DS section padding.
        reachable=set()
        seeds = [local(hid,e) for e in bank['warps']+bank['objects']]
        if hid.startswith('MAP_RUINS_OF_ALPH_') and hid.endswith('_HIDDEN_ROOM'):
            # These four rooms have no objects or warp-bank entries. The fall is a coordinate script.
            seeds.extend(local(hid,event) for event in bank['coords'])
        # A climbable cliff can be the only route to an intermediate ledge
        # with no warp or NPC. Preserve the actual walkable land at both ends.
        for y in range(height):
            for x in range(width):
                behavior = word(hid,x,y)&255
                if behavior in (75,76):
                    direction = (0,1) if behavior==75 else (1,0)
                    for sign in (-1,1):
                        p=x+sign*direction[0],y+sign*direction[1]
                        if walkable(p): seeds.append(p)
        from hgss_safari_fields import AREA, outdoors, passages as safari_passages
        if outdoors(hid):
            passages.update(safari_passages(hid,native_ids,lambda key,x,y: not word(key,x,y)&32768))
        if AREA.fullmatch(hid):
            # In the DS these twelve unwarped templates are inserted into matrix 212.
            # Adjacent cells meet at their open north, south, east and west margins.
            seeds.extend((x,y) for n in range(32) for x,y in ((0,n),(31,n),(n,0),(n,31)) if walkable((x,y)))
        seeds.extend(passages)
        seeds.append((6,6)) if hid.endswith('NEW_BARK_PLAYER_HOUSE_2F') else None
        queue=deque()
        for x,y in seeds:
            if not(0<=x<width and 0<=y<height):continue
            for dx,dy,_ in DIRS+[(0,0,'')]:
                p=x+dx,y+dy
                if walkable(p) and p not in reachable: reachable.add(p);queue.append(p)
        while queue:
            x,y=queue.popleft()
            for dx,dy,_ in DIRS:
                p=(x+dx,y+dy)
                # A cliff rim is blocked to walking, but the floor on its landing
                # side is part of the same playable cave, not unused matrix padding.
                if (word(hid,*p)&255)=={(1,0):56,(-1,0):57,(0,-1):58,(0,1):59}[(dx,dy)]:
                    p=(p[0]+dx,p[1]+dy)
                if p not in reachable and walkable(p):
                    reachable.add(p);queue.append(p)
        safe = sorted(p for p in reachable if (word(hid,*p)&255) not in surf and p not in passages)
        if not safe: safe=sorted(reachable) or [(0,0)]
        def closest(p,choices):
            return min(choices,key=lambda q:(q[0]-p[0])**2+(q[1]-p[1])**2)
        def project(pos):
            x,y=pos
            if reference:
                ranked=sorted(reference,key=lambda r:(x-r[0])**2+(y-r[1])**2)[:4]
                if (ranked[0][0],ranked[0][1])==(x,y): return list(ranked[0][2:])
                weighted=[(1/((x-a)**2+(y-b)**2), nx+2*(x-a),ny+2*(y-b)) for a,b,nx,ny in ranked]
                sw=sum(v[0] for v in weighted)
                pred=(round(sum(w*px for w,px,py in weighted)/sw),round(sum(w*py for w,px,py in weighted)/sw))
            else: pred=(2*x+1,2*y+1)
            if pred in reachable and (word(hid,*pred)&255) not in surf:return list(pred)
            return list(closest(pred,safe))
        old_size=old.get('size',[0,0])
        converted=bytearray()
        for y in range(old_size[1]):
            for x in range(old_size[0]):
                px,py=project([x,y]); converted.extend(struct.pack('<HH',px,py))
        spawn=project(old['spawn']) if old.get('spawn') else list(safe[0])
        if tuple(spawn) not in safe:spawn=list(closest(spawn,safe))
        if hid=='MAP_NEW_BARK_PLAYER_HOUSE_2F':spawn=[6,6]
        if AREA.fullmatch(hid):spawn=list(closest((15,29),safe))
        if mid in ('johto_olivine_lighthouse_1f','johto_goldenrod_game_corner','johto_ecruteak_tin_tower_entrance'):
            interior = [p for p in safe if sum((p[0]+dx,p[1]+dy) in reachable and (p[0]+dx,p[1]+dy) not in passages for dx,dy,_ in DIRS)>=3]
            if interior:spawn=list(closest(spawn,interior))
        # Preserve custom cross-region footpaths and game-specific rooms.
        targets = {r['to']['map'] for r in passages.values()}
        for w in old.get('warps',[]):
            to=w['to']
            if to['map'] in targets or to['map']==mid or to['map'] in source.get('merged_maps',{}): continue
            if to['map'] in native_ids.values() and not w.get('atlas'): continue
            p = closest(project(w['at']),[p for p in safe if p not in passages] or safe)
            if to.get('remember_passage',{}).get('key')=='johto_center':
                # Both regions use this same upstairs, but its return is the actual approach to
                # this staircase, never the old Crystal coordinates of an unrelated actor.
                near=[(p[0]+dx,p[1]+dy) for dx,dy,_ in DIRS if (p[0]+dx,p[1]+dy) in safe]
                if near:
                    back={'region':'johto','map':mid,'at':list(near[0]),'hgss':True}
                    to={**to,'remember_passage':{'key':'johto_center','destination':back}}
            passages[p]={**w,'at':list(p),'trigger':'step','to':to}
        words=bytearray()
        for y in range(height):
            for x in range(width):
                v=word(hid,x,y)
                if (x,y) not in reachable and not v&32768: v|=32768
                # DS's gym script supplies the platform collision above these rail pads.
                if hid=='MAP_AZALEA_GYM' and x in (3,9,15) and y in (8,9,16,17,18,23,24,31,32,33):
                    v &= 0x7fff
                words.extend(struct.pack('<H',v))
        bounds=[min(p[0] for p in safe),min(p[1] for p in safe),max(p[0] for p in safe),max(p[1] for p in safe)]
        body={'header':hid,'encounter_bank':('SAFARI_'+hid[-2:]) if AREA.fullmatch(hid) else h['encounter_bank'],'name':old.get('name',hid[4:].replace('_',' ').title()),'size':h['size'],'parts':parts,'bounds':bounds,
              'spawn':spawn,'warps':list(passages.values()),'terrain':base64.b64encode(words).decode(),
              'legacy_size':old_size,'legacy_xy':base64.b64encode(converted).decode()}
        if hid in ('MAP_WHIRL_ISLANDS_1F','MAP_ICE_PATH_B2F'):
            whirl=hid=='MAP_WHIRL_ISLANDS_1F'
            body['name']='漩涡列岛一层' if whirl else '冰雪小径·地下二层'
            body['extra_objects']=[]
            for old_id,(rect,anchors) in (WHIRL_1F if whirl else ICE_B2).items():
                spec=old_maps[old_id]
                room_tiles=[p for p in safe if rect[0]<=p[0]<=rect[2] and rect[1]<=p[1]<=rect[3]]
                positions=[]
                for y in range(spec['size'][1]):
                    for x in range(spec['size'][0]):
                        a,b=closest((x,y),anchors)
                        nx,ny=anchors[a,b]
                        positions.append(closest((nx+2*(x-a),ny+2*(y-b)),room_tiles))
                merged[old_id]={'map':mid,'size':spec['size'],'positions':positions}
                for obj in spec.get('objects',[]):
                    if obj.get('kind') in ('item','hidden'):
                        x,y=obj['at']
                        at=anchors.get((x,y),positions[y*spec['size'][0]+x])
                        body['extra_objects'].append({**obj,'at':list(at),'legacy_at':[x,y],'legacy_map':old_id})
        if hid=='MAP_ICE_PATH_B1F':
            body['extra_objects']=[{'kind':'boulder','at':list(local(hid,r)),'sprite':'boulder','ice_rock':r['id']} for r in bank['objects'] if r['spriteId']=='SPRITE_ROCK']
            for i,(pit,landing,_) in enumerate(ICE_PITS):
                body['warps'].append({'at':list(pit),'trigger':'step','ice_pit':i+1,'to':{'region':'johto','map':native_ids['MAP_ICE_PATH_B2F'],'at':list(landing),'hgss':True}})
        if hid=='MAP_ICE_PATH_B2F':
            for i,(_,_,rock) in enumerate(ICE_PITS):
                body['extra_objects'].append({'kind':'boulder','sprite':'boulder','at':list(rock),'ice_rest':i+1})
        if hid=='MAP_ICE_PATH_B3F':
            body['extra_objects']=[{'kind':'rock','sprite':'rock','at':list(local(hid,r))} for r in bank['objects'] if r['spriteId']=='SPRITE_BREAKROCK']
            ice=next(r for r in bank['objects'] if r['scriptId'].endswith('_nevermeltice'))
            body['native_objects']={'IcePathB3FNevermeltice':list(local(hid,ice))}
        fields[mid] = body
        index[mid]=hid
    from johto_dynamic_fields import install, registry
    install(fields,native_ids,ident,local)
    from hgss_safari_fields import install_counter
    install_counter(fields)
    for mid,field in fields.items():
        dump(out/(mid+'.json'),field)
    dump(DATA/'registry.json',registry(ROOT,fields,index,source.get('merged_maps',{})))
    dump(DATA/'map_index.json',index)
    dump(DATA/'merged_rooms.json',merged)
    for path in out.glob('*.json'):
        if path.stem not in index:path.unlink()
    print(f'{len(index)} native map headers compiled')


if __name__=='__main__': compile_fields()
