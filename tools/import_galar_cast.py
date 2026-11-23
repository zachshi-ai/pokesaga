"""Build Galar's Emerald-scale cast from the Pokabbie/pokeemerald-rogue graphics tree."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw
from import_alola_cast import costume
from import_kalos_cast import field_frames, rgba

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = {
    "聂梓": "galar/piers", "丹帝": "galar/leon", "亚洛": "galar/milo", "露璃娜": "galar/nessa",
    "卡芜": "galar/kabu", "彩豆": "galar/bea", "欧尼奥": "galar/allister",
    "波普菈": "galar/opal", "玛瓜": "galar/gordie", "美蓉": "galar/melony",
    "奇巴纳": "galar/raihan", "赫普": "rival/hop", "玛俐": "rival/marnie", "彼特": "rival/bede",
}
TAILORED = {
    "木兰博士": ("old_woman","e2dfd7","ddd4e8","glasses"), "索妮亚": ("beauty","ea995e","bb9161","ponytail"),
    "洛兹": ("gentleman","615855","777979",""), "奥利薇": ("woman_5","f2dca4","e9e3d3","long"),
    "呐喊队男队员": ("man_2","dc5f98","3d3d4a","band"), "呐喊队女队员": ("girl_3","dd6498","434051","band"),
    "马士德": ("expert_m","d8d2af","d0a83b","band"), "蜜叶": ("woman_5","69554a","7da852","long"),
    "皮欧尼": ("hiker","4b4647","ed9152","visor"), "夏科娅": ("girl_3","513b34","b74758","hat"),
    "西尔迪": ("gentleman","e4c674","a84354",""), "索德": ("gentleman","f6d684","46739b",""),
    "医生": ("scientist_1","5f584e","e9e6d8","glasses"), "女助手": ("woman_5","614842","ddd9cf","long"),
    "马洛科蒙职员": ("devon_employee","57535c","495468","glasses"), "大厦同事": ("man_4","4e4846","67727c",""),
    "培育家": ("woman_3","844f47","a6bb6a","band"), "武馆门生": ("expert_m","55463d","d8a83e","band"),
    "极巨汤师傅": ("man_3","6c554a","d5ab49","band"), "塔中门生": ("expert_m","403f38","e3c354","band"),
    "村长": ("old_man","d0cfc5","7a6d8b",""), "村民": ("man_4","8c796d","727e6f",""),
    "巢穴调查员": ("scientist_1","684f48","e7e1d5","glasses"), "妈妈": ("mom","665249","aaca9e",""), "列车员": ("devon_employee","5d5049","475d7c",""),
    "联盟工作人员": ("devon_employee","58453a","bc5e57",""), "联盟接待员": ("link_receptionist","745246","bec8d4",""),
}
MONS={"熊徒弟":891,"蕾冠王":898,"百合根娃娃":548,"啃果虫":840,"呆呆兽":79,"急冻鸟":144,"闪电鸟":145,"火焰鸟":146,"无极汰那":890,"敲音猴":810,"炎兔儿":813,"泪眼蜥":816,"毛辫羊":831,"来电汪":835,"莫鲁贝可":877,"喷火龙":6,"苍响":888,"藏玛然特":889}


def tailored(name, specs, source):
    model, hair, cloth, feature=specs
    cells=[]
    for i,frame in enumerate(field_frames(source / (model+".png"))):
        tile=costume(frame,i,hair,cloth,feature,name)
        d=ImageDraw.Draw(tile)
        _,top,_,bottom=frame.getbbox()
        if name=="木兰博士":
            d.line((13,top+12,13,bottom-1),fill="#79583b")
            d.line((12,top+11,14,top+11),fill="#a49978")
        elif name in ("索德","西尔迪"):
            if name=="索德":
                d.polygon([(7,top+2),(8,max(0,top-5)),(10,top+3)],fill="#f1d582",outline="#a38952")
            else:
                d.polygon([(3,top+3),(5,top),(11,top),(14,top+4),(12,top+7),(5,top+6)],fill="#e0c17b",outline="#a38952")
        elif name=="索妮亚":
            d.line((3,top+2,11,top+2),fill="#535e60")
            for x in (5,9):
                d.ellipse((x-1,top,x+1,top+2),fill="#8bc6c4",outline="#59494b")
        elif "呐喊队" in name:
            d.line((5,top+13,10,top+16),fill="#dc6397",width=2)
            if i in (0,3,4):d.line((3,top+6,5,top+8),fill="#d25189")
        elif name=="洛兹" and i in (0,3,4):
            d.line((6,top+11,9,top+11),fill="#57534e")
            d.line((8,top+13,9,top+17),fill="#a05a55")
        elif name=="奥利薇" and i in (0,3,4):
            d.line((7,top+12,9,top+15),fill="#8e464b")
        cells.append(tile)
    return cells


def field_objects():
    actors={}
    for name in ("木雕王冠","积雪的田地","古墓旁的田地","蜂巢","极巨菇菇","传说的大树","钢铁遗迹","岩山遗迹","冰山遗迹","抉择遗迹"):
        tile=Image.new("RGBA",(32,32))
        d=ImageDraw.Draw(tile)
        if "遗迹" in name:
            colors={"钢铁遗迹":("#73878f","#b8cdd0"),"岩山遗迹":("#946249","#deab6d"),"冰山遗迹":("#79acbc","#e4f8ef"),"抉择遗迹":("#655789","#d2a259")}
            edge,high=colors[name]
            d.polygon([(5,28),(5,11),(10,5),(22,5),(26,11),(26,28)],fill=edge,outline="#42434e")
            d.line([(6,12),(10,7),(21,7),(24,12)],fill=high,width=2)
            d.rectangle((11,13,20,28),fill="#484354",outline=high)
            for x,y in [(15,14),(13,17),(17,17),(11,20),(19,20),(15,22),(15,25)]:
                d.point((x,y),fill="#fbe097")
        elif "田地" in name:
            d.polygon([(3,21),(10,17),(28,19),(29,28),(7,30),(2,26)],fill="#765640",outline="#4f534b")
            for x in (6,12,18,24):d.line((x,26,x+3,20),fill="#ba9672",width=2)
            if "积雪" in name:d.line([(3,21),(10,17),(27,19)],fill="#e3f2ed",width=2)
        elif name=="木雕王冠":
            d.polygon([(6,14),(12,19),(16,10),(20,19),(26,14),(23,26),(9,26)],fill="#ac8851",outline="#604b3d")
            d.line((10,23,22,23),fill="#dbc084",width=2)
        elif name=="蜂巢":
            d.line((15,10,19,4),fill="#574933",width=2)
            d.ellipse((7,10,24,26),fill="#dfaa4f",outline="#745639")
            for y in (13,16,20,23):d.line((10,y,21,y),fill="#bc8038")
            d.ellipse((17,17,21,21),fill="#544337")
        elif name=="极巨菇菇":
            for x,y in ((7,24),(22,23),(15,20)):
                d.rectangle((x-1,y-1,x+1,y+5),fill="#efbfd6")
                d.polygon([(x-5,y),(x-3,y-4),(x,y-7),(x+3,y-4),(x+5,y)],fill="#cf5479",outline="#843954")
                d.point((x-1,y-3),fill="#ffe3bf")
        else:
            d.rectangle((13,19,19,30),fill="#77614d",outline="#4b5148")
            for x,y in [(13,10),(8,18),(20,17),(22,10),(15,7)]:
                d.ellipse((x-6,y-5,x+6,y+6),fill="#966689",outline="#654e70")
                d.line((x-3,y-3,x,y-4),fill="#d69cab")
        actors[name]=[tile]*12
    return actors

def build(source):
    base=source/"graphics/object_events/pics"
    actors={name:field_frames(base/"rogue/npc"/(path+".png")) for name,path in ORIGINAL.items()}
    faces={name:rgba(source/"graphics/trainers/front_pics"/(path+".png")) for name,path in ORIGINAL.items()}
    actors.update({name:tailored(name,spec,base/"people") for name,spec in TAILORED.items()})
    actors["球球男"]=field_frames(base/"rogue/npc/misc/ball_guy.png")
    for name,path in {"克拉拉":"rival/klara","赛宝利":"rival/avery"}.items():
        actors[name]=field_frames(base/"rogue/npc"/(path+".png"))
    actors.update(field_objects())
    for name,species in MONS.items():
        path=ROOT/"assets/mon"/f"{species}.png"
        if species in (79,144,145,146):
            path=ROOT/"assets/mon/forms"/f"{species}_galar.png"
        image=rgba(path)
        # Some source front sprites still contain the reserved green palette entry.
        key = (152, 208, 160, 255)
        if image.getpixel((0, 0)) == key:
            image.putdata([(0, 0, 0, 0) if pixel == key else pixel for pixel in image.getdata()])
        image=image.crop(image.getbbox())
        size=30 if species in (6,888,889) else 18
        image.thumbnail((size,size),Image.Resampling.NEAREST)
        tile=Image.new("RGBA",(32,32))
        tile.paste(image,((32-image.width)//2,31-image.height))
        actors[name]=[tile]*12
    dest=ROOT/"assets/galar"
    dest.mkdir(exist_ok=True)
    field=Image.new("RGBA",(768,32*((len(actors)+1)//2)))
    gallery=Image.new("RGBA",(256,64*((len(faces)+3)//4)))
    index={"field":{},"portraits":{}}
    for i,(name,cells) in enumerate(sorted(actors.items())):
        x,y=384*(i%2),32*(i//2)
        index["field"][name]=[x,y,cells[0].width]
        for j,c in enumerate(cells):field.paste(c,(x+j*c.width,y))
    for i,(name,img) in enumerate(sorted(faces.items())):
        x,y=i%4*64,i//4*64
        gallery.paste(img,(x,y))
        index["portraits"][name]=[x,y]
    field.save(dest/"cast.png",optimize=True)
    gallery.save(dest/"portraits.png",optimize=True)
    (dest/"cast.json").write_text(json.dumps(index,ensure_ascii=False,separators=(",",":"))+"\n")


if __name__=="__main__":
    build(Path(sys.argv[1]))
