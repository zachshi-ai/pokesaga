"""Reconstruct wild fields from X/Y grass instances and the zone's cartridge encounter methods."""
import numpy as np
from scipy import ndimage
from kalos_surfaces import GRASS,ROUGH,YELLOW,RED,PURPLE,WATER,SNOW,LAND,ROAD,STAIR,STONE,BRIDGE,put
FLOWERS={'yellow_flowers':YELLOW,'red_flowers':RED,'purple_flowers':PURPLE}
def habitats(parts,origin,cells,solid,z,number):
    methods=z.get('wild',{}).get('x',{})
    if not methods:return cells
    allowed=[(k,code) for k,code in FLOWERS.items() if k in methods]
    rough='rough_terrain' in methods
    h,w=cells.shape
    shoots=np.zeros((h,w),bool)
    depths=np.full((h,w),-1.e8,np.float32);rough_surface=np.zeros((h,w),np.int16)
    for node,name,p,uv,idx,tex,mat in parts:
        if node.endswith('_grass'):
            centers=p[idx].mean(1)
            tiles=np.floor(centers[:,[0,2]]/18).astype(int)-origin
            xx,yy=tiles.T; inside=(xx>=0)&(yy>=0)&(xx<w)&(yy<h)
            shoots[yy[inside],xx[inside]]=True
        if rough and (name.startswith(('r09_ground','r13_arachi','numa','au_numa','wi_yuki')) or 'snow' in name):
            put(depths,rough_surface,p,idx,ROUGH,origin)
    shoots=ndimage.binary_closing(shoots,structure=np.ones((3,3)))|shoots
    mask=(shoots|(cells==GRASS))&~solid&(cells!=WATER)
    if number==263:cells[mask]=ROUGH
    elif allowed:
        # The exported GARC instances preserve patch positions, while the procedural grass shader
        # has no baked colour UVs. Assign each whole bed one available local flower/grass material.
        labels,groups=ndimage.label(mask)
        beds=sorted(range(1,groups+1),key=lambda i:tuple(np.mean(np.argwhere(labels==i),axis=0)[::-1]))
        kinds=([GRASS] if 'grass' in methods else [])+[c for _,c in allowed]
        large=[i for i in beds if np.count_nonzero(labels==i)>=3]
        ids={g:kinds[i%len(kinds)] for i,g in enumerate(large)}
        for g in beds:cells[labels==g]=ids.get(g,kinds[0])
    elif 'grass'in methods:cells[mask]=GRASS
    if rough:
        mark=(rough_surface==ROUGH)&~solid&(cells!=WATER)&~np.isin(cells,[YELLOW,RED,PURPLE])
        if number==278:mark|=(cells==SNOW)&~solid
        if not mark.any() and not allowed and 'grass' not in methods:mark=(cells!=WATER)&~solid&~np.isin(cells,[STAIR,BRIDGE])
        cells[mark]=ROUGH
    return cells
