"""Fit Emerald scenery to Platinum's opening towns and the GBA demake's surveyed paths.

Input layouts: sinnoh-remakes/pokeemerald-platinum e74208ef7922bb252ac585c07e73ddae5f3ee42d.
Only the path, planted area and fence positions are read from those layouts. All tiles and
facades in the output come from the local Emerald resources or are drawn in their palettes.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from bake_emerald_field import Emerald, TOWN
from platinum_layout import OUT, ROOT, write
from johto_gba_outdoor import AUTOTILES

ASSETS = ROOT / 'assets/platinum_native/streets'
# Offsets verified against all nine native house doors and the Route 201 arrow / tips signs.
SURVEY = {'sinnoh_twinleaf': ('TwinleafTown', 4, -2),
          'sinnoh_201': ('Route201', 0, 8),
          'sinnoh_sandgem': ('SandgemTown', -2, -2)}
# DS movement and GBA metatiles share a 16-pixel walking grid.
ROAD = {0x10:(0,0),0x11:(0,1),0x12:(0,2),0x18:(1,0),0x19:(1,1),0x1a:(1,2),
        0x20:(2,0),0x21:(2,1),0x22:(2,2)}
FENCES = {0x2a,0x2b,0x2c,0x32,0x33,0x3a,0x3b,0x3c}
FLOWERS = {0x09,0x14,0x17}
DOOR_TILES = {'home_red','home_green','home_blue','home_city','lab','mart','center'}
HOUSES = {'sinnoh_twinleaf': {(9,11):'rival',(20,21):'player',(20,11):'cottage',(10,21):'cottage'},
          'sinnoh_sandgem': {(7,22):'cottage',(16,22):'helper'}}


def fence_form(tiles, x, y):
    def is_fence(xx, yy):
        return 0 <= xx < tiles.shape[1] and 0 <= yy < tiles.shape[0] and tiles[yy,xx] in FENCES
    return tuple(is_fence(x+dx,y+dy) for dx,dy in ((-1,0),(1,0),(0,-1),(0,1)))


def draw_fence(im, x, y, links):
    """A waist-high twin rail. Corner posts meet along the original planted enclosure."""
    d=ImageDraw.Draw(im); x=x*16; y=y*16
    edge,shade,top='#5d5c56','#bcb99b','#efead3'
    left,right,up,down=links
    for dy in (3,8):
        if left or right:
            a=x if left else x+7; b=x+15 if right else x+9
            d.rectangle((a,y+dy,b,y+dy+2), fill=edge)
            d.line((a,y+dy,b,y+dy), fill=top)
    if up or down:
        for dx in (7,10):
            d.line((x+dx,y if up else y+3,x+dx,y+15 if down else y+9),fill=shade)
    for px in ([2,10] if left and right else [7]):
        d.rectangle((x+px,y+1,x+px+3,y+11),fill=edge)
        d.rectangle((x+px,y+2,x+px+2,y+9),fill=shade)
        d.line((x+px+1,y,x+px+2,y),fill=top)
        d.line((x+px,y+2,x+px,y+8),fill=top)


def yard_art(emerald, ref, mid, doc):
    name,dx,dy=SURVEY[mid]
    dirs=ref/'data/layouts'
    meta=next(a for a in json.loads((dirs/'layouts.json').read_text())['layouts']
              if a['name']==name+'_Layout')
    tiles=np.fromfile(dirs/name/'map.bin',dtype='<u2').reshape(meta['height'],meta['width']) & 1023
    w,h=doc['size'];im=Image.new('RGBA',(16*w,16*h));water=doc['physics'].get('water',[])
    flower=emerald.metatile(TOWN,4); lawn=emerald.metatile(TOWN,1)
    beach=emerald.metatile('Route109', 0x124)
    for yy,xx in np.ndindex(tiles.shape):
        x,y=xx+dx,yy+dy
        if not (0<=x<w and 0<=y<h) or water and water[y][x]:continue
        code=int(tiles[yy,xx]); chip=None
        if code in ROAD:
            row,col=ROAD[code];chip=emerald.metatile(TOWN,AUTOTILES['trail'][row][col])
        elif mid=='sinnoh_sandgem' and code in (0x90,0x91,0x97,0x98,0x99,0x9b,0x9c,0x9e,0x9f,0xa0,0xa6):
            # Sandgem's beach leads straight onto Route 219. Keep cliff and tree footprints.
            if not doc['physics']['collision'][y][x]:chip=beach
        elif code in FLOWERS:chip=flower
        elif code in FENCES:
            # Match the visible fence to the actual blocked cell in Platinum.
            if doc['physics']['collision'][y][x]:
                im.alpha_composite(lawn,(x*16,y*16));draw_fence(im,x,y,fence_form(tiles,xx,yy))
            continue
        if chip:im.alpha_composite(chip,(x*16,y*16))
    if mid=='sinnoh_twinleaf':
        # The square retaining wall around the southern pond follows the real surf cells.
        pen=ImageDraw.Draw(im)
        def is_water(x, y):
            return 0<=x<w and 0<=y<h and water[y][x]
        for y in range(h):
            for x in range(w):
                if not is_water(x,y):continue
                left,top=x*16,y*16
                if not is_water(x,y-1):
                    for k,color in enumerate(('#545657','#a59c8d','#7b7672','#53677b')):
                        pen.line((left,top+k,left+15,top+k),fill=color)
                    pen.point((left+7,top+1),fill='#7b7672')
                if not is_water(x-1,y):pen.line((left,top,left,top+15),fill='#706b66',width=2)
                if not is_water(x+1,y):pen.line((left+15,top,left+15,top+15),fill='#706b66',width=2)
        # The GBA layout's two flower beds occupy the lawns either side of the north lane.
        for x,y in [(7,4),(9,4),(10,5),(21,4),(23,5),(25,4)]:
            if not doc['physics']['collision'][y][x]:im.alpha_composite(flower,(x*16,y*16))
    im.save(ASSETS/(mid+'.png'),optimize=True)


def make_facades():
    field=ROOT/'assets/emerald/field'
    for dest,source,main,bright in [
            ('player','home','#388678','#86bd88'),('rival','home','#387c79','#73a996'),
            ('helper','home','#4f80a7','#91bcd8'),('cottage','home_green','#538673','#9abd95')]:
        img=Image.open(field/(source+'.png')).convert('RGBA')
        px=img.load();roof_height=img.height//2
        # Preserve the baked roof outlines, highlights and tile seams of the Emerald house.
        dark=(45,66,72);lo=tuple(bytes.fromhex(main[1:]));hi=tuple(bytes.fromhex(bright[1:]))
        for y in range(roof_height+5):
            for x in range(img.width):
                r,g,b,a=px[x,y]
                if a and ((r>g and r>b+15) if source=='home' else g>r and g>b):
                    value=(r*3+g*5+b*2)//10
                    rgb=hi if value>=202 else tuple((lo[i]+hi[i])//2 for i in range(3)) if value>=160 else lo if value>=112 else dark
                    px[x,y]=(*rgb,a)
        if dest!='cottage':
            d=ImageDraw.Draw(img)
            d.rectangle((15,4,21,15),fill='#485b61')
            d.rectangle((16,5,19,13),fill='#bbad98')
            d.rectangle((14,3,22,6),fill='#68736f');d.line((15,3,21,3),fill='#dad1af')
        if source=='home':
            # Emerald's doorway is at x=56. Platinum places each of these doors one cell
            # from the left of its five-cell foundation: mirror to anchor at x=24.
            img=img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        img.save(ASSETS/(dest+'.png'),optimize=True)


def dress(doc):
    """Register baked art without replacing Platinum's terrain, encounters, or events."""
    mid=doc['id']
    if mid not in SURVEY:return
    art=doc['hoenn_art']
    art['scene']=['res://assets/platinum_native/streets/'+mid+'.png',0,0]
    for index,prop in enumerate(art['p']):
        label=HOUSES.get(mid,{}).get((prop[1],prop[2]))
        if label and (prop[0] in DOOR_TILES or prop[0].startswith('res://assets/platinum_native/streets/')):
            image='res://assets/platinum_native/streets/'+label+'.png'
            anchor=[24,64] if label=='cottage' else [24,80]
            art['p'][index]=[image,prop[1],prop[2],anchor]


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('emerald',type=Path)
    p.add_argument('retro_platinum',type=Path)
    args=p.parse_args()
    ASSETS.mkdir(parents=True,exist_ok=True)
    emerald=Emerald(args.emerald)
    make_facades()
    for key in SURVEY:
        path=OUT/'maps'/(key+'.json');doc=json.loads(path.read_bytes())
        yard_art(emerald,args.retro_platinum,key,doc)
        dress(doc);write(path,doc)
