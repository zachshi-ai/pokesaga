"""Canalave's library furniture, drawn around Emerald book, chair and cabinet details."""

import base64
import json
import zlib
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

from platinum_layout import ROOT

INK = "#49434a"
RECESS = "#584a48"
DARK = "#775548"
OAK = "#a67353"
HONEY = "#c39467"
EDGE = "#dec091"
PAGES = "#e5dfc3"
TEAL = "#527c83"
BLUE = "#617e9e"


@lru_cache(None)
def donor(name, box):
    """Get native pixels by room position, independent of atlas numbering."""
    data = json.loads((ROOT / "content/hoenn_native/maps" / (name+".json")).read_bytes())
    width, height = data["size"]
    left, top, right, bottom = box
    result = Image.new("RGBA", (right-left, bottom-top))
    with Image.open(ROOT / "assets/hoenn_native/tiles.png") as sheet:
        for layer in ("t", "a"):
            if layer not in data["hoenn_art"]:
                continue
            ids = np.frombuffer(zlib.decompress(base64.b64decode(data["hoenn_art"][layer])), "<u2")
            ids = ids.reshape(height, width)
            for ty in range(top//16, (bottom+15)//16):
                for tx in range(left//16, (right+15)//16):
                    index = int(ids[ty,tx])
                    if index:
                        x, y = index%64*16, index//64*16
                        tile = sheet.crop((x,y,x+16,y+16)).convert("RGBA")
                        result.alpha_composite(tile, (tx*16-left,ty*16-top))
    return result


@lru_cache(None)
def birch_folio():
    # This is the open-tilted red volume on the laboratory's north workbench.
    # Mask its footprint so neither the neighbouring papers nor desk comes
    # with it to the library shelf.
    book = donor("littleroot_birch_lab", (131,19,144,31)).copy()
    silhouette=Image.new("L",book.size)
    ImageDraw.Draw(silhouette).polygon([(0,4),(5,0),(7,0),(12,6),(12,7),
                                        (6,11),(4,11),(0,6)], fill=255)
    book.putalpha(silhouette)
    return book


def closed_book(draw, x, y, width, color):
    """A horizontal folio with a visible fore edge and its spine to the left."""
    draw.rectangle((x,y,x+width,y+3), fill=INK)
    draw.line((x+2,y+2,x+width-1,y+2), fill=PAGES)
    draw.line((x+1,y,x+width-1,y), fill=color)
    draw.point((x,y+1), fill=color)


def open_book(draw, x, y):
    draw.polygon([(x,y+1),(x+3,y),(x+6,y+1),(x+9,y),(x+12,y+1),
                  (x+12,y+7),(x+8,y+6),(x+6,y+7),(x+3,y+6),(x,y+7)],fill=DARK)
    for side in (0,7):
        draw.polygon([(x+side,y),(x+side+2,y-1),(x+side+5,y),
                      (x+side+5,y+4),(x+side+3,y+4),(x+side,y+5)],fill=PAGES)
        draw.line((x+side+1,y+1,x+side+3,y+1),fill="#aca58e")
        draw.line((x+side+1,y+3,x+side+2,y+3),fill="#c5bda3")
    draw.line((x+6,y+1,x+6,y+5),fill="#bbaa8d")


@lru_cache(None)
def shelf_books():
    # Real binding groups from Birch's laboratory and the Slateport Fan Club.
    # Replace the steel shelf recess with walnut, retaining the distinct spines.
    birch = donor("littleroot_birch_lab", (3,20,29,24))
    lower = donor("littleroot_birch_lab", (3,27,29,31))
    club = donor("em_slateport_city_pokemon_fan_club", (5,36,27,40))
    dyes = {
        (65,65,82):(80,66,64), (65,74,106):(80,66,64),
        (98,98,197):(101,109,153), (82,131,189):(82,129,153),
        (82,180,65):(114,146,106), (172,65,57):(145,81,71),
        (213,82,65):(178,94,74), (139,139,148):(185,164,129),
        (180,180,164):(212,197,157), (255,246,41):(204,172,88),
        (238,131,106):(183,111,88), (205,106,106):(171,103,98),
        (246,246,255):(227,221,200), (172,205,213):(155,183,183),
    }
    result=[]
    for strip in (birch,lower,club):
        pixels=strip.convert("RGB")
        pixels.putdata([dyes.get(c,c) for c in pixels.getdata()])
        result.append(pixels)
    return result


@lru_cache(None)
def casework(width, deep):
    height = 49 if deep else 33
    image = Image.new("RGBA",(width,height))
    p = ImageDraw.Draw(image)
    cornice = 14 if deep else 3
    # Dark end-grain and grounded feet give the case thickness even at the
    # ends of an aisle. Two uninterrupted boards join multiple cabinet bays.
    p.rectangle((2,2,width-2,height-2), fill=DARK)
    p.rectangle((width-4,2,width-2,height-3), fill="#855f4b")
    p.line((width-2,3,width-2,height-3),fill=INK)
    p.rectangle((1,2,width-5,cornice+1),fill=HONEY,outline=DARK)
    p.line((2,2,width-6,2),fill=EDGE)
    if deep:
        p.rectangle((3,4,width-7,10),fill="#b98d65")
        for x in range(18,width-10,39):
            p.line((x,7,x+7,7),fill="#af825e")
            p.line((x+2,8,x+6,8),fill="#c2956d")
        p.line((3,12,width-6,12),fill="#936849")
        # Reading-room island cases have an occasional display book rather
        # than an empty uniform slab across their entire two-cell depth.
        if width >= 48:
            folio=birch_folio().resize((10,9),Image.Resampling.NEAREST)
            image.alpha_composite(folio,(8,2))
        if width >= 80:
            open_book(p,width-29,5)

    bay_count=max(1,width//32)
    for bay in range(bay_count):
        left = 2 + (width-6)*bay//bay_count
        right = 2 + (width-6)*(bay+1)//bay_count-1
        p.rectangle((left+1,cornice+4,right-1,height-6),fill=RECESS)
        for row, (top,bottom) in enumerate(((cornice+5,height-18),(height-15,height-7))):
            strip = shelf_books()[(bay+row+(1 if deep else 0)) % 3]
            # Mix actual upright book groups with a pair of laid-down folios.
            span = right-left-4
            stacked = (bay+row+int(deep))%3 == 1
            upright = span-10 if stacked else span
            volumes = strip.resize((upright,bottom-top+1),Image.Resampling.NEAREST)
            image.paste(volumes,(left+3,top))
            if stacked:
                closed_book(p,right-10,bottom-2,9,TEAL)
                closed_book(p,right-9,bottom-5,8,"#a76657")
            p.line((left+1,bottom+1,right,bottom+1), fill="#d4ad79")
            p.line((left+2,bottom+2,right,bottom+2), fill="#876547")
        p.line((left,cornice+2,left,height-4),fill=HONEY)
        p.line((left+1,cornice+3,left+1,height-5),fill="#ccaa78")
        p.line((right,cornice+3,right,height-5),fill=DARK)
    p.rectangle((0,cornice,width-2,cornice+3),fill=OAK)
    p.line((1,cornice,width-3,cornice),fill=EDGE)
    p.line((1,cornice+3,width-2,cornice+3),fill=DARK)
    p.rectangle((1,height-5,width-3,height-3),fill=OAK)
    p.line((2,height-5,width-4,height-5),fill="#cda379")
    p.line((2,height-2,width-3,height-2),fill=INK)
    return image


@lru_cache(None)
def reading_table():
    image=Image.new("RGBA",(32,33))
    p=ImageDraw.Draw(image)
    # Two chairs face each other across the table. The near seat is visible
    # below the apron. Both backs use the Trainer School chair's dark rails.
    p.rectangle((10,1,21,8),fill=INK)
    p.rectangle((11,2,20,5),fill="#a4784e")
    p.line((11,2,20,2),fill=EDGE)
    p.line((12,6,19,6),fill=TEAL)
    for x in (4,26):
        p.rectangle((x,19,x+2,29),fill=DARK)
        p.line((x,21,x,28),fill=HONEY)
    p.rectangle((1,8,30,22),fill=INK)
    p.rectangle((2,9,29,20),fill=HONEY)
    p.line((2,9,28,9),fill=EDGE)
    p.line((3,19,28,19),fill="#bd8a65")
    p.line((2,20,29,20),fill=OAK)
    p.line((3,21,28,21),fill=DARK)
    closed_book(p,4,11,6,TEAL)
    open_book(p,14,12)
    p.polygon([(11,23),(20,23),(21,28),(10,28)],fill="#689185",outline=DARK)
    p.rectangle((9,27,22,30),fill=DARK)
    p.line((10,27,21,27),fill=EDGE)
    p.line((10,29,21,29),fill=OAK)
    for x in (10,20):
        p.line((x,30,x,32),fill=DARK)
    return image


def reception(picture):
    """Paint static fittings into the blocked western stack and eastern counter."""
    overlay=Image.new("RGBA",picture.size)
    p=ImageDraw.Draw(overlay)
    # Continuous bevelled solid-oak countertop. The two arms leave the
    # receptionist's floor cells and the gap on the south side unobstructed.
    outline=[(209,129),(286,129),(287,130),(287,190),(256,190),(256,178),
             (272,178),(272,144),(224,144),(224,190),(209,190)]
    p.polygon(outline,fill=DARK,outline=INK)
    top=[(211,130),(285,130),(285,185),(258,185),(258,179),(274,179),
         (274,140),(221,140),(221,185),(211,185)]
    p.polygon(top,fill="#c3976b",outline="#a87b55")
    p.line([(211,131),(284,131),(284,184)],fill=EDGE)
    p.line([(211,184),(211,132),(219,132)],fill="#dcbd8c")
    p.line([(221,142),(272,142)],fill="#e0b982")
    p.line((213,151,213,177),fill="#b18860")
    p.line((278,147,278,165),fill="#b18860")
    for x in (212,259,274):
        right=221 if x==212 else 271 if x==259 else 284
        p.rectangle((x,186,right,189),fill=OAK)
        p.line((x,186,right,186),fill=HONEY)
    for left in (225,248):
        p.rectangle((left,140,left+20,143),fill="#976b4d")
        p.line((left+1,140,left+19,140),fill="#d4aa76")
        p.line((left+9,141,left+12,141),fill="#806346")
    for left, top in ((214,153),(276,150)):
        p.rectangle((left,top,left+6,top+18),fill="#ad805a",outline="#ad845d")
        p.line((left+1,top+1,left+5,top+1),fill="#d1a376")
        p.line((left+1,top+2,left+1,top+17),fill="#b88e65")
    # The ledger, little pen pot and return tray each have their own outline.
    p.rectangle((230,132,247,139),fill="#65817c",outline="#627570")
    open_book(p,232,132)
    p.rectangle((250,135,252,139),fill="#4b6870")
    p.line((251,136,253,131),fill=DARK)
    p.point((253,131),fill="#d7bd83")
    p.rectangle((266,132,275,138),fill=DARK)
    p.rectangle((267,133,274,136),fill=PAGES)
    p.line((269,134,272,134),fill="#aaab98")
    p.rectangle((275,173,281,176),fill="#668187",outline=INK)
    p.line((276,173,280,173),fill="#a4b6ae")

    # One stepped reference / return cabinet follows the original blocked
    # cells (9,8-11), (8,10-11), (7,11); no new collision on adjacent aisles.
    cabinet=[(145,129),(158,129),(159,130),(159,190),(113,190),(112,189),
             (112,177),(128,177),(128,161),(145,161)]
    p.polygon(cabinet, fill=OAK, outline=INK)
    p.polygon([(146,130),(157,130),(157,181),(114,181),(114,178),(130,178),
               (130,162),(146,162)],fill="#ba8d64")
    p.line([(113,178),(129,178),(129,162),(146,162),(146,130),(157,130)],fill=EDGE)
    p.rectangle((146,132,156,146),fill=DARK)
    p.rectangle((147,133,155,144),fill="#d7c99f")
    p.line((149,136,153,136),fill="#a88d69")
    p.line((149,139,152,139),fill="#a88d69")
    p.rectangle((145,148,157,160), fill=RECESS, outline=DARK)
    row=shelf_books()[0].crop((0,0,10,4)).resize((10,6),Image.Resampling.NEAREST)
    overlay.paste(row,(147,151))
    p.line((146,157,156,157), fill=EDGE)
    p.line((146,159,156,159), fill=DARK)
    overlay.alpha_composite(birch_folio(),(131,164))
    p.rectangle((145,169,156,171),fill=INK)
    p.line((145,168,155,168),fill="#d2b184")
    p.rectangle((115,182,156,188),fill="#88674d",outline=DARK)
    p.line((115,182,156,182),fill=HONEY)
    p.line((137,183,137,188),fill=OAK)
    p.rectangle((121,184,129,186),fill="#cfbd92")
    p.rectangle((144,184,152,186),fill="#cfbd92")
    p.line((124,185,127,185),fill="#87785e")
    p.line((147,185,150,185),fill="#87785e")
    p.line((114,189,156,189),fill=DARK)
    # A projected bevel must not turn into an apparent barrier at an aisle.
    # The western display and the staff entrance both have a stepped footprint.
    cells={(x,8) for x in range(13,18)} | {(13,y) for y in range(9,12)} | {
        (17,y) for y in range(9,12)} | {(16,11),(9,8),(9,9),(8,10),(9,10),(7,11),(8,11),(9,11)}
    for x,y in cells:
        box=(16*x,16*y,16*x+16,16*y+16)
        picture.alpha_composite(overlay.crop(box),(16*x,16*y))
    return picture
