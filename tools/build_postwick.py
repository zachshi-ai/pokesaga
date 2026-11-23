#!/usr/bin/env python3
"""Draw the Galar opening in Emerald metatiles. Usage: build_postwick.py /path/to/pokeemerald"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from bake_emerald_field import Emerald, pack
from johto_gba_outdoor import AUTOTILES
from kalos_gym_rooms import tile

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / 'content/regions/galar/maps'
ART = ROOT / 'assets/galar/postwick'
PROPS = ROOT / 'assets/emerald/field'
ANCHORS = json.loads((ROOT/'content/emerald_fields.json').read_bytes())['anchors']


def read(path):
    return json.loads(path.read_bytes())


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':'))+'\n')


def passage(cell, target, arrival, trigger='step', atlas=False):
    warp = {'at': list(cell), 'trigger': trigger,
            'to': {'region':'galar', 'map':target, 'at':list(arrival)}}
    if atlas:
        warp['atlas'] = 'world'
    return warp


def farmhouse(key):
    # Use Emerald window and door pixels, with the gables and half-timbering of Postwick.
    large = key == 'hop'
    w, h = (96,82) if large else (78,66)
    door_x = 56 if large else 24
    im = Image.new('RGBA',(w,h))
    d = ImageDraw.Draw(im)
    timber, light, shade = '#65554c', '#f0dcac', '#bba384'
    roof, tile_mid, edge = ('#85594a','#b5755a','#694b47') if large else ('#9c575c','#bf7976','#704d60')
    roof_y, beam_y = h//2+4, h-23
    d.rectangle((4,roof_y-5,w-5,h-1),fill=timber)
    d.rectangle((6,roof_y-2,w-7,h-5),fill=light)
    d.rectangle((6,h-7,w-7,h-4),fill=shade)
    for x in range(6,w-6,16):
        d.rectangle((x,roof_y-2,x+2,h-5),fill=timber)
        d.line((x+2,beam_y+1,min(w-7,x+15),h-7),fill=shade,width=2)
    d.rectangle((5,beam_y-2,w-6,beam_y),fill=timber)
    d.rectangle((5,roof_y-1,w-6,roof_y+2),fill=shade)
    # Chimneys behind the tiled pitch, staggered tile seams inside its silhouette.
    d.rectangle((w-22,4,w-15,23),fill='#8b625b',outline=edge)
    for y in range(6,19,4):
        d.line((w-21,y,w-16,y),fill='#c18e72')
    d.rectangle((w-24,2,w-13,5),fill='#75585a',outline=edge)
    mask = Image.new('L',im.size)
    ImageDraw.Draw(mask).polygon([(1,roof_y),(13,10),(w-13,10),(w-2,roof_y)],fill=255)
    tiles = Image.new('RGBA',im.size,roof)
    t = ImageDraw.Draw(tiles)
    for y in range(12,roof_y,4):
        t.line((0,y,w,y),fill=tile_mid)
        for x in range((y//4%2)*4,w,8):
            t.line((x,y+1,x-1,y+3),fill=edge)
    im.paste(tiles,(0,0),mask)
    d.line((1,roof_y,w-2,roof_y),fill=edge,width=3)
    peak=door_x
    d.polygon([(peak-17,roof_y),(peak,13),(peak+18,roof_y)],fill=light,outline=timber)
    d.line((peak-18,roof_y,peak,11,peak+19,roof_y),fill=edge,width=3)
    d.line((peak-15,roof_y-3,peak,15,peak+16,roof_y-3),fill=tile_mid,width=2)
    d.line((peak,17,peak,roof_y),fill=timber,width=2)
    d.line((peak-10,roof_y-7,peak+10,roof_y-7),fill=timber,width=2)
    window=Image.open(PROPS/'home_red.png').convert('RGBA').crop((32,41,49,55))
    door=Image.open(PROPS/'home.png').convert('RGBA').crop((47,59,64,80))
    im.alpha_composite(door,(door_x-8,h-21))
    for wx in ([13,74] if large else [46]):
        im.alpha_composite(window,(wx,h-24))
        d.rectangle((wx,h-10,wx+16,h-8),fill='#89634b')
        for fx in range(wx+1,wx+16,3):
            d.point((fx,h-11),fill='#9c4254')
    d.line((3,h-2,w-4,h-2),fill='#706a59')
    d.line((door_x-8,h-2,door_x+8,h-2),fill='#b5a88d')
    im.save(ART/(key+'_cottage.png'),optimize=True)
    return [door_x,h],w,h


def stone_wall(vertical):
    im=tile('grass').convert('RGB')
    if vertical:
        return stone_wall(False).transpose(Image.Transpose.TRANSPOSE)
    d=ImageDraw.Draw(im)
    d.rectangle((0,6,15,11),fill='#6b746c')
    d.line((0,12,15,12),fill='#7f9f75')
    for a,b,y in [(-2,3,5),(5,9,5),(11,16,5),(0,6,8),(8,13,8),(15,17,8)]:
        d.rectangle((a,y,b,y+2),fill='#a4aa94')
        d.line((a+1,y,b-1,y),fill='#c4c4a5')
    return im


def save_scene(mid, m, image, grid, props):
    w, h = image.width//16, image.height//16
    image.save(ART/(mid+'.png'),optimize=True)
    m.update(size=[w,h], tiles=grid.tolist(), art_props=[],
             hoenn_art={'s':[w,h], 't':pack(np.zeros((h,w),dtype='<u2')), 'p':props,
                        'scene':['res://assets/galar/postwick/'+mid+'.png',0,0]})
    write(MAPS/(mid+'.json'), m)


class Pasture:
    def __init__(self, em, mid):
        self.em, self.mid = em, mid
        self.map = read(MAPS/(mid+'.json'))
        self.w, self.h = self.map['size']
        self.material = Image.new('L', (self.w,self.h))
        self.pen = ImageDraw.Draw(self.material)
        self.grid = np.zeros((self.h,self.w),dtype=np.uint8)
        self.grid[[0,-1],:] = 1
        self.grid[:,[0,-1]] = 1
        self.props = []

    def path(self, corners, width):
        self.pen.line(corners, fill=1, width=width, joint='curve')

    def place(self, key, x, y, width=1, left=0, depth=1):
        self.props.append([key, x, y])
        self.grid[max(0,y-depth+1):y+1,max(0,x-left):x-left+width] = 1

    def house(self, key, x, y):
        anchor,w,h = farmhouse(key)
        self.props.append(['res://assets/galar/postwick/'+key+'_cottage.png',x,y,anchor])
        left = (x*16+8-anchor[0]+4)//16
        right = (x*16+8-anchor[0]+w-5)//16
        self.grid[max(0,y-(h-7)//16):y+1,left:right+1] = 1
        self.grid[y,x] = 0

    def grove(self, corners):
        # Irregular woodland margins with overlapping trunks, keeping the field exits clear.
        mask = Image.new('1', (self.w,self.h))
        ImageDraw.Draw(mask).polygon(corners,fill=1)
        for y in range(2,self.h,2):
            for x in range((y//2)%2,self.w-1,2):
                if mask.getpixel((x,y)):
                    self.place('tree',x,y,2,1,2)

    def fence(self, a, b):
        self.pen.line([a,b],fill=3 if a[1]==b[1] else 4,width=1)
        self.grid[min(a[1],b[1]):max(a[1],b[1])+1,min(a[0],b[0]):max(a[0],b[0])+1] = 1

    def save(self):
        materials = np.asarray(self.material)
        self.grid[(materials==2) & (self.grid==0)] = 11
        self.grid[0,materials[0]==1] = 0
        self.grid[-1,materials[-1]==1] = 0
        self.grid[materials[:,0]==1,0] = 0
        image = Image.new('RGB',(self.w*16,self.h*16))
        fixed = {0:tile('grass'), 2:tile('tall'), 3:stone_wall(False), 4:stone_wall(True), 5:tile('flowers')}
        for y, x in np.ndindex(materials.shape):
            k = materials[y,x]
            if k == 1:
                row = 0 if y and materials[y-1,x]!=1 else 2 if y+1<self.h and materials[y+1,x]!=1 else 1
                col = 0 if x and materials[y,x-1]!=1 else 2 if x+1<self.w and materials[y,x+1]!=1 else 1
                chip = self.em.metatile('LittlerootTown',AUTOTILES['trail'][row][col])
            else:
                chip = fixed[k]
            image.paste(chip,(x*16,y*16))
        save_scene(self.mid,self.map,image,self.grid,self.props)


def town(em):
    f = Pasture(em,'galar_postwick')
    f.path([(-2,17),(8,17),(12,19),(18,19),(23,16),(27,13),(30,13)],3)
    f.path([(20,18),(21,13),(21,-2)],3)
    f.path([(12,19),(12,15)],3)
    f.path([(30,13),(30,10)],3)
    f.pen.rectangle((27,15,37,21),fill=1)
    f.pen.rectangle((9,12,13,13),fill=5)
    f.pen.rectangle((26,10,27,11),fill=5)
    f.grove([(0,0),(17,0),(14,6),(9,9),(4,13),(0,13)])
    f.grove([(32,0),(42,0),(42,10),(38,6),(34,5)])
    f.grove([(0,21),(5,20),(9,27),(17,33),(15,34),(0,34)])
    f.grove([(33,29),(42,23),(42,34),(20,34),(23,32)])
    f.house('player',12,14)
    f.house('hop',30,9)
    for a,b in [((4,22),(20,22)),((22,22),(26,22)),((26,22),(26,28)),
                ((9,28),(26,28)),((9,24),(9,27)),((29,22),(38,22)),
                ((38,14),(38,21)),((4,14),(4,15)),((4,19),(4,20)),
                ((22,4),(26,4)),((19,7),(19,11))]:
        f.fence(a,b)
    # The exercise court is in front of Hop and Leon's house.
    for x,y in [(27,13),(37,13),(33,23),(15,15),(10,15),(6,15),(25,8),(34,12)]:
        f.place('flowers',x,y)
    sheep=Image.open(ROOT/'assets/party/831.png').convert('RGBA')
    small=sheep.crop(sheep.getbbox())
    small.thumbnail((24,23),Image.Resampling.NEAREST)
    small.save(ART/'wooloo.png',optimize=True)
    for x,y in [(12,22),(14,25),(19,24),(23,26)]:
        f.props.append(['res://assets/galar/postwick/wooloo.png',x,y,[small.width//2,small.height]])
        f.grid[y,x]=1
    f.map['npcs']=[n for n in f.map['npcs'] if not (n.get('heal') or n.get('shop'))]
    f.map['npcs'][0]['at']=[16,23]
    f.map['spawn']=[13,17]
    next(n for n in f.map['npcs'] if n.get('transit'))['at']=[14,17]
    f.map['objects']=[{'kind':'sign','at':[18,9],'text':'向北穿过1号道路，可抵达木杆镇。'},
                      {'kind':'sign','at':[3,16],'text':'西面的小门通向微寐森林。'},
                      {'kind':'sign','at':[36,21],'text':'赫普和丹帝练习对战的场地。'}]
    for s in f.map['objects']:
        f.place('sign',*s['at'])
    f.map['warps']=[passage((12,14),'galar_player_home',(3,6),'door'),
                    passage((30,9),'galar_hop_home',(9,7),'door')]
    for offset in (-1,0,1):
        f.map['warps'].append(passage((0,17+offset),'galar_weald',(29,15),atlas=True))
        f.map['warps'].append(passage((21+offset,0),'galar_1',(17+offset,29),atlas=True))
    f.save()
    # A chalked grass court uses the actual turf underneath; markings do not affect movement.
    path=ART/'galar_postwick.png'
    im=Image.open(path).convert('RGB')
    turf=tile('grass')
    for yy in range(15,21):
        for xx in range(28,37):
            im.paste(turf,(xx*16,yy*16))
    p=ImageDraw.Draw(im)
    p.rectangle((451,243,587,332),outline='#e8e8b0',width=2)
    p.line((519,244,519,331),fill='#e8e8b0',width=2)
    p.ellipse((505,273,533,301),outline='#e8e8b0',width=2)
    im.save(path,optimize=True)


def route(em):
    f=Pasture(em,'galar_1')
    f.path([(17,33),(17,21),(19,16),(23,11),(26,6),(26,-2)],3)
    f.pen.polygon([(6,8),(12,5),(19,7),(18,13),(13,17),(13,21),(6,24),(4,21)],fill=2)
    f.path([(17,26),(12,23),(9,20),(10,17)],2)
    f.path([(12,13),(13,9),(17,8),(23,8)],2)
    f.grove([(0,0),(19,0),(16,4),(9,6),(4,9),(0,14)])
    f.grove([(0,16),(4,19),(6,25),(13,28),(14,30),(0,30)])
    f.grove([(28,0),(34,0),(34,30),(21,30),(21,26),(25,22),(29,20),(31,10)])
    for a,b in [((20,22),(20,27)),((21,17),(21,20)),((27,7),(27,11)),((20,5),(23,5))]:
        f.fence(a,b)
    for x,y in [(23,14),(25,19),(14,26),(17,5),(5,15),(27,16),(9,10)]:
        f.pen.point((x,y),fill=5)
    f.map['objects']=[{'kind':'sign','at':[15,26],'text':'南边是化朗镇。大路直达木杆镇，西面的草丛也能绕回大路。'}]
    f.place('sign',15,26)
    f.map['warps']=[passage((26+o,0),'galar_wedgehurst',(17,25),atlas=True) for o in (-1,0,1)]
    f.map['warps'] += [passage((17+o,30),'galar_postwick',(21+o,1),atlas=True) for o in (-1,0,1)]
    f.save()


def room(em, mid, name, native, layout, warps, npcs, decorations):
    source=read(ROOT/'content/hoenn_native/maps'/(native+'.json'))
    w,h=source['size']
    im=em.patch(layout,0,0,w,h).convert('RGB')
    grid=np.array(source['physics']['collision'],dtype=np.uint8)
    props=[]
    for key,x,y in decorations:
        props.append([key,x,y])
        sprite=Image.open(PROPS/(key+'.png')).convert('RGBA')
        ax,ay=ANCHORS[key]
        left,top=x*16+8-ax,(y+1)*16-ay
        alpha=sprite.getchannel('A')
        for row in range(max(0,top//16),min(h,(top+sprite.height+15)//16)):
            for col in range(max(0,left//16),min(w,(left+sprite.width+15)//16)):
                px,py=col*16-left,row*16-top
                if alpha.crop((px,py,px+16,py+16)).getbbox():
                    grid[row,col]=1
    spawn=source['spawn'] if mid!='galar_player_home' else [3,6]
    m={'name':name,'style':'interior','biome':'interior','spawn':spawn,
       'npcs':npcs,'objects':[],'warps':warps}
    save_scene(mid,m,im,grid,props)


def build(source):
    ART.mkdir(parents=True,exist_ok=True)
    em=Emerald(source)
    town(em)
    route(em)
    # Retain the nurse and supply service from the earlier Galar map.
    room(em,'galar_player_home','化朗镇・主角的家','em_dewford_town_house1','House3',
         [passage((x,7),'galar_postwick',(12,15),'down') for x in (3,4)],
         [{'name':'妈妈','at':[6,4],'gfx':'mom','heal':True,'field_art':'mom'}], [('ceilingbed',1,4)])
    room(em,'galar_hop_home','化朗镇・赫普和丹帝的家','littleroot_west_home_1f','LittlerootTown_BrendansHouse_1F',
         [passage((x,8),'galar_postwick',(30,10),'down') for x in (8,9)]+
         [passage((8,2),'galar_hop_upstairs',(7,2))],
         [{'name':'补给商','at':[4,6],'gfx':'clerk','shop':True}], [])
    room(em,'galar_hop_upstairs','化朗镇・赫普家二楼','littleroot_west_home_2f','LittlerootTown_BrendansHouse_2F',
         [passage((7,1),'galar_hop_home',(8,3))], [], [('ceilingbed',2,4),('tv',4,2)])
    registry=MAPS.parent/'region.json'
    r=read(registry)
    r['start']['at']=[13,17]
    for key in ('galar_player_home','galar_hop_home','galar_hop_upstairs'):
        if key not in r['maps']:r['maps'].append(key)
    registry.write_text(json.dumps(r,ensure_ascii=False,indent=1))
    atlas=ROOT/'content/world_destinations.json'
    data=read(atlas)
    galar=data['regions']['galar']
    galar['hub'].update(at=[13,17],npc_at=[14,17])
    next(loc for loc in galar['locations'] if loc['map']=='galar_postwick')['at']=[13,17]
    write(atlas,data)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('emerald',type=Path)
    build(parser.parse_args().emerald)
