"""Five-tile Canalave Library and the two paved quays of Platinum's C02 map."""
import base64
import json
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from platinum_layout import ROOT


def facade():
    # Platinum C2_S02: a broad seamed roof over three upper and two lower
    # windows. The shallow projecting canopy has its own four square supports.
    image = Image.new("RGBA", (80, 94))
    d = ImageDraw.Draw(image)
    edge, shade, stone, light = "#384f59", "#72857f", "#aaba9f", "#c5cdb0"
    teal, roof, seam, glint = "#346b85", "#508ca2", "#49839b", "#83b5c2"

    # Short run of end blocks and a single shaded return along the garden side.
    d.rectangle((6, 35, 73, 88), fill=shade, outline=edge)
    d.rectangle((8, 38, 70, 85), fill=stone)
    for y in range(42, 85, 6):
        d.line((8, y, 69, y), fill="#9caa94")
        for x in range(9 + 6 * ((y // 6) % 2), 70, 13):
            d.line((x, y + 1, x, min(85, y + 5)), fill="#a1b09a")
    d.line((9, 40, 9, 85), fill=light, width=2)
    d.line((70, 39, 70, 85), fill=shade, width=2)
    d.line((7, 85, 72, 85), fill="#879588", width=2)
    d.line((7, 88, 72, 88), fill=edge)

    # Upright sheet-metal ribs sit above staggered green-grey masonry. The
    # eaves expose a dark underside, like Emerald's harbour warehouses.
    d.polygon([(2, 7), (6, 2), (72, 2), (77, 7), (79, 37),
               (77, 40), (3, 40), (1, 37)], fill=edge)
    d.polygon([(4, 8), (8, 4), (71, 4), (75, 8), (77, 33),
               (3, 33)], fill=roof)
    # The DS silhouette has three transverse levels. On GBA the value steps
    # separate its broad lit upper plane from the steeper rolled front eave.
    d.polygon([(5, 9),(75, 9),(75, 16),(4, 16)], fill="#5b99ac")
    d.polygon([(4, 22),(76, 22),(77, 28),(3, 28)], fill="#4b829b")
    d.polygon([(3, 29),(77, 29),(77, 33),(3, 33)], fill="#42778e")
    d.line((8, 4, 71, 4), fill=glint, width=2)
    # Broken and staggered joints leave the roof's perspective to its eaves;
    # an unbroken line from ridge to gutter reads as a vertical shutter.
    for y, phase in [(8,0), (17,7), (23,0), (29,7)]:
        for x in range(11+phase, 74, 16):
            d.line((x, y, x, y+3), fill=seam)
            d.point((x+1, y+1), fill="#6296a8")
    d.line((5, 16, 75, 16), fill="#76a6b4")
    d.line((4, 27, 76, 27), fill="#658fa6")
    d.line((3, 32, 77, 32), fill="#3c6c86")
    d.line((3, 33, 77, 33), fill=glint)
    d.rectangle((3, 34, 77, 37), fill=teal)
    d.line((4, 36, 76, 36), fill="#40798a")
    d.line((4, 38, 76, 38), fill="#537a7e")
    d.line((6, 40, 73, 40), fill=shade, width=2)
    for x in (6, 73):
        d.line((x, 3, x, 7), fill="#ae9470", width=2)
        d.point((x, 3), fill="#e0c58e")

    def window(x, y):
        d.rectangle((x, y + 2, x + 8, y + 8), fill=edge)
        d.line((x + 2, y, x + 6, y), fill=shade)
        d.line((x + 1, y + 1, x + 7, y + 1), fill=edge)
        d.rectangle((x + 2, y + 2, x + 6, y + 7), fill="#74879b")
        d.line((x+6,y+3,x+6,y+7), fill="#586b83")
        d.line((x + 2, y + 3, x + 4, y + 2), fill="#b5c6c9")
        d.point((x + 2, y + 4), fill="#90aaba")
        d.line((x - 1, y + 8, x + 9, y + 8), fill=light)
        d.line((x - 1, y + 9, x + 9, y + 9), fill=shade)

    for x in (13, 35, 57):
        window(x, 43)
    for x in (13, 57):
        window(x, 55)
    # A one-cell-wide recessed glazed door at the actual warp, with no raised
    # staircase on the walking cell. Keep part of the doorway lit under the hood.
    d.rectangle((30, 67, 49, 88), fill=edge)
    d.rectangle((32, 69, 47, 87), fill="#516d75")
    for x in (33, 41):
        d.rectangle((x, 70, x + 5, 84), fill="#77a3a7")
        d.line((x, 72, x + 2, 70), fill="#bfd5ce")
        d.line((x, 80, x + 5, 80), fill="#526e74")
        d.line((x, 85, x + 5, 85), fill=teal)
    d.rectangle((23, 89, 56, 91), fill="#a7ada0")
    d.line((23, 89, 56, 89), fill="#d5d8bf")

    # Horizontal porch wings, short four-post arcade and a raised central hood.
    for x in (7, 23, 54, 70):
        d.rectangle((x, 70, x + 2, 89), fill=shade)
        d.line((x, 71, x, 88), fill=light)
        d.line((x - 1, 90, x + 3, 90), fill="#697873")
    d.polygon([(4, 67), (25, 67), (39, 59), (53, 67), (74, 67),
               (76, 74), (53, 74), (39, 67), (25, 74), (3, 74)], fill=teal, outline=edge)
    d.line([(4, 68), (25, 68), (39, 60), (54, 68), (74, 68)], fill=glint)
    for x in (10, 16, 22, 57, 63, 69):
        d.line((x, 69, x - 1, 72), fill=seam)
    d.line([(5, 73), (25, 73), (39, 65), (54, 73), (74, 73)], fill="#638e95")
    return image


def harbour_house(original):
    # Retain the tiled central doorway, inset facade and adjacent window of
    # Platinum C2_H01A. Its old plain-blue roof lost the source lighting.
    rgba = np.array(original)
    rgb = rgba[:, :, :3]
    y, x = np.indices(rgba.shape[:2])
    visible = rgba[:, :, 3] > 128
    roof = visible & (y < 51) & (rgb[:, :, 2].astype(int) > rgb[:, :, 0].astype(int)+35)
    with Image.open(ROOT / "assets/emerald/field/home_blue.png") as home:
        shingles = np.asarray(home.convert("L").crop((7,12,23,28)), dtype=int)
    value = shingles[y%16, x%16]
    value = (value-shingles.mean())*.40 + np.select([y < 5, y < 23, y < 36], [8,4,0], default=-7)
    rgb[roof] = np.asarray((83,112,149)) + value[roof, None].astype(int)
    eave = roof & ~ndimage.binary_erosion(roof)
    rgb[eave] = (60,84,111)
    glass = (x > 40) & (y > 56) & (y < 73) & visible & (rgb[:,:,2] > 196)
    rgb[glass] = np.array((129,162,176)) + ((x[glass]+y[glass])%9==0)[:,None] * 35
    return Image.fromarray(rgba)


def quays(bg):
    # The original road and land shaders share a compound cross-in-square
    # motif. Recover their two surface masks before the town is indexed so
    # planters, pier timbers, retaining walls and the actual shore survive.
    pixels = np.array(bg)
    rgb = pixels[:, :, :3]
    def matches(colors):
        mask = np.zeros(rgb.shape[:2], dtype=bool)
        for color in colors:
            mask |= np.all(rgb == color, axis=2)
        return mask

    street = matches([(165,198,189), (148,189,173), (140,173,165), (132,165,148)])
    court = matches([(206,222,206), (198,214,189), (181,206,181), (181,198,173)])
    water = matches([(41,115,231), (33,107,214), (99,165,255), (74,148,247)])
    y, x = np.indices(street.shape)
    # Use the actual Slateport water and granite setts, resolved through GBA
    # map coordinates so rearranging the baked tile atlas cannot change the art.
    map_data = json.loads((ROOT / "content/hoenn_native/maps/hoenn_slateport.json").read_bytes())
    width, height = map_data["size"]
    ids = np.frombuffer(zlib.decompress(base64.b64decode(map_data["hoenn_art"]["t"])),
                        dtype="<u2").reshape(height, width)
    def slateport(x, y):
        tile = int(ids[y, x])
        if tile >= 49152:
            tile -= 49152
            tx, ty = tile % 8 * 128, tile // 8 * 16
            name = "water"
        else:
            tx, ty = tile % 64 * 16, tile // 64 * 16
            name = "tiles"
        with Image.open(ROOT / f"assets/hoenn_native/{name}.png") as sheet:
            return np.asarray(sheet.crop((tx, ty, tx+16, ty+16)).convert("L"), dtype=int)
    # Retain the original streets connecting all entrances. Reduce the width
    # of the dark paving at the library into a single approach from the bridge.
    frontage = (x >= 14) & (x < 158) & (y >= 173) & (y < 309)
    aisle = (x >= 72) & (x < 105) & (y >= 224)
    all_paving = street | court
    # The tiny crenellations in the old border came from the flower motif in
    # its texels. Follow the centres of the native surfaces to a clean curb.
    road = ndimage.gaussian_filter(street.astype(float), 3.5) >= 0.46
    road = all_paving & road & (~frontage | aisle)
    pavement = all_paving & ~road
    # Long limestone flags on the civic court; the streets use Slateport's
    # smaller granite setts with the colours of Canalave's waterfront.
    width, height = 19, 10
    row = y // height
    offset = (x + width // 2 * (row % 2)) % width
    block = (x + width // 2 * (row % 2)) // width
    tone = ((block * 17 + row * 23 + (row // 3) * 5) % 5) - 2
    rgb[pavement] = (np.array((198,202,186)) + 2 * tone[pavement, None])
    rgb[pavement & ((y % height == 0) | (offset == 0))] = (181,187,173)
    rgb[pavement & (y % height == 1) & (offset > 1) & (offset < width - 3)] = (205,208,191)
    cobble = slateport(12,14)
    grain = (cobble - cobble.mean()) * .40
    rgb[road] = (np.array((166,184,177)) + grain[y[road] % 16, x[road] % 16, None])
    boundary = pavement & ndimage.binary_dilation(road)
    rgb[boundary] = (149,163,154)
    rgb[pavement & ndimage.binary_dilation(boundary) & ~boundary] = (212,212,192)

    # Fountain plinth, the landing under the doors, and waterside wear.
    fountain = ((x-32)/21.0)**2 + ((y-274)/15.0)**2
    rgb[all_paving & (fountain < 1.08) & (fountain > .89)] = (157,170,161)
    rgb[all_paving & (fountain < .89) & (fountain > .76)] = (216,216,194)
    landing = all_paving & (abs(x-88) <= 18) & (y >= 236) & (y < 243)
    rgb[landing] = (195,195,175)
    rgb[landing & ((x-71)%12 == 0)] = (177,182,166)
    rgb[landing & (y == 241)] = (215,213,190)
    rgb[landing & (y == 242)] = (163,172,158)

    sea = slateport(38,1)
    swell = (sea - sea.mean()) * .39
    distance = ndimage.distance_transform_edt(water)
    shore = np.clip(1-distance/15, 0, 1)
    sea_level = (swell[y%16, x%16] + shore * 11).astype(int)
    rgb[water] = np.array((80,146,180)) + sea_level[water, None]
    # Occasional short broken crests over the softer native wave forms.
    for row in range(bg.height // 12):
        for col in range(bg.width // 29):
            px = 29*col + (row*11 + 7*col*col) % 24
            py = 12*row + (row*7 + col*3) % 9
            for dy, dx, span, color in [(0,0,3,(115,174,195)), (1,3,4,(109,167,191))]:
                sy, sx = py+dy, px+dx
                crest = rgb[sy, sx:sx+span]
                crest[water[sy, sx:sx+span]] = color
    return Image.fromarray(pixels)


def bridge_layers(parts):
    # C2_S03A/B each contain their rolling deck, railings, cables and tower.
    # The horizontal floor faces are below the player's feet. Sort the far
    # rail against its own waterline, independent of the two near-side towers.
    layers = {"deck": [], "rear": [], "front": []}
    for material, xyz, uv, indices, texture in parts:
        tris = indices.reshape(-1, 3)
        points = xyz[tris]
        deck = points[:, :, 1].max(axis=1) <= .01
        rear = ~deck & (points[:, :, 2].max(axis=1) < 0)
        for key, keep in (("deck", deck), ("rear", rear), ("front", ~deck & ~rear)):
            if not keep.any():
                continue
            used, index = np.unique(tris[keep].ravel(), return_inverse=True)
            layers[key].append((material, xyz[used], uv[used],
                                np.ascontiguousarray(index, dtype="uint32"), texture))
    return layers
