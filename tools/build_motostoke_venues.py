"""Build the Budew Drop Inn and the opening ceremony stadium on Motostoke's upper street."""
import base64
import json
import zlib
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
REGION = ROOT / "content/regions/galar"
DEST = ROOT / "assets/galar"
CITY = "galar_motostoke"
VENUES = {"inn": (23, 18, 14, 12), "stadium": (31, 25, 29, 12)}


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")


def asset(name):
    return Image.open(ROOT / "assets" / (name + ".png")).convert("RGBA")


def repeat(im, art, box):
    x1, y1, x2, y2 = box
    patch = Image.new("RGBA", (x2-x1, y2-y1))
    for y in range(0, patch.height, art.height):
        for x in range(0, patch.width, art.width):
            patch.paste(art, (x, y))
    im.alpha_composite(patch, (x1, y1))


def venue(kind, city):
    w, h, cx, cy = VENUES[kind]
    mid = CITY + "_" + kind
    inn = kind == "inn"
    dest = [w//2, h-3]
    mask = [[int(x in (0, w-1) or y < 2 or y==h-1) for x in range(w)] for y in range(h)]
    mask[h-2][w//2] = 0
    im = Image.new("RGBA", (16*w, 16*h), "#353b48")
    d = ImageDraw.Draw(im)
    def rect(box, colour, outline=None, width=1):
        d.rectangle(box, fill=colour, outline=outline, width=width)
    def solid(x1, y1, x2, y2):
        for ry in range(y1,y2+1):
            for rx in range(x1,x2+1):
                mask[ry][rx]=1
    def prop(name,x,y,foot=True):
        obj=asset(name)
        im.alpha_composite(obj,(16*x+8-obj.width//2,16*y+16-obj.height))
        if foot:solid(x,y,x,y)
    def carpet(x1,y1,x2,y2):
        rect((x1,y1,x2,y2),"#7f3d49","#4f3846",2)
        d.rectangle((x1+3,y1+3,x2-3,y2-3),outline="#d9ae77",width=2)
        for y in range(y1+9,y2-6,16):
            for x in range(x1+9,x2-5,16):
                d.point((x,y),fill="#a35a58")
                d.point((x+1,y+1),fill="#a35a58")
    def planks():
        inks=["#b88e67","#c19a74","#c7a07b","#bd9473"]
        for r,y in enumerate(range(32,16*(h-1),8)):
            for col,x in enumerate(range(16 - 16*(r%2),16*(w-1),32)):
                left=max(16,x)
                right=min(16*(w-1)-1,x+31)
                rect((left,y,right,y+7),inks[(r*3+col*5)%4])
                d.line((left,y,right,y),fill="#d1ae8c")
                d.line((left,y+7,right,y+7),fill="#a68165")
                d.line((right,y+1,right,y+7),fill="#a27d62")
                if right-left>15:
                    d.line((left+5,y+4,left+11,y+4),fill=inks[(r*3+col*5+2)%4])
    def sofa(x,y):
        rect((x+2,y+10,x+29,y+14),"#624737")
        rect((x,y,x+32,y+12),"#705947","#4e4139")
        rect((x+2,y+1,x+30,y+5),"#ad6e58","#875340")
        for k in (3,17):
            rect((x+k,y+5,x+k+11,y+10),"#c2866b","#895744")
            d.line((x+k+1,y+6,x+k+10,y+6),fill="#dda486")
        for xx in (x,x+29):rect((xx,y+5,xx+3,y+11),"#a87652","#71503c")
    def desk(x,y,length,colors):
        a,b,c=colors
        rect((x+2,y+4,x+length+2,y+16),"#71665d")
        rect((x,y,x+length,y+14),b,a)
        for xx in range(x+3,x+length-8,13):
            rect((xx,y+7,xx+10,y+12),b,a)
            d.point((xx+8,y+8),fill=c)
        rect((x-1,y-2,x+length+1,y+4),c,a)
        d.line((x+1,y-1,x+length-1,y-1),fill="#f3d9aa")
    if inn:
        planks()
        repeat(im,asset("island_landmarks/office_wall"),(16,0,16*(w-1),32))
        carpet(157,70,210,16*(h-1)-1)
        carpet(34,92,138,159)
        # The historical hero dominates the lobby. His sword and shield have separate silhouettes.
        x,y=104,78
        d.ellipse((x-25,y-2,x+25,y+6),fill="#80654b")
        for yy,half,c in [(y-5,23,"#735440"),(y-8,21,"#ad9262"),(y-11,18,"#e4c988")]:
            rect((x-half,yy,x+half,yy+4),c,"#766147")
        d.polygon([(x-6,y-12),(x-7,y-32),(x-13,y-24),(x-17,y-28),(x-11,y-41),(x-3,y-44),(x+7,y-42),(x+13,y-26),(x+9,y-13),(x+3,y-12),(x+1,y-23),(x-1,y-12)],fill="#c39851",outline="#795a39")
        d.ellipse((x-6,y-53,x+4,y-42),fill="#dcb774",outline="#76593a")
        d.polygon([(x-7,y-48),(x-8,y-53),(x+2,y-56),(x+7,y-52),(x+3,y-48)],fill="#e2c173",outline="#896940")
        d.polygon([(x-19,y-30),(x-21,y-58),(x-18,y-65),(x-15,y-57),(x-16,y-30)],fill="#f2d896",outline="#93703e")
        d.line((x-22,y-32,x-13,y-33),fill="#a27a3c",width=3)
        d.polygon([(x+3,y-36),(x+13,y-39),(x+18,y-35),(x+16,y-22),(x+11,y-19),(x+5,y-24)],fill="#e1bd69",outline="#8c693c")
        solid(5,3,7,4)
        for xx in (2,20):
            for yy in (3,13):prop("emerald/field/plant_indoor",xx,yy)
        desk(14*16,4*16,73,("#614a40","#996b51","#cf9d6e"))
        solid(14,4,18,4)
        # Brass service bell, dark leather register and the inn’s stained-glass bud.
        d.ellipse((270,59,277,64),fill="#d3ad68",outline="#806544")
        rect((276,61,287,63),"#835a4d")
        for xx in (238,286):
            d.polygon([(xx,25),(xx+8,16),(xx+16,25),(xx+8,34)],fill="#83a581",outline="#534f49")
            d.ellipse((xx+5,22,xx+11,28),fill="#ccc889",outline="#63785f")
        for xx in (2,19):prop("emerald/field/bookshelf_home",xx,2)
        for xx in (3,19):
            for yy in (10,12):
                sofa(xx*16,yy*16)
                solid(xx,yy,xx+1,yy)
    else:
        repeat(im,asset("island_landmarks/lab_tile"),(16,32,16*(w-1),16*(h-1)))
        for yy in range(224,16*(h-1),32):
            for xx in (33,16*w-47):
                rect((xx,yy,xx+9,yy+4),"#875852")
                d.line((xx,yy+1,xx+8,yy+1),fill="#c49571")
        repeat(im,asset("island_landmarks/dome_seats"),(16,0,16*(w-1),48))
        # Striped field, touchlines, halfway circle, goals and spectator banks.
        rect((32,48,16*w-33,189),"#659956","#425c4b",3)
        for x in range(36,16*w-42,48):
            rect((x,51,x+22,185),"#73a661")
        d.rectangle((47,58,16*w-48,178),outline="#e3e9be",width=2)
        d.line((w*8,59,w*8,177),fill="#e3e9be",width=2)
        d.ellipse((w*8-26,92,w*8+26,144),outline="#e3e9be",width=2)
        for x,s in [(47,1),(16*w-48,-1)]:
            d.line([(x,94),(x+25*s,94),(x+25*s,142),(x,142)],fill="#e3e9be",width=2)
        for x in range(35,16*w-35,34):
            rect((x,39,x+18,48),"#a34540","#633c3c")
            d.line((x+2,41,x+16,41),fill="#f2bd77")
        # Keep the field and concourse connected through the broad central player tunnel.
        for x1,x2 in [(16,16*12-1),(16*19,16*(w-1)-1)]:
            repeat(im,asset("island_landmarks/dome_seats"),(x1,192,x2,224))
            solid(x1//16,12,(x2-1)//16,13)
        carpet(214,224,281,16*(h-1)-1)
        desk(7*16,15*16,74,("#4f5662","#747e86","#c1b4a7"))
        solid(7,15,11,15)
        for xx in (121,166):
            rect((xx,229,xx+10,238),"#414953","#343c49")
            rect((xx+1,230,xx+9,235),"#88c2bd")
            d.line((xx+2,231,xx+7,231),fill="#cde2d3")
        # Match-day banners frame the concourse entrance.
        for xx in (64,16*w-86):
            rect((xx-2,227,xx+23,230),"#967f59","#574d4b")
            d.polygon([(xx,231),(xx+20,231),(xx+20,254),(xx+10,261),(xx,254)],fill="#a95147",outline="#643e3f")
            d.polygon([(xx+11,235),(xx+7,244),(xx+13,244),(xx+8,252),(xx+17,241),(xx+11,241)],fill="#f8d78f")
            solid(xx//16,14,(xx+18)//16,15)
        for x in (3,27):
            for y in (16,21):prop("emerald/field/plant_indoor",x,y)
        for x in (5,25):
            for y in (18,20):
                prop("switch_fields/props/bench",x,y)
    rect((w*8-10,(h-2)*16+6,w*8+25,(h-2)*16+11),"#e5ba79","#735b4d")
    im.convert("RGB").save(DEST/(mid+".png"),optimize=True)
    door={"at":[w//2,h-2],"trigger":"down","to":{"region":"galar","map":CITY,"at":[cx,cy+1]}}
    obj={"kind":"sign","at":[6,4],"text":"传说中的英雄曾以剑与盾平息闇夜。"} if inn else {"kind":"sign","at":[8,15],"text":"机擎竞技场　道馆挑战报名处"}
    room={"name":"机擎市・含羞苞旅店" if inn else "机擎竞技场","style":"interior","biome":"interior","tiles":mask,"npcs":[],"objects":[obj],"warps":[door],"spawn":dest,"size":[w,h],"switch_field_revision":1,"art_props":[],"hoenn_art":{"s":[w,h],"t":base64.b64encode(zlib.compress(bytes(2*w*h),9)).decode(),"p":[],"scene":["res://assets/galar/"+mid+".png",0,0]}}
    write(REGION/"maps"/(mid+".json"),room)
    site="hotel" if inn else "stadiumgate"
    src="res://assets/switch_fields/props/"+site+".png"
    art=asset("switch_fields/props/"+site)
    city["hoenn_art"]["p"]=[v for v in city["hoenn_art"]["p"] if v[0]!=src]
    city["hoenn_art"]["p"].append([src,cx,cy,[art.width//2,art.height]])
    city["switch_sites"]=[v for v in city["switch_sites"] if v["kind"]!=site]+[{"kind":site,"at":[cx,cy]}]
    city["warps"]=[v for v in city["warps"] if v["to"]["map"]!=mid]+[{"at":[cx,cy],"trigger":"door","to":{"region":"galar","map":mid,"at":dest},"switch_door":True}]
    for yy in range(cy-(art.height//16)+1,cy+1):
        for xx in range(cx-art.width//32,cx+art.width//32+1):
            assert city["tiles"][yy][xx]!=2
            city["tiles"][yy][xx]=1
    return mid


def build():
    DEST.mkdir(exist_ok=True)
    city_path=REGION/"maps"/(CITY+".json")
    city=json.loads(city_path.read_text())
    index=json.loads((REGION/"region.json").read_text())
    for kind in VENUES:
        mid=venue(kind,city)
        if mid not in index["maps"]:index["maps"].append(mid)
    write(city_path,city)
    write(REGION/"region.json",index)


if __name__ == "__main__":
    build()
