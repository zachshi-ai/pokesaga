"""Build Alola actors in the Emerald overworld scale. Input is Pokabbie/pokeemerald-rogue 5ccb74cf."""
from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw, ImageColor
from import_kalos_cast import field_frames, rgba

ROOT=Path(__file__).resolve().parents[1]
ORIGINAL=dict(zip('阿塞萝拉 哈拉 哈普乌 伊利马 卡希丽 卡奇 库库伊 水莲 玛奥 茉莉 马玛内的表哥 默丹 丽姿 马玛内'.split(),
'acerola hala hapu ilima kahili kiawe kukui lana mallow mina molayne nanu olivia sophocles'.split()))
ORIGINAL['马睿因']=ORIGINAL.pop('马玛内的表哥')
TAILORED={
 '莉莉艾':('lass','f1dc98','f8f4dc','hat'), '莉莉艾（决心）':('lass','edda92','e8f2f2','ponytail'),
 '露莎米奈':('beauty','f1dc92','f5f7e2','long'), '古兹马':('man_2','e2e2ea','323640','glasses'),
 '布尔美丽':('girl_3','cd787b','3a404c','ponytail'), '扎奥博':('scientist_1','74a34b','f7f4df','glasses'),
 '碧珂':('woman_5','9964a1','f7f6ee','glasses'), '芭内特':('scientist_2','e0e3e9','759ca7','band'),
 '达尔斯':('scientist_1','c1dfea','d9e7ec','visor'), '西奥尼拉':('gentleman','dbe6ec','d9e7ec','visor'),
 '阿玛茉':('girl_2','b63465','d9e7ec','visor'), '米翎':('woman_1','ab687d','d9e7ec','visor'),
 '骷髅队员':('man_2','333c4f','292f39','band'), '以太职员':('devon_employee','98693b','e8eee3','hat'),
 '以太研究员':('scientist_1','8a6345','e8eee3','hat'), '登山男大卫':('hiker','8b654e','b75152',''),
 '妈妈':('mom','64412c','d9d7b1',''), '宝可梦学校老师':('woman_4','73513b','f6dd9a',''),
 '运动少女广美':('running_triathlete_f','74492f','d46c59',''), '短裤小子乔伊':('boy_2','7b523b','7bacda',''),
 '幼儿园小朋友米娅':('little_girl','9d7844','ecc074',''), '希望训练家约瑟夫':('rich_boy','784d32','789ac1',''),
 '联盟向导':('link_receptionist','71655c','bed7df',''), '小明':('boy_1','704a3c','3b75b2',''), '龙葵':('man_2','ad4039','332e42','band'),
 '哈普乌的祖母':('old_woman','c2b9aa','b07655',''), '成也・大木':('kanto/prof_oak','e1d5bb','6baca1',''),
 '皇家蒙面人':('black_belt','30313b','db6058','mask')}
MONS={'小星云':789,'卡璞・鸣鸣':785,'索尔迦雷欧':791,'露奈雅拉':792,'奈克洛兹玛':800,'虚吾伊德':793,'猫鼬少':734,'小拉达':19,'弱丁鱼':746,'滴蛛':751,'锹农炮虫':738,'谜拟丘':778,'杖尾鳞甲龙':784,'泥驴仔':749,'好胜蟹':739,'虫电宝':737,'穿山鼠':27,'长毛狗':508,'六尾':37}
MONS.update({'猫鼬探长':735,'拉达':20,'蝶结萌虻':743,'托戈德玛尔':777,'鬼斯':92,'鬼斯通':93,'耿鬼':94,'兰螳花':754,'焰后蜥':758,'阿罗拉椰蛋树':103,'心鳞宝':782,'鳞甲龙':783,'嘎啦嘎啦':105,'滴蛛霸':752})
REGIONAL={'拉达','小拉达','嘎啦嘎啦','阿罗拉椰蛋树','六尾','穿山鼠'}
VISITORS={'帅哥':('rogue/npc/misc/looker',''),'莉拉':('people/frontier_brains/anabel','salon_maiden_anabel_front_pic'),'赤日':('rogue/npc/team/galactic_cyrus','team/galactic_cyrus_front_pic'),'魁奇思':('rogue/npc/team/plasma_ghetsis','team/plasma_ghetsis_front_pic'),'弗拉达利':('rogue/npc/team/flare_lysander','team/flare_lysandre_front_pic'),'阿克罗玛':('rogue/npc/team/neo_plasma_colress',''),'赤焰松':('people/team_magma/maxie','magma_leader_maxie_front_pic'),'水梧桐':('people/team_aqua/archie','aqua_leader_archie_front_pic'),'坂木':('people/kanto/giovanni','kanto/leader_giovanni_front_pic')}
INGREDIENTS={'小蘑菇':('tiny_mushroom','mushroom'),'复活草':('revival_herb','revival_herb'),'奇迹种子':('miracle_seed','miracle_seed'),'文柚果':('sitrus_berry','sitrus_berry'),'芒芒果':('mago_berry','mago_berry'),'大根茎':('energy_root','energy_root')}
def ingredient_cells(source):
    out={}
    for name,(key,pal) in INGREDIENTS.items():
        src=Image.open(source/'graphics/items/icons'/(key+'.png'))
        colors=(source/'graphics/items/icon_palettes'/(pal+'.pal')).read_text().splitlines()[3:]
        src.putpalette([int(c) for line in colors for c in line.split()])
        src.info['transparency']=0
        art=src.convert('RGBA');art=art.crop(art.getbbox());art.thumbnail((17,18),Image.Resampling.NEAREST)
        frame=Image.new('RGBA',(32,32));frame.paste(art,((32-art.width)//2,29-art.height));out[name]=[frame]*12
    jar=Image.new('RGBA',(16,32));d=ImageDraw.Draw(jar)
    d.polygon([(5,19),(10,19),(12,22),(12,28),(10,30),(5,30),(3,28),(3,22)],fill='#df9a23',outline='#694723')
    d.line((4,24,11,24),fill='#fbe8ac');d.line((5,21,5,27),fill='#f8cb5d');d.rectangle((4,17,11,19),fill='#866a41',outline='#544831')
    out['甜甜蜜']=[jar]*12
    return out
def costume(tile,i,hair,cloth,feature,name):
    im=tile.copy(); l,t,r,b=im.getbbox();h=b-t
    for y in range(t,b):
        for x in range(l,r):
            red,g,blue,a=im.getpixel((x,y))
            if not a or max(red,g,blue)<43:continue
            tone=(red+g+blue)/480
            if t+1<=y<t+5 or (t+h//2+1<y<b-3 and r-l>4):
                tint=hair if y<t+5 else cloth
                rgb=ImageColor.getrgb('#'+tint)
                im.putpixel((x,y),tuple(min(255,int(c*max(.51,min(1.15,tone)))) for c in rgb)+(255,))
    d=ImageDraw.Draw(im); back=i in (1,5,6);dy=int(i in (3,5,7,10))
    if feature=='hat':
        d.ellipse((2,t-2,13,t+3),fill='#fcf4d6',outline='#97877d');d.line((0,t+4,15,t+4),fill='#cfbc97')
    elif feature in ('visor','glasses','mask','band') and not back:
        y=t+5+dy
        d.line((3,y,12,y),fill='#2f424a',width=2)
        if feature=='visor':d.line((4,y-1,11,y-1),fill='#81bfdf')
    elif feature in ('long','ponytail'):
        d.line((r-3,t+4,r-2,t+(13 if feature=='long' else 8)),fill='#'+hair,width=2)
    if name in ('莉莉艾','莉莉艾（决心）','露莎米奈'):
        front=i in (0,3,4); right=i in (9,10,11); side=not front and not back
        y=t+dy
        # Blonde tresses frame the face and fall over the white travelling clothes.
        shade='#ac955c';gold='#e6cd82';light='#fff0af'
        if back:
            d.polygon([(4,y+4),(11,y+4),(12,y+10),(10,y+12),(5,y+12),(3,y+9)],fill=gold,outline=shade)
            d.line((5,y+4,5,y+9),fill=light)
        else:
            for x in ([11] if side and not right else [3] if side else [2,12]):
                length=6 if name=='莉莉艾（决心）' else 10 if name=='露莎米奈' else 8
                d.line((x,y+5,x,y+length+4),fill=shade,width=2)
                d.line((x,y+5,x,y+length+2),fill=gold)
            if front:
                d.line((4,y+4,10,y+3),fill=gold,width=2)
                d.point((4,y+5),fill=light)
                if name=='露莎米奈':
                    d.polygon([(5,y+4),(12,y+3),(9,y+7),(7,y+7)],fill=gold,outline=shade)
                    d.polygon([(6,y+12),(10,y+12),(8,y+15)],fill='#4d6c69')
                elif name=='莉莉艾（决心）':d.line((4,y+13,10,y+17),fill='#67979e')
        if name=='莉莉艾':
            d.ellipse((2,y-2,13,y+3),fill='#fff8e5',outline='#9b907b')
            d.line((3,y+2,12,y+2),fill='#94c7cf');d.line((0,y+4,15,y+4),fill='#a69f88')
            d.line((1,y+3,14,y+3),fill='#fff5dc')
    elif name=='古兹马':
        y=t+dy
        d.polygon([(2,y+4),(2,y+1),(5,y+2),(5,y),(8,y+1),(10,y-1),(11,y+1),(13,y),(12,y+4),(9,y+5),(6,y+4)],fill='#eceaf0',outline='#727783')
        if not back:
            d.line((3,y+4,12,y+4),fill='#252936')
            d.line((4,y+4,6,y+4),fill='#ccaa40');d.line((9,y+4,11,y+4),fill='#ccaa40')
            if i in (0,3,4):d.polygon([(5,y+12),(10,y+12),(8,y+15)],fill='#c5a74c')
    return im
def main(source):
    base=source/'graphics/object_events/pics'; pics=source/'graphics/trainers/front_pics'; actors={}; faces={}
    for name,path in {**{n:'alola/'+v for n,v in ORIGINAL.items()},'哈乌':'rival/hau','格拉吉欧':'rival/gladion'}.items():
        actors[name]=field_frames(base/'rogue/npc'/(path+'.png'));faces[name]=rgba(pics/(path+'.png'))
    for name,(field,portrait) in VISITORS.items():
        actors[name]=field_frames(base/(field+'.png'))
        if portrait:faces[name]=rgba(pics/(portrait+'.png'))
    for region,names in [('kalos',['德克希欧','吉娜']),('unova',['越橘'])]:
        path=ROOT/'assets'/region;cells=json.loads((path/'cast.json').read_text())
        sheet=rgba(path/'cast.png')
        for name in names:
            x,y,w=cells.get('field',cells)[name]
            actors[name]=[sheet.crop((x+w*i,y,x+w*(i+1),y+32)) for i in range(12)]
    actors.update(ingredient_cells(source))
    for name,(model,hair,cloth,f) in TAILORED.items():
        actors[name]=[costume(tile,i,hair,cloth,f,name) for i,tile in enumerate(field_frames(base/'people'/(model+'.png')))]
    for name,sid in MONS.items():
        img=rgba(ROOT/'assets/mon'/(f'forms/{sid}_alola.png' if name in REGIONAL else f'{sid}.png'));img=img.crop(img.getbbox());img.thumbnail((30,28),Image.Resampling.NEAREST)
        tile=Image.new('RGBA',(32,32));tile.paste(img,((32-img.width)//2,32-img.height));actors[name]=[tile]*12
    dest=ROOT/'assets/alola';dest.mkdir(exist_ok=True)
    atlas=Image.new('RGBA',(384*2,32*((len(actors)+1)//2)));pidx={};idx={}
    for i,(name,cells) in enumerate(sorted(actors.items())):
        x,y=384*(i%2),32*(i//2);w=cells[0].width;idx[name]=[x,y,w]
        for j,c in enumerate(cells):atlas.paste(c,(x+j*w,y))
    gallery=Image.new('RGBA',(256,64*((len(faces)+3)//4)))
    for i,(name,im) in enumerate(sorted(faces.items())):
        x,y=(i%4)*64,(i//4)*64;gallery.paste(im,(x,y));pidx[name]=[x,y]
    atlas.save(dest/'cast.png',optimize=True);gallery.save(dest/'portraits.png',optimize=True)
    (dest/'cast.json').write_text(json.dumps({'field':idx,'portraits':pidx},ensure_ascii=False,separators=(',',':'))+'\n')
if __name__=='__main__':main(Path(sys.argv[1]))
