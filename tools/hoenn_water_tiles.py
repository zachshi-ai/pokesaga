"""Native Emerald overworld water animation tile banks, in source VRAM order."""
from functools import lru_cache

import numpy as np
from PIL import Image

from bake_emerald_field import Emerald


ANIM_START = 49152
BANKS = {
    'gTileset_General': (
        ('water', 432, 30, 8), ('sand_water_edge', 464, 10, 8),
        ('land_water_edge', 480, 10, 4), ('waterfall', 496, 6, 4)),
    'gTileset_Sootopolis': (('stormy_water', 240, 96, 8),),
    'gTileset_Pacifidlog': (('water_currents', 496, 8, 8),),
}


def chips(path):
    frame = np.array(Image.open(path))
    return frame.reshape(frame.shape[0]//8,8,frame.shape[1]//8,8).transpose(0,2,1,3).reshape(-1,8,8)


class Frame(Emerald):
    def __init__(self, original, phase):
        self.base = original
        self.phase = phase

    @lru_cache(None)
    def tileset(self, name):
        sheet, table, colors = self.base.tileset(name)
        if name not in BANKS:
            return sheet, table, colors
        sheet = np.pad(sheet, ((0,512-len(sheet)),(0,0),(0,0)))
        folder = self.base.dirs[name.removeprefix('gTileset_').lower()]/'anim'
        for bank, start, count, length in BANKS[name]:
            phase = self.phase % length
            if bank == 'sand_water_edge' and phase == 7:
                phase = 0
            if bank == 'stormy_water':
                cells = np.concatenate([chips(folder/bank/f'{phase}_{mon}.png') for mon in ('kyogre','groudon')])
            else:
                cells = chips(folder/bank/f'{phase}.png')
            sheet[start:start+count] = cells[:count]
        return sheet, table, colors


class WaterTiles:
    def __init__(self, original):
        self.original = original
        self.frames = [Frame(original, i) for i in range(8)]
        self.sequences = {}

    @lru_cache(None)
    def tile(self, primary, secondary, mid, above):
        table = self.original.tileset(primary if mid<512 else secondary)[1][mid%512]
        if above:
            table = table[4:]
        def animated(entry):
            n = int(entry) & 1023
            return any(start <= n%512 < start+count for _,start,count,_ in BANKS.get(primary if n<512 else secondary,()))
        if not any(animated(entry) for entry in table):
            return None
        seq = tuple(frame.tile(primary,secondary,mid,above).tobytes() for frame in self.frames)
        if len(set(seq)) == 1:
            return None
        if seq not in self.sequences:
            self.sequences[seq] = ANIM_START + len(self.sequences)
        return self.sequences[seq]

    def save(self, path):
        image = Image.new('RGBA', (1024, ((len(self.sequences)+7)//8)*16))
        for seq, tile in self.sequences.items():
            i = tile-ANIM_START
            for j, raw in enumerate(seq):
                image.paste(Image.frombytes('RGBA',(16,16),raw),((i%8*8+j)*16,i//8*16))
        image.save(path,optimize=True)
