"""Fit an Aether Foundation elevator to the four existing lobby passage anchors."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
P = 16
STOPS = {
    "alola_aether_docks": "down",
    "alola_aether_mansion": "up",
    "alola_aether_conservation": "left",
    "alola_aether_lab": "right",
}
SILVER="#d1dcd4"
STEEL="#6f8d96"


def floor(m):
    w,h=m["size"];size=(w*P,h*P)
    im=Image.new("RGB",size,"#cbd8d1")
    d=ImageDraw.Draw(im)
    for y in range(0,h*P,16):
        for x in range(-32,w*P,32):
            l=x+(16 if y%32 else 0)
            d.rectangle((l,y,l+31,y+15),outline="#aebeb6")
            d.line((l+1,y+1,l+29,y+1),fill="#dce4d9")
    # The rear aquarium is a window in the artificial island's glass gallery.
    for x in range(0,w*P,32):
        d.rectangle((x,0,x+32,44),fill=STEEL,outline="#495b72")
        d.rectangle((x+2,3,x+29,40),fill="#6195aa")
        d.rectangle((x+3,5,x+28,23),fill="#71b5bc")
        d.line((x+3,25,x+21,5),fill="#9cd5cc",width=2)
        d.line((x+6,31,x+27,9),fill="#7fc3c8",width=2)
        for j in (0,1):
            yy=19+(j*7+x//32*3)%14;xx=x+8+j*9
            d.ellipse((xx,yy,xx+4,yy+2),fill="#d8d59d")
            d.line((xx-2,yy,xx,yy+1,xx-2,yy+2),fill="#d8d59d")
        d.rectangle((x,39,x+31,45),fill=SILVER,outline=STEEL)
        d.line((x+1,40,x+29,40),fill="#f4f4db")
    for y in range(46,h*P,16):
        for x in (0,(w-1)*P):
            d.rectangle((x,y,x+P-1,y+15),fill="#93a4ad",outline="#637987")
            d.line((x+1,y+1,x+13,y+1),fill=SILVER)
    d.rectangle((0,(h-1)*P,w*P,(h-1)*P+6),fill="#a3b2b0",outline=STEEL)
    d.line((1,(h-1)*P+1,w*P-2,(h-1)*P+1),fill="#ecf1df",width=2)
    # A flush guide stripe leads to the lift without inventing obstacles on the old floor.
    cx=11*P+P//2
    for x in (cx-23,cx+23):
        d.line((x,90,x,207),fill="#a6bebe",width=2)
        d.line((x+2,90,x+2,207),fill="#d9dfbd")
    d.polygon([(cx,79),(cx+12,91),(cx,103),(cx-12,91)],outline="#bea878",width=2)
    d.polygon([(cx,84),(cx+7,91),(cx,98),(cx-7,91)],fill="#8da8a7")
    left=9*P+2;top=13*P+5;right=14*P-2;bottom=17*P-2
    points=[(left+8,top),(right-8,top),(right,top+8),(right,bottom-7),(right-7,bottom),(left+7,bottom),(left,bottom-7),(left,top+8)]
    d.polygon(points,fill="#586c80",outline="#455c6a")
    d.line(points+[points[0]],fill="#8b9faa",width=2)
    d.rounded_rectangle((left+3,top+3,right-3,bottom-3),5,fill="#b4c7bd",outline="#e9e9d5",width=2)
    for y in range(top+10,bottom-9,7):d.line((left+7,y,right-7,y),fill="#a2b6b0")
    for dx in (-1,1):
        xx=cx+dx*26
        d.line((xx,top+7,xx,top+15),fill="#698d96",width=3)
        d.line((xx,top+7,xx,top+10),fill="#b2ecdc",width=2)
    arrows={"up":[(-4,2),(0,-3),(4,2)],"down":[(-4,-2),(0,3),(4,-2)],
            "left":[(2,-4),(-3,0),(2,4)],"right":[(-2,-4),(3,0),(-2,4)]}
    for warp in m["warps"]:
        direction=STOPS[warp["to"]["map"]];warp["trigger"]=direction
        x,y=warp["at"];xx=x*P+8;yy=y*P+8
        d.rounded_rectangle((xx-6,yy-6,xx+6,yy+6),2,fill="#526b79",outline="#f2dfad")
        d.line([(xx+dx,yy+dy) for dx,dy in arrows[direction]],fill="#efda96",width=2)
    # Avoid generating duplicate staff if the renderer runs on its own output.
    m["npcs"]=[npc for npc in m["npcs"] if not npc.get("alola_lift")]
    m["npcs"].append({"name":"电梯接待员","at":[13,13],"gfx":"scientist","facing":"down","alola_lift":True})
    im.quantize(96).save(ROOT/"assets/alola/maps/aether_entrance.png",optimize=True)
