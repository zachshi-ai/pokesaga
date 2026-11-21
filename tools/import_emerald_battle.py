"""Decode the original GBA battle terrain screenblocks and their 4-bit palettes."""
from pathlib import Path
from struct import iter_unpack

from PIL import Image

from asset_paths import project_path, source_path


def read_palette(path):
    return [int(n) for line in path.read_text().splitlines()[3:] for n in line.split()]


def render(tiles_path, map_path, palette, y_start, y_end, bank_offset):
    with Image.open(tiles_path) as image:
        tiles = image.copy()
    colors = bytes(palette)
    screen = Image.new("RGB", (240, (y_end-y_start)*8))
    entries = list(iter_unpack("<H", map_path.read_bytes()))
    for y in range(y_start, y_end):
        for x in range(30):
            word = entries[y * 32 + x][0]
            index = word & 1023
            left = index % (tiles.width // 8) * 8
            top = index // (tiles.width // 8) * 8
            tile = tiles.crop((left, top, left + 8, top + 8))
            bank = max(0, (word >> 12) - bank_offset)
            tile.putpalette(colors[bank * 48:(bank + 1) * 48])
            if word & 0x400:
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if word & 0x800:
                tile = tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            screen.paste(tile.convert("RGB"), (x * 8, (y-y_start) * 8))
    return screen


if __name__ == "__main__":
    inputs = Path(source_path("emerald_original", "graphics/battle_environment"))
    out = Path(project_path("assets/emerald/battle"))
    out.mkdir(parents=True, exist_ok=True)
    for name, folder, pal in [
        ("grass", "tall_grass", "palette"), ("forest", "long_grass", "palette"),
        ("sand", "sand", "palette"), ("water", "water", "palette"),
        ("underwater", "underwater", "palette"), ("cave", "cave", "palette"),
        ("building", "building", "palette"), ("gym", "building", "gym"),
        ("league", "stadium", "drake"), ("ice", "stadium", "glacia"), ("sky", "sky", "palette"),
    ]:
        source = inputs/folder
        render(source/"tiles.png", source/"map.bin", read_palette(source/(pal+".pal")),
               0, 14, 2).save(out/(name+".png"), optimize=True)
    ui = Path(source_path("emerald_original", "graphics/battle_interface"))
    palettes = read_palette(ui/"textbox_0.pal") + read_palette(ui/"textbox_1.pal")
    render(ui/"textbox.png", ui/"textbox_map.bin", palettes, 14, 20, 0).save(out/"dialogue.png")
    for side in ["player", "opponent"]:
        with Image.open(ui/f"healthbox_singles_{side}.png") as image:
            image.info["transparency"] = 0
            panel = image.convert("RGBA")
            panel.crop(panel.getbbox()).save(out/f"hp_{side}.png")
