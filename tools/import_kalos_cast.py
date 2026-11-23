"""Build the Kalos field sprites and trainer portraits using the Emerald Rogue sprite sheets.

Source: Pokabbie/pokeemerald-rogue, 5ccb74cf1ef2c0349dfa5d70883b030bbc9ff803.
Additional Kalos supporting cast: reshaped and recoloured Emerald-size character cells.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
from import_platinum_cast import GBA_FRAMES, rgba

ROOT=Path(__file__).resolve().parents[1]
LEADERS={'紫罗兰':'viola','查克洛':'grant','可尔妮':'korrina','福爷':'ramos','希特隆':'clement','玛绣':'valerie',
         '葛吉花':'olympia','得抚':'wulfric','帕琦拉':'malva','志米':'siebold','雁铠':'wikstrom','朵拉塞娜':'drasna','卡露妮':'diantha'}
PARTNERS={'莎莉娜':('people/serena/walking','serena_front_pic'),'莎娜':('rogue/npc/rival/shauna','rival/shauna'),
          '提耶鲁诺':('rogue/npc/rival/tierno','rival/tierno'),'多罗巴':('rogue/npc/rival/trevor','rival/trevor'),
          '帅哥':('rogue/npc/misc/looker',None),'弗拉达利':('rogue/npc/team/flare_lysander','team/flare_lysandre_front_pic'),
          '闪焰队员':('rogue/npc/team/flare_grunt_m','team/flare_grunt_m_front_pic'),
          '闪焰队女团员':('rogue/npc/team/flare_grunt_f','team/flare_grunt_f_front_pic')}
# A supporting actor's wardrobe is assigned per source palette slot, retaining the eyes/skin ramps.
MODELS={
 '欧斯先生':('gentleman','mr_o'),'布拉塔诺':('scientist_1','professor'), '三色堇':('reporter_f','journalist'), '妈妈':('mom','mother'),
 '吉娜':('scientist_2','sina'),'德克希欧':('scientist_1','dexio'),'可可布尔':('old_man_2','gurkinn'),
 '柚丽嘉':('little_girl','bonnie'),'ＡＺ':('hiker','az'),'库瑟洛斯奇':('scientist_1','xerosic'),
 '阿可碧':('scientist_2','aliana'),'克蕾儿':('scientist_2','celosia'),'芭菈':('scientist_2','bryony'),'茉蜜姬':('scientist_2','mable'),
 '玛琪艾儿':('girl_1','emma'),'艾丝普莉':('ninja_boy','essentia'),'轮滑手凛香':('running_triathlete_f',''),
 '空手道王':('black_belt',''),'城主':('gentleman',''),'香殿主人':('rich_boy',''),'管家':('gentleman',''),
 '化石研究员':('scientist_1',''),'工程师':('scientist_2',''),'闪焰队干部':('rocket_m','admin'),
 '咖啡店员':('gentleman',''),'工厂会长':('devon_employee',''),'讲故事的老人':('old_man',''),
 '精英训练家':('cooltrainer_m',''),'联盟向导':('link_receptionist','')}
HAIR={'professor':['#26334b','#36435e','#506180'],'sina':['#662241','#a14863','#d06c80'],'dexio':['#533c29','#a0773d','#d0a259'],
      'xerosic':['#962c1a','#d65323','#ff813a'],'aliana':['#a45016','#ed8e23','#edbd47'],
      'celosia':['#581447','#9e2780','#d14ca5'],'bryony':['#314a38','#67914c','#a7c761'],'mable':['#193c67','#30699d','#5999bf'],
      'emma':['#26363a','#344951','#526760'],'essentia':['#222330','#38394f','#57536a'],
      'mother':['#64311e','#874b24','#ad733b'],'journalist':['#705024','#af893f','#dfc479'],
      'gurkinn':['#755d62','#ba9b9a','#e0c8bf'],'bonnie':['#91692f','#c39447','#efd37b'],'az':['#665e5b','#a49c8d','#c3bdac'],
      'mr_o':['#71455f','#bb759b','#e3a3c5'],'admin':['#ac251d','#eb4731','#ff8656']}
MONS={'路卡利欧':448,'卡比兽':143,'多丽米亚':676,'暴雪王':460,'妙喵':677}


def field_frames(path):
    im=rgba(path)
    n=im.width//16
    if n==3:order=(0,1,2,0,0,1,1,2,2,2,2,2)
    else:order=GBA_FRAMES
    out=[]
    for i,idx in enumerate(order):
        tile=im.crop((16*idx,0,16*(idx+1),im.height))
        if tile.height<32:
            padded=Image.new('RGBA',(16,32))
            padded.paste(tile,(0,32-tile.height));tile=padded
        out.append(ImageOps.mirror(tile) if i>=9 else tile)
    return out


def attire(tile, style, face):
    if not style:return tile
    tile=tile.copy()
    bb=tile.getbbox()
    if not bb:return tile
    x0,top,x1,bottom=bb
    colors=HAIR[style]
    dy=1 if face in (3,5,7,10) else 0
    draw=ImageDraw.Draw(tile)
    if style=='mr_o':
        for y in range(top,bottom):
            for x in range(x0,x1):
                r,g,b,a=tile.getpixel((x,y))
                if a and (y<top+5 or top+10<y<bottom-3) and max(r,g,b)>65:
                    draw.point((x,y),fill=('#8b507a' if r+g+b<240 else '#c474a3' if r+g+b<480 else '#e59abe'))
        return tile
    # Give the five Flare researchers the team's visor and colour-coded swept hair.
    if style in ('aliana','celosia','bryony','mable','xerosic','professor','sina','dexio','emma','essentia','journalist','mother','bonnie','az','gurkinn','admin'):
        back=face in (1,5,6); side=face in (2,7,8,9,10,11); right=face>=9
        for y in range(top,min(top+5,bottom)):
            for x in range(x0,x1):
                pixel=tile.getpixel((x,y))
                if pixel[3]>0 and sum(pixel[:3])<650:
                    lum=sum(pixel[:3]);draw.point((x,y),fill=colors[0 if lum<235 else 1 if lum<405 else 2])
        if style in ('aliana','celosia','bryony','mable','xerosic'):
            yy=top+7
            if not back:
                xx=8 if right else 2 if side else 4
                draw.line((xx,yy,xx+(4 if side else 7),yy),fill='#40314b',width=2)
                draw.point((xx+1,yy-1),fill='#e97158')
            draw.line((6,top+13,9,top+13),fill='#b64b39')
        if style=='professor':
            draw.line((3,top+2,6,top),fill=colors[0])
            if not back:draw.line((5,top+13,7,top+16),fill='#62748d')
        elif style=='az':
            if top>1:
                for (x,y) in [(4,top-1),(5,top-2),(6,top-1),(8,top-1),(9,top-2),(10,top-1)]:draw.point((x,y),fill=colors[1])
            if not back:draw.line((4,top+11,9,top+15),fill='#556e73',width=2)
            # Taller than the player's sprite, like AZ in the original.
            chunk=tile.crop(tile.getbbox())
            chunk=chunk.resize((min(16,chunk.width),min(31,chunk.height+5)),Image.Resampling.NEAREST)
            tile=Image.new('RGBA',(16,32));tile.paste(chunk,((16-chunk.width)//2,32-chunk.height))
        elif style=='bonnie' and not back:draw.rectangle((3,20+dy,5,24+dy),fill='#dec07c')
        elif style=='gurkinn' and not side:draw.line((5,top+1,10,top+1),fill='#85454a')
        elif style=='essentia':
            for x,y in [(5,top+6),(6,top+6),(9,top+6),(10,top+6),(8,top+14)]:draw.point((x,y),fill='#97d7d2' if not back else '#343445')
    return tile


def object_frames(name):
    if name in MONS:
        im=rgba(ROOT/'assets/mon'/f'{MONS[name]}.png')
        im=im.crop(im.getbbox())
        im.thumbnail((24 if name in ('卡比兽','暴雪王') else 16,22),Image.Resampling.NEAREST)
        cell=Image.new('RGBA',(32,32));cell.paste(im,((32-im.width)//2,32-im.height))
    else:
        cell=Image.new('RGBA',(16,32))
        d=ImageDraw.Draw(cell)
        if name=='镜子':
            d.rounded_rectangle((2,7,13,28),radius=2,fill='#775039',outline='#493a31')
            d.rectangle((4,9,11,24),fill='#b4d0dc',outline='#584637')
            d.line((5,17,10,11),fill='#e8f1ed');d.line((5,21,10,15),fill='#dbe6e4')
            d.rectangle((3,28,5,30),fill='#5e4435');d.rectangle((10,28,12,30),fill='#5e4435')
        elif name=='大岩石':
            d.polygon([(0,28),(1,23),(5,18),(10,17),(14,22),(15,28),(9,30),(3,30)],fill='#978975',outline='#4c514d')
            d.polygon([(3,24),(6,19),(9,19),(6,24)],fill='#c6b599')
        else:
            d.rounded_rectangle((2,17,13,28),radius=2,fill='#515967',outline='#293841')
            d.rectangle((4,19,11,24),fill='#9ad7d3',outline='#58747d')
            d.line((4,26,7,26),fill='#e5cc7c')
    return [cell]*12


def main(source):
    base=source/'graphics/object_events/pics'
    pics=source/'graphics/trainers/front_pics'
    dest=ROOT/'assets/kalos'
    entries={}
    portraits={}
    for name,key in LEADERS.items():
        entries[name]=field_frames(base/'rogue/npc/kalos'/f'{key}.png')
        portraits[name]=rgba(pics/'kalos'/f'{"clemont" if key=="clement" else key}.png')
    for name,(key,pic) in PARTNERS.items():
        entries[name]=field_frames(base/(key+'.png'))
        if pic and (pics/(pic+'.png')).exists():portraits[name]=rgba(pics/(pic+'.png'))
    for name,(key,style) in MODELS.items():
        path=base/'people'/(key+'.png')
        if not path.is_file():path=base/'rogue/npc/misc'/'veteran.png'
        entries[name]=[attire(tile,style,i) for i,tile in enumerate(field_frames(path))]
    for name in list(MONS)+['镜子','大岩石','全息影像通讯器','能源装置']:entries[name]=object_frames(name)
    atlas=Image.new('RGBA',(384*2,32*((len(entries)+1)//2)))
    rects={}
    for i,(name,frames) in enumerate(sorted(entries.items())):
        x,y=384*(i%2),32*(i//2)
        w=frames[0].width
        rects[name]=[x,y,w]
        for j,tile in enumerate(frames):atlas.paste(tile,(x+j*w,y))
    img=Image.new('RGBA',(256,64*((len(portraits)+3)//4)))
    pidx={}
    for i,(name,portrait) in enumerate(sorted(portraits.items())):
        x,y=64*(i%4),64*(i//4)
        img.paste(portrait,(x,y))
        pidx[name]=[x,y]
    dest.mkdir(exist_ok=True)
    atlas.save(dest/'cast.png',optimize=True)
    img.save(dest/'portraits.png',optimize=True)
    (dest/'cast.json').write_text(json.dumps({'field':rects,'portraits':pidx},ensure_ascii=False,separators=(',',':'))+'\n')
    print(len(entries),'field sprites;',len(portraits),'trainer portraits')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rogue',type=Path)
    main(parser.parse_args().rogue)
