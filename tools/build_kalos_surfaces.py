#!/usr/bin/env python3
"""Bake native X/Y scene geometry once per distinct view for the tile-map builder."""
import argparse
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
import json
from pathlib import Path
import numpy as np
from scipy import ndimage
from kalos_mesh import FieldModel
from kalos_habitats import habitats
from kalos_surfaces import bounds, raster, VOID,LAND,WATER,GRASS,ROUGH,FLOOR
from kalos_art import image
from kalos_locations import ALIAS,TOWNS,mid

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/kalos/maps'
def tile_ownership(view, origin, end):
    w,h=view['grid']
    r=view['zones']
    grid=np.repeat(np.asarray(r[::2],np.int16),r[1::2]).reshape(h,w)
    xs=np.arange(origin[0],end[0])//10;ys=np.arange(origin[1],end[1])//10
    own=grid[np.clip(ys,0,h-1)[:,None],np.clip(xs,0,w-1)[None,:]]
    own[(ys<0)|(ys>=h),:]=-1;own[:,(xs<0)|(xs>=w)]=-1
    return own

def one(task):
    root,view_id,view,zones=task
    raw=Path(root)
    dest=raw/'planes';dest.mkdir(exist_ok=True)
    parts=list(FieldModel(raw/f'view-{view_id}.glb.gzip').parts())
    lo,hi=bounds(parts)
    own=tile_ownership(view,lo,hi)
    outdoor=(view['kind']=='region' or view_id in (33,48,74,77,78,101,193,195,206,207,210,211,212,214,215,216,217,218,223,224,225,59,63))
    all_cells,all_block,all_floor,all_top=raster(parts,lo,hi,outdoor)
    rendered={}
    for number,z in zones:
        owned=own==number
        if view['kind']!='region' or not owned.any():
            owned=np.ones_like(own,bool)
        yy,xx=np.where(owned & (all_top>-32000))
        if not len(xx):yy,xx=np.where(owned)
        origin=np.maximum(0,(xx.min()-3,yy.min()-5))
        end=np.minimum(hi-lo,(xx.max()+4,yy.max()+3))
        x,y=origin;ex,ey=end;clip=np.s_[y:ey,x:ex]
        cells=all_cells[clip].copy();ok=owned[clip];solid=all_block[clip].copy() | ~ok
        if np.count_nonzero((~solid)&(cells!=WATER)) < 45:
            # Some small rooms pack the whole floor and the furniture in one texture atlas.
            # Sample the dominant horizontal height rather than opening the model's entire rectangle.
            top=all_top[clip];vals=top[(top>-32000)&ok]
            if len(vals):
                levels,counts=np.unique(np.rint(vals/4)*4,return_counts=True)
                level=levels[np.argmax(counts)]
                if number in (104,105,106):level=0
                bed=(abs(top-level)<8)&ok
                if number==303:
                    # Overhead cave walls obscure the subterranean floor in the topmost-surface pass.
                    bed=(all_floor[clip]>-32000)&ok
                solid[bed]=False;cells[bed]=FLOOR
        cells[~ok]=VOID
        absolute=lo+origin
        cells=habitats(parts,absolute,cells,solid,z,number)
        key=tuple([*origin,*end])
        if key not in rendered:
            img_id=f'xy_{view_id}_{number}' if view['kind']=='region' else f'xy_{view_id}'
            im=image(parts,absolute,cells,all_block[clip],all_floor[clip],outdoor,number)
            im.save(ART/(img_id+'.png'),optimize=True)
            rendered[key]=img_id
        np.savez_compressed(dest/(str(number)+'.npz'),origin=absolute,kind=cells,collision=solid,owner=ok,
                            height=all_floor[clip],art=rendered[key],outdoor=outdoor)
    return (view_id,len(zones))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('view',nargs='*',type=int);parser.add_argument('--jobs',type=int,default=4)
    args=parser.parse_args(); d=json.loads((args.source/'map.json').read_text());ART.mkdir(parents=True,exist_ok=True)
    grouped=defaultdict(list)
    for key,z in d['zones'].items():grouped[int(z['view'])].append((int(key),z))
    views=args.view or list(grouped)
    jobs=[(args.source,i,d['views'][str(i)],grouped[i]) for i in views]
    with ProcessPoolExecutor(args.jobs) as pool:
        for i,result in enumerate(pool.map(one,jobs)):
            if args.view or not i%20:print('Rendered',i+1,'of',len(views),result,flush=True)
if __name__=='__main__':main()
