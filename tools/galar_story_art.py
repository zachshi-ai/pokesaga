"""Pixel furnishings and terrain for the eight post-Turffield story landmarks."""
from math import sin, cos, tau
from random import Random
from PIL import ImageDraw

NAVY="#334755"
GOLD="#dbbc74"

def ring(d,x,y,r,ink,width=1,segments=12):
    pts=[(round(x+cos(i*tau/segments)*r),round(y+sin(i*tau/segments)*r)) for i in range(segments)]
    d.line(pts+pts[:1],fill=ink,width=width)

def dining(s,maritime):
    d=s.draw
    # A marine compass woven into the runner, or the inn's old shield insignia.
    cx=11*16+8
    for y in range(64,196,12):
        for x in (132,234):
            d.line([(x,y),(x+2,y+2),(x,y+4)],fill="#adc0ab" if maritime else GOLD)
    if maritime:
        for radius in (22,16):ring(d,cx,139,radius,"#82a5a3")
        for direction in range(8):
            a=direction*tau/8
            length=23 if direction%2==0 else 14
            d.polygon([(cx+round(cos(a)*length),139+round(sin(a)*length)),
                       (cx+round(cos(a+1.57)*3),139+round(sin(a+1.57)*3)),(cx,139)],fill="#c7c7a1")
        for x in (111,207):
            for j in range(3):
                y=25+j*3
                d.line((x+4+j*4,y,x+13+j*4,y),fill="#b5d5c5")
            d.polygon([(x+28,33),(x+40,33),(x+36,37),(x+32,37)],fill=NAVY)
            d.polygon([(x+35,19),(x+35,32),(x+28,32)],fill="#e6ddbd")
    else:
        d.polygon([(cx-17,120),(cx+17,120),(cx+14,140),(cx,154),(cx-14,140)],outline="#d6ae75",width=2)
        for a,b in [(-1,1),(1,-1)]:
            d.line((cx+a*11,126,cx+b*9,144), fill="#dcc898",width=2)
        for x in (113,209):
            d.polygon([(x+2,14),(x+42,14),(x+42,38),(x+23,43),(x+2,38)],fill="#82544a",outline="#513943")
            for k in range(3):
                px=x+7+k*10
                d.polygon([(px,33),(px+4,23-k*2),(px+7,32),(px+4,30)],fill=("#e9cb88","#c8c8b0","#e8a36c")[k])
    for y in (5,10):
        for x in (4,18):
            xx=x*16+8;yy=y*16+5
            d.rounded_rectangle((xx-15,yy-8,xx+15,yy+3),radius=3,fill="#b38763",outline="#725946")
            d.rectangle((xx-4,yy-7,xx+4,yy+2),fill="#d1bea1" if maritime else "#b75d55")
            for px in (xx-9,xx+10):
                d.ellipse((px-3,yy-4,px+3,yy),fill="#eae3c4",outline="#9e9c87")
                d.point((px+4,yy-3),fill="#e4d6aa")
            d.point((xx,yy-4),fill="#527f67")
    for x in (12,352):
        d.rectangle((x-3,10,x+3,23),fill="#674c42")
        d.rectangle((x-4,13,x+4,20),fill="#e8c37b",outline="#9d7955")
        d.line((x,14,x,18),fill="#f6e8ab")

def tower(s):
    d=s.draw;w=s.im.width
    if s.mid.endswith("lift") or s.mid.endswith("suite"):
        for x in range(18,w-18,28):
            # City skyline reflections are confined to the glazed upper wall.
            for j in range(3):
                h=(x*3+j*13)%17+7;px=x+j*7
                d.rectangle((px,38-h,px+5,38),fill=("#405965","#526c7c","#5a7584")[j])
                for wy in range(37-h+3,37,4):d.point((px+2,wy),fill="#b8c5ac")
        cx=9*16+8 if s.mid.endswith("lift") else 12*16+8
        cy=8*16+5
        for r in (17,20):ring(d,cx,cy,r,"#ad8b77",1,8)
        d.line([(cx-13,cy+5),(cx-6,cy-8),(cx,cy+1),(cx+7,cy-8),(cx+13,cy+5)],fill="#dbbb95",width=2)
        for x in (5,w-13):
            d.rectangle((x,16,x+7,39),fill="#364850",outline="#b9aea0")
            for y in range(18,37,4):d.line((x+2,y,x+5,y),fill="#a9c4bb")
    elif s.mid.endswith("energy_plant"):
        for x in (3*16,30*16):
            for y in range(57,s.im.height-36,16):
                d.rectangle((x,y,x+9,y+15),fill="#596973",outline="#394956")
                d.line((x+2,y+2,x+2,y+14),fill="#a7a795")
            for y in (83,208):
                d.line((x+5,y,87 if x<100 else 435,y),fill="#424855",width=5)
                d.line((x+5,y-1,87 if x<100 else 435,y-1),fill="#b38886",width=2)
        for x in (202,319):
            for y in range(82,326,12):
                d.polygon([(x,y+3),(x+5,y),(x+5,y+4),(x,y+7)],fill="#bd9e64")
        for y in range(106,310,32):
            d.line((219,y,309,y),fill="#819393")
            d.line((222,y+2,306,y+2),fill="#53636c")
        for x in (28,494):
            d.rectangle((x-9,18,x+9,33),fill="#43545d",outline="#263844")
            for dy in range(20,33,4):d.line((x-6,dy,x+6,dy),fill="#7a8a86")
    else:
        cx,cy=14*16+8,10*16+6
        # Weathered red and blue inlays, cut flush with the rooftop fighting platform.
        for radius,color in [(56,"#a39a94"),(52,"#927e83"),(34,"#a5a4a0")]:ring(d,cx,cy,radius,color,2,16)
        for i in range(8):
            a=i*tau/8
            d.line((cx+round(cos(a)*39),cy+round(sin(a)*39),cx+round(cos(a)*47),cy+round(sin(a)*47)),fill="#bdab94",width=2)
        for sign,color in [(-1,"#a28683"),(1,"#8299a4")]:
            points=[(cx+sign*x,cy+y) for x,y in [(5,10),(8,-7),(17,-17),(17,-6),(22,-10),(21,-3),(30,2),(20,6),(16,16)]]
            d.polygon(points,fill=color,outline="#5b616e")
        for x in range(18,s.im.width-18,30):
            d.rectangle((x,13,x+12,25),fill="#727b88",outline="#4f5868")
            d.line((x+2,14,x+9,14),fill="#c2bfb4")

def landscape(s):
    from kalos_gym_rooms import sprite
    d=s.draw;rng=Random(822)
    altar=s.mid.endswith("altar")
    if altar:
        # A worn stone causeway, broken pavers and moss. No change to the walk mask.
        for y in range(4*16,15*16,9):
            shift=rng.randrange(10)
            for x in range(5*16+shift,19*16+60,18):
                if rng.random()<0.72:
                    d.line((x,y,x+7,y),fill="#9b9d8b")
                    d.line((x+8,y,x+10,y+2),fill="#b2ae97")
                if rng.random()<0.22:
                    d.line((x+4,y+4,x+8,y+4),fill="#899779")
        for x in (13*16+3,15*16+12):
            d.line((x,113,x,134),fill="#616c68",width=3)
            d.line((x-3,117,x+4,117),fill="#c4af7d",width=2)
        for y in (3,7,11,15,18):
            for x in (2,26):
                xx=x*16;yy=y*16
                for ox,oy in ((-12,-11),(13,-17)):
                    im=sprite("tree");s.im.paste(im,(xx+ox-im.width//2, yy+oy-im.height//2),im)
        for _ in range(110):
            x=rng.choice([rng.randrange(20,78),rng.randrange(385,443)]);y=rng.randrange(52,282)
            d.line((x,y,x+2,y-2),fill="#7d9d67")
            if _%7==0:d.point((x+3,y-3),fill="#d2bf85")
    else:
        for y,row in enumerate(s.mask):
            for x,code in enumerate(row):
                if code!=2:continue
                xx=x*16;yy=y*16
                if s.mask[y-1,x]!=2:
                    d.line((xx,yy,xx+15,yy),fill="#cbdac2",width=2)
                    d.line((xx+1,yy+3,xx+9,yy+3),fill="#a3c3ca")
                if s.mask[y+1,x]!=2:d.line((xx,yy+15,xx+15,yy+15),fill="#9bbdc0")
                if (x+3*y)%7==0:
                    d.line([(xx+2,yy+7),(xx+5,yy+7),(xx+7,yy+5),(xx+12,yy+5)], fill="#c3dce0")
        for x,y in ((2,4),(5,3),(19,3),(26,5),(25,18),(22,19),(4,18),(9,17)):
            px=x*16+7;py=y*16+3
            d.line([(px-7,py-5),(px-2,py-7),(px+5,py-6)], fill="#d2dbcf",width=2)
        for cx,cy in ((12,7),(12,14)):
            x=cx*16;y=cy*16
            for j in range(4):
                d.rectangle((x-6,y+j*4,x+22,y+j*4+3),fill="#a68b6c",outline="#806f60")
            for px in (x-6,x+20):d.rectangle((px,y+1,px+2,y+12),fill="#796554")

def finish(site):
    key=site.mid
    if key in ("galar_seafood","galar_circhester_grill"):dining(site,key=="galar_seafood")
    elif key in ("galar_weald_altar","galar_circhester_bay"):landscape(site)
    else:tower(site)
