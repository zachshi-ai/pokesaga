"""Mark tangible counters on the original center floor and keep the healing return inside the lobby."""
import numpy as np
from scipy.ndimage import binary_dilation
from unova_art import K, encode

def decorate(data):
    from unova_crossings import attach
    attach(data)
    for actor in data.get('unova_cast',()):
        kind={10000:'boulder',10004:'cut'}.get(actor.get('script'))
        if not kind or len(actor.get('at',()))!=2:continue
        at=[int(n) for n in actor['at']]
        if kind=='boulder' and (actor.get('flag')=='EVENT_FLAG_0x036b' or
              any(obj['kind']=='boulder' and obj['at']==at for obj in data['objects'])):continue
        data['objects'].append({'at':at,'kind':kind,'unova_obstacle':True,'legacy_map':data['unova_era']+'_'+data['id']})
    actors=data.get('unova_cast',())
    nurse=next((a for a in actors if a.get('script')==2100 and len(a.get('at',()))==2),None)
    if not nurse:return
    physics=data['physics']
    block=np.array([[int(c) for c in row] for row in physics['collision']],dtype=bool)
    h,w=block.shape
    mask=np.zeros((h,w),dtype=np.uint8)
    x,y=nurse['at']
    if y+2>=h or block[y+2,x]:return
    mask[y+1,x]=1
    data['spawn']=[x,y+2]
    for row in actors:
        if int(row['model'])==77 and len(row['at'])==2:
            tx,ty=row['at']
            if tx>=2 and block[ty,tx-1] and not block[ty,tx-2]:mask[ty,tx-1]=1
    physics['counter']=mask.tolist()
    cells=np.zeros((h,w),dtype='<u2')
    floor=~block
    cells[binary_dilation(floor,iterations=1)]=K['wall']
    cells[floor]=K['clinic']
    # The checkout counters and nurse station rise from the tile beneath them.
    art=data['hoenn_art']
    props=[p for p in art['p'] if p[0] in ('pc','plant_indoor','woodstairs')]
    props.extend([['officecounter',x,y+1],['bookshelf',x-3,y],['pc',x+3,y]])
    for row in actors:
        if len(row['at'])!=2:continue
        tx,ty=row['at']
        if int(row['model'])==77 and tx>=1 and mask[ty,tx-1]:
            props.append(['carebench_compact',tx-1,ty])
    art.update(t=encode(cells),p=[list(p) for p in sorted(set(map(tuple,props)),key=lambda p:(p[2],p[1],p[0]))])

def add_phenomena(data, env):
    # Field/map/map_attr.c, MapTile_GetEncounterEffectKind. Keep this compact:
    # most maps contain no special terrain, and dry/wet surfaces may overlap.
    kind=env & 0xffff
    encounter=(env & 0x40000)!=0
    marks=np.zeros(env.shape,dtype=np.uint8)
    marks[encounter & np.isin(kind,(4,5,8,0x21))]=1
    marks[encounter & (kind==0x0a)]=2
    marks[kind==0x20]=3
    marks[encounter & np.isin(kind,(0x3d,0x3f,0x43))]=4
    if marks.any():
        data['physics']['phenomena']=[''.join(map(str,line)) for line in marks.tolist()]
