#!/usr/bin/env python3
"""Rasterize original Sun/Moon fields into a 100-world-unit walk grid and an indexed field image."""
import argparse
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import json, re, subprocess
import numpy as np
from PIL import Image
from scipy import ndimage
from kalos_mesh import FieldModel
from kalos_surfaces import put,paint,VOID,LAND,ROAD,STONE,WATER,GRASS,ROUGH,SNOW,SAND,STAIR,BLOCK,WOOD,FLOOR,BRIDGE
from kalos_art import emerald_tile
BASE='https://3ds.pzfans.com/static/zones/pokemon-sun-moon/data/'
UNIT=100
PX=8
class Model(FieldModel):
    def texture(self,mat):
        tx=mat.get('pbrMetallicRoughness',{}).get('baseColorTexture')
        if not tx:return np.full((1,1,4),255,np.uint8),0
        tid=self.gltf['textures'][tx['index']]['extensions']['EXT_texture_webp']['source']
        if tid not in self.images:
            self.images[tid]=np.asarray(Image.open(BytesIO(self.view(self.gltf['images'][tid]['bufferView']))).convert('RGBA'))
        return self.images[tid],tx.get('texCoord',0)
def surface(node,material):
    n=material.lower()
    if re.search(r'shadow|_efct|_effect|_glow|farview|_mist|_smoke|_sky|_cloud|seaedge|fishpoint',n):return VOID
    if re.search(r'bridge|hashi|pier',n):return BRIDGE
    if re.search(r'water|_pond|_sea|deepsea|ocean|_river|_lake',n):return WATER
    if re.search(r'plant|tree|bush|yashi|bld|house|cliff|_wall|rock|roof|_saku|fence|sign|table|_chair|_bed|_obj|box|monitor|tower|_lamp|deco|shelf',n):return BLOCK
    if re.search(r'stair|step',n):return STAIR
    if re.search(r'tile|brick|stone',n):return STONE
    if re.search(r'snow|yuki',n):return SNOW
    if re.search(r'sand|beach',n):return SAND
    return LAND

def bake(spec):
    cache,name=spec; out=cache/'planes';out.mkdir(exist_ok=True)
    m=Model(cache/(name+'.glb.gzip'))
    parts=[]
    for node,mat,p,uv,ix,tex,meta in m.parts():
        code=surface(node,mat)
        if code==VOID:continue
        parts.append((code,mat.lower(),p*(18/UNIT),uv,ix,tex,meta))
    verts=np.concatenate([v[2][:,[0,2]] for v in parts]);o=np.floor(verts.min(0)/18).astype(int)-2
    w,h=(np.ceil(verts.max(0)/18).astype(int)+3)-o
    floors=np.full((h,w),-1e6,np.float32);top=floors.copy();ids=np.zeros((h,w),np.int16);objects=ids.copy()
    island=name in {"melemele","akala","ulaula","poni"}
    groundbase=floors.copy();roofs=floors.copy()
    for code,mat,p,uv,ix,tex,meta in parts:
        if island and re.search(r"ground|road|hodou|hill[0-9]|stone|_tile|beachslope",mat) and code!=BLOCK:
            put(groundbase,objects,p,ix,code,o)
        if island and re.search(r"matome|[0-9]scn|cutout|_obj[0-9]|pokecen|_house|_motel|school|_ship|library|_cafe|_police",mat):
            put(roofs,objects,p,ix,code,o)
        if code==BLOCK:put(top,objects,p,ix,code,o)
        else:put(floors,ids,p,ix,code,o)
    # Where a monolithic world material is the floor, use roof height jumps to delineate its walls.
    solid=(ids==VOID)|(top>floors+7)
    if island:
        distance,nearest=ndimage.distance_transform_edt(groundbase < -1e5,return_indices=True)
        solid|=(distance<9)&(roofs>groundbase[tuple(nearest)]+18)
    sample=np.where(ids!=0,floors,1e6)
    local=ndimage.minimum_filter(sample,size=5)
    relief=np.minimum(floors,local)
    relief=relief[tuple(ndimage.distance_transform_edt(ids==0,return_distances=False,return_indices=True))]
    rgba=np.zeros((h*PX,w*PX,4),np.uint8);rgba[:]=[30,47,54,255]
    far=np.full(rgba.shape[:2],-1e8,np.float32)
    for code,node,p,uv,ix,tex,meta in parts:
        xx=p[:,0]/18-o[0];zz=p[:,2]/18-o[1]
        base=relief[np.clip(zz.astype(int),0,h-1),np.clip(xx.astype(int),0,w-1)]
        rise=np.clip((p[:,1]-base)/18,-2,12)
        v=np.column_stack([xx*PX,(zz-rise*.46)*PX,p[:,1]/18+zz*.5,uv])
        paint(rgba,far,v,ix,tex)
    rgb=rgba[:,:,:3].copy()
    center=rgb.reshape(h,PX,w,PX,3).mean(axis=(1,3))
    r,g,b=center.transpose(2,0,1)
    water=(b>g*1.08)&(b>r*1.55)&(g>r*1.16)&(ids!=0)
    ids[water]=WATER
    ids[(ids==LAND)&(r>150)&(r>b*1.25)&(g>b*1.1)]=SAND
    # Retain buildings, cave strata and room furniture, pixelate their textures, and replace open ground with Emerald's patterns.
    for code,key,mask in [(WATER,'water',ids==WATER),(LAND,'grass',(ids==LAND)&(g>r*1.08)&(g>b*1.12)),(SAND,'sand',ids==SAND),(SNOW,'snow',ids==SNOW)]:
        take=mask&~solid
        if not take.any():continue
        positions=np.argwhere(take)
        tex=emerald_tile(key,PX)
        shaped=rgb.reshape(h,PX,w,PX,3).transpose(0,2,1,3,4)
        ys,xs=positions.T
        shaped[ys,xs]=(shaped[ys,xs].astype(np.float32)*.28+tex.astype(np.float32)*.72).astype(np.uint8)
    rgb=np.uint8(np.clip(np.round(rgb.astype(np.float32)/8)*8,0,248))
    Image.fromarray(rgb).quantize(144,dither=Image.Dither.NONE).save(out/(name+'.png'),optimize=True)
    np.savez_compressed(out/(name+'.npz'),origin=o,kind=ids,solid=solid)
    return name,w,h
def fetch(args):
    cache,name=args
    dst=cache/Path(name).name
    if not dst.exists():
        subprocess.run(['curl','--fail','--location','--silent','--show-error','--retry','4',BASE+name,'-o',str(dst)+'.part'],check=True)
        Path(str(dst)+'.part').replace(dst)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('cache',type=Path);p.add_argument('--jobs',type=int,default=3);p.add_argument('--force',action='store_true');args=p.parse_args();cache=args.cache;cache.mkdir(exist_ok=True,parents=True)
    for n in ['maps/scenes.json','locations.json','geometry.json','encounters.json','field_items.json','trainers.json','gifts.json']:fetch((cache,n))
    scenes=['melemele','akala','ulaula','poni']+[s['file'] for s in json.loads((cache/'scenes.json').read_text())['scenes']]
    with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(fetch,[(cache,'maps/'+n+'.glb.gzip') for n in scenes]))
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        for result in pool.map(bake,[(cache,n) for n in scenes if args.force or not(cache/'planes'/(n+'.npz')).exists()]):print(*result,flush=True)
if __name__=='__main__':main()
