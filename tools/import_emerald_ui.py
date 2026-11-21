"""Assemble the Emerald title, PokéNav and bag art from their original GBA tiles."""
import argparse
import struct
from pathlib import Path

from PIL import Image

from asset_paths import project_path, source_path


def palette(path):
    return [tuple(map(int, line.split())) for line in path.read_text().splitlines()[3:]]


def tile_at(sheet, index):
    cols = sheet.width // 8
    x, y = index % cols * 8, index // cols * 8
    return sheet.crop((x, y, x + 8, y + 8))


def text_layer(stem, width, height, first_bank=0):
    sheet = Image.open(stem.with_suffix(".png"))
    data = stem.with_suffix(".bin").read_bytes()
    entries = struct.unpack(f"<{len(data)//2}H", data)
    layer = Image.new("P", (width * 8, height * 8))
    for y in range(height):
        for x in range(width):
            entry = entries[y * 32 + x]
            tile = tile_at(sheet, entry & 1023)
            if entry & 1024:
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if entry & 2048:
                tile = tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            offset = ((entry >> 12) - first_bank) * 16
            tile = tile.point([(i % 16) + offset for i in range(256)])
            layer.paste(tile, (x * 8, y * 8))
    return layer


def colorize(pixels, colors):
    pixels.putpalette([v for rgb in colors for v in rgb])
    return pixels.convert("RGB")


def sprite(pixels, colors):
    mask = Image.frombytes("L", pixels.size, pixels.tobytes()).point(lambda i: 255 if i else 0)
    image = colorize(pixels, colors).convert("RGBA")
    image.putalpha(mask)
    return image.crop(image.getbbox())


def build(graphics, dest):
    dest.mkdir(parents=True, exist_ok=True)
    # DrawStdWindowFrame uses the nine 8px tiles of the selected window frame.
    # Index 0 lets the map show through outside the corners and outer lip.
    with Image.open(graphics / "text_window/1.png") as frame:
        frame.info["transparency"] = 0
        frame.convert("RGBA").save(dest / "menu_frame.png", optimize=True)

    title = graphics / "title_screen"
    colors = palette(title / "rayquaza_and_clouds.pal")
    # The original title animates palette entry 15. Use its bright gold-green frame.
    colors[15] = (255, 255, 98)
    silhouette = text_layer(title / "rayquaza", 30, 20, first_bank=14)
    colorize(silhouette, colors).save(dest / "rayquaza_title.png", optimize=True)

    # Reuse the party screen's striped field and the original closed bag frame.
    party = text_layer(graphics / "party_menu/bg", 30, 20)
    party.putpalette(Image.open(graphics / "party_menu/bg.png").getpalette())
    party.crop((32, 16, 112, 64)).convert("RGB").save(dest / "party_panel.png", optimize=True)
    bag = Image.open(graphics / "bag/bag_male.png").crop((0, 0, 64, 64))
    sprite(bag, palette(graphics / "bag/bag.pal")).save(dest / "bag.png", optimize=True)

    item = Image.open(graphics / "items/icons/poke_ball.png")
    ball = sprite(item, palette(graphics / "items/icon_palettes/poke_ball.pal"))
    green = (18, 103, 81)
    launcher = Image.new("RGBA", (192, 192), green)
    foreground = Image.new("RGBA", (432, 432))
    # Use the red dome and dark outline as an Android themed-icon stencil.
    indices = Image.frombytes("L", item.size, item.tobytes())
    stencil = indices.point(lambda i: 255 if i in (1, 2) or 7 <= i <= 11 else 0)
    mono = Image.new("RGBA", item.size, "white")
    mono.putalpha(stencil)
    mono = mono.crop(indices.getbbox())
    themed = Image.new("RGBA", foreground.size)
    for canvas, chip, scale in [(launcher, ball, 6), (foreground, ball, 14), (themed, mono, 14)]:
        chip = chip.resize((chip.width * scale, chip.height * scale), Image.Resampling.NEAREST)
        canvas.alpha_composite(chip, ((canvas.width - chip.width) // 2, (canvas.height - chip.height) // 2))
    launcher.convert("RGB").save(dest / "launcher.png", optimize=True)
    foreground.save(dest / "launcher_foreground.png", optimize=True)
    themed.save(dest / "launcher_monochrome.png", optimize=True)
    Image.new("RGB", foreground.size, green).save(dest / "launcher_background.png", optimize=True)

    # The region map uses a 64-column affine map, single-byte tile IDs and an
    # 8bpp sheet with the two visible palette banks loaded at hardware bank 7.
    nav = graphics / "pokenav/region_map"
    sheet = Image.open(nav / "map.png")
    data = (nav / "map.bin").read_bytes()
    region = Image.new("P", (248, 152))
    for y in range(region.height // 8):
        for x in range(region.width // 8):
            region.paste(tile_at(sheet, data[y * 64 + x]), (x * 8, y * 8))
    colors = [(0, 0, 0)] * 112 + palette(nav / "map.pal")
    colorize(region, colors).save(dest / "hoenn_map.png", optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(source_path("emerald_original")))
    parser.add_argument("--project", type=Path, default=Path(project_path()))
    args = parser.parse_args()
    build(args.source / "graphics", args.project / "assets/emerald/ui")
