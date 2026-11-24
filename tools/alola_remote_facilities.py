"""Aether dock crane and hangar, and the cable growths in Xurkitree's habitat."""
from functools import lru_cache
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
INK="#344052"
GRAY="#76909a"
WHITE="#e0e6cf"
LIGHT="#c0d3bd"


@lru_cache(None)
def fixture(key):
    if key in ("freight_shed","dock_crane"):
        art=Image.new("RGBA",(64,64));d=ImageDraw.Draw(art)
        d.polygon([(1,56),(8,48),(59,48),(63,55),(58,62),(5,62)],fill="#819399",outline=INK)
        if key=="freight_shed":
            d.polygon([(2,37),(10,19),(45,19),(59,29),(59,55),(52,59),(3,59)],fill="#cdd4cb",outline=INK)
            d.polygon([(1,36),(10,17),(46,17),(53,34)],fill="#88a0a4",outline=INK)
            for x in range(6,49,5): d.line((x,32,x+6,20),fill="#bacec2")
            d.polygon([(46,18),(60,27),(60,55),(52,59),(52,35)],fill="#7c8d91",outline=INK)
            d.rectangle((7,39,34,57),fill="#72858e",outline=INK)
            for y in range(41,57,3):d.line((9,y,32,y),fill="#9faeaa")
            d.rectangle((38,39,48,46),fill="#648292",outline=INK)
            for x in (39,44):d.line((x,40,x,45),fill="#b7d5cd")
            d.line((3,36,52,35),fill=WHITE,width=2)
            for x in range(8,34,6): d.line((x,57,x+2,59),fill="#f3c570",width=2)
        else:
            d.polygon([(14,53),(22,47),(42,47),(49,53),(44,58),(15,58)],fill=GRAY,outline=INK)
            d.rectangle((23,26,33,54),fill="#557782",outline=INK)
            for y in range(29,51,6):d.line((24,y,31,y+4,24,y+5),fill="#dfc389")
            d.polygon([(12,28),(18,19),(31,19),(35,25),(33,32),(13,33)],fill="#d2ae64",outline=INK)
            d.rectangle((17,22,24,27),fill="#739ba6",outline=INK)
            d.line((28,22,47,7,57,10),fill=INK,width=5)
            d.line((28,21,47,7,57,10),fill="#d6b37b",width=2)
            d.line((30,25,47,12,56,12),fill="#9b8667",width=2)
            d.line((55,11,55,32),fill=INK)
            d.arc((51,29,57,35),0,220,fill="#c4a270",width=2)
    else:
        w,h={"cable_spire":(35,62),"charged_bough":(35,52),"storm_stone":(49,46),"cable_root":(49,46)}[key]
        art=Image.new("RGBA",(w,h));d=ImageDraw.Draw(art)
        cx=w//2;cy=h-3
        d.ellipse((cx-13,cy-3,cx+13,cy+2),fill="#414d62")
        if key=="storm_stone":
            for x,yy,height,width in [(12,cy-3,16,7),(29,cy-5,21,8),(21,cy,33,9)]:
                d.polygon([(x-width,yy-3),(x-width+1,yy-height+7),(x+3,yy-height),(x+width,yy-height+10),(x+width-1,yy-3),(x,yy)],fill="#53637d",outline=INK)
                d.polygon([(x+2,yy-height+3),(x+3,yy-height+14),(x-3,yy-height+21),(x-1,yy-4),(x-7,yy-6),(x-6,yy-height+11)],fill="#788b91")
                d.line((x+3,yy-height+7,x-2,yy-height+14,x+1,yy-height+17,x-3,yy-height+22),fill="#dfcc83")
        else:
            reach=cy-8 if key!="cable_root" else cy-16
            branches=[[(cx-5,cy),(cx-2,cy-9),(cx-7,cy-16),(cx,cy-reach//2),(cx+3,cy-reach)],
                      [(cx,cy-reach//2),(cx-8,cy-reach//2-3),(3,cy-reach//2-12),(5,cy-reach//2-20)],
                      [(cx,cy-reach//2+3),(cx+6,cy-reach//2-4),(w-5,cy-reach//2-6),(w-2,cy-reach//2-15)]]
            for pts in branches:
                d.line(pts,fill="#253041",width=5,joint="curve")
                d.line([(x-1,y) for x,y in pts],fill="#59727d",width=2)
                for xx,yy in pts[1:-1]:
                    d.line((xx-2,yy+1,xx+2,yy-1),fill=LIGHT,width=2)
                x,y=pts[-1]
                d.polygon([(x,y-4),(x+1,y-1),(x+4,y),(x+1,y+1),(x,y+4),(x-1,y+1),(x-3,y),(x-1,y-1)],fill="#f6dfa4")
                d.point((x,y),fill="#f4f1d1")
    path=ROOT/"assets/alola/facilities"/(key+".png")
    path.parent.mkdir(exist_ok=True)
    art.save(path,optimize=True)
    return "res://"+path.relative_to(ROOT).as_posix()


def place(m, mid):
    for row in m["hoenn_art"]["p"]:
        key=Path(row[0]).stem
        if mid=="alola_aether_docks":
            dest={"home_blue":"freight_shed","home_city":"dock_crane"}.get(key)
        elif mid in ("alola_ultra_plant","ultra_plant"):
            dest={"reactor":"charged_bough","coil":"cable_spire","crystals":"storm_stone","amethyst":"cable_root"}.get(key)
        else:
            return
        if dest:row[0]=fixture(dest)
