"""Emerald-scale facades for Kalos and Alola. The doorway shares the original sprite's foot anchor."""
from functools import lru_cache
from pathlib import Path
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
FIELD = ROOT / "assets/emerald/field"
ANCHORS = json.loads((ROOT / "content/emerald_fields.json").read_text())["anchors"]
BUILDINGS = {"home", "home_red", "home_blue", "home_green", "home_city", "center", "mart", "gym", "academy"}
PAINT = {
    "home": ("#415577","#738cac","#a5b8c6"),
    "home_blue": ("#3b596e","#6388a0","#9db3b7"),
    "home_green": ("#44635e","#709381","#b0b69a"),
    "home_red": ("#784d50","#ad7166","#d6a084"),
    "home_city": ("#554e6b","#827591","#b2a2b2"),
    "mart": ("#346a86","#508caa","#9ac6c9"),
    "center": ("#943f48","#c55c60","#ea9280"),
    "gym": ("#43556b","#6d8993","#aab8ab"),
    "academy": ("#545e68","#839497","#c2c6b4"),
}
OUTLINE = "#35424c"
STONE = "#dcc9a6"
LIT = "#f4e7c7"
MORTAR = "#948b7f"


def window(draw, x, y, width, height, shutters=False):
    draw.rectangle((x-1,y-1,x+width,y+height+1), fill="#746f66")
    draw.rectangle((x,y,x+width-1,y+height-1),fill="#37556a")
    draw.rectangle((x+1,y+1,x+width-2,y+height//2),fill="#8cb3bc")
    draw.line((x+width//2,y,x+width//2,y+height),fill="#ded7ba")
    draw.line((x,y+height//2,x+width-1,y+height//2),fill="#abbac1")
    draw.line((x-2,y+height+1,x+width+1,y+height+1),fill=LIT)
    if shutters:
        for xx in (x-3,x+width+1):
            draw.rectangle((xx,y,xx+1,y+height-1),fill="#648179")


def emblem(draw, center, y, kind):
    if kind=="center":
        x=center
        draw.ellipse((x-6,y-6,x+6,y+6),fill="#f4e2bc",outline=OUTLINE)
        draw.pieslice((x-5,y-5,x+5,y+5),180,360,fill="#cf625b")
        draw.line((x-5,y,x+5,y),fill=OUTLINE)
        draw.ellipse((x-2,y-2,x+2,y+2),fill=LIT,outline=OUTLINE)
    elif kind=="mart":
        draw.rectangle((center-5,y-2,center+5,y+5),fill="#3b7385",outline=OUTLINE)
        draw.arc((center-3,y-7,center+3,y+1),180,360,fill=LIT,width=2)
        draw.line((center-3,y,center-3,y+3),fill="#b1d6d1")
    elif kind=="gym":
        draw.polygon([(center,y-6),(center+6,y-3),(center+5,y+2),(center,y+6),(center-5,y+2),(center-6,y-3)],fill="#be914e",outline=OUTLINE)
        draw.line((center-3,y,center,y+2,center+3,y-2),fill=LIT,width=2)


@lru_cache(None)
def facade(region, name, centered=False):
    if name.removesuffix("_compact") not in BUILDINGS:
        raise KeyError(name)
    kind=name.removesuffix("_compact")
    native=Image.open(FIELD/(kind+".png")).size
    target=Image.open(FIELD/(name+".png")).size
    w,h=native
    x=w//2 if centered else ANCHORS[kind][0]
    ink,roof,glint=PAINT[kind]
    pic=Image.new("RGBA",native)
    d=ImageDraw.Draw(pic)
    side=max(5,w//11); back=4; right=w-side-3; foot=h-4
    kalos=region=="kalos"
    eave=round(h*(.53 if kalos else .50))
    top=max(1,round(h*.05))
    overlap=3 if not kalos else 2
    d.rounded_rectangle((4,foot-5,w-2,h-1),radius=3,fill="#79896b")
    d.polygon([(back,eave-2),(right,eave-2),(right,foot),(back,foot)],fill=STONE if kalos else "#ebd9a6",outline=OUTLINE)
    d.polygon([(right,eave),(w-3,eave-5),(w-3,foot-4),(right,foot)],fill="#938574" if kalos else "#a38e68",outline=OUTLINE)
    for yy in range(eave+6,foot-2,7 if kalos else 4):
        d.line((back+1,yy,right-1,yy),fill="#c7b593" if kalos else "#cfbc8e")
        if kalos:
            for xx in range(7+((yy//7)%2)*5,right-2,10):d.line((xx,yy+1,xx,yy+2),fill="#c7b593")
    d.polygon([(back-2,eave+1),(right,eave+1),(w-2,eave-5),(w-2,eave-2),(right,eave+5),(back-2,eave+5)],fill="#615c56",outline=OUTLINE)
    peak=max(8,w//6) if kind not in ("mart","center","home_green") else w//4
    if kind in ("home_red","home_city"):
        top+=3
        d.rectangle((right-12,top-3,right-7,top+8), fill="#b1816b", outline=OUTLINE)
        d.line((right-13,top-3,right-6,top-3),fill="#e6b997",width=2)
    roofbase=eave-2
    ridge=[(peak,top+2),(right-peak//2,top+2)]
    d.polygon([(1,roofbase),ridge[0],ridge[1],(w-2,roofbase-5),(right,roofbase+1)],fill=ink,outline=OUTLINE)
    face=[(2,roofbase-1),ridge[0],ridge[1],(right,roofbase-1)]
    d.polygon(face,fill=roof,outline=ink)
    roofmask=Image.new("1",native);ImageDraw.Draw(roofmask).polygon(face,fill=1)
    pattern=Image.new("RGBA",native);p=ImageDraw.Draw(pattern)
    if kalos:
        # Mansard slate courses follow the plane. Dormers are painted over the slates.
        for yy in range(top+4,eave,4):
            p.line((0,yy,w,yy),fill=ink)
            for xx in range((yy%8)//2,w,7):p.line((xx,yy-2,xx-1,yy-1),fill=glint)
    else:
        for xx in range(0,w+14,5):
            p.line((xx+8,top,xx-6,eave-1),fill=glint)
            p.line((xx+9,top,xx-5,eave-1),fill=ink)
        p.line((0,eave-8,w,eave-8),fill=ink)
    mask=Image.new("L",native);mask.paste(pattern.getchannel("A"),mask=roofmask)
    pic.paste(pattern,mask=mask)
    d.line((peak,top+2,right-peak//2,top+2),fill=glint,width=2)
    d.line((1,roofbase,right,roofbase),fill=glint)
    d.line((right,roofbase,w-3,roofbase-5),fill=ink,width=2)
    if kalos:
        for wx in range(13,right-8,max(18,w//5)):
            wy=top+max(7,(eave-top)//2)
            d.rectangle((wx-4,wy,wx+4,wy+6),fill=STONE,outline=OUTLINE)
            window(d,wx-2,wy+1,4,4)
            d.polygon([(wx-6,wy),(wx,wy-6),(wx+6,wy)],fill=ink,outline=OUTLINE)
            d.line((wx-5,wy-1,wx,wy-6),fill=glint)
    elif kind.startswith("home"):
        # Island houses have a shaded veranda and a secondary gable over the entry.
        for xx in range(8,right-2,7):
            d.line((xx,eave+3,xx,eave+6),fill="#856b50",width=2)
        for xx in (11,right-6):
            yy=foot-9
            d.rectangle((xx-4,yy,xx+4,yy+2),fill="#987052",outline="#665b4b")
            d.line((xx-5,yy-2,xx+5,yy-2),fill="#537b62",width=2)
            for off in (-3,1,4): d.point((xx+off,yy-3), fill="#eba783")
    else:
        d.line((2,eave+1,right-1,eave+1),fill="#e5c489",width=2)
    dh=min(20,max(16,h//4));dw=8 if w>=72 else 6
    dy=foot-dh
    for wx in range(10,right-7,14):
        if abs(wx+3-x)<=dw+5:continue
        window(d,wx,max(eave+8,dy+1),7,8,shutters=not kalos)
    if dy-eave>18:
        for row in range(eave+11,dy-7,14):
            for wx in range(12,right-8,16):
                window(d,wx,row,8,7,shutters=not kalos)
            d.line((back+2,row+10,right-2,row+10),fill=MORTAR)
            d.line((back+2,row+11,right-2,row+11),fill=LIT)
    if kalos and kind in ("home_green","home_red","home_city"):
        for wx in range(10,right-7,14):
            if abs(wx+3-x)<=dw+5: continue
            yb=max(eave+8,dy+1)+10
            d.rectangle((wx-2,yb,wx+8,yb+2),fill="#875b4b")
            for ox in (0,3,6):
                d.line((wx+ox,yb-2,wx+ox,yb),fill="#528060")
                d.point((wx+ox,yb-2),fill="#ea9e81")
    for xx in (back+2,right-3):
        d.rectangle((xx,eave+5,xx+2,foot-3),fill="#eee1bb" if kalos else "#a57c53")
        d.line((xx+2,eave+6,xx+2,foot-2),fill=MORTAR)
    d.rectangle((x-dw-2,dy-2,x+dw+2,foot),fill="#b39e7e",outline="#71695d")
    d.rectangle((x-dw,dy,x+dw,foot),fill="#364452")
    d.rectangle((x-dw+2,dy+3,x+dw-2,foot-3),fill="#4d6874")
    d.line((x,dy+2,x,foot-2),fill="#273e4b")
    d.point((x+2,foot-6),fill="#e9c67d")
    ay=dy-3
    if not kalos or kind in ("center","mart"):
        d.polygon([(x-dw-4,ay-3),(x+dw+3,ay-3),(x+dw+7,ay+3),(x-dw-7,ay+3)],fill=roof if kind in ("mart","center") else "#c18960",outline=OUTLINE)
        d.line((x-dw-6,ay+3,x+dw+6,ay+3),fill=glint)
        if not kalos:
            for xx in (x-dw-5,x+dw+5):
                d.line((xx,ay+4,xx,foot-1),fill=OUTLINE,width=2);d.line((xx,ay+4,xx,foot-2),fill="#d0af7f")
    else:
        d.polygon([(x-dw-4,ay+1),(x,ay-5),(x+dw+4,ay+1)],fill=LIT,outline=MORTAR)
    if kind in ("center","mart"):
        # Glazed skylight and fascia on the clinic; a striped canvas shop canopy.
        if kind=="center":
            wid=min(14,w//4)
            d.pieslice((x-wid,top,x+wid,top+wid*2),180,360,fill="#ae5354",outline=OUTLINE)
            d.arc((x-wid+2,top+2,x+wid-2,top+wid*2-2),180,355,fill="#e8a180",width=2)
            d.line((x-wid,top+wid,x+wid,top+wid),fill=LIT,width=2)
        else:
            left=6
            d.polygon([(left,ay-3),(right-1,ay-3),(right+1,ay+2),(left-2,ay+2)],fill="#54899a",outline=OUTLINE)
            for xx in range(left+2,right-2,6):d.line((xx,ay-2,xx-1,ay+1),fill="#d0d2ae",width=2)
            d.line((left-1,ay+3,right,ay+3),fill="#376678")
    if kind in ("academy","gym"):
        # An entrance pavilion breaks up the silhouette of larger public buildings.
        wid=round(w*.17);left=x-wid;rightbay=x+wid
        d.polygon([(left,eave-3),(x,top+3),(rightbay,eave-3)],fill=glint,outline=OUTLINE)
        d.polygon([(left+4,eave-5),(x,top+10),(rightbay-4,eave-5)],fill=roof,outline=ink)
        d.ellipse((x-4,eave-15,x+4,eave-7),fill=LIT,outline=OUTLINE)
        d.line((x,eave-14,x,eave-11,x+2,eave-10),fill=OUTLINE)
        for xx in (left+2,rightbay-3):
            d.rectangle((xx,eave,xx+3,foot-2),fill=LIT,outline=MORTAR)
    if not kalos and kind.startswith("home"):
        d.polygon([(x-dw-10,ay),(x,ay-12),(x+dw+11,ay)],fill=ink,outline=OUTLINE)
        d.polygon([(x-dw-7,ay-1),(x,ay-10),(x+dw+8,ay-1)],fill=glint)
        for yy in range(ay-6,ay,2):d.line((x-2,yy,x+2,yy),fill=ink)
    if kind in ("center","mart","gym"):emblem(d,x,ay-7,kind)
    d.line((x-dw-3,foot,x+dw+3,foot),fill=LIT)
    d.line((x-dw-5,foot+2,x+dw+5,foot+2),fill="#9c9684")
    return pic.resize(target,Image.Resampling.NEAREST) if target!=native else pic


@lru_cache(None)
def city_gate():
    # The gatehouses on Lumiose's five radial roads share an open arch, slate
    # pavilion roofs and flanking watch windows. The far street is visible in the arch.
    art=Image.new("RGBA",(64,64))
    d=ImageDraw.Draw(art)
    for left in (2,39):
        d.rectangle((left+2,13,left+20,60),fill="#dac9ab",outline=OUTLINE)
        d.rectangle((left+16,15,left+20,59),fill="#aea18d")
        d.rectangle((left+1,52,left+21,60),fill="#9d978b",outline="#686c68")
        d.line((left+2,53,left+20,53),fill=LIT)
        d.polygon([(left,16),(left+5,6),(left+11,1),(left+17,6),(left+22,16)],fill="#688698",outline=OUTLINE)
        d.polygon([(left+11,3),(left+16,7),(left+20,14),(left+12,14)],fill="#43566a")
        d.line((left+1,16,left+21,16),fill="#d4c7a6",width=2)
        window(d,left+8,24,6,9)
        for yy in (38,44,50):
            d.line((left+3,yy,left+17,yy),fill="#b8ac95")
    d.rectangle((13,22,51,39),fill=STONE,outline=OUTLINE)
    d.polygon([(10,23),(14,17),(50,17),(54,23)],fill="#718a98",outline=OUTLINE)
    d.line((13,24,51,24),fill=LIT)
    d.ellipse((19,30,45,62),fill="#655e5a",outline="#b29d83",width=2)
    d.rectangle((21,46,43,59),fill="#655e5a")
    d.ellipse((24,34,40,65),fill="#354b57")
    d.rectangle((24,48,40,60),fill="#354b57")
    d.rectangle((27,50,37,60),fill="#918f81")
    d.line((23,61,41,61),fill="#e2d1ab",width=2)
    d.line((17,62,46,62),fill="#a9a092")
    d.polygon([(32,25),(35,28),(32,31),(29,28)],fill="#8f7654",outline="#dfc99a")
    return art


@lru_cache(None)
def store_facade(region, key):
    dest=ROOT/"assets"/region/"frontages"/(key+".png")
    dest.parent.mkdir(exist_ok=True)
    facade(region,key).save(dest,optimize=True)
    return "res://"+dest.relative_to(ROOT).as_posix()


def dress_map(m, region):
    """Keep each existing in-world sprite foot, including old maps with an implicit anchor."""
    prefix=f"res://assets/{region}/frontages/"
    for row in m.get("hoenn_art",{}).get("p",[]):
        old=row[0]
        key=Path(old).stem if old.startswith(prefix) else old
        if key.removesuffix("_compact") not in BUILDINGS:continue
        row[0]=store_facade(region,key)
        if len(row)<4:row.append(ANCHORS[key])


def install(region):
    for path in (ROOT/"content/regions"/region/"maps").glob("*.json"):
        data=json.loads(path.read_bytes())
        original=[r[0] for r in data.get("hoenn_art",{}).get("p",[])]
        dress_map(data,region)
        if original!=[r[0] for r in data.get("hoenn_art",{}).get("p",[])]:
            path.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")


if __name__=="__main__":
    for region in ("alola","kalos"):
        install(region)
