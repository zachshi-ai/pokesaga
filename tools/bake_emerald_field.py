#!/usr/bin/env python3
"""Build the GBA Emerald field atlas from a local pret/pokeemerald checkout.

Use the unmodified data at 9103e529c2fbdd7add4a1ff3350c6c1f92112c42.
"""
import argparse
import base64
import json
import re
import zlib
from functools import lru_cache
from pathlib import Path
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(os.environ.get('POKESAGA_PROJECT', Path(__file__).resolve().parents[1])).resolve()
OUT = ROOT / 'assets/emerald/field'
CELL = 16


def normalized(label):
    return re.sub('[^a-z0-9]', '', label.lower())


class Emerald:
    def __init__(self, source):
        self.source = Path(source)
        self.layouts = {Path(l['blockdata_filepath']).parent.name: l for l in
                        json.loads((self.source / 'data/layouts/layouts.json').read_text())['layouts']}
        self.dirs = {normalized(p.name): p for p in (self.source / 'data/tilesets').glob('*/*')
                     if (p / 'metatiles.bin').is_file()}

    @lru_cache(None)
    def tileset(self, name):
        folder = self.dirs[normalized(name.removeprefix('gTileset_'))]
        image = np.array(Image.open(folder / 'tiles.png'))
        assert image.ndim == 2, folder
        tiles = image.reshape(image.shape[0]//8,8,image.shape[1]//8,8).transpose(0,2,1,3).reshape(-1,8,8)
        if name == 'gTileset_General':
            for label, start, count in [('water',432,30),('sand_water_edge',464,10),
                                        ('land_water_edge',480,10),('waterfall',496,6),('flower',508,4)]:
                f = np.array(Image.open(folder / 'anim' / label / '0.png'))
                chips = f.reshape(f.shape[0]//8,8,f.shape[1]//8,8).transpose(0,2,1,3).reshape(-1,8,8)
                tiles[start:start+count] = chips[:count]
        entries = np.fromfile(folder / 'metatiles.bin', dtype='<u2').reshape(-1,8)
        palettes = []
        for i in range(16):
            lines = (folder / 'palettes' / f'{i:02}.pal').read_text().splitlines()[3:19]
            palette = [[*map(int, line.split()),255] for line in lines]
            palette[0][3] = 0
            palettes.append(np.array(palette, np.uint8))
        return tiles, entries, palettes

    @lru_cache(None)
    def tile(self, primary, secondary, mid, upper_only=False):
        # Emerald reserves 512 tile/metatile IDs and the first six BG palettes for the primary.
        sets = [self.tileset(primary), self.tileset(secondary)]
        table = sets[mid >= 512][1][mid % 512]
        out = Image.new('RGBA',(16,16))
        for n, entry in enumerate(table):
            if upper_only and n < 4:
                continue
            tile_id = int(entry) & 1023
            sheet = sets[tile_id >= 512][0]
            if tile_id % 512 >= len(sheet):  # Unpopulated VRAM (for runtime overlays).
                continue
            pixels = sheet[tile_id % 512]
            if entry & 1024: pixels = pixels[:, ::-1]
            if entry & 2048: pixels = pixels[::-1, :]
            palette = int(entry) >> 12
            chip = Image.fromarray(sets[palette >= 6][2][palette][pixels & 15])
            out.alpha_composite(chip, ((n%2)*8, ((n%4)//2)*8))
        return out

    @lru_cache(None)
    def grid(self, name):
        layout = self.layouts[name]
        return np.fromfile(self.source / layout['blockdata_filepath'], dtype='<u2',count=layout['height']*layout['width']).reshape(
            layout['height'],layout['width']) & 1023

    def metatile(self, name, mid, upper_only=False):
        l = self.layouts[name]
        return self.tile(l['primary_tileset'],l['secondary_tileset'],int(mid),upper_only)

    def patch(self, name, x, y, w, h):
        grid = self.grid(name)[y:y+h,x:x+w]
        assert grid.shape == (h,w), (name,x,y,w,h)
        out = Image.new('RGBA',(w*16,h*16))
        for j, row in enumerate(grid):
            for i, mid in enumerate(row):
                out.alpha_composite(self.metatile(name, mid), (i*16,j*16))
        return out

TOWN = 'LittlerootTown'
ROOM = 'LittlerootTown_BrendansHouse_2F'
CLINIC = 'PokemonCenter_1F'
CAVE = 'GraniteCave_1F'
ICE = 'ShoalCave_LowTideIceRoom'


def cut_background(image, samples):
    """Clear only exact native background colours. Preserve the sprite's native outline."""
    pixels = np.array(image)
    for sample in samples:
        for color in sample.convert('RGB').getcolors(256) or []:
            pixels[np.all(pixels[:, :, :3] == color[1], axis=2),3] = 0
    return Image.fromarray(pixels)


def make_props(e):
    anchors = {}
    grass = [e.metatile(TOWN,1)]
    pavement = [e.metatile('RustboroCity',i) for i in (0x2bb,0x2c3,0x2c4)]
    room_floor = [e.metatile(ROOM,0x201),e.metatile(ROOM,0x205)]
    room_wall = [e.metatile(ROOM,0x254),e.metatile(ROOM,0x216)]
    clinic_floor = [e.metatile(CLINIC,0x202)]
    def store(kind, img, anchor, backgrounds=(), small=False):
        if backgrounds:
            img = cut_background(img,backgrounds)
        if not img.getbbox():
            raise ValueError(f'Empty prop: {kind}')
        img.save(OUT / (kind+'.png'),optimize=True)
        anchors[kind]=anchor
        if small:
            half=img.resize((img.width//2,img.height//2),Image.Resampling.NEAREST)
            store(kind+'_compact',half,[anchor[0]//2,anchor[1]//2])
    def group(kind,name,rect,door,backgrounds=(),small=False):
        x,y,w,h=rect
        store(kind,e.patch(name,x,y,w,h),[(door-x)*16+8,h*16],backgrounds,small)
    for kind,name,rect,door,bg in [
        ('home',TOWN,(2,4,5,5),5,grass),
        ('home_red','PetalburgCity',(9,16,4,4),10,grass),
        ('home_green','VerdanturfTown',(0,11,4,4),1,grass),
        ('home_blue','LilycoveCity',(11,11,4,4),12,grass),
        ('home_city','MauvilleCity',(18,11,4,4),19,grass),
        ('mart','PetalburgCity',(24,9,4,4),25,grass),
        ('center','PetalburgCity',(19,13,4,4),20,grass),
        ('lab',TOWN,(3,12,7,5),7,grass),
        ('gym','PetalburgCity',(12,4,6,5),15,grass),
        ('academy','RustboroCity',(7,7,10,9),11,pavement),
        ('streetlamp','RustboroCity',(19,15,1,2),19,pavement),
        ('fountain','RustboroCity',(27,38,3,3),28,pavement),
        ('planter','VerdanturfTown',(15,18,3,1),16,grass),
    ]: group(kind,name,rect,door,bg,True)
    def mosaic(name,ids):
        out=Image.new('RGBA',(len(ids[0])*16,len(ids)*16))
        for y,row in enumerate(ids):
            for x,mid in enumerate(row):
                out.alpha_composite(e.metatile(name, mid),(x*16,y*16))
        return out
    store('tree',mosaic(TOWN,[[0x1ce,0x1cf],[0x1d6,0x1d7],[0x1e6,0x1e7]]),[16,48],grass,True)
    store('ruin',mosaic(TOWN,[[0x9e,0x9f,0x9e],[0xa6,0xa7,0xa6]]),[24,32],grass,True)
    store('sign',e.metatile(TOWN,3),[8,16],grass)
    store('flowers',e.metatile(TOWN,4),[8,16],grass)
    store('banner',e.metatile(TOWN,0x1b),[8,16],grass)
    # Furniture uses the actual multi-cell arrangements from Brendan's upstairs bedroom.
    # Some furniture extends above the wall or rug, so clear only its surrounding wall/floor.
    group('ceilingbed',ROOM,(0,3,3,3),1,room_floor)
    group('tv',ROOM,(4,0,1,3),4,room_floor+room_wall)
    group('pc',ROOM,(0,0,1,3),0,room_floor+room_wall)
    group('clock',ROOM,(5,0,1,2),5,room_wall)
    group('woodstairs','LittlerootTown_BrendansHouse_1F',(8,1,3,3),9,room_floor+room_wall)
    # A framed Hoenn map on the Pokémon Center wall.
    poster=e.patch(CLINIC,11,0,2,2).crop((1,7,31,25))
    store('map',poster,[22,18])
    group('desk','LittlerootTown_BrendansHouse_1F',(2,6,4,2),4,room_floor)
    group('bookshelf',CLINIC,(2,1,2,2),3,clinic_floor)
    group('carebench',CLINIC,(1,3,2,1),2,clinic_floor,True)
    # Front of counter only. The nurse stands behind it on the original event cell.
    group('officecounter',CLINIC,(4,2,6,2),6,clinic_floor,True)
    # Furniture silhouettes are cut at pixel coordinates on the original room layouts.
    # Preserve all original palette entries inside each silhouette (including shared greys).
    def detail(kind,name,box,anchor,polygon=None):
        g=e.grid(name)
        img=e.patch(name,0,0,g.shape[1],g.shape[0]).crop(box)
        if polygon:
            mask=Image.new('L',img.size,0)
            ImageDraw.Draw(mask).polygon(polygon,fill=255)
            img.putalpha(mask)
        store(kind,img,anchor)
    detail('woodstairs','LittlerootTown_BrendansHouse_1F',(123,25,149,50),[13,24],
           [(1,1),(22,1),(22,2),(25,2),(25,24),(0,24),(0,2)])
    detail('clock',ROOM,(81,7,96,22),[7,12],[(5,1),(10,1),(14,5),(14,10),(10,14),(5,14),(1,10),(1,5)])
    detail('pc',ROOM,(0,8,16,46),[8,32],[(1,2),(13,2),(15,6),(15,23),(15,37),(0,37),(0,6)])
    detail('tv',ROOM,(64,12,80,40),[8,28],[(3,0),(12,0),(15,3),(15,26),(14,27),(1,27),(0,26),(0,4)])
    detail('console',ROOM,(50,23,64,40),[7,17],[(2,2),(9,2),(11,4),(11,10),(13,14),(13,16),(0,16),(0,4)])
    detail('bookshelf_home','LittlerootTown_BrendansHouse_1F',(48,18,72,48),[7,30])
    detail('plant_indoor',CLINIC,(16,9,33,40),[8,31],
           [(2,0),(7,0),(12,5),(15,2),(16,5),(14,16),(12,18),(13,24),(11,30),(4,30),(3,24),(4,16),(0,13),(0,4)])
    poster=e.patch(CLINIC,11,0,2,2).crop((3,9,29,23))
    poster=poster.resize((17,11),Image.Resampling.NEAREST)
    store('map',poster,[10,20])
    # Take field objects from their original first standing animation frames.
    for name,file,x,w,h in [
        ('pickup','misc/item_ball',0,16,16),('cut_tree','misc/cuttable_tree',0,16,16),
        ('rock','misc/breakable_rock',0,16,16),('boulder','misc/pushable_boulder',0,16,16),
        ('statue','misc/statue',0,16,32),('berry_tree','berry_trees/oran',32,32,32),
        ('soil','berry_trees/dirt_pile',0,16,16)]:
        src=Image.open(e.source/'graphics/object_events/pics'/(file+'.png'))
        indexed=src.crop((x,0,x+w,h))
        sprite=indexed.convert('RGBA')
        sprite.putalpha(indexed.point([0]+[255]*255).convert('L') if indexed.mode!='P' else
                        Image.fromarray(np.where(np.array(indexed)==0,0,255).astype(np.uint8)))
        store(name,sprite,[w//2,h])
    return anchors


class Atlas:
    def __init__(self):
        self.images=[]
        self.ids={}

    def add(self,image):
        raw=image.tobytes()
        if raw not in self.ids:
            self.ids[raw]=len(self.images)
            self.images.append(image)
        return self.ids[raw]

    def save(self):
        rows=(len(self.images)+31)//32
        out=Image.new('RGBA',(32*16,rows*16))
        for n,img in enumerate(self.images):
            out.paste(img,(n%32*16,n//32*16))
        out.save(OUT/'tiles.png',optimize=True)


def pack(grid):
    return base64.b64encode(zlib.compress(grid.astype('<u2').tobytes(),9)).decode()


class Fields:
    def __init__(self,e):
        self.e=e
        self.atlas=Atlas()
        self.empty=self.atlas.add(Image.new('RGBA',(16,16)))
        self.props=make_props(e)

    @lru_cache(None)
    def cell(self,layout,mid):
        return self.atlas.add(self.e.metatile(layout,mid))

    def native(self,layout):
        grid=self.e.grid(layout)
        image=np.zeros_like(grid,dtype='uint16')
        above=np.zeros_like(image)
        for i in np.unique(grid):
            mid=int(i)
            image[grid==i]=self.cell(layout,mid)
            l=self.e.layouts[layout];name=l['primary_tileset' if mid<512 else 'secondary_tileset']
            attrs=np.fromfile(self.e.dirs[normalized(name.removeprefix('gTileset_'))]/'metatile_attributes.bin',dtype='<u2')
            if int(attrs[mid%512])>>12 != 1:
                above[grid==i]=self.atlas.add(self.e.metatile(layout,mid,True))
        return {'s':list(reversed(grid.shape)),'t':pack(image),'a':pack(above),'p':[]}

    def terrain(self,v):
        # Single logical cell => complete Emerald metatile. Paths, cliffs, shorelines and
        # interiors are adjusted for neighbours below. ID meanings come from field_layouts.
        source=[
          (TOWN,1),(TOWN,1),(TOWN,0xa1),(TOWN,0x121),(TOWN,4),
          (TOWN,0x69),(CAVE,0x201),(TOWN,0x1d9),(TOWN,0x121),(TOWN,0x1b),
          (TOWN,0x121),(TOWN,0xd),('MauvilleCity',0x109),(ROOM,0x201),(ROOM,0x2a1),
          (ROOM,0x216),(CAVE,0x211),(ICE,0x38d),('MtChimney',0x14f),
          ('FortreeCity',0x256),('Route113',0x20a),(TOWN,1),(TOWN,0x14f),
          ('Route119',0x1d9),(TOWN,0x121),(ICE,0x381),('SkyPillar_1F',0x241),
          ('MauvilleCity_Gym',0x201),(TOWN,0xab),(ROOM,0x211),
          (TOWN,0),('RustboroCity',0x2bb),('RustboroCity',0x2bb),('MauvilleCity',0x109),
          (CLINIC,0x202),('SkyPillar_1F',0x241),(ICE,0x389)]
        return source[v]

    def pixmap(self, image):
        height,width=image.height//16,image.width//16
        ids=np.empty((height,width),np.uint16)
        for y in range(height):
            for x in range(width):
                ids[y,x]=self.atlas.add(image.crop((x*16,y*16,x*16+16,y*16+16)))
        return {'s':[width,height],'t':pack(ids),'p':[]}

    def bedrooms(self,w,h,upstairs):
        # Keep the floor, back wall, handrails and furniture in the same 16px grid
        # as the original Gen III room. Desk/furnishing placement follows Kanto collision.
        img=Image.new('RGBA',(w*16,h*16))
        for y in range(h):
            for x in range(w):
                mid=0x254 if y==0 else 0x216 if y==1 else 0x201
                tile=self.e.metatile(ROOM,mid)
                if y==1:  # Some edge metatiles include one jamb pixel on the border.
                    tile=tile.crop((8,0,9,16)).resize((16,16))
                img.paste(tile,(x*16,y*16))
        def piece(name,rect,at):
            x,y,ww,hh=rect
            img.alpha_composite(self.e.patch(name,x,y,ww,hh),(at[0]*16,at[1]*16))
        def prop(kind,x,y):
            sprite=Image.open(OUT/(kind+'.png'))
            ax,ay=self.props[kind]
            img.alpha_composite(sprite,(x*16+8-ax,(y+1)*16-ay))
        if upstairs:
            piece(ROOM,(0,3,3,3),(1,4))  # The bed ends at (2,6), next to the spawn.
            piece(ROOM,(4,3,4,4),(4,3))
            prop('pc',1,2)
            prop('clock',4,1)
            prop('tv',6,5)
            prop('console',5,5)
            prop('bookshelf_home',8,3)
            prop('map',11,1)
        else:
            # A continuous Emerald kitchen bench, shelves, windows and dining table.
            piece('LittlerootTown_BrendansHouse_1F',(0,0,7,3),(0,0))
            rug=np.zeros((4,6),np.uint16)
            self.rug(rug,0,0,6,4)
            for ry,rr in enumerate(rug):
                for rx,tile in enumerate(rr):
                    img.paste(self.atlas.images[tile],((rx+4)*16,(ry+3)*16))
            # Crop the table and chairs inside the blue rug, clear of the television cabinet.
            furniture=self.e.patch('LittlerootTown_BrendansHouse_1F',2,6,4,2)
            img.alpha_composite(furniture,(5*16,4*16))
            prop('plant_indoor',1,7)
            door=self.e.patch('LittlerootTown_BrendansHouse_1F',7,8,2,1)
            img.alpha_composite(door,(4*16,8*16))
        prop('woodstairs',10,2)
        return self.pixmap(img)

    def lab(self,w,h):
        lab='LittlerootTown_ProfessorBirchsLabWithTable'
        floor=self.e.metatile(lab,0x202)
        img=Image.new('RGBA',(w*16,h*16))
        for y in range(h):
            for x in range(w):
                img.paste(floor,(x*16,y*16))
        def piece(box,to):
            img.alpha_composite(self.e.patch(lab,*box),(to[0]*16,to[1]*16))
        piece((0,0,13,3),(0,0))
        # The open main aisle is three tiles wide. Bookcases sit on the two blocked
        # runs on row 8; the full experiment table is rooted at (8..10,4).
        for x in (0,2,8,10):
            piece((0,5,2,3),(x,6))
        piece((8,4,3,2),(8,3))
        piece((10,6,3,3),(0,3))
        plant=Image.open(OUT/'plant_indoor.png')
        img.alpha_composite(plant,(0,12*16-9))
        img.alpha_composite(plant,(12*16,12*16-9))
        piece((6,12,2,1),(6,12))
        return self.pixmap(img)

    def clinic(self,plan,data):
        w,h=plan['s']
        nurse=next((n for n in data.get('npcs',[]) if n.get('gfx') in ('nurse','nurse_joy') or '护士' in n.get('name','')),None)
        if not nurse or w<10 or h<7:
            return None
        nx,ny=nurse['at']
        if not 4<=nx<w-3 or not 1<=ny<=h-4:
            return None
        # Masonry, equipment and furniture are separate original tile groups. Extend the
        # floor between pieces without duplicating the staircase, monitor or waiting seats.
        src=self.e.patch(CLINIC,0,0,14,9)
        img=Image.new('RGBA',(w*16,h*16))
        floor=self.e.metatile(CLINIC,0x202)
        lowerwall=src.crop((177,16,178,32)).resize((16,16),Image.Resampling.NEAREST)
        for y in range(h):
            for x in range(w):
                if x in (0,w-1):
                    sx=0 if x==0 else 13
                    sy=y if y<3 else (8 if y==h-1 else 4)
                    tile=src.crop((sx*16,sy*16,(sx+1)*16,(sy+1)*16))
                else:
                    tile=self.e.metatile(CLINIC,0x20b) if y==0 else lowerwall if y==1 else floor
                img.alpha_composite(tile,(x*16,y*16))
        def paste(box,x,y):
            img.alpha_composite(src.crop(box),(x,y))
        paste((16,0,64,48),(nx-6)*16,0)
        paste((64,0,160,64),(nx-3)*16,(ny-2)*16)
        paste((160,0,208,48),(w-4)*16,0)
        paste((16,48,48,64),16,3*16)
        paste((80,64,144,128),(nx-2)*16,(ny+2)*16)
        paste((0,80,32,128),0,(h-4)*16)
        paste((160,96,208,128),(w-4)*16,(h-3)*16)
        exits=[warp['at'] for warp in data.get('warps',[]) if 'at' in warp
               and warp['at'][1]>=h-3 and warp['at'][0]>2]
        dx,dy=(sorted(exits)[len(exits)//2] if exits else [nx,h-1])
        paste((96,128,128,144),max(1,dx-1)*16,dy*16)
        return self.pixmap(img)

    def draw(self,key,plan,data):
        w,h=plan['s'];region,name=key.split('/')
        if key in ('kanto/pallet_town_players_house_2f','kanto/pallettown_playershouse_1f'):
            return self.bedrooms(w,h,name.endswith('2f'))
        if key=='kanto/pallettown_professoroakslab':
            return self.lab(w,h)
        if 'center' in name:
            clinic=self.clinic(plan,data)
            if clinic:return clinic
        if region=='hoenn' and data.get('emerald') in ('littleroot_town','route101'):
            layout={'littleroot_town':TOWN,'route101':'Route101'}[data['emerald']]
            if self.e.grid(layout).shape==(h,w): return self.native(layout)
        a=np.frombuffer(zlib.decompress(base64.b64decode(plan['t'])),np.uint8).reshape(h,w)
        ids=np.zeros((h,w),np.uint16)
        for val in np.unique(a):
            ids[a==val]=self.empty if val==30 else self.cell(*self.terrain(int(val)))
        biome=plan['b']
        compact=data.get('emerald','').startswith('johto_') and region=='johto'
        # Represent thick strips with the correct edge tile, preserving every walkable cell.
        # Each 3x3 Emerald border has distinct inner, edge and corner metatiles.
        def borders(mask,layout,tiles):
            n=np.pad(mask,1,constant_values=True)
            for y,x in zip(*np.nonzero(mask)):
                north,east,south,west=(not n[y,x+1],not n[y+1,x+2],not n[y+2,x+1],not n[y+1,x])
                dx=-1 if west else 1 if east else 0
                dy=-1 if north else 1 if south else 0
                ids[y,x]=self.cell(layout,tiles[dy+1][dx+1])
        if biome in ('desert','coast'):
            # General's path-edge metatiles have a green grass fringe. Dunes and beaches
            # meet other sand, bare boulders and boardwalks, so keep their continuous sand.
            ids[np.isin(a,[3,5,10,24])]=self.cell(TOWN,0x121)
        elif biome=='snow':
            ids[np.isin(a,[3,5,10])]=self.cell(ICE,0x381)
        else:
            borders(np.isin(a,[3,10,24]),TOWN,[[0x118,0x119,0x11a],[0x120,0x121,0x122],[0x128,0x129,0x12a]])
        borders(a==2,TOWN,[[0xb0,0xb1,0xb2],[0xb8,0xa1,0xba],[0xc8,0xc9,0xca]])
        if biome in ('cave','highland','volcano','ruins','desert'):
            borders(a==6,CAVE,[[0x208,0x209,0x20a],[0x210,0x211,0x212],[0x218,0x219,0x21a]])
        if biome=='snow':
            borders(a==36,ICE,[[0x378,0x379,0x37a],[0x380,0x381,0x382],[0x388,0x389,0x38a]])
        raw=np.asarray(data.get('tiles',[]))
        if raw.shape==a.shape:
            bridge=raw==13
            if np.any(bridge) and biome not in ('space','interior'):
                # Route 120's complete rope-and-plank cross section has two rails. Fit the
                # deck to single-cell routes by trimming interior plank rows only.
                timber=self.e.patch('Route120',15,15,1,2)
                deck=Image.new('RGBA',(16,16))
                deck.paste(timber.crop((0,0,16,4)),(0,0))
                deck.paste(timber.crop((0,8,16,16)),(0,4))
                deck.paste(timber.crop((0,28,16,32)),(0,12))
                along_x=self.atlas.add(deck)
                along_y=self.atlas.add(deck.transpose(Image.Transpose.ROTATE_90))
                pier=self.cell('PacifidlogTown',0x221)
                padded=np.pad(bridge,1)
                for by,bx in zip(*np.nonzero(bridge)):
                    west,east=padded[by+1,bx],padded[by+1,bx+2]
                    north,south=padded[by,bx+1],padded[by+2,bx+1]
                    ids[by,bx]=pier if (west or east) and (north or south) else along_x if west or east else along_y
            # Local stone covers sidewalks and plazas. Garden plots use grass; tall featured
            # objects are rooted on their site's ground rather than an isolated cave chip.
            if biome=='city':
                ids[raw==0]=self.cell(TOWN,1)
                ids[raw==6]=self.cell('RustboroCity',0x2bb)
                ids[0,raw[0]==6]=self.cell('RustboroCity',0x2e1)
                ids[-1,raw[-1]==6]=self.cell('RustboroCity',0x2e1)
            for landmark in data.get('art_props',[]):
                if landmark.get('kind') in ('tree','flowers','plant','fountain','statue','banner','tower','streetlamp','planter','rock'):
                    x,y=landmark['at'];lw,lh=landmark.get('size',[1,1])
                    x0=max(0,int(x-lw//2));x1=min(w,int(x+lw//2+1))
                    y0=max(0,int(y-lh+1))
                    mask=np.isin(raw[y0:y+1,x0:x1],[5,6,7,9])
                    xlo=max(0,x0-1); xhi=min(w,x1+1); ylo=max(0,y0-1); yhi=min(h,y+3)
                    neighbors=ids[ylo:yhi,xlo:xhi][np.isin(raw[ylo:yhi,xlo:xhi],[0,3,10,12])]
                    default={'city':12,'snow':25,'desert':24,'coast':10,'cave':16,
                             'highland':5,'ruins':26,'volcano':20,'space':35}.get(biome,0)
                    base=int(np.bincount(neighbors).argmax()) if neighbors.size else self.cell(*self.terrain(default))
                    ids[y0:y+1,x0:x1][mask]=base
        if biome=='interior':
            self.indoor(ids,a,plan,key,compact)
        buildings={'home','lab','birch_lab','gym','mart','center','academy','ruin'}
        door_anchors=[p for p in plan['p'] if p[0] in buildings]
        props=[]
        for kind,x,y,_,_ in plan['p']:
            if kind=='birch_lab':kind='lab'
            if kind=='home':
                variants=['home','home_red','home_green','home_blue','home_city']
                kind=variants[(x*7+y*13)%len(variants)]
            if kind=='tree' and any(abs(x-p[1])<=2 and p[2]-4<=y<=p[2] for p in door_anchors):
                continue
            if compact and kind+'_compact' in self.props:kind+='_compact'
            if kind not in self.props: raise ValueError((key,kind))
            props.append([kind,x,y])
        return {'s':[w,h],'t':pack(ids),'p':props}

    def indoor(self,ids,a,plan,key,compact):
        h,w=a.shape
        clinic='center' in key.lower() or 'pokecen' in key.lower()
        featured=key.endswith('/pallet_town_players_house_2f') or key.endswith('/pallettown_playershouse_1f')
        floor=self.cell(CLINIC,0x202) if clinic else self.cell(ROOM,0x201)
        if featured or clinic:ids[:]=floor
        else:ids[(a==15)|(a==27)]=floor
        wall_set=CLINIC if clinic else ROOM
        if clinic:
            ids[0,:]=self.cell(CLINIC,0x20b)
            if h>4:ids[1,:]=self.atlas.add(self.e.patch(CLINIC,11,1,1,1).crop((1,0,2,16)).resize((16,16),Image.Resampling.NEAREST))
        else:
            ids[0,:]=self.cell(ROOM,0x254)
            if h>4:
                ids[1,:]=self.cell(ROOM,0x216)
        if not featured:
            inset=np.zeros_like(a,dtype=bool)
            inset[2:,:]=a[2:,:]==15
            # Colour and outline internal obstructions with an actual cabinet face.
            if clinic:
                ids[inset]=self.cell(CLINIC,0x202)
            else:
                borders=np.pad(inset,((0,1),(0,0)),constant_values=False)
                ids[inset & ~borders[1:]]=self.cell(ROOM,0x278)
                ids[inset & borders[1:]]=self.cell(ROOM,0x205)
        if featured:
            if key.endswith('2f'):
                self.rug(ids,4,4,5,3)
            else:
                self.rug(ids,4,4,4,3)
            ids[2,10]=self.cell(ROOM,0x201)
        else:
            ids[a==29]=self.cell(ROOM,0x211)
            ids[a==14]=self.cell(CLINIC,0x203) if clinic else self.cell(ROOM,0x2a1)

    def rug(self,ids,x,y,w,h):
        for j in range(h):
            for i in range(w):
                dy=0 if j==0 else 2 if j==h-1 else 1
                dx=0 if i==0 else 2 if i==w-1 else 1
                ids[y+j,x+i]=self.cell(ROOM,0x298+dy*8+dx)


def set_output(project):
    global ROOT,OUT
    import field_layouts
    ROOT=Path(project).resolve()
    OUT=ROOT/'assets/emerald/field'
    field_layouts.ROOT=ROOT
    field_layouts.META=ROOT/'content/emerald_maps'


def main():
    from asset_paths import source_path
    from field_layouts import compile_map
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=Path(source_path('emerald_original')))
    parser.add_argument('--project',type=Path,default=ROOT)
    args=parser.parse_args()
    set_output(args.project)
    OUT.mkdir(parents=True,exist_ok=True)
    art=Fields(Emerald(args.source))
    maps={}
    for path in sorted((ROOT/'content/regions').glob('*/maps/*.json')):
        data=json.loads(path.read_text());region=path.parents[1].name
        key=region+'/'+path.stem
        plan=compile_map(path.stem,data,region)
        if not plan: raise ValueError('Could not resolve walk grid for '+key)
        maps[key]=art.draw(key,plan,data)
        maps[key]["biome"]=plan["b"]
    art.atlas.save()
    index={'tiles':len(art.atlas.images),'anchors':art.props,'maps':maps}
    (ROOT/'content/emerald_fields.json').write_text(json.dumps(index,separators=(',',':'))+'\n')
    print(len(maps),'fields;',len(art.atlas.images),'unique Emerald metatiles;',len(art.props),'props')


if __name__=='__main__':
    main()
