"""Room shells, continuous Emerald flooring and activity-specific furniture for Alola."""

from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

from platinum_library_furniture import donor

HOME = "littleroot_west_home_1f"
DEVON = "em_rustboro_city_devon_corp_2f"
LAB = "littleroot_birch_lab"
CLUB = "em_slateport_city_pokemon_fan_club"
MART = "em_rustboro_city_mart"

# These rooms use authored flat footprints because the Sun/Moon atlas lacks a
# room mesh. Keep the shell, discard the one-tile solids left by the *previous*
# furniture, then let the fitted, visible props own their bases.
FAMILIES = {
    "living": "home", "nursery": "home", "beachlodge": "home",
    "roadside": "home", "desertlodge": "home", "dining": "club",
    "civic": "office", "study": "home", "atelier": "home",
    "laboratory": "lab", "cleanroom": "lab", "studio": "studio",
    "resort": "club", "market": "shop",
}
FLOORS = {
    "home": (HOME, 7, 4), "club": (CLUB, 2, 3), "office": (DEVON, 4, 2),
    "lab": (LAB, 5, 5), "studio": (DEVON, 4, 2), "shop": (MART, 3, 3),
}
# The full furnishings are placed by Field.place, which checks both their bases
# and every arrival, path to a door, NPC, item and edition-specific interaction.
LAYOUTS = {
    "malie_library": [("library_wall", .23, .22), ("library_wall", .74, .22),
                      ("library_case", .25, .46), ("library_case", .72, .46),
                      ("reading_table", .26, .71), ("reading_table", .75, .71)],
    "malie_library_2f": [("library_wall", .42, .22), ("library_wall", .75, .22),
                         ("library_case", .33, .51), ("library_case", .75, .51),
                         ("reading_table", .48, .75)],
    "motel_2": [("ceilingbed", .18, .35), ("ceilingbed", .18, .69),
                ("desk", .75, .35), ("plant_indoor", .79, .66), ("tv", .53, .27)],
    "motel_8": [("ceilingbed", .76, .32), ("ceilingbed", .76, .64),
                ("tv", .22, .24), ("desk", .22, .54), ("plant_indoor", .4, .26)],
    "motel_13": [("ceilingbed", .22, .35), ("tv", .6, .25), ("desk", .71, .53),
                 ("plant_indoor", .18, .67), ("bookshelf_home", .4, .27)],
    "tide_song": [("officecounter", .65, .36), ("plant_indoor", .83, .24),
                 ("plant_indoor", .18, .22), ("desk", .22, .52), ("desk", .22, .74)],
    "home_1f": [("bookshelf_home", .18, .24), ("tv", .44, .24),
                ("desk", .66, .55), ("plant_indoor", .80, .26)],
    "aether_house": [("ceilingbed", .17, .42), ("ceilingbed", .33, .42),
                     ("bookshelf_home", .75, .27), ("desk", .72, .61)],
    "ilima_room": [("bookshelf_home", .22, .24), ("desk", .24, .54),
                   ("ceilingbed", .74, .46), ("tv", .55, .27)],
    "mina_house": [("easel", .28, .51), ("desk", .22, .26),
                   ("ceilingbed", .76, .63), ("plant_indoor", .74, .24)],
    "paniola_salon": [("desk", .18, .47), ("desk", .72, .49),
                     ("officecounter", .62, .28), ("barrel", .23, .27)],
    "seafolk_restaurant": [("officecounter", .26, .28), ("desk", .68, .38),
                           ("desk", .68, .67), ("plant_indoor", .23, .67)],
}

def family(f):
    if not f.native or f.m.get("alola_zone") != -1:
        return None
    return FAMILIES.get(f.style)

def clear_old_furniture(f):
    if family(f):
        # None of these rectangular adapted rooms has inner masonry. The
        # source collision includes bookcases, beds and single-point desks.
        h,w=f.s.shape
        assert np.all(f.s[:3]) and np.all(f.s[-1]) and np.all(f.s[:,[0,-1]])
        f.s=np.ones((h,w),bool)
        f.s[3:h-1,1:w-1]=False

@lru_cache(None)
def sample(name, x, y, high=1):
    return donor(name, (x*16,y*16,(x+1)*16,(y+high)*16)).convert("RGB")

def surface(f, im):
    key = family(f)
    if not key:
        return im
    w, h = f.w, f.h
    base = sample(*FLOORS[key])
    if key=="home":
        # Birch and walnut boards retain the grain marks of the native metatile.
        colors={"malie_library":((109,83,64),(197,159,111)),
                "malie_library_2f":((108,79,63),(192,154,113)),
                "motel_13":((120,91,73),(202,171,125)),
                "motel_8":((106,85,69),(191,167,132))}
        low,high=colors.get(f.mid,((120,95,71),(205,175,130)))
        lum=np.asarray(base).mean(2)
        mix=((lum-lum.min())/max(1,np.ptp(lum)))[:,:,None]
        base=Image.fromarray((np.array(low)+(np.array(high)-low)*mix).astype("uint8"))
    wall=Image.new("RGB",(16,32))
    trim=ImageDraw.Draw(wall)
    palette={
        "home":("#efe1be","#d7c29f","#a18869","#806350"),
        "club":("#f2dfbc","#dfcaa7","#b88e72","#81665c"),
        "office":("#e0d8cf","#cfc5b4","#a9998c","#796f6f"),
        "studio":("#dcd6e4","#c6c1d2","#a595ad","#726d83"),
        "shop":("#e0e7d9","#c3d9ce","#9dbcb3","#69867e"),
        "lab":("#e1e7d9","#cad8d0","#9fafaf","#677e84"),
    }
    light,face,wood,ink=palette[key]
    for yy,col in [(0,ink),(1,light),(3,face),(20,wood),(22,light),(23,wood),(29,ink),(30,wood),(31,ink)]:
        trim.rectangle((0,yy,15,31),fill=col)
    trim.line((0,5,0,18),fill=light)
    trim.line((1,5,1,18),fill=face)
    # Shadows belong on the wall's foot, and the shell uses a single floor to
    # its edge. A pathfinder's changing path width is never a floor material.
    out = Image.new("RGB", im.size, "#253039")
    for y,x in np.argwhere(~f.terrain_solid):
        out.paste(base,(int(x)*16,int(y)*16))
    for x in range(1,w-1):
        rows=np.flatnonzero(~f.terrain_solid[:,x])
        if len(rows):
            y=int(rows[0])
            out.paste(wall,(x*16,(y-2)*16))
            ImageDraw.Draw(out).line((x*16,y*16,x*16+15,y*16),fill="#92877b")
    floor=~f.terrain_solid
    d=ImageDraw.Draw(out)
    for y,x in np.argwhere(floor):
        x,y=int(x),int(y)
        if x and not floor[y,x-1]:
            d.line((x*16,y*16,x*16,y*16+15),fill="#736865")
        if x+1<w and not floor[y,x+1]:
            d.line((x*16+15,y*16,x*16+15,y*16+15),fill="#736865")
    if f.mid.startswith("malie_library"):
        # A single woven runner leads from the lobby to the reading bays. The
        # second-floor aisle turns left toward the western stairs.
        left,top,right,bottom=((9,5,13,15) if f.mid=="malie_library" else (3,5,19,7))
        x,y,r,b=left*16+3,top*16+3,right*16-3,bottom*16-3
        d.rectangle((x,y,r,b),fill="#66868b",outline="#495e68",width=2)
        d.rectangle((x+3,y+3,r-3,b-3),outline="#c1b18a")
        for u in range(x+10,r-5,12):
            d.point((u,y+6),fill="#d6c59c");d.point((u,b-6),fill="#d6c59c")
    # Use the native threshold at the actual warp. A small inset frame keeps
    # decorative rugs distinct from walkable links, with no fake tiles to follow.
    for x,y in f.door:
        if (y>=h//2 and 0<x<w-1 and floor[y,x]):
            rug=donor(HOME,(8*16,8*16,10*16,9*16)).crop((2,2,30,15)).convert("RGB")
            out.paste(rug,(x*16-6,y*16+1))
    return out

def furnish(f):
    items=LAYOUTS.get(f.mid)
    if not items or not family(f):
        return False
    subjects = iter(["旧书里，四座岛屿各有一位守护神。人们在遗迹中祈愿，与守护神相见。",
                     "书页上画着太阳和月亮。传说中的宝可梦与阿罗拉的光有着久远的联系。"])
    for key, u, v in items:
        point = f.place(key,(round(u*(f.w-1)),round(v*(f.h-1))),max_shift=4)
        if point and key=="library_case" and f.mid=="malie_library_2f":
            f.m["objects"].append({"kind":"sign","at":list(point),"text":next(subjects),"baked":True})
    return True


def stairs(image,x,y):
    # The front lip sits on the actual step trigger, directly north of the return landing.
    stair=donor(HOME,(7*16+12,16+9,9*16+5,3*16)).convert("RGB")
    image.paste(stair,(x*16-4,(y+1)*16-stair.height))
