"""Import four native Trainer Hill layouts, directions and parties per course."""
import json,re,struct
from pathlib import Path

def compile_hill(name, puzzle, tile, source, attr):
    hit=re.fullmatch(r'TrainerHill_([1-4])F',name)
    if not hit:return
    n=int(hit[1])-1
    root=Path(__file__).resolve().parents[1]/'content'
    species={r['key']:r['id'] for r in json.loads((root/'species.json').read_text())}
    moves={r['key'].replace('_',''):r['id'] for r in json.loads((root/'moves.json').read_text())}
    moves.update(FAINTATTACK=moves['FEINTATTACK'],HIJUMPKICK=moves['HIGHJUMPKICK'],VICEGRIP=moves['VISEGRIP'] if 'VISEGRIP' in moves else moves.get('VICEGRIP'))
    tower=(source/'src/battle_tower.c').read_text()
    def array(symbol,prefix):
        body=re.search(symbol+r'\[\d+\]\s*=\s*\{(.*?)\};',tower,re.S)[1]
        return re.findall(prefix+r'\w+',body)
    graphics={}
    for g in ('Male','Female'):
        graphics.update(zip(array('gTower'+g+'FacilityClasses','FACILITY_CLASS_'),array('gTower'+g+'TrainerGfxIds','OBJ_EVENT_GFX_')))
    floors=(source/'src/data/battle_frontier/trainer_hill.h').read_text()
    for mode in ('Normal','Variety','Unique','Expert'):
        body=re.search('sFloors_'+mode+r'\[\] =\s*\{(.*?)\n\};',floors,re.S)[1]
        floor=re.split(r'\.trainerNum1\s*=',body)[n+1]
        raw=(source/re.search(r'metatileData = INCBIN_U8\("([^"]+)"',floor)[1]).read_bytes()
        collision=(source/re.search(r'collisionData = INCBIN_U16\("([^"]+)"',floor)[1]).read_bytes()
        bits=struct.unpack('<16H',collision)
        cells=[];ledge=[[0]*16 for _ in range(21)];slide=[[0]*16 for _ in range(21)]
        for i,local in enumerate(raw):
            x,y=i%16,i//16;cells.append([x,y+5,*tile(512+local),(bits[y]>>(15-x))&1])
            behavior=int(attr[512+local])&255
            if behavior==0x3b:ledge[y+5][x]=2
            if 0x44<=behavior<=0x48:slide[y+5][x]=[4,8,1,2,255][behavior-0x44]
        xy=re.findall(r'COORDS_XY\((\d+),\s*(\d+)\)',floor)
        directions=re.search(r'TRAINER_DIRS\(DIR_(\w+), DIR_(\w+)\)',floor).groups()[::-1]
        distances=re.search(r'TRAINER_RANGE\((\d+),\s*(\d+)\)',floor).groups()[::-1]
        actors=[]
        for i,section in enumerate(re.split(r'\.name = _\("',floor)[1:]):
            label=section.split('"')[0];cl=re.search(r'facilityClass = (FACILITY_CLASS_\w+)',section)[1]
            team=[]
            for row in re.split(r'\.species = SPECIES_',section)[1:]:
                mon=row.split(',')[0]
                held=re.search(r'heldItem = ITEM_(\w+)',row)
                attacks=re.findall(r'MOVE_(\w+)',re.search(r'\.moves = \{([^}]+)',row)[1])
                team.append(dict(species=species[mon],moves=[moves[k.replace('_','')] for k in attacks if k!="NONE"],held=held[1] if held else ''))
            assert len(team)==6,(name,mode,label)
            team=team[i*3:i*3+3]
            actors.append(dict(at=[int(xy[i][0]),int(xy[i][1])+5],source_gfx=graphics.get(cl,'OBJ_EVENT_GFX_BOY_1'),
                               name=label,source_script='EmeraldHillTrainer',hill_id=f'{n+1}-{i+1}',facing={'SOUTH':'up','WEST':'left','EAST':'right','NORTH':'down'}[directions[i]],sight=int(distances[i]),team=team))
        assert len(actors)==2 and len(cells)==256
        puzzle.setdefault('hill',{})[mode]=dict(tiles=cells,actors=actors,ledge=ledge,slide=slide)
