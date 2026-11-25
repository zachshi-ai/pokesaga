"""Fit Emerald's healing station and integrated Mart around XY/SM service actors."""

from functools import lru_cache
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from platinum_library_furniture import donor

ROOT=Path(__file__).resolve().parents[1]
CENTER="em_battle_frontier_pokemon_center_1f"
STORE="em_lilycove_city_department_store_1f"
MART="em_rustboro_city_mart"

def align(record, region):
    """Align feet, fixtures and the crossing used by World's counter interaction."""
    anchors=record[region+"_anchors"]
    anchors["mart"]=[19,8]
    collision=record["physics"]["collision"]
    counters=np.zeros_like(collision)
    for left,right in [(7,12),(17,21)]:
        for x in range(left,right+1):
            collision[9][x]=1
            counters[9,x]=1
    record["physics"]["counter"]=counters.tolist()
    return record

@lru_cache(None)
def piece(room, box):
    return donor(room,tuple(n*16 for n in box)).convert("RGB")

def scene(region):
    # Both chains use the same service coordinates. In Alola the café's warm
    # timber and apricot trim distinguish its waiting area from Kalos's blue lobby.
    image=Image.new("RGB",(416,416),"#212830")
    d=ImageDraw.Draw(image)
    def stamp(src,x,y): image.paste(src,(x*16,y*16))
    def fixture(room, box, at, polygon):
        pic=piece(room,box)
        mask=Image.new("L",pic.size);ImageDraw.Draw(mask).polygon(polygon,fill=255)
        image.paste(pic,(at[0]*16,at[1]*16),mask)
    def rectangles(rect, fill, outline):
        l,t,r,b=rect
        d.rectangle((l*16,t*16,r*16-1,b*16-1),fill=fill,outline=outline,width=2)
    for y in range(5,22):
        for x in range(2,24):
            stamp(piece(CENTER,(3,4,4,5)),x,y)
    # One rear wall, with its own panel joins; never repeat the cropped
    # screen or bookcase implicitly attached to one of Emerald's wall tiles.
    for y,col in [(48,"#8c817d"),(50,"#fff3d5"),(53,"#e7d8bc"),(65,"#e8d1ac"),
                  (70,"#d39a70"),(73,"#eee0bf"),(75,"#b3947c"),(78,"#92766a")]:
        d.rectangle((32,y,383,79),fill=col)
    for x in range(48,382,32):d.line((x,54,x,66),fill="#cfbea6")
    accent="#799ba8" if region=="kalos" else "#cd956e"
    shade="#557e90" if region=="kalos" else "#a47155"
    # A bordered single-material entrance runner and an uninterrupted lobby
    # leave routes to shopping, healing and the PC legible at player scale.
    rectangles((10,10,13,21),accent,shade)
    for x in (163,204): d.line((x,161,x,328),fill="#e5d5ad")
    for y in range(170,315,16):
        for x in (169,199):d.line((x,y,x+2,y+2),fill=shade)
    for x in (3,22):
        fixture(CENTER,(1,1,2,3),(x,4),[(3,0),(10,0),(15,6),(13,13),(10,18),(12,22),(9,26),(4,26),(2,22),(4,16),(0,13),(0,7)])
    # The original nurse stands at (7,2), in front of the healing equipment.
    # An upper machine and detached front counter enclose the actor's own tile.
    fixture(CENTER,(4,1,10,4),(7,7),[(0,9),(15,9),(16,1),(45,1),(47,7),(48,7),
            (48,0),(65,0),(65,15),(78,15),(78,9),(92,9),(92,24),(95,32),(94,42),
            (89,47),(7,47),(1,43),(0,35)])
    # Point of sale from Lilycove; its cashier stands at (19,8) with the front
    # counter on row nine. Mask the donor's surrounding department-store floor.
    fixture(STORE,(6,1,12,4),(17,7),[(0,8),(14,8),(14,32),(79,32),(79,8),
            (95,8),(95,47),(0,47)])
    # PC, supplies and the seating/refrigerator share their solid footprints.
    fixture(CENTER,(10,0,11,3),(15,6),[(1,8),(13,8),(15,16),(15,37),(12,41),(3,41),(0,37),(0,16)])
    for x in (17,19,21):
        fixture(MART,(6,1,8,2),(x,4),[(1,1),(30,1),(30,15),(1,15)])
    fixture(CENTER,(1,3,3,4),(3,13),[(2,1),(28,1),(31,4),(31,11),(28,14),(3,14),(1,11)])
    fixture(CENTER,(10,6,13,8),(18,15),[(1,1),(13,1),(14,12),(16,12),(16,1),(43,1),(46,5),(46,24),(41,29),(20,29),(16,26),(13,29),(2,29),(0,25)])
    # Integrate the machine on the west side and the dispensers to its east;
    # their existing solid footprints now have visible pixels on the ground.
    for x in (5,13):
        fixture(CENTER,(2,1,4,3),(x,7),[(0,0),(30,0),(30,18),(0,18)])
    # Low shadow under the two display units keeps the plinth off the back wall.
    for x in (5,13):d.line((x*16,8*16+3,(x+2)*16-2,8*16+3),fill="#bda784")
    stamp(piece(CENTER,(6,8,8,9)),11,20)
    return image

def write_maps():
    for region,out in [("kalos","gba_center"),("alola","center")]:
        scene(region).quantize(192,dither=Image.Dither.NONE).save(ROOT/"assets"/region/"maps"/(out+".png"),optimize=True)
        for path in (ROOT/"content/regions"/region/"maps").glob("*.json"):
            record=json.loads(path.read_bytes())
            if record.get(region+"_center"):
                align(record,region)
                path.write_text(json.dumps(record,ensure_ascii=False,separators=(",",":"))+"\n")

if __name__=="__main__":
    write_maps()
