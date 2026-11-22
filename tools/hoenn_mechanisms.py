"""Read Emerald's scripted map variants and gym mechanism definitions."""
import re
import numpy as np
from PIL import Image


def compile_mechanisms(art,m,row,scripts,source,asset_folder):
    name=m['name'];layout=m['layout'];puzzle={}
    phys,blocks,attrs,primary,secondary=art.rows(layout)
    labels={k:int(v,16) for k,v in re.findall(r'#define (METATILE_\w+)\s+(0x[0-9A-Fa-f]+)',(source/'include/constants/metatile_labels.h').read_text())}
    def tile(v):
        return [art.tile_id(primary,secondary,v),art.tile_id(primary,secondary,v,True) if (attrs[v]>>12)!=1 else 0]
    def changes(label):
        body=scripts.get(name+'_'+label,'')
        return [[int(x),int(y),*tile(labels[k]),int(v=='TRUE')] for x,y,k,v in re.findall(r'setmetatile (\d+), (\d+), (METATILE_\w+), (TRUE|FALSE)',body)]
    elite={"EverGrandeCity_SidneysRoom":"h_sidney","EverGrandeCity_PhoebesRoom":"h_phoebe",
           "EverGrandeCity_GlaciasRoom":"h_glacia","EverGrandeCity_DrakesRoom":"h_drake"}
    if name in elite:
        # PokemonLeague_EliteFour_SetAdvanceToNextRoomMetatiles, data/scripts/elite_four.inc.
        cells=[[6,1,*tile(labels["METATILE_EliteFour_OpenDoor_Frame"]),0],
               [6,2,*tile(labels["METATILE_EliteFour_OpenDoor_Opening"]),0]]
        for x in (0,1,2,3,4,8,9,10,11,12):
            side="Right" if x%2==0 else "Left"
            if x>=8: side="Left" if x%2==0 else "Right"
            cells.append([x,2,*tile(labels["METATILE_EliteFour_"+side+"SpotlightOff"]),1])
        puzzle["league_exit"]={"flag":elite[name],"open":cells}
    if name=='InsideOfTruck':
        puzzle['always']=changes('OnLoad')
        puzzle['closed']=[[4,y,*tile(labels['METATILE_InsideOfTruck_DoorClosedFloor_'+suffix]),0] for y,suffix in enumerate(('Top','Mid','Bottom'),1)]
    if name=='SkyPillar_Outside':
        puzzle['pillar_door']=changes('EventScript_OpenDoor')
    if name=='SootopolisCity':
        changed,storm,*_=art.rows('LAYOUT_SOOTOPOLIS_CITY_LEGENDS_BATTLE')
        puzzle['legends']=[[x,y,*tile(int(storm[y,x])),changed['collision'][y][x]] for y,x in np.argwhere(storm!=blocks).tolist()]
        puzzle['lake_terrain']=[[x,y,changed['water'][y][x],changed['elevation'][y][x]] for y,x in np.argwhere(np.array(phys['water'])!=changed['water']).tolist()]
    if name.startswith('SkyPillar') and layout+'_CLEAN' in art.layouts:
        _,clean,*_=art.rows(layout+'_CLEAN')
        puzzle['clean']=[[x,y,*tile(int(clean[y,x])),art.rows(layout+'_CLEAN')[0]['collision'][y][x]] for y,x in np.argwhere(clean!=blocks).tolist()]
        if name in ('SkyPillar_2F','SkyPillar_4F'):
            puzzle['hole_return']='em_sky_pillar_'+('1f' if name.endswith('2F') else '3f')
    if name in ('AbandonedShip_Corridors_B1F','AbandonedShip_HiddenFloorCorridors'):
        doors={'StorageRoom':'ITEM_STORAGE_KEY'} if name=='AbandonedShip_Corridors_B1F' else {
            'Room'+str(n):'ITEM_ROOM_'+str(n)+'_KEY' for n in (1,2,4,6)}
        puzzle['ship_locks']={}
        for room,item in doors.items():
            shut=changes('EventScript_Lock'+room)
            opened=changes('EventScript_Unlock'+room)
            puzzle['ship_locks']['h_lock_'+item]={'open':opened,'closed':shut}
            at=shut[0][:2]
            warp=next(w for w in row['warps'] if w['at']==at)
            warp['trigger']='down' if room in ('Room4','Room6') else 'door'
    if name=='NewMauville_Inside':
        puzzle['power_barriers']={color:changes('EventScript_SetBarrierState'+color+'Button') for color in ('Blue','Green')}
        puzzle['power_switches']={f"{event['x']},{event['y']}":color for event in row['coord_events']
                                  for color in ('Blue','Green','Red') if event['script'].endswith('_'+color+'Button')}
        puzzle['generator_off']=changes('EventScript_SetGeneratorOffMetatiles')
    if name=='MauvilleCity_Gym':
        alt=changes('EventScript_SetAltBarriers');puzzle['alt']=alt
        puzzle['off']=[]
        for y,x in np.ndindex(blocks.shape):
            v=int(blocks[y,x])
            key=next((k for k in labels if k.startswith('METATILE_MauvilleGym_') and labels[k]==v),None)
            if key and key.endswith('_On') and key[:-3]+'_Off' in labels:
                puzzle['off'].append([x,y,*tile(labels[key[:-3]+'_Off']),0 if ('Beam' in key or 'PoleTop' in key) else phys['collision'][y][x]])
        for q in row['coord_events']:
            if 'Switch' in q['script']:puzzle.setdefault('buttons',[]).append([q['x'],q['y'],int(q['script'][-1])])
        puzzle['pressed']=tile(labels['METATILE_MauvilleGym_PressedSwitch'])
    if name=='PetalburgCity_Gym':
        gates={}
        for obj in row['objects']:
            label=obj['source_script'];body=scripts.get(label,'')
            if not label.endswith('Door') or 'VAR_0x8008' not in body:continue
            x,y=obj['at'];required=re.search(r'goto_if_not_defeated (TRAINER_\w+)',body)
            target=[int(re.search(r'setvar VAR_0x800'+i+r', (\d+)',body)[1]) for i in ('8','9')]
            gates[x,y]=required[1] if required else 'entrance'
            for w in row['warps']:
                if w['at']==[x,y]:
                    w.update(trigger='door',trainer_gate=gates[x,y])
                    w['to'].update(at=target,facing='up')
        puzzle['doors']={k:changes('EventScript_Set'+k+'RoomDoorMetatiles') for k in ['Entrance','Speed','Accuracy','Confusion','Defense','Recovery','Strength','OHKO']}
    if name=='SootopolisCity_Gym_1F':
        puzzle['stairs']=[[8,y,*tile(labels['METATILE_SootopolisGym_Stairs']),0] for y in (15,16,10,11,4,5)]
        puzzle['cracked']=tile(labels['METATILE_SootopolisGym_Ice_Cracked'])
    if name=='MossdeepCity_Gym':
        start=labels['METATILE_MossdeepGym_YellowArrow_Right']
        puzzle['arrows']={f'{x},{y}':int(blocks[y,x])-start for y,x in np.ndindex(blocks.shape) if start<=blocks[y,x]<start+40}
        colors=['Yellow','Blue','Green','Purple','Red']
        for q in row['coord_events']:
            for i,c in enumerate(colors):
                if c+'FloorSwitch' in q['script']:puzzle.setdefault('switches',{})[f"{q['x']},{q['y']}"]=i
    if name in ('FortreeCity_Gym','Route110_TrickHousePuzzle6'):
        src=(source/'src/rotating_gate.c').read_text()
        label='Fortree' if name.startswith('Fortree') else 'TrickHouse'
        body=re.search('sRotatingGate_'+label+r'PuzzleConfig\[\]\s*=\s*\{(.*?)\};',src,re.S)[1]
        gates=[[int(x),int(y),shape.lower(),int(r)//90] for x,y,shape,r in re.findall(r'\{\s*(\d+),\s*(\d+), GATE_SHAPE_(\w+), GATE_ORIENTATION_(\d+)',body)]
        puzzle['gates']=gates
        for shape in {g[2] for g in gates}:
            img=Image.open(source/'graphics/rotating_gates'/(shape+'.png'))
            out=img.convert('RGBA');out.putalpha(Image.fromarray(np.where(np.array(img)==0,0,255).astype('B')))
            out.save(asset_folder/(shape+'.png'))
        puzzle['rotation']={}
        for label,key in [('North','up'),('South','down'),('East','right'),('West','left')]:
            part=re.search('sRotatingGate_RotationInfo'+label+r'\[4 \* 4\]\s*=\s*\{(.*?)\};',src,re.S)[1]
            puzzle['rotation'][key]=[[] if s=='GATE_ROT_NONE' else [1 if 'ROT_CW' in s else -1,('NORTH','EAST','SOUTH','WEST').index(s.split('GATE_ARM_')[1].split(',')[0]),int(s[-2])] for s in re.findall(r'GATE_ROT_NONE|GATE_ROT_\w+\(GATE_ARM_\w+, \d\)',part)]
    if puzzle:row['mechanisms']=puzzle
