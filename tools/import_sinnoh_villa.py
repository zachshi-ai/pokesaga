"""Import Platinum Villa footprints, its order form, and rasterize the original furniture models.

First decode the models with cargo run --release --manifest-path tools/hgss_render/Cargo.toml
--example villa -- <pokeplatinum> <mesh-cache>. Pass those same two directories below.
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

src,models=map(Path,sys.argv[1:])
root=Path(__file__).resolve().parents[1]
script=(src/'res/field/maps/villa/scripts.s').read_text()
compiled=(src/'src/overlay005/villa_furniture.c').read_text()
keys=re.findall(r'CallIfEq VAR_0x8002, VILLA_FURNITURE_(\w+), Villa_CheckMoney_',script)
prices=list(map(int,re.findall(r'^Villa_CheckMoney_\w+:\n\s*CheckMoney VAR_0x8003, (\d+)',script,re.M)))
zh=['桌子','大沙发','小沙发','床','床头柜','电视','音响组合','书柜','陈列架','盆栽','电脑桌','音乐盒','宝可梦铜像','宝可梦银像','钢琴','来客用家具','挂钟','名画','茶具','吊灯']
assert len(keys)==len(prices)==len(zh)==20
art=Image.new('RGBA',(5*96,4*112))
rows={}
for i,(key,price,name) in enumerate(zip(keys,prices,zh)):
    key=key.lower(); pieces=json.loads((models/f'{key}.json').read_text())
    points=np.array([v[0] for piece in pieces for v in piece['vertices']])
    screen=np.column_stack((points[:,0],points[:,2]-.72*points[:,1]))
    origin=np.floor(screen.min(axis=0)).astype(int); size=(np.ceil(screen.max(axis=0)).astype(int)-origin)+1
    width,height=map(int,size); rgba=np.zeros((height,width,4),dtype=np.uint8); depth=np.full((height,width),-1e10)
    for piece in pieces:
        vertices=piece['vertices']
        tex=None if piece['texture'] is None else np.array(Image.open(models/f"{key}_{piece['texture']}.png").convert('RGBA'))
        for j in range(0,len(vertices),3):
            xyz=np.array([v[0] for v in vertices[j:j+3]])
            xy=np.column_stack((xyz[:,0],xyz[:,2]-.72*xyz[:,1]))-origin
            xx,yy=np.meshgrid(np.arange(width)+.5,np.arange(height)+.5)
            a,b,c=xy; det=(a[0]-c[0])*(b[1]-c[1])-(a[1]-c[1])*(b[0]-c[0])
            if abs(det)<.025:continue
            w=((xx-c[0])*(b[1]-c[1])-(b[0]-c[0])*(yy-c[1]))/det
            v=((a[0]-c[0])*(yy-c[1])-(xx-c[0])*(a[1]-c[1]))/det
            weights=np.stack([w,v,1-w-v],axis=-1)
            z=weights@(xyz[:,1]+.72*xyz[:,2])
            mask=np.all(weights>=-.0001,axis=-1)&(z>=depth)
            if not mask.any():continue
            if tex is None: colors=np.full((height,width,4),255,dtype=np.uint8)
            else:
                uv=weights@np.array([v[1] for v in vertices[j:j+3]])
                colors=tex[(np.floor(uv[:,:,1]*tex.shape[0]).astype(int)%tex.shape[0]),(np.floor(uv[:,:,0]*tex.shape[1]).astype(int)%tex.shape[1])]
            shading=weights@np.array([v[2] for v in vertices[j:j+3]])
            colors=np.rint(np.clip(colors*shading*np.array(piece['color'])/(255.*255.),0,255)).astype(np.uint8)
            mask&=colors[:,:,3]>12
            rgba[mask]=colors[mask];depth[mask]=z[mask]
    assert width<=96 and height<=112,(key,size)
    u,v=i%5*96,i//5*112
    art.paste(Image.fromarray(rgba),(u,v))
    rows[key]={'name':name,'price':price,'texture':[u,v,width,height],'offset':origin.tolist(),'placements':[]}
chunks=re.findall(r'\.furnitureType = VILLA_FURNITURE_(\w+),(.*?)\n    },',compiled,re.S)
for key,block in chunks:
    if '.position' not in block:continue
    coords=[]
    for axis in ['x','z']:
        edge,n=re.search(fr'\.{axis} = MAP_OBJECT_COORD_(EDGE|CENTER)_TO_FX32\((\d+)\)',block).groups()
        coords.append(int(n)*16+(8 if edge=='CENTER' else 0))
    bounds=re.findall(r'\.(?:left|top|right|bottom) = (\d+)',block)
    rows[key.lower()]['placements'].append({'anchor':coords,'bounds':list(map(int,bounds)) if '.isCollisionEnabled = TRUE' in block else []})
for key,row in rows.items():assert row['placements'],key
# The open order book sits on the table in the same 16-pixel field scale.
book=Image.new('RGBA',(13,11));pen=ImageDraw.Draw(book)
pen.polygon([(0,2),(4,1),(6,2),(9,0),(12,1),(12,8),(7,10),(5,9),(0,10)],fill='#564232')
pen.polygon([(1,2),(4,2),(6,3),(6,8),(3,7),(1,8)],fill='#ecd699')
pen.polygon([(7,3),(10,1),(11,2),(11,7),(7,8)],fill='#fff1bf')
pen.line([(2,4),(4,4)],fill='#986c4a');pen.line([(8,4),(10,3)],fill='#986c4a')
art.alpha_composite(book,(425,92))
art.save(root/'assets/platinum/villa.png')
(root/'content/sinnoh_villa.json').write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':'))+'\n')
