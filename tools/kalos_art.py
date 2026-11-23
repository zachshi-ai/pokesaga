"""Paint original buildings and terrain onto the flat Emerald field grid."""
from pathlib import Path
import numpy as np
from scipy import ndimage
from PIL import Image
from kalos_surfaces import (BLOCK,BRIDGE,FLOOR,GRASS,ICE,LAND,PURPLE,RED,ROAD,ROUGH,SAND,
                           SNOW,STAIR,STONE,VOID,WATER,WOOD,YELLOW,classify,paint)
from unova_art import K

ASSETS=Path(__file__).resolve().parents[1]/'assets'
PIX=10

def emerald_tile(key,px):
    src=Image.open(ASSETS/'unova/tiles.png').convert('RGB')
    x=K[key]%16*16;y=K[key]//16*16
    return np.array(src.crop((x,y,x+16,y+16)).resize((px,px),Image.Resampling.NEAREST))

def image(parts,origin,cells,blocked,floors,outdoor,zone,px=PIX):
    h,w=cells.shape
    pic=np.full((h*px,w*px,4),[22,29,32,255],np.uint8)
    depth=np.full(pic.shape[:2],-1e8,np.float32)
    # Smooth the walking elevation before projecting the height of a roof, tree or interior wall.
    # The feet remain aligned with a map tile even on Kalos's elevated streets.
    ok=floors>-32000
    if ok.any():
        low=ndimage.minimum_filter(np.where(ok,floors,1e8),size=7)
        points=ndimage.distance_transform_edt(low>1e6,return_distances=False,return_indices=True)
        relief=low[tuple(points)]
    else:relief=np.zeros((h,w))
    for node,name,p,uv,idx,tex,mat in parts:
        if classify(node,name,outdoor)==VOID:continue
        xx=p[:,0]/18-origin[0];zz=p[:,2]/18-origin[1]
        if xx.min()>w+7 or xx.max()<-7 or zz.min()>h+12 or zz.max()<-8:continue
        base=relief[np.clip(zz.astype(int),0,h-1),np.clip(xx.astype(int),0,w-1)]
        rise=np.maximum(-27,np.minimum(260,p[:,1]-base))/18
        ys=(zz-rise*.52)*px
        # The camera sees south-facing walls and roofs, with a fixed GBA field view.
        vertices=np.column_stack((xx*px,ys,p[:,1]/18+zz*.52,uv))
        paint(pic,depth,vertices,idx,tex)
    rgb=pic[:,:,:3].copy()
    if outdoor:
        # Native ornament, façades and shadows survive. Open grass, flower patches and water
        # take their ground pattern from Emerald; footpaths still follow the X/Y mesh.
        gy,gx=np.ogrid[:h*px,:w*px]
        depth0=np.repeat(np.repeat(floors,px,0),px,1)/18+(gy/px)*.52
        ground=np.abs(depth-depth0)<.55
        palette={LAND:'grass',GRASS:'tall',YELLOW:'flowers',RED:'flowers',PURPLE:'flowers',ROUGH:'rockfloor',WATER:'water',SAND:'sand',SNOW:'snow'}
        for category,key in palette.items():
            tile=emerald_tile(key,px)
            mask=np.repeat(np.repeat((cells==category)&(~blocked),px,0),px,1)&ground
            if category in (YELLOW,RED,PURPLE):
                colour={YELLOW:[249,213,59],RED:[226,73,87],PURPLE:[160,103,202]}[category]
                tile=tile.copy()
                bright=tile[:,:,0].astype(int)>tile[:,:,1]*1.03
                tile[bright]=colour
            if category==LAND:
                mask&=(rgb[:,:,1].astype(int)>rgb[:,:,0]*1.03)&(rgb[:,:,1].astype(int)>rgb[:,:,2]*1.04)
            if mask.any():
                tiling=tile[gy%px,gx%px]
                mix=.80 if category!=WATER else .72
                rgb[mask]=np.clip(rgb[mask]*(1-mix)+tiling[mask]*mix,0,255)
    # Indexed art in discrete GBA-like colour steps. Keep luminous windows and the cool shadow colour.
    rgb=np.uint8(np.clip(np.round((rgb.astype(float)*.95+6)/8)*8,0,248))
    return Image.fromarray(rgb).quantize(112,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
