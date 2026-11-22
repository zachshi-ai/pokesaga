"""Compile physical elevator returns and the named alternate zones used by Platinum field scripts."""
from collections import defaultdict
import json
from pathlib import Path

def landing_only(header, event):
    dest=event['dest_header_id'];anchor=event['id']
    if dest=='MAP_HEADER_UNION_ROOM' or (header=='MAP_HEADER_ETERNA_CITY_GYM' and dest.endswith('_DP_GYM')):return True
    if header=='MAP_HEADER_HEARTHOME_CITY_GYM_ENTRANCE_ROOM':
        return anchor.endswith('TRAINER_ROOM_2') or anchor.endswith('LEADER_ROOM_1')
    # These are coordinates from a different water level, retained as dummy
    # destination anchors. Only the matching matrix has a real walk-off tile.
    if header in ('MAP_HEADER_LAKE_ACUITY','MAP_HEADER_LAKE_VALOR'):
        return 'LOW_WATER' in event['dest_warp_id'] or 'DRAINED' in event['dest_warp_id']
    # The actual 1F return is a scripted portal to Spear Pillar, never to 6F.
    return header=='MAP_HEADER_DISTORTION_WORLD_1F' and anchor=='WARP_MT_CORONET_6F'

def lake_tables(row):
    if row['id'] not in ('sinnoh_verity_lakefront','sinnoh_valor_lakefront','sinnoh_acuity_lakefront'):return
    slots=defaultdict(list)
    for warp in row['warps']:
        if warp.get('source_warp','').startswith('WARP_LAKE_'):
            slots[tuple(warp['at'])].append(warp['to'])
    for items in slots.values():
        alternates={w['map']:dict(w) for w in items}
        for w in items:w['platinum_alternates']=alternates

def prepare(fields):
    stops=defaultdict(list)
    byid={r['id']:r for r in fields.values()}
    for origin in fields.values():
        for warp in origin['warps']:
            if warp.get('dest_warp')!='WARP_DYNAMIC':continue
            d=byid[warp['to']['map']]
            if not d['id'].endswith('_elevator'):continue
            pos=warp['at'][:]
            if warp['trigger']=='door': pos[1]+=1
            back={'region':'sinnoh','map':origin['id'],'at':pos,'platinum_native':True,'facing':'down'}
            stops[d['id']].append(back)
            warp['to']['remember_passage']={'key':d['id'],'destination':back}
            warp['to']['at']=[3,5]
    for cid,targets in stops.items():
        r=byid[cid];door=next(e for e in r['bank']['warp_events'] if e['id']=='WARP_DYNAMIC')
        r['lift_stops']=targets
        r['warps'].append({'at':[door['x'],door['z']],'trigger':'down','to':dict(targets[0],recall_passage=cid)})
    for row in fields.values():
        name=row['id']
        if name.startswith('sinnoh_turnback_cave_'):
            for w in row['warps']:
                if w.get('source_warp','').startswith('WARP_TURNBACK_CAVE_ENTRANCE_'):
                    w['turnback_maze']=True

def links(row,fields):
    mid=row['id'];out=[]
    # FieldSail, Spear Pillar's portal and the Marsh train run from interaction scripts.
    # Only list destinations whose actions are implemented in the runtime modules.
    edges={
        'sinnoh_canalave':['sinnoh_iron_island','sinnoh_fullmoon_island'],
        'sinnoh_iron_island':['sinnoh_canalave'],'sinnoh_fullmoon_island':['sinnoh_canalave'],
        'sinnoh_canalave_city_harbor_inn':['sinnoh_newmoon_island'],'sinnoh_newmoon_island':['sinnoh_canalave'],
        'sinnoh_snowpoint':['sinnoh_fight'],'sinnoh_fight':['sinnoh_snowpoint'],
        'sinnoh_spear':['sinnoh_spear_pillar_distorted'],'sinnoh_spear_pillar_distorted':['sinnoh_distortion_world_1f'],
        'sinnoh_distortion_world_1f':['sinnoh_spear_pillar_distorted'],'sinnoh_distortion_world_giratina_room':['sinnoh_spring'],
        'sinnoh_turnback_cave_giratina_room':['sinnoh_distortion_world_turnback_cave_room'],
        'sinnoh_distortion_world_turnback_cave_room':['sinnoh_turnback_cave_giratina_room'],
        'sinnoh_pastoria_city_observatory_gate_1f':['sinnoh_great_marsh_6'],'sinnoh_great_marsh_6':['sinnoh_pastoria_city_observatory_gate_1f'],
    }
    # Conditional map replacements selected by SinnohCampaign.destination and
    # SinnohSide.destination use the same source door as the default layout.
    edges.update({
        'sinnoh_214':['sinnoh_ruin_maniac_cave_long','sinnoh_maniac_tunnel'],
        'sinnoh_228':['sinnoh_rock_peak_ruins'],
        'sinnoh_mt_coronet_1f_north_room_2':['sinnoh_iceberg_ruins'],
        'sinnoh_iron_island_b3f':['sinnoh_iron_ruins'],
        'sinnoh_mt_coronet_6f':['sinnoh_spear_pillar_dialga','sinnoh_spear_pillar_palkia']})
    if mid in ('sinnoh_spear','sinnoh_spear_pillar_dialga','sinnoh_spear_pillar_palkia'):
        out.append('sinnoh_hall_of_origin')
    out+=edges.get(mid,[])
    if mid.startswith('sinnoh_turnback_cave_') and mid!='sinnoh_turnback_cave_giratina_room':
        out+=['sinnoh_turnback_cave_pillar_room','sinnoh_turnback_cave_giratina_room','sinnoh_turnback_cave_entrance']
        out += [f'sinnoh_turnback_cave_pillar_{i}_room_{j}' for i in range(1,4) for j in range(1,7)]
    return out

def technical(name):
    # Platinum retains Diamond/Pearl layouts and unused header slots. Link-only rooms,
    # contest and facility battle views are managed by the dedicated UI scenes.
    return (name.startswith('sinnoh_unknown_') or '_dp_' in name or name.startswith('sinnoh_battle_tower_')
        or name.startswith('sinnoh_communication_club_') or name in ('sinnoh_record_mixing_room','sinnoh_wifi_plaza_entrance',
        'sinnoh_contest_hall_stage_ongoing_contest','sinnoh_underground','sinnoh_union_room'))

def fixtures(r,art):
    out=[];seen=set();w,h=r['size'];origin=r['origin']
    occupied={tuple([e['x']-origin[0],e['z']-origin[1]]) for e in r['bank'].get('bg_events',[])}
    import numpy as np
    cells=[(int(x),int(y)) for y,x in zip(*np.nonzero((r['words']&255)==131))]
    for (bx,by),land in r['rows'].items():
        for _,model,px,py in art.section(land,r['area'])['props']:
            if model not in ('pc','pc01','pc02') or r['header']['mapType']!='MAP_TYPE_INDOORS':continue
            x=bx*32-origin[0]+int(px);y=by*32-origin[1]+int(py)
            if not any(abs(x-a)<=1 and abs(y-b)<=1 for a,b in cells):cells.append((x,y))
    for x,y in cells:
        if (x,y) in seen or (x,y) in occupied:continue
        seen.add((x,y))
        out.append({'kind':'sign','baked':True,'at':[x,y],'platinum_at':[x+origin[0],y+origin[1]],'source_script':'Platinum_StoragePC'})
    return out
