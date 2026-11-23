#!/usr/bin/env python3
"""Draw X/Y field scenes as Emerald metatiles, preserving the map's actual geometry and door feet.

Run after the Kalos map builder. The map atlas supplies geometry, UV boundaries, and
silhouettes for landmarks; none of its RGB pixels are used as game art.
"""
import argparse
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from functools import lru_cache
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from kalos_field_palette import IDS, NAMES, material, pattern, room_style
from kalos_gym_rooms import sprite, tile
from kalos_field_fixtures import dress, furnish, fixture
from kalos_locations import TOWNS
from kalos_mesh import FieldModel
from kalos_surfaces import paint, GRASS, RED, PURPLE, YELLOW, ROUGH

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT/'assets/kalos/maps'
MAPS = ROOT/'content/regions/kalos/maps'


def write(path, value):
    path.write_text(json.dumps(value,ensure_ascii=False,separators=(',',':'))+'\n')


def inks(texture, key, n, outdoor):
    """An RGBA image of material identifiers, five relief levels and a silhouette mask."""
    src=Image.fromarray(texture)
    if max(src.size)>96:src.thumbnail((96,96),Image.Resampling.BOX)
    a=np.asarray(src); col=a[:,:,:3].astype(np.int16);red,green,blue=col.transpose(2,0,1)
    valid=a[:,:,3]>128
    result=np.zeros(a.shape,np.uint8);result[:,:,3]=a[:,:,3]
    if not valid.any():return result
    lum=(red*4+green*7+blue*2)//13
    median=int(np.median(lum[valid])); span=max(66,int(np.quantile(lum[valid],.90)-np.quantile(lum[valid],.10)))
    relief=np.clip(np.rint((lum-median)*2.8/span),-3,3).astype(int)+3
    if key not in ('atlas','roof'):
        result[:,:,0]=IDS[key]
        if key in ('grass','water','tall','flower','path','sand','cobble','ground','leaves','autumn','frost','marsh','ice','snow'):
            relief=np.clip(relief,2,4)
    else:
        ids=np.full(lum.shape,IDS['plaster' if outdoor else room_style(n)[0]],np.uint8)
        # A single packed material can contain the windows, roof and stonework. Its chroma
        # separates those patches before new, world-grid-aligned materials are applied.
        ids[(red>blue+14)&(green>blue+5)]=IDS['wood' if not outdoor else 'brick']
        ids[(red>green+20)&(red>blue+20)]=IDS['redroof' if outdoor else 'carpet']
        ids[(green>red+7)&(green>blue+5)]=IDS['greenroof' if outdoor else 'vine']
        ids[(blue>red+8)&(green>red+2)]=IDS['blueroof' if outdoor else 'glass']
        ids[(blue>green+11)&(red>green+10)]=IDS['silk']
        if key=='roof':ids[(col.max(2)-col.min(2))<19]=IDS['roof']
        if outdoor:
            ids[(green>red+18)&(green>blue+25)]=IDS['leaves']
        ids[lum<36]=IDS['coal']
        result[:,:,0]=ids
    result[:,:,1]=relief
    return np.ascontiguousarray(result)


@lru_cache(None)
def lookup(px):
    # Standalone Emerald tree crowns also provide the native leaves, highlights and
    # shadow notches inside the original forest, hedge and hedge-maze silhouettes.
    patterns=np.stack([pattern(k) for k in NAMES])
    tree=sprite('tree').crop((7,9,23,25)); backing=Image.new('RGB',tree.size,'#60975e');backing.paste(tree,(0,0),tree);canopy=np.asarray(backing).astype(int)
    for name,tint in [('leaves',(0,0,0)),('autumn',(105,-19,-28)),('frost',(85,62,72))]:
        p=np.clip(canopy+np.asarray(tint),0,255).astype(np.uint8)
        patterns[IDS[name]]=p
    table=np.empty((len(NAMES),7,px,px,3),np.uint8)
    for i,p in enumerate(patterns):
        s=np.asarray(Image.fromarray(p).resize((px,px),Image.Resampling.NEAREST),dtype=float)
        for level in range(7):
            amount=(level-3)*.13
            dest=np.array([242,236,208] if amount>0 else [43,47,62])
            table[i,level]=np.rint((s+(dest-s)*abs(amount))/3)*3
    return table


def draw_plane(encoded,depth,px):
    h,w=depth.shape;result=np.empty((h,w,3),np.uint8);table=lookup(px)
    for y in range(0,h,128):
        to=min(y+128,h);ids=encoded[y:to,:,0];tone=encoded[y:to,:,1].copy()
        # South-facing eaves, raised steps and hanging galleries cast one pixel of ink
        # on both sides of a depth break. Flat paths keep a soft colour boundary.
        lower=depth[np.minimum(np.arange(y,to)+1,h-1)]
        edge=(depth[y:to]-lower>.60)&(ids!=0)
        tone[edge]=np.maximum(tone[edge].astype(int)-2,0)
        yy,xx=np.ogrid[y:to,:w]
        result[y:to]=table[ids,tone,yy%px,xx%px]
    return Image.fromarray(result)


def marker(pic,m,px):
    """Mark the exact sill for an indoor entrance on a town street, without covering an adjacent door."""
    n=m['kalos_zone']
    if n not in TOWNS and n not in (188,309,355):return
    d=ImageDraw.Draw(pic);seen=set()
    for w in m['warps']:
        t=w['to'];dest=t['map'];x,y=w['at']
        if w.get('source_warp','').startswith(('matrix','interregional')) or (x,y) in seen:continue
        if dest in ('kalos_crystals','kalos_geosenge','kalos_lumiose_central') or dest.removeprefix('kalos_').isdigit():continue
        seen.add((x,y));X=x*px;Y=y*px
        # Carpet and threshold are flat at the warp regardless of which direction the
        # source camera faced. The model of its building remains behind the actual sill.
        d.rectangle((X+1,Y+px-5,X+px-2,Y+px-1),fill='#795953')
        d.line((X+2,Y+px-4,X+px-3,Y+px-4),fill='#dfba8a')
        d.line((X+3,Y+px-2,X+px-4,Y+px-2),fill='#bd806c')


def render(raw, parts, m):
    n=m['kalos_zone']
    with np.load(raw/'planes'/f'{n}.npz') as f:
        origin=f['origin'];cells=f['kind'];height=f['height'];outdoor=bool(f['outdoor'])
    if n in (182,301,356):outdoor=True
    h,w=cells.shape
    # Big circular set-piece backdrops exceed 4,096 px at native resolution. Keep
    # their sprites aligned with a walking step and below mobile's texture limit.
    px=16 if max(h,w)<=250 else 10
    encoded=np.zeros((h*px,w*px,4),np.uint8)
    depth=np.full((h*px,w*px),-1e8,np.float32)
    ok=height>-32000
    if ok.any():
        floor=ndimage.minimum_filter(np.where(ok,height,1e8),size=7)
        coords=ndimage.distance_transform_edt(floor>1e6,return_distances=False,return_indices=True)
        ground=floor[tuple(coords)]
    else:ground=np.zeros((h,w))
    cache={}
    for node,name,p,uv,idx,texture,_ in parts:
        xx=p[:,0]/18-origin[0];zz=p[:,2]/18-origin[1]
        if xx.min()>w+6 or zz.min()>h+15 or xx.max()<-6 or zz.max()<-10:continue
        key=material(node,name,outdoor,n)
        if key is None:continue
        token=(id(texture),key)
        if token not in cache:cache[token]=inks(texture,key,n,outdoor)
        base=ground[np.clip(zz.astype(int),0,h-1),np.clip(xx.astype(int),0,w-1)]
        # The drawn feet stay at X/Y walk coordinates. Compression only affects vertical
        # projection, making a route's ledges readable in the GBA tile camera.
        rise=np.clip(p[:,1]-base,-27,260)/18
        v=np.column_stack([xx*px,(zz-rise*.52)*px,p[:,1]/18+zz*.52,uv])
        paint(encoded,depth,v,idx,cache[token])
    # Align encounter fields with the actual flower/grass masks on the walkable surface.
    for cat,brush in ((GRASS,'tall'),(RED,'redflower'),(PURPLE,'purpleflower'),(YELLOW,'yellowflower'),(ROUGH,'snow' if n==278 else 'ground')):
        ys,xs=np.where(cells==cat)
        for y,x in zip(ys,xs):
            e=encoded[y*px:(y+1)*px,x*px:(x+1)*px]
            d=depth[y*px:(y+1)*px,x*px:(x+1)*px]
            near=(abs(d-(height[y,x]/18+y*.52))<.85)|np.isin(e[:,:,0],[IDS['tall'],IDS['flower']])
            e[:,:,0][near]=IDS[brush];e[:,:,1][near]=3
    # A 3DS sloping bank or water mesh can project across the centre of a dry
    # walk tile. Resolve its water/land boundary on the walking grid, leaving
    # architectural and canopy silhouettes above the ground plane.
    if outdoor and 'water' in m['physics'] and n not in (23,):
        water=np.asarray(m['physics']['water'],bool);solid=np.asarray(m['physics']['collision'],bool)
        salt=n in (45,157,172,187,188,266,270,357)
        dry_key='sand' if salt else 'marsh' if n in (273,281) else 'snow' if n in (222,278) else 'cobble' if n in TOWNS else 'grass'
        for y in range(h):
            c=encoded[y*px:(y+1)*px];ids=c[:,:,0]
            wet=np.isin(ids,[IDS['water'],IDS['tank'],IDS['aqua']]);nonwater=np.repeat(~water[y]&~solid[y],px)
            replace=wet&nonwater[None,:];ids[replace]=IDS[dry_key];c[:,:,1][replace]=3
            # Retain small raised rocks and bridges. A surfable crossing must show
            # a water surface even if a neighbouring bank overlaps the model plane.
            for x in np.where(water[y])[0]:
                part=ids[:,x*px:(x+1)*px]
                if np.isin(part,[IDS['path'],IDS['sand'],IDS['grass'],IDS['ground'],IDS['rock'],IDS['brick'],IDS['cobble']]).mean()>.6:
                    part[:]=IDS['water'];c[:,x*px:(x+1)*px,1]=3
    pic=draw_plane(encoded,depth,px)
    pic=dress(pic,m,px)
    for kind,x,y,scale in m.get('kalos_furnishings',[]):
        if kind.startswith('xy_'):fixture(pic,kind,x,y,px,scale)
    marker(pic,m,px)
    return pic


def output_name(m):
    # The east and west halves of Route 7 share a continuous source zone.
    return 'field_'+str(m['kalos_zone'])


def bake_task(task):
    raw,view,maps,stage=task;parts=list(FieldModel(raw/f'view-{view}.glb.gzip').parts())
    out=[];rendered=set()
    for m in maps:
        n=m['kalos_zone']
        if n not in rendered:
            pic=render(raw,parts,m)
            pic.quantize(144,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).save(stage/(output_name(m)+'.png'),optimize=False)
            rendered.add(n)
        out.append((m['id'],output_name(m)))
    return out


def crossing(stage):
    # Interregional Link: the sentry path leads north from Paldea across a small
    # wooded terrace. Keep the exact left/north edge lanes and existing NPC steps.
    path=MAPS/'kalos_pass_paldea_n3.json';m=json.loads(path.read_text());w,h=m['size'];p=16
    tiles=np.full((h,w),0,np.uint8);land=Image.new('L',(w,h),0);d=ImageDraw.Draw(land)
    d.polygon([(0,0),(11,0),(13,4),(11,6),(9,6),(8,8),(1,8),(0,9)],fill=6)
    d.polygon([(18,0),(30,0),(30,9),(26,9),(24,7),(19,7),(17,4)],fill=6)
    d.polygon([(28,10),(30,10),(30,22),(20,22),(21,18),(25,17),(27,14)],fill=6)
    d.polygon([(1,16),(5,16),(7,18),(10,18),(12,22),(0,22)],fill=6)
    # The eastern stream falls through two terraces. The lower basin is a side
    # destination reached by the southern spur; the two interregional exits stay dry.
    d.line([(24,0),(24,4),(25,5),(25,8),(23,10),(23,12),(21,15),(20,18)],fill=2,width=2)
    d.polygon([(18,17),(20,16),(23,18),(22,20),(19,21),(16,20),(16,18)],fill=2)
    d.line([(0,11),(6,11),(10,13),(14,13),(17,11),(17,9),(15,7),(15,0)],fill=3,width=3)
    d.line([(12,13),(12,15),(15,17),(15,20)],fill=3,width=2)
    d.rectangle((14,10,19,13),fill=3)
    a=np.asarray(land).copy();a[0,15]=8;a[11,0]=8;a[3,14]=3;a[10,3]=0
    m['tiles']=a.tolist();m['art_props']=[]
    pic=Image.new('RGB',(w*p,h*p));d=ImageDraw.Draw(pic)
    for y in range(h):
        for x in range(w):
            v=a[y,x];key={0:'grass',2:'water',3:'path',6:'rock',8:'path'}[v]
            pic.paste(Image.fromarray(pattern(key)),(x*p,y*p))
            if v==6 and y+1<h and a[y+1,x]!=6:
                X=x*p;Y=y*p;d.rectangle((X,Y+p-8,X+p-1,Y+p-1),fill='#a59277');d.line((X,Y+p-8,X+p-1,Y+p-8),fill='#cbb697',width=2);d.line((X,Y+p-1,X+p-1,Y+p-1),fill='#807263')
            if v==2 and y>0 and a[y-1,x]!=2:d.line((x*p,y*p,(x+1)*p-1,y*p),fill='#b3c7b3',width=2)
    # Carved steps follow the rise to Couriway, with a log footrail by the lower pool.
    for y in (3,4,6):
        for x in (14,15,16):
            if a[y,x]==3:pic.paste(tile('stairs'),(x*p,y*p))
    for x in (13,14,15):
        if a[20,x]!=2:d.line((x*p,20*p+2,(x+1)*p,20*p+2),fill='#937658',width=3);d.rectangle((x*p+3,20*p-2,x*p+6,20*p+7),fill='#c0a47c',outline='#7e6b58')
    for y in range(3,h,2):
        for x in range(1+(y//3)%2,w-1,2):
            if a[y,x]!=6 or a[y-1,x]!=6:continue
            art=sprite('tree') if (x<11 and y<=8) or (x>26 and y>15) else sprite('boulder') if (x*3+y)%5==0 else None
            if art:pic.paste(art,((x+1)*p-art.width//2,(y+1)*p-art.height),art)
    for x,y in ((6,9),(9,15),(13,18),(18,7),(21,13),(11,9),(4,13)):
        if a[y,x]==0:pic.paste(tile('flowers'),(x*p,y*p))
    for row in m['objects']:
        if row['kind']=='sign':
            x,y=row['at'];a[y,x]=6;pic.paste(sprite('sign'),(x*p,y*p),sprite('sign'))
    m['tiles']=a.tolist();pic.quantize(112).save(stage/'field_couriway_pass.png')
    return m


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path);parser.add_argument('--jobs',type=int,default=3)
    parser.add_argument('--stage',type=Path,default=ART);parser.add_argument('--zones',nargs='+',type=int)
    args=parser.parse_args();args.stage.mkdir(parents=True,exist_ok=True)
    maps={};grouped=defaultdict(list);entries=defaultdict(set)
    for f in sorted(MAPS.glob('*.json')):
        m=json.loads(f.read_text());name=m.get('kalos_image','');n=m.get('kalos_zone')
        for warp in m['warps']:
            target=warp['to'];entries[target['map']].add(tuple(target['at']))
        if not name.startswith(('xy_','field_')) or n is None or args.zones and n not in args.zones:continue
        maps[m['id']]=m;grouped[m['kalos_matrix']].append(m)
    for mid,plan in maps.items():furnish(plan,entries[mid])
    phases=json.loads((ROOT/'content/kalos_geosenge.json').read_text());source=json.loads((args.source/'map.json').read_text())
    if 'kalos_geosenge' in maps and (not args.zones or 23 in args.zones):
        m=dict(maps['kalos_geosenge'],id='kalos_crater_phase',kalos_zone=23);grouped[source['zones']['23']['view']].append(m)
    jobs=[(args.source,v,rows,args.stage) for v,rows in grouped.items()];done={}
    with ProcessPoolExecutor(args.jobs) as pool:
        for batch in pool.map(bake_task,jobs):done.update(batch)
    if not args.zones:link=crossing(args.stage)
    if args.stage.resolve()==ART.resolve():
        for mid,name in done.items():
            if mid=='kalos_crater_phase':continue
            m=maps[mid];m['kalos_image']=name;m['hoenn_art']['scene'][0]='res://assets/kalos/maps/'+name+'.png';write(MAPS/(mid+'.json'),m)
        for tag,key in [('stones','kalos_geosenge'),('weapon','kalos_crystals'),('crater','kalos_crater_phase')]:
            if key in done:phases[tag]['art']=done[key]
        write(ROOT/'content/kalos_geosenge.json',phases)
        if not args.zones:
            from unova_art import encode
            link['hoenn_art']={'s':link['size'],'t':encode(np.zeros(tuple(reversed(link['size'])),np.uint16)),'scene':['res://assets/kalos/maps/field_couriway_pass.png',0,0],'p':[]};write(MAPS/'kalos_pass_paldea_n3.json',link)
            # Retire old projection files from the exported game, including their import settings.
            for png in ART.glob('xy_*.png'):
                png.unlink();png.with_suffix('.png.import').unlink(missing_ok=True)
    print(f'Drew {len(done)} X/Y zones and story phases, from {len(grouped)} original scene views.',flush=True)

if __name__=='__main__':main()
