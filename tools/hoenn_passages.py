"""Record the non-walking approaches and the rooms instantiated only by side activities."""
import re

def activity(name):
    # These fixed rooms have ordinary, reversible doors even without a facility session.
    if name in ('UnionRoom','TradeCenter','BattleFrontier_BattlePalaceBattleRoom','BattleFrontier_BattlePalaceCorridor','BattleFrontier_BattleTowerBattleRoom'):
        return ''
    if name.startswith(('TerraCave_','MarineCave_')) or name=='Underwater_MarineCave':return 'temporary_abnormal_weather'
    if name.startswith('SecretBase_'):return 'player_secret_base'
    if name.startswith(('BirthIsland_','NavelRock_','FarawayIsland_','SouthernIsland_')):return 'distribution_ticket'
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
    grouped={mid:activity(row['emerald_original']) for mid,row in result.items() if activity(row['emerald_original'])}
    return dict(activities=grouped,passages=extras)
