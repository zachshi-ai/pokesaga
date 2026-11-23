"""The five working islands of Poké Pelago, built from Emerald terrain and field furnishings."""
from PIL import Image,ImageDraw
from kalos_gym_rooms import tile,sprite
from kalos_surfaces import LAND,WATER,WOOD
import numpy as np
OFFICE=(14,10)
def design(mid):
    isle=mid.split('_')[-1];w,h=31,24;p=16
    mat=Image.new('L',(w,h),WATER);d=ImageDraw.Draw(mat)
    d.polygon([(3,11),(5,7),(9,5),(14,4),(17,3),(23,5),(25,7),(28,9),(27,14),(23,17),(19,19),(13,20),(8,18),(4,16)],fill=LAND)
    d.rectangle((11,17,13,22),fill=WOOD)
    k=np.array(mat,dtype=np.int16);block=np.zeros((h,w),bool);block[[0,-1],:]=True;block[:,[0,-1]]=True
    interior=(k==LAND);from scipy.ndimage import distance_transform_edt
    dist=distance_transform_edt(interior)
    pic=Image.new('RGB',(w*p,h*p))
    for y in range(h):
        for x in range(w):
            key='sea' if k[y,x]==WATER else 'bridge' if k[y,x]==WOOD else 'sand' if dist[y,x]<2.2 else 'grass'
            pic.paste(tile(key),(x*p,y*p))
    def put(name,x,y):
        stamp=sprite(name);pic.paste(stamp,(round((x+.5)*p-stamp.width/2),(y+1)*p-stamp.height),stamp)
        block[y,x]=True
    for x,y in [(8,8),(9,8),(22,7),(24,9),(21,16)]:put('tree',x,y)
    if isle=='abeens':
        trunk=sprite('tree').resize((56,78),Image.Resampling.NEAREST)
        pic.paste(trunk,(13*p,5*p),trunk)
        dr=ImageDraw.Draw(pic)
        for x,y,c in [(15,7,'#f4c875'),(14,6,'#ee9272'),(15,6,'#91d29b'),(14,8,'#e6a5b6')]:
            dr.ellipse((x*p+3,y*p+5,x*p+9,y*p+13),fill=c,outline='#6b684c')
        block[9,14:16]=True
    elif isle=='aplenny':
        for x in range(11,19,2):
            for y in [7,9,13]:put('soil',x,y)
        put('berry_tree',18,9)
    elif isle=='aphun':
        for x,y in [(12,8),(13,7),(14,7),(15,7),(16,7),(17,8),(12,9),(17,9)]:put('boulder',x,y)
        pic.paste(tile('cave'),(14*p,8*p));block[8,14]=True
    elif isle=='evelup':
        for x,y in [(11,7),(16,7),(20,13)]:put('carebench',x,y)
        for x in range(11,19):pic.paste(tile('ground'),(x*p,12*p))
    else:
        for x in range(11,18):
            for y in [7,8,9]:
                pic.paste(tile('water'),(x*p,y*p));k[y,x]=WATER
        for x,y in [(10,7),(18,7),(12,6),(16,6),(10,9),(18,9)]:put('rock',x,y)
    put('sign',*OFFICE)
    return k,block,pic
