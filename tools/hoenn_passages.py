"""Record the non-walking approaches and the rooms instantiated only by side activities."""
import re

def activity(name):
    # These fixed rooms have ordinary, reversible doors even without a facility session.
    if name in ('UnionRoom','TradeCenter','BattleFrontier_BattlePalaceBattleRoom','BattleFrontier_BattlePalaceCorridor','BattleFrontier_BattleTowerBattleRoom'):
        return ''
    if name.startswith(('BattlePyramidSquare','ContestHall')):return 'contest' if name.startswith('Contest') else 'generated_pyramid_floor'
    if name in ('BattleColosseum_2P','BattleColosseum_4P','RecordCorner','TradeCenter','UnionRoom'):return 'link_session'
    if 'BattleTent' in name and name.endswith(('BattleRoom','Corridor')):return 'battle_challenge'
    if name.startswith('BattleFrontier_Battle') and (name.endswith(('BattleRoom','PreBattleRoom','Corridor','Elevator','PartnerRoom','ThreePathRoom','RoomFinal','RoomNormal','RoomWildMons','PyramidFloor','PyramidTop'))):return 'battle_challenge'
    return ''

def record(result,ids,story):
    extras={}
    def add(mid,target,kind):
        row=dict(target={k:v for k,v in target.items() if k in ('map','region','at','hoenn_native')},kind=kind)
        if row not in extras.setdefault(mid,[]):extras[mid].append(row)
    def link(a,b,at,kind):add(a,dict(region='hoenn',map=b,at=at,hoenn_native=True),kind)
    for e in story['events']:
        for step in e['steps']:
            if 'warp' in step:add(e['map_id'],step['warp'],'story')
            for row in step.get('hoenn_transport',[]):add(e['map_id'],row['target'],'transport')
    for mid,m in result.items():
        for dive in [m.get('dive_connection',{}),*m.get('dive_at',{}).values()]:
            if dive:link(mid,dive['map'],dive.get('at',result[dive['map']]['spawn']),'dive')
    link('littleroot_town','em_inside_of_truck',[2,2],'chapter_start')
    for port in ['em_lilycove_city_harbor','em_slateport_city_harbor']:
        link(port,'em_ss_tidal_corridor',[1,10],'ss_ticket')
        link(port,'em_battle_frontier_outside_west',[19,67],'ss_ticket')
        link('em_ss_tidal_corridor',port,[8,11],'ss_ticket')
        link('em_battle_frontier_outside_west',port,[8,11],'ss_ticket')
    link('hoenn_125','hoenn_shoal',[20,30],'high_tide')
    for i in range(2,9):link('em_route110_trick_house_entrance',f'em_route110_trick_house_puzzle{i}',[0,21],'trick_house')
    port='em_lilycove_city_harbor'
    for mid,at in [('em_southern_island_exterior',[13,22]),('em_navel_rock_harbor',[8,4]),('em_birth_island_harbor',[8,4]),('em_faraway_island_entrance',[13,38])]:
        link(port,mid,at,'event_ticket')
        link(mid,port,[8,11],'event_ticket')
    for mid,m in result.items():
        for o in m['objects']:
            if 'secret_site' not in o:continue
            room=o['room']
            link(mid,room,result[room]['mechanisms']['base']['pc_at'],'secret_power')
            x,y=o['at']
            # All 75 native sites are investigated from the adjacent open tile.
            occupied={tuple(a['at']) for a in m['npcs']}
            x,y=next((x+dx,y+dy) for dx,dy in ((0,1),(-1,0),(1,0),(0,-1)) if 0<=x+dx<m['size'][0] and 0<=y+dy<m['size'][1] and not m['physics']['collision'][y+dy][x+dx] and (x+dx,y+dy) not in occupied)
            link(room,mid,[x,y],'secret_power')
        for site in m.get('mechanisms',{}).get('weather_sites',{}).values():
            if site['entry']:
                x,y=site['entry']
                link(mid,'em_terra_cave_entrance',[8,17],'weather')
                link('em_terra_cave_entrance',mid,[x,y+1],'weather')
            else:
                link(mid,'em_underwater_marine_cave',[9,7],'weather')
                link('em_underwater_marine_cave',mid,site['deep'][0],'weather')
    grouped={mid:activity(row['emerald_original']) for mid,row in result.items() if activity(row['emerald_original'])}
    return dict(activities=grouped,passages=extras)
