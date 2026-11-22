"""Map-local gates and event openings used by the Emerald optional encounters."""
import re

MAPS=('Route103','Route105','Route111','Route114','Route115','Route116','Route118','Route120','Route125','Route127','Route129','Route130',
      'SealedChamber_OuterRoom','IslandCave','DesertRuins','AncientTomb','BirthIsland_Exterior','FarawayIsland_Interior','LittlerootTown_ProfessorBirchsLab','LilycoveCity_Harbor','LittlerootTown_BrendansHouse_1F')

def compile_map(name,row,puzzle,changes,tile,labels,source):
    if name in ('BirthIsland_Exterior','FarawayIsland_Interior','LittlerootTown_ProfessorBirchsLab'):puzzle['moving_legend']=True
    gates={'Route105':('h_regi_doors','CloseRegiEntrance'),'Route111':('h_regi_doors','EventScript_CloseDesertRuins'),
           'Route120':('h_regi_doors','EventScript_CloseAncientTomb'),'SealedChamber_OuterRoom':('h_regi_dig','EventScript_CloseInnerRoomEntrance'),
           'IslandCave':('h_regice_open','EventScript_HideRegiEntrance'),'AncientTomb':('h_registeel_open','EventScript_HideRegiEntrance'),
           'DesertRuins':('h_regirock_open','EventScript_HideRegiEntrance')}
    if name in gates:
        flag,script=gates[name]
        cells=changes(script)
        assert cells,(name,script)
        puzzle['sealed']={'flag':flag,'closed':cells}
    if name=='IslandCave':
        src=(source/'src/braille_puzzles.c').read_text().split('sRegicePathCoords[][2] =')[1].split('};')[0]
        puzzle['regice_lap']=[[int(x),int(y)] for x,y in re.findall(r'\{(\d+),\s*(\d+)\}',src)]
        assert len(puzzle['regice_lap'])==36
    weather=(source/'data/scripts/abnormal_weather.inc')
    if name.startswith('Route') and name[5:].isdigit():
        text=weather.read_text()
        for facing,body in re.findall('AbnormalWeather_EventScript_PlaceTiles'+name+r'(\w+)::\n((?:\t[^\n]*\n)+)',text):
            key=name.removeprefix('Route')+facing
            tiles=[];entry=[];deep=[]
            for x,y,label,collision in re.findall(r'setmetatile (\d+), (\d+), (METATILE_\w+), (TRUE|FALSE)',body):
                x,y=int(x),int(y)
                tiles.append([x,y,*tile(labels[label]),int(collision=='TRUE')])
                if 'DeepWater' in label:deep.append([x,y])
                if label.endswith('Entrance_Bottom'):entry=[x,y]
            assert entry or deep,(key,body)
            puzzle.setdefault('weather_sites',{})[key]=dict(tiles=tiles,deep=deep,entry=entry)
            if entry:
                row['objects'].append(dict(at=entry,kind='sign',native_fixture=True,source_script='WeatherDoor'+key))
    if name=='LittlerootTown_BrendansHouse_1F':
        row['objects'].append(dict(at=[1,3],kind='sign',native_fixture=True,source_script='EmeraldRoamingTV'))
