"""Build Galar's Emerald-scale cast from the Pokabbie/pokeemerald-rogue graphics tree."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw
from import_alola_cast import costume
from import_kalos_cast import field_frames, rgba

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = {
    "丹帝": "galar/leon", "亚洛": "galar/milo", "露璃娜": "galar/nessa",
    "卡芜": "galar/kabu", "彩豆": "galar/bea", "欧尼奥": "galar/allister",
    "波普菈": "galar/opal", "玛瓜": "galar/gordie", "美蓉": "galar/melony",
    "奇巴纳": "galar/raihan", "赫普": "rival/hop", "玛俐": "rival/marnie", "彼特": "rival/bede",
}
TAILORED = {
    "木兰博士": ("old_woman","e2dfd7","ddd4e8","glasses"), "索妮亚": ("beauty","ea995e","bb9161","ponytail"),
    "洛兹": ("gentleman","615855","777979",""), "奥利薇": ("woman_5","f2dca4","e9e3d3","long"),
    "呐喊队男队员": ("man_2","dc5f98","3d3d4a","band"), "呐喊队女队员": ("girl_3","dd6498","434051","band"),
    "妈妈": ("mom","665249","aaca9e",""), "列车员": ("devon_employee","5d5049","475d7c",""),
    "联盟工作人员": ("devon_employee","58453a","bc5e57",""), "联盟接待员": ("link_receptionist","745246","bec8d4",""),
}
MONS={"敲音猴":810,"炎兔儿":813,"泪眼蜥":816,"毛辫羊":831,"来电汪":835,"莫鲁贝可":877,"喷火龙":6,"苍响":888,"藏玛然特":889}


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


def build(source):
    base=source/"graphics/object_events/pics"
    actors={name:field_frames(base/"rogue/npc"/(path+".png")) for name,path in ORIGINAL.items()}
    faces={name:rgba(source/"graphics/trainers/front_pics"/(path+".png")) for name,path in ORIGINAL.items()}
    actors.update({name:tailored(name,spec,base/"people") for name,spec in TAILORED.items()})
    actors["球球男"]=field_frames(base/"rogue/npc/misc/ball_guy.png")
    for name,species in MONS.items():
        image=rgba(ROOT/"assets/mon"/f"{species}.png")
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
