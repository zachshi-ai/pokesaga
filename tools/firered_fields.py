"""Read the pinned FireRed layouts, VRAM tile banks and field attributes together.

One layout block selects both the picture and the terrain on the same 16px cell.
The regional overworld reuses the existing member offsets so saves and events
stay in the coordinate system in which they were authored.
"""
import json
import re
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image


def load(path):
    return json.loads(path.read_text())


def write_like(path, data):
    original = path.read_text()
    options = {'indent':1} if original.startswith('{\n') else {'separators':(',',':')}
    path.write_text(json.dumps(data,ensure_ascii=False,**options) + ('\n' if original.endswith('\n') else ''))


def symbol(name):
    return re.sub('[^a-z0-9]', '', name.lower())


def chips(path):
    image = np.asarray(Image.open(path))
    return image.reshape(image.shape[0] // 8, 8, image.shape[1] // 8, 8).transpose(0, 2, 1, 3).reshape(-1, 8, 8)


# src/tileset_anims.c loads these tiles into VRAM before display.
ANIMATIONS = {
    'general': [('flower', 508, 4), ('water_current_landwatersedge', 416, 48), ('sandwatersedge', 464, 18)],
    'celadoncity': [('fountain', 744, 8)], 'silphco': [('fountain', 976, 8)],
    'mtember': [('steam', 896, 8)], 'vermiliongym': [('motorizeddoor', 880, 7)],
    'celadongym': [('flowers', 739, 4)],
}
SURFABLE = [0x10, 0x11, 0x12, 0x13, 0x15, 0x1a, 0x1b, 0x50, 0x51, 0x52, 0x53]
# Store the *approach* direction blocked by each fence edge (FR uses both cells).
FENCES = [8, 4, 2, 1, 8 | 2, 4 | 2, 8 | 1, 4 | 1]
DIRECTIONS = [4, 8, 1, 2]


# Open passages use the post-event map state available in the study world.
# Each script calls setmetatile x,y,id,0, replacing the tile and clearing collision.
OPEN_TILES = {
    'LAYOUT_FIVE_ISLAND_MEADOW': [(12,21,0x2af)],
}
for room in ['LORELEIS','BRUNOS','AGATHAS','LANCES']:
    y = 5 if room == 'LANCES' else 2
    OPEN_TILES['LAYOUT_POKEMON_LEAGUE_'+room+'_ROOM'] = [(6,y,0x296),(6,y-1,0x28e)]


def align_saffron(project, source):
    """Saffron's walled city is a separate map behind four gates in FireRed.
    Only SaffronCity_Connection adjoins the surrounding Routes 5–8.
    """
    meta_path = project/'content/emerald_maps/kanto_main.json'
    map_path = project/'content/regions/kanto/maps/kanto_main.json'
    meta, world = load(meta_path), load(map_path)
    old = meta['member_maps']['SAFFRON_CITY']
    if old != meta['member_maps']['SAFFRON_CITY_CONNECTION']:
        return
    new = [312,150]
    dx,dy = new[0]-old[0], new[1]-old[1]
    original = load(source/'data/maps/SaffronCity/map.json')
    for group,key in [('npcs','object_events'),('objects','bg_events')]:
        points = {(old[0]+r['x'],old[1]+r['y']) for r in original[key]}
        for row in world[group]:
            x,y = row['at']
            if (x,y) in points:
                row['at'] = [x+dx,y+dy]
    for row in world.get('areas', []):
        if row['name'] == 'SAFFRON_CITY':
            for k in ['x0','x1']: row[k] += dx
            for k in ['y0','y1']: row[k] += dy
    for row in world.get('zones', []):
        if row.get('name') == 'SAFFRON_CITY':
            row['rect'][0] += dx
            row['rect'][1] += dy
    meta['member_maps']['SAFFRON_CITY'] = new
    write_like(map_path, world)
    write_like(meta_path, meta)


class FireRedFields:
    def __init__(self, source, project, atlas):
        self.source = Path(source)
        self.meta = Path(project) / 'content/emerald_maps'
        self.atlas = atlas
        self.layouts = {l['id']: l for l in load(self.source / 'data/layouts/layouts.json')['layouts'] if 'id' in l}
        self.maps = {symbol(p.parent.name): load(p)['layout'] for p in (self.source / 'data/maps').glob('*/map.json')}
        self.folders = {symbol(p.parent.name): p.parent for p in (self.source / 'data/tilesets').glob('*/*/metatiles.bin')}
        self.written = set()

    @lru_cache(None)
    def bank(self, key):
        name = symbol(key.removeprefix('gTileset_'))
        folder = self.folders[name]
        base = 0 if folder.parent.name == 'primary' else 640
        tiles = np.zeros((640 if base == 0 else 384, 8, 8), np.uint8)
        # gTileset_SilphCo shares the condominium graphics but owns its metatiles.
        graphics = self.folders['condominiums'] if name == 'silphco' else folder
        original = chips(graphics / 'tiles.png')
        tiles[:min(len(original), len(tiles))] = original[:len(tiles)]
        for anim, address, size in ANIMATIONS.get(name, []):
            tiles[address-base:address-base+size] = chips(folder / 'anim' / anim / '0.png')[:size]
        palette = []
        for i in range(16):
            colors = (graphics / 'palettes' / f'{i:02}.pal').read_text().splitlines()[3:19]
            rgba = [[*map(int, line.split()), 255] for line in colors]
            rgba[0][3] = 0
            palette.append(np.array(rgba, np.uint8))
        return tiles, palette, np.fromfile(folder/'metatiles.bin', '<u2').reshape(-1,8), np.fromfile(folder/'metatile_attributes.bin', '<u4')

    @lru_cache(None)
    def metatile(self, primary, secondary, mid):
        banks = [self.bank(primary), self.bank(secondary)]
        bank = banks[mid >= 640]
        index = mid - (640 if mid >= 640 else 0)
        attrib = int(bank[3][index])
        top = Image.new('RGBA', (16, 16))
        tile = Image.new('RGBA', (16, 16))
        for n, word in enumerate(bank[2][index]):
            word = int(word)
            address = word & 1023
            pixels = banks[address >= 640][0][address - (640 if address >= 640 else 0)]
            if word & 1024: pixels = pixels[:, ::-1]
            if word & 2048: pixels = pixels[::-1, :]
            pal = word >> 12
            img = Image.fromarray(banks[pal >= 7][1][pal][pixels & 15])
            xy = ((n % 2)*8, (n % 4)//2*8)
            (top if n >= 4 else tile).alpha_composite(img, xy)
        tile.alpha_composite(top)
        # Covered metatiles leave the actor in front of both layers.
        foreground = self.atlas.add(top) if ((attrib >> 29) & 3) != 1 else 0
        return self.atlas.add(tile), foreground, attrib & 0x1ff

    @lru_cache(None)
    def layout(self, key):
        l = self.layouts[key]
        shape = (l['height'], l['width'])
        block = np.fromfile(self.source / l['blockdata_filepath'], '<u2').reshape(shape)
        for x,y,opened in OPEN_TILES.get(key, []):
            block[y,x] = (int(block[y,x]) & 0xf000) | opened
        mid = block & 1023
        table = np.zeros((1024,3), np.uint16)
        for i in np.unique(mid):
            table[i] = self.metatile(l['primary_tileset'], l['secondary_tileset'], int(i))
        ground, above, behavior = table[mid].transpose(2,0,1)
        return ground, above, block, behavior

    def aligned(self, layout, size):
        l = self.layouts[layout]
        if [l['width'], l['height']] != size:
            raise ValueError(f'{layout}: cannot map source coordinates into {size}')
        return self.layout(layout)

    def collision(self, meta, blocks, behavior):
        # Layout bits 10–11 are fixed collision and bits 12–15 are elevation.
        # Ground at elevation 3 and water at elevation 1 can both have collision=0.
        d = np.zeros(256, np.uint8)
        d[0x30:0x38] = FENCES
        jumps = np.zeros_like(d)
        jumps[0x38:0x3c] = DIRECTIONS
        slide = np.zeros_like(d)
        slide[0x23] = 255
        slide[0x44:0x48] = DIRECTIONS
        currents = np.zeros_like(d)
        currents[0x50:0x54] = DIRECTIONS
        fields = {
            'collision': ((blocks >> 10) & 3) != 0, 'elevation': blocks >> 12,
            'water': np.isin(behavior,SURFABLE), 'ledge': jumps[behavior], 'dirblock': d[behavior],
            'grass': np.isin(behavior,[0x02,0xd1]), 'counter': behavior == 0x80,
            'waterfall': behavior == 0x13, 'current': currents[behavior],
            'slide': slide[behavior], 'button': behavior == 0x20, 'hole': behavior == 0x66,
        }
        # Whirlpool, Dive and Rock Climb are not FireRed metatile behaviors.
        for legacy in ['whirl', 'deep', 'climb']:
            meta.pop(legacy, None)
        for name, grid in fields.items():
            if name in ('collision','elevation') or np.any(grid):
                meta[name] = grid.astype(np.uint8).tolist()
            else:
                meta.pop(name, None)

    def align_spawn(self, path, data, meta):
        x,y = data['spawn']
        w,h = meta['size']
        collision = meta['collision']
        water = meta.get('water')
        occupied = {tuple(n['at']) for n in data.get('npcs', [])}
        warps = {tuple(n['at']) for n in data.get('warps', [])}
        def dry(px, py):
            return (0 <= px < w and 0 <= py < h and collision[py][px] == 0
                    and not (water and water[py][px]))
        if dry(x,y):
            return
        options = [(abs(px-x)+abs(py-y), py, px) for py in range(h) for px in range(w)
                   if dry(px,py) and (px,py) not in occupied | warps]
        if not options:
            raise ValueError(f'{path}: no free floor for entry spawn')
        _,sy,sx = min(options)
        data['spawn'] = [sx,sy]
        write_like(path, data)

    def mansion(self, floor, lid):
        layout = self.layouts[lid]
        script = (self.source/'data/scripts/pokemon_mansion.inc').read_text()
        header = (self.source/'include/constants/metatile_labels.h').read_text()
        labels = dict(re.findall(r'#define (METATILE_PokemonMansion_\w+)\s+(0x[0-9A-Fa-f]+)',header))
        native = load(self.source/'data/maps'/('PokemonMansion_'+floor)/'map.json')
        result = {'statues': [[e['x'],e['y']] for e in native['bg_events'] if e.get('script','').endswith('_Statue')]}
        for state,action in [('on','Press'),('off','Reset')]:
            label = 'PokemonMansion_EventScript_'+action+'Switch_'+floor+'::'
            body = script.split(label,1)[1].split('\n\treturn',1)[0]
            changes = []
            for x,y,tile,solid in re.findall(r'setmetatile\s+(\d+),\s*(\d+),\s*(\w+),\s*([01])',body):
                mid = int(labels[tile],16)
                bg,fg,_ = self.metatile(layout['primary_tileset'],layout['secondary_tileset'],mid)
                changes.append([int(x),int(y),bg,fg,int(solid)])
            if not changes:
                raise ValueError(f'{label} has no metatile changes')
            result[state] = changes
        return result

    def draw(self, region, name, data):
        if region not in ('kanto','sevii') or not data.get('emerald'):
            return None
        path = self.meta / (data['emerald']+'.json')
        meta = load(path)
        map_path = self.meta.parent/'regions'/region/'maps'/(name+'.json')
        members = meta.get('member_maps', {})
        lid = self.maps.get(symbol(name), meta.get('id','').removesuffix('_FRLG'))
        if not members and meta['id'].removesuffix('_FRLG') != lid:
            # Older Lavender Center 2F pointed at the common ground-floor physics.
            path = self.meta/(lid.removeprefix('LAYOUT_').lower()+'_frlg.json')
            meta = load(path)
            if meta['id'].removesuffix('_FRLG') != lid:
                raise ValueError(f'{map_path}: expected physics for {lid}')
            data['emerald'] = path.stem
            write_like(map_path,data)
        w,h = meta['size']
        if members:
            ground = np.zeros((h,w),np.uint16)
            above = np.zeros_like(ground)
            blocks = np.full_like(ground,1<<10)
            behavior = np.zeros_like(ground)
            for member,(x,y) in members.items():
                src = self.layout('LAYOUT_'+member)
                mh,mw = src[0].shape
                for dest, part in zip((ground, above, blocks, behavior),src):
                    dest[y:y+mh,x:x+mw] = part
        else:
            if lid == 'LAYOUT_THREE_ISLAND_DUNSPARCE_TUNNEL':
                lid += '_DUG_OUT'
            ground,above,blocks,behavior = self.aligned(lid,meta['size'])
        if path not in self.written:
            self.collision(meta,blocks,behavior)
            result = json.dumps(meta, ensure_ascii=False, separators=(',',':'))
            if result != path.read_text():
                path.write_text(result)
            self.written.add(path)
        self.align_spawn(map_path,data,meta)
        from bake_emerald_field import pack
        result = {'s':[w,h],'t':pack(ground),'p':[]}
        if np.any(above):
            result['a'] = pack(above)
        gates = {'mt_ember_exterior': (42,39,0x346,'ember_ruby_requested'),
                 'six_island_ruin_valley': (24,24,0x358,'ruin_valley_cut_door')}
        if name in gates:
            x,y,opened,flag = gates[name]
            layout = self.layouts[lid]
            bg,fg,_ = self.metatile(layout['primary_tileset'],layout['secondary_tileset'],opened)
            result['quest_door'] = {'flag':flag,'closed':[x,y,int(ground[y,x]),int(above[y,x]),1],
                                    'open':[x,y,bg,fg,0]}
        if name.startswith('pokemon_mansion_') and name.rsplit('_',1)[-1] in ('1f','2f','3f','b1f'):
            result['mansion'] = self.mansion(name.rsplit('_',1)[-1].upper(),lid)
        # PokeSaga repurposes the upstairs wall plaque as its world map.
        if name == 'pallet_town_players_house_2f':
            result['p'] = [['map',11,1]]
        return result
