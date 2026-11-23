"""Draw complete Emerald streets and piers on the original island collision grid."""
import math
import numpy as np
from scipy import ndimage
from PIL import Image,ImageDraw
from kalos_gym_rooms import tile,sprite
from kalos_surfaces import WATER,WOOD,BLOCK
TOWNS={'iki','hauoli','hauoli_outskirts','hauoli_marina','hauoli_beachfront','heahea','konikoni','paniola','malie','seafolk','tapu','po','royal','hano','hano_beach'}
def stamp(im,key,x,y,scale=1):
    a=sprite(key)
    if scale!=1:a=a.resize((round(a.width*scale),round(a.height*scale)),Image.Resampling.NEAREST)
    im.paste(a,(round((x+.5)*16-a.width/2),(y+1)*16-a.height),a)
def decks(k,s):
    # Open the source's tall wooden boat and two wharves. The character stands on the planks.
    h,w=k.shape
    if (w,h)!=(61,31):raise ValueError('Seafolk source bounds changed')
    mask=Image.new('1',(w,h));d=ImageDraw.Draw(mask)
    d.polygon([(6,2),(9,0),(16,0),(20,3),(20,15),(16,24),(15,29),(10,29),(9,24),(5,15),(5,5)],fill=1)
    d.rectangle((1,9,37,12),fill=1);d.rectangle((2,27,29,29),fill=1);d.rectangle((26,22,29,28),fill=1)
    d.rectangle((25,21,31,23),fill=1)
    for rect in [(11,4,14,6),(11,16,14,19)]:d.rectangle(rect,fill=0)
    m=np.asarray(mask,bool);s[m]=False;k[m]=WOOD
    # Reserve the water between the dock and the dining boat.
    k[21:23,25:32]=WOOD;s[21:23,25:32]=False

def paint(area):
    w,h=area.w,area.h;p=16
    original=np.asarray(area.pic);pix=original.reshape(h,p,w,p,3).mean((1,3))
    r,g,b=pix.transpose(2,0,1);shade=(r+g+b)/3
    vegetated=(g>r*1.11)&(g>b*1.07)
    water=area.k==WATER
    if area.mid=='seafolk':water|=(~area.walk)&(area.k!=WOOD)
    road=(~water)&~vegetated&((shade>115)|(area.walk&(r>=g*.93)))
    asphalt=road&(abs(r-g)<18)&(abs(b-g)<25)
    path=road&~asphalt
    if area.mid=='seafolk':path[:]=False;asphalt[:]=False
    if area.mid=='hauoli_marina':asphalt|=~water&area.walk
    canvas=np.empty((h,p,w,p,3),np.uint8);cells=canvas.transpose(0,2,1,3,4)
    cells[:]=np.asarray(tile('grass'))
    cells[asphalt]=np.asarray(tile('pave'))
    beach=area.mid in ('hauoli_beachfront','hano_beach')
    if beach:
        cells[path]=np.asarray(tile('sand'))
    else:
        pad=np.pad(path,1,constant_values=True);dx=np.where(~pad[1:-1,:-2],0,np.where(~pad[1:-1,2:],2,1));dy=np.where(~pad[:-2,1:-1],0,np.where(~pad[2:,1:-1],2,1))
        for iy in range(3):
            for ix in range(3):cells[path&(dx==ix)&(dy==iy)]=np.asarray(tile('trail_'+str(iy)+str(ix)))
    pad=np.pad(~water,1);edges=pad[:-2,1:-1].astype('uint8')+2*pad[2:,1:-1]+4*pad[1:-1,2:]+8*pad[1:-1,:-2]
    for e in range(16):cells[water&(edges==e)]=np.asarray(tile('shore_'+str(e)))
    cells[(area.k==WOOD)|((~water)&(area.mid=='seafolk'))]=np.asarray(tile('bridge'))
    result=Image.fromarray(canvas.reshape(h*p,w*p,3))
    if area.mid=='seafolk':
        # Boat cabins sit on a pier and remain clear of the open gangways.
        for x,y in [(12,5),(13,18)]:
            stamp(result,'home_city',x,y,.68)
        return result
    # Scenery footprints only occupy source-blocked cells. Leave traffic clear at every threshold.
    barrier=area.s&~water
    for a in area.warps:
        x,y=a['at'];barrier[max(0,y-3):y+2,max(0,x-3):x+4]=False
    built=np.zeros_like(water)
    buildings=barrier&~vegetated&(shade>55)&(r>g*.85)
    components,n=ndimage.label(buildings)
    for ys,xs in ndimage.find_objects(components):
        w0=xs.stop-xs.start;h0=ys.stop-ys.start
        if w0<3 or h0<2 or w0*h0>320:continue
        x=xs.start+w0//2;y=ys.stop-1
        for key,scale in [('home_green' if area.mid in ['iki','hauoli_outskirts'] else 'home_city' if (x+y)%3 else 'home_blue',1),('home_red',.75)]:
            a=sprite(key);sw=round(a.width*scale/16);sh=round(a.height*scale/16)
            l=x-sw//2;t=y-sh+1
            if l<0 or t<0 or l+sw>w or y>=h:continue
            if not np.all(barrier[t+1:y+1,l:l+sw]) or built[t:y+1,l:l+sw].any():continue
            stamp(result,key,x,y,scale);built[t:y+1,l:l+sw]=True;break
    thick=ndimage.distance_transform_edt(barrier)>1.3
    for y in range(3,h,2):
        for x in range(1+(y//2)%2,w-1,2):
            if not thick[y,x] or built[y-2:y+1,x-1:x+2].any():continue
            if np.all(barrier[y-1:y+1,x-1:x+1]):
                stamp(result,'tree',x,y);built[y-2:y+1,x-1:x+1]=True
    # Narrow nonwalkable medians have an explicit kerb, hedge or fence at their boundary.
    remain=barrier&~built&ndimage.binary_dilation(area.walk)
    for y,x in np.argwhere(remain):
        result.paste(tile('verge' if vegetated[y,x] else 'fence'),(x*16,y*16))
    return result
