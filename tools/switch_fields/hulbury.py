"""Lay the market street and quay with the walking surfaces of Slateport City."""
from PIL import Image, ImageDraw


def waterfront(emerald, canvas, cells):
    def chip(tile_id):
        return emerald.metatile("SlateportCity", tile_id).convert("RGB")

    # Keep the dark grout and tile joints from the original metatiles, with a
    # warm local limestone ramp between the brick street and the sandy shore.
    stone = chip(0x211)
    quay = chip(0x202)
    def limestone(tile, base):
        pixels = list(tile.getdata())
        def light(rgb):
            return (rgb[0] * 3 + rgb[1] * 6 + rgb[2]) / 10
        average = sum(map(light, pixels)) / len(pixels)
        ramp = {}
        for rgb in set(pixels):
            shade = max(-12, min(9, round((light(rgb) - average) * 0.55)))
            ramp[rgb] = tuple(channel + shade for channel in base)
        coloured = tile.copy()
        coloured.putdata([ramp[rgb] for rgb in pixels])
        return coloured

    cobbles = limestone(stone, (187, 177, 157))
    flags = limestone(quay, (173, 167, 151))
    surface = {}
    for y in range(14, 25):
        for x in range(1, 32):
            if cells[y][x] == 2:
                continue
            street = (16 <= y <= 17 and x <= 19) or (15 <= x <= 16 and 16 <= y <= 23)
            market = 8 <= x <= 16 and 17 <= y <= 21
            beacon = 17 <= x <= 21 and 15 <= y <= 17
            pier = y in (22, 23) and 15 <= x <= 23
            if street or market or beacon or pier:
                surface[x, y] = flags if pier or beacon else cobbles
    draw = ImageDraw.Draw(canvas)
    for (x, y), tile in surface.items():
        x0, y0 = x * 16, y * 16
        canvas.paste(tile, (x0, y0))
        if (x, y - 1) not in surface:
            draw.line((x0, y0, x0 + 15, y0), fill="#a19785")
        if (x, y + 1) not in surface:
            draw.line((x0, y0 + 14, x0 + 15, y0 + 14), fill="#d6cbb2")
            draw.line((x0, y0 + 15, x0 + 15, y0 + 15), fill="#958c7d")

    # Preserve the exact beach foam and bridge pilings. Only water pixels take
    # the original animated-water pattern, including cells adjacent to the quay.
    wave = chip(0x170)
    for y, row in enumerate(cells):
        for x, terrain in enumerate(row):
            if terrain != 2:
                continue
            at = (x * 16, y * 16)
            original = canvas.crop((*at, at[0] + 16, at[1] + 16)).convert("RGB")
            mask = Image.new("L", (16, 16))
            mask.putdata([255 if blue - red > 100 and blue > green + 22 else 0
                          for red, green, blue in original.getdata()])
            canvas.paste(wave, at, mask)
