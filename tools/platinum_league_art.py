"""Dress Platinum's scripted League arenas in Emerald League metatiles."""
import base64
import json
import math
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps

from bake_emerald_field import Emerald, pack
from platinum_layout import ROOT, OUT, write

ROOMS = {
    "aaron": "SidneysRoom",
    "bertha": "SidneysRoom",
    "flint": "DrakesRoom",
    "lucian": "PhoebesRoom",
    "champion": "ChampionsRoom",
}

def room_picture(emerald, member):
    layout = "EverGrandeCity_" + ROOMS[member]
    source = emerald.grid(layout)
    # The DS arena has a wider aisle than the GBA hall. Repeat straight sections,
    # keeping the central emblem, door and stairs on the native x=8 axis.
    columns = [0, 1, 2, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10, 11, 12]
    if member == "champion":
        # Platinum's floor is a separate map prop (champ_room, 110). It has a
        # lift at (8,8), stone walls, teal trim and a gold hub. Keep the source
        # hall's bevels continuous when fitting its lift deck between the doors.
        original = emerald.patch(layout, 0, 0, 13, 13)
        image = Image.new("RGBA", (17*16, 19*16))
        for top, bottom, target_top, target_bottom in [(0, 4, 0, 4), (4, 10, 4, 14), (10, 13, 14, 19)]:
            strip = original.crop((0, top*16, original.width, bottom*16))
            strip = strip.resize((15*16, (target_bottom-target_top)*16), Image.Resampling.NEAREST)
            image.alpha_composite(strip, (16, target_top*16))
    else:
        rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13]
        image = Image.new("RGBA", (16 * len(columns), 16 * len(rows)))
        for y, sy in enumerate(rows):
            for x, sx in enumerate(columns):
                tile = emerald.metatile(layout, source[sy, sx])
                image.alpha_composite(tile, (16*x, 16*y))
    if member == "aaron":
        # The Bug specialist's green arena distinguishes it from Bertha's ochre hall.
        palette = ImageOps.colorize(ImageOps.grayscale(image), "#253d2b", "#d4dc93", mid="#829947")
        floor = (0, 3*16, image.width, 11*16)
        image.paste(palette.crop(floor), floor, image.getchannel("A").crop(floor))
    if member == "champion":
        alpha = image.getchannel("A")
        floor_pixel = emerald.metatile(layout, 0x313).getpixel((8, 8))
        deck = np.all(np.array(image) == floor_pixel, axis=2)
        wall = ImageOps.colorize(ImageOps.grayscale(image), "#222532", "#d7cda7", mid="#514d67")
        wall.putalpha(alpha)
        image = wall
        # Pixel detail from a real Ever Grande court gives the lift deck a
        # quiet tile pattern underneath its medallion.
        donor = emerald.metatile("EverGrandeCity_PhoebesRoom", emerald.grid("EverGrandeCity_PhoebesRoom")[6,3])
        texture = ImageOps.colorize(ImageOps.grayscale(donor), "#5a5967", "#797583")
        repeat = np.tile(np.array(texture), (image.height//16, image.width//16, 1))
        pixels = np.array(image)
        pixels[deck,:3] = repeat[deck]
        image = Image.fromarray(pixels)
        # The lift's round gold centre, segmented tiles and turquoise guide rails
        # are features of Platinum's champion room model, not bedroom furniture.
        layer = Image.new("RGBA", (80, 80))
        pen = ImageDraw.Draw(layer)
        pen.ellipse((2, 2, 77, 77), fill="#383a49", outline="#252a3b", width=2)
        pen.ellipse((5, 4, 74, 74), fill="#656775", outline="#527e85", width=3)
        pen.ellipse((9, 8, 70, 70), fill="#706e7c", outline="#939099")
        for dy in (18, 31, 45, 58):
            pen.line((16 if dy in (18, 58) else 11, dy, 63 if dy in (18, 58) else 68, dy), fill="#676775")
        pen.line((6, 39, 73, 39), fill="#354f5c", width=5)
        pen.line((6, 38, 73, 38), fill="#68a29c", width=2)
        pen.ellipse((25, 24, 54, 54), fill="#383c49", outline="#454656", width=2)
        pen.ellipse((28, 27, 51, 50), fill="#b6a555", outline="#725f44", width=2)
        pen.arc((30, 29, 49, 48), 175, 295, fill="#ded184", width=2)
        image.alpha_composite(layer, ((8*16+8)-40, (8*16+8)-40))
    return image

def dress(emerald_source):
    emerald = Emerald(emerald_source)
    atlas_path = ROOT / "assets/platinum_native/tiles.png"
    sheet = Image.open(atlas_path).convert("RGBA")
    tiles = [sheet.crop((x, y, x+16, y+16)) for y in range(0, sheet.height, 16) for x in range(0, sheet.width, 16)]
    indices = {tile.tobytes(): i for i, tile in enumerate(tiles) if tile.getbbox()}

    def tile_id(tile):
        if not tile.getbbox(): return 0
        pixels = tile.tobytes()
        if pixels not in indices:
            indices[pixels] = len(tiles)
            tiles.append(tile)
        return indices[pixels]

    for member in ROOMS:
        path = OUT / "maps" / f"sinnoh_pokemon_league_{member}_room.json"
        data = json.loads(path.read_bytes())
        art = data["hoenn_art"]
        grid = np.zeros(art["s"][::-1], dtype="<u2")
        picture = room_picture(emerald, member)
        for y in range(0, picture.height, 16):
            for x in range(0, picture.width, 16):
                grid[y//16, x//16] = tile_id(picture.crop((x,y,x+16,y+16)))
        art["t"] = pack(grid)
        write(path, data)

    # The three retained Diamond/Pearl return doors are one row beyond Platinum's
    # model. Extend the existing gym floor and give each doorway a visible threshold.
    path = OUT / "maps/sinnoh_hearthome_city_gym_leader_room.json"
    data = json.loads(path.read_bytes())
    art = data["hoenn_art"]
    grid = np.frombuffer(zlib.decompress(base64.b64decode(art["t"])), dtype="<u2").reshape(art["s"][::-1]).copy()
    grid[15:17,1:15] = grid[14,1]
    for warp in data["warps"]:
        x,y = warp["at"]
        if y == 17:
            grid[y,x] = tile_id(emerald.metatile("EverGrandeCity_PhoebesRoom", emerald.grid("EverGrandeCity_PhoebesRoom")[13,6]))
    art["t"] = pack(grid)
    write(path, data)

    result = Image.new("RGBA", (256, 16 * math.ceil(len(tiles) / 16)))
    for i, tile in enumerate(tiles):
        result.paste(tile, ((i % 16)*16, (i // 16)*16))
    result.save(atlas_path, optimize=True)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pokeemerald", type=Path)
    dress(parser.parse_args().pokeemerald)
