"""USUM's beach cave. The first island, northern pit, and southeast breakwater use real field actions."""
import numpy as np
from PIL import Image, ImageDraw
from kalos_gym_rooms import sprite,tile
from kalos_surfaces import BLOCK,LAND,WATER

BOULDER=(16,7)
PIT=(16,6)
REEF=(28,15)
PEARL=(16,13)
MACHINE=(16,3)
CLAY=(28,20)
def design():
    w,h=35,25
    terrain=Image.new('L',(w,h),BLOCK)
    d=ImageDraw.Draw(terrain)
    d.polygon([(2,10),(5,7),(11,8),(13,6),(20,6),(26,8),(28,7),(32,10),(32,20),(28,23),(6,23),(2,20)],fill=WATER)
    d.polygon([(2,13),(6,12),(8,15),(13,17),(15,20),(22,21),(22,23),(5,23),(2,20)],fill=LAND)
    d.polygon([(11,8),(14,7),(18,7),(21,8),(20,10),(16,10),(13,9)],fill=LAND)
    d.rectangle((15,2,18,4),fill=LAND)
    d.rectangle((16,4,16,8),fill=LAND)
    d.polygon([(14,13),(16,12),(18,13),(17,14),(15,14)],fill=LAND)
    d.rectangle((24,15,33,23),fill=BLOCK)
    d.rectangle((28,15,28,19),fill=WATER)
    for pt in [(27,15),(29,15)]:d.point(pt,fill=BLOCK)
    d.rectangle((27,19,29,21),fill=LAND)
    k=np.asarray(terrain,dtype=np.int16).copy()
    img=Image.new('RGB',(w*16,h*16),'#27353d')
    dr=ImageDraw.Draw(img)
    for y in range(h):
        for x in range(w):
            code=k[y,x]
            if code==BLOCK:
                if x==0 or y==0 or x==w-1 or y==h-1:continue
                if not (k[y-1:y+2,x-1:x+2]!=BLOCK).any():continue
                tx=tile('cliff')
            else:tx=tile('rockfloor' if code==LAND else 'water')
            img.paste(tx,(x*16,y*16))
            if code==WATER and y and k[y-1,x]==LAND:
                dr.line((x*16,y*16,x*16+15,y*16),fill='#d1e1c8',width=2)
    x,y=PIT
    dr.ellipse((x*16+1,y*16+4,x*16+14,y*16+13),fill='#2d2933',outline='#75665c',width=2)
    return k,k==BLOCK,img

def objects():
    def pickup(xy,key,name):
        return {'at':list(xy),'kind':'item','name':name,'flag':'a_sandy_'+key,'alola_pickup':{'key':key,'name':name,'qty':1,'medicine':0,'note':''}}
    return [
        {'at':list(BOULDER),'kind':'boulder','sprite':'boulder'},
        {'at':list(REEF),'kind':'rock','sprite':'rock','alola_reef':True,'flag':'a_sandy_reef'},
        pickup(PEARL,'BIG_PEARL','大珍珠'),
        pickup(MACHINE,'TM24','招式学习器24'),
        pickup(CLAY,'LIGHT_CLAY','光之黏土'),
    ]
