"""Compose scripted field models at their original FieldExpObj translations."""
import re
from pathlib import Path

def placements(src,z):
    gid=z['i'];rows=[];directory=''
    if src.era=='b2' and gid in (140,141,142,143,144):
        directory='gimmick_league_'+{140:'shauntal',141:'grimsley',142:'marshal',143:'caitlin',144:'champion'}[gid]
        if gid==144:
            # Room open state: Iris's stage lights and its ornate perimeter.
            rows=[(1,(256,0,768)),(5,(256,0,768))]
        elif gid==140:
            rows=[(i,(256,0,256)) for i in (0,9,29,36,39)]
        elif gid==141:
            rows=[(0,(256,0,256))]
        elif gid==142:
            rows=[(i,(256,0,256)) for i in (3,7,8)]+[(0,(248,0,120))]
        elif gid==143:
            rows=[(i,(256,0,256)) for i in (0,4,10,12,16,19)]
    if (src.era=='bw' and gid==63) or (src.era=='b2' and z['mid']=='unova_nimbasa_old_gym'):
        directory='roller_coaster'
        coords=[(360,32,600),(664,32,616),(552,32,104),(88,32,600)]
        rows=[(0,p) for p in coords]+[(2,p) for p in ((472,32,536),(216,32,264),(744,32,664),(408,32,152))]+[(19+i,p) for i,p in enumerate(coords)]
    if src.era=='b2' and gid==63:
        directory='gym_elec'
        # The stage objects use indices into the game's G3D actor resource array.
        f=src.b2/'src/field/gimmick/gym_elec.c'
        if f.exists():
            text=f.read_text()
            actors=text.split('sActors[OBJECT_COUNT] = {',1)[1].split('};',1)[0]
            assets=[int(k) for k in re.findall(r'^\s*\{\s*(\d+),',actors,re.M)]
            for name in ['sModelSetups','sStageObjectSetups','sEffectSetups']:
                table=re.search(name+r'\[[^\]]+\]\s*=\s*\{(.*?)\n\};',text,re.S)
                if not table:continue
                for n,coords in re.findall(r'\{\s*(\d+),\s*\{([^}]+)\}',table[1]):
                    numbers=[float(x) for x in re.findall(r'-?\d+(?:\.\d+)?',coords.replace('FX32_CONST',''))]
                    if len(numbers)==3 and int(n)<len(assets):rows.append((assets[int(n)],tuple(numbers)))
    for i,pos in rows:
        p=src.field/'gimmicks'/directory/('%02d'%i)/'model.glb'
        if p.exists():yield p,pos
