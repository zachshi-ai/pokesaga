"""Translate the bedroom, downstairs room and integrated XY centres to Emerald's indoor metatiles."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from kalos_surfaces import FLOOR,VOID
from kalos_locations import CENTERS
from bake_emerald_field import Emerald

ROOT=Path(__file__).resolve().parents[1]
SPECIAL={1,2,*CENTERS}
def layout(number):
    if number==1:return (4,3,23,17),[(6,9,7,11),(10,5,12,5),(16,5,17,5)]
    if number==2:return (21,23,41,38),[(22,25,26,26),(29,29,33,31),(24,31,25,32)]
    return (2,3,23,21),[(5,7,8,9),(13,7,14,9),(17,8,21,9),(3,13,4,13),(19,15,20,16)]
def physics(number,shape):
    (x,y,right,bottom),furniture=layout(number)
    kinds=np.zeros(shape,np.int16)
    kinds[y+2:bottom+1,x:right+1]=FLOOR
    solid=kinds==VOID
    for l,t,r,b in furniture:solid[t:b+1,l:r+1]=True
    return kinds,solid
def bake(source,dest):
    em=Emerald(source)
    def sheet(name):
        record=em.layouts[name];w,h=record['width'],record['height']
        raw=np.fromfile(em.source/record['blockdata_filepath'],dtype='<u2').reshape(h,w)
        img=Image.new('RGBA',(16*w,16*h))
        for y,row in enumerate(raw):
            for x,tile in enumerate(row):img.paste(em.metatile(name,int(tile)&1023),(16*x,16*y))
        return img
    bedroom=sheet('LittlerootTown_BrendansHouse_2F');living=sheet('LittlerootTown_BrendansHouse_1F');clinic=sheet('PokemonCenter_1F')
    pool=ROOT/'assets/emerald/field'
    for number,tag,wh in ((1,'bedroom',(28,20)),(2,'living',(46,42)),(13,'center',(26,26))):
        im=Image.new('RGB',(wh[0]*16,wh[1]*16),'#20242b')
        (l,t,r,b),_=layout(number)
        def stamp(src,tx,ty,x,y,w=1,h=1):
            pic=src.crop((tx*16,ty*16,(tx+w)*16,(ty+h)*16))
            im.paste(pic,(x*16,y*16),pic.getchannel('A'))
        def prop(key,x,y):
            piece=Image.open(pool/(key+'.png')).convert('RGBA')
            im.paste(piece,(int(x*16+8-piece.width/2),int((y+1)*16-piece.height)),piece)
        if number in (1,2):
            for y in range(t,b+1):
                for x in range(l,r+1):
                    if y<t+2:stamp(living,4,0,x,y)
                    else:stamp(bedroom,8,7,x,y)
            for x in range(l,r+1):stamp(living,6,2,x,t+2)
            for x in (l+4,r-5):stamp(living,5,0,x,t,2,2)
            if number==1:
                # Native bedroom puts the mirror in reach of the door, the bed to the west and stairs east.
                stamp(bedroom,1,4,6,9,2,3)
                stamp(bedroom,4,3,12,9,4,4)
                stamp(bedroom,0,0,10,4,2,3);stamp(bedroom,4,0,16,4,2,2)
                prop('map',14,5);prop('plant_indoor',5,6);stamp(living,7,1,20,4,3,3)
                dr=ImageDraw.Draw(im);x,y=8*16,6*16
                dr.rounded_rectangle((x+1,y-16,x+15,y+5),3,fill='#694955',outline='#393343',width=2)
                dr.rectangle((x+4,y-12,x+12,y+1),fill='#a6cbcf');dr.line((x+5,y-4,x+11,y-10),fill='#f8efcd',width=2)
            else:
                stamp(living,0,0,22,24,5,3);stamp(living,7,1,37,24,3,3)
                stamp(living,1,6,28,29,6,3);stamp(living,2,4,24,31,3,2)
                prop('plant_indoor',39,31);prop('bookshelf_home',22,27);prop('clock',35,25)
                stamp(living,8,8,28,37,2,1)
        else:
            from kalos_alola_centers import scene
            im=scene("kalos")
        im.quantize(128,method=Image.Quantize.MEDIANCUT).save(dest/('gba_'+tag+'.png'),optimize=True)
if __name__=='__main__':
    import sys
    bake(Path(sys.argv[1]),ROOT/'assets/kalos/maps')
