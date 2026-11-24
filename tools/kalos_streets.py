"""Fit Emerald buildings to the actual door feet and street surfaces of the two opening cities."""
from functools import lru_cache
from pathlib import Path
import numpy as np
from scipy import ndimage
from PIL import Image,ImageDraw
from kalos_gym_rooms import tile,sprite
from kalos_surfaces import LAND,ROAD,SAND,WATER
from regional_frontages import BUILDINGS, facade, city_gate
ROOT=Path(__file__).resolve().parents[1]

def draw(a):
    rural=a.number==0
    px=16 if rural else 12
    h,w=a.kind.shape; yy,xx=np.ogrid[:h*px,:w*px]
    def texture(name):
        t=np.array(tile(name).resize((px,px),Image.Resampling.NEAREST))
        if name in ('pave','stone') and not rural:
            base=np.array([216,204,174] if name=='pave' else [169,167,154])
            lum=t.mean(axis=2);t=np.uint8(np.clip(base+((lum-lum.mean())*.21)[:,:,None],0,255))
        return t[yy%px,xx%px]
    def layer(image,mask,key):
        sel=np.repeat(np.repeat(mask,px,axis=0),px,axis=1)
        image[sel]=texture(key)[sel]
    plane=texture('grass' if rural else 'pave').copy()
    walk=~a.solid
    road=(a.kind==ROAD)&walk
    layer(plane,road,'ground' if rural else 'stone')
    layer(plane,(a.kind==WATER)&walk,'water')
    if rural:
        layer(plane,(a.kind==SAND)&walk,'sand')
        field=a.kind==5
        layer(plane,field,'flowers')
    else:
        grass=~walk
        layer(plane,grass,'grass')
        rim=ndimage.binary_dilation(walk,iterations=1)&~walk
        layer(plane,rim,'stone')
        if not road.any():
            rounded=ndimage.distance_transform_edt(walk)
            layer(plane,(rounded>3)&walk,'stone')
    im=Image.fromarray(plane);d=ImageDraw.Draw(im)
    def fixture(name,p,scale=1):
        x,y=p
        art=city_gate() if name=='city_gate' else facade('kalos',name,centered=True) if not rural and name in BUILDINGS else sprite(name)
        art=art.resize((max(1,round(art.width*px/16*scale)),max(1,round(art.height*px/16*scale))),Image.Resampling.NEAREST)
        im.paste(art,(round((x+.5)*px-art.width/2),round((y+1)*px-art.height)),art)
    excluded=np.zeros((h,w),bool);pred=a.warps
    for row in pred:
        x,y=row['at'];excluded[max(0,y-6):y+4,max(0,x-4):x+5]=True
    # Inactive land around boulevards is a fenced park or a block of rooftops.
    # Fill its interior with trees and façades in perspective, keeping the collision border legible.
    ok=(~walk)&~excluded
    density=ndimage.distance_transform_edt(ok)
    for y in range(3,h-1,3 if rural else 5):
        for x in range(2+(y%3),w-2,3 if rural else 6):
            if density[y,x]<(1.7 if rural else 3):continue
            if rural or (x//12+y//19)%5 in (0,1):fixture('tree',(x,y))
            elif density[y,x]>4:fixture(('home_city','home_blue','home_red')[(x//7+y//5)%3],(x,y),1.18)
    if rural:
        # The original west-to-east row has three usable homes, an open gateway and enclosed gardens.
        for wv in pred:
            x,y=wv['at'];m=wv['to']['map']
            if wv.get('source_warp')=='matrix':continue
            key='home_red' if 'home_1f' in m else 'home_blue' if 'rival' in m else 'home_green'
            fixture(key,(x,y-1),1.25)
            for dx in (-3,3):fixture('flowers',(x+dx,y+1))
            for dx in (-5,5):fixture('tree',(x+dx,y+2))
        # Gated flower gardens and hedges lead to the cobbled path between the homes.
        for wx,wy in [v['at'] for v in pred if v['source_warp']!='matrix']:
            for dx in (-4,4):
                for off in range(2,7):
                    xx,yy=wx+dx,wy+off
                    if 0<xx<w and 0<yy<h and not road[yy,xx] and (xx,yy) not in [tuple(p) for p in a.anchors.values()]:
                        fixture('flowers',(xx,yy))
            line=wy+7
            for xx in range(wx-3,wx+4):
                if xx not in (wx,wx+1) and 0<xx<w and not road[line,xx]:
                    X,Y=xx*px,line*px;d.rectangle((X,Y+2,X+px,Y+6),fill='#849971',outline='#607760');d.rectangle((X+2,Y-2,X+4,Y+8),fill='#b4bd93')
        for x,y in ((30,25),(46,24),(16,23)):
            if walk[y,x]:fixture('flowers',(x,y))
    else:
        taken=set()
        protected=set(tuple(p) for p in [a.spawn,*a.anchors.values(),*a.lips.values(),*(s['at'] for s in a.warps)])
        def dress_front(pt,key,scale):
            x,y=pt;fixture(key,(x,y),scale)
            # Traditional street façades have window boxes, rails and small striped awnings.
            if key.startswith('home'):
                X,Y=round((x+.5)*px),round((y+1)*px);W=round(1.65*px*scale)
                d.rectangle((X-W,Y-2*px,X+W,Y-2*px+2),fill='#795662')
                for k in (-1,1):
                    win=X+k*round(px*scale)
                    d.rectangle((win-3,Y-px,win+3,Y-px+2),fill='#486c54');d.point((win-2,Y-px-1),fill='#f1a494')
        def build_front(x,y,key):
            # Reserve a small, solid shop bay where the source has no scripted street coordinates.
            for scale,rad,rows in [(1.20,2,4),(.86,1,3)]:
                rect={(vx,vy) for vx in range(x-rad,x+rad+1) for vy in range(y-rows,y)}
                if any(v in protected or v in taken for v in rect) or x-rad<1 or x+rad>=w-1 or y-rows<2:continue
                sample=a.solid.copy()
                for vx,vy in rect:sample[vy,vx]=True
                # Check the actual walking interior without automated threshold tiles.
                for wp in a.warps:wx,wy=wp['at'];sample[wy,wx]=True
                comps,_=ndimage.label(~sample);ax,ay=a.spawn;anchor=comps[ay,ax]
                if not anchor or any(comps[py,px] not in (0,anchor) for px,py in protected):continue
                if any(not any(0<=vx<w and 0<=vy<h and comps[vy,vx]==anchor for vx,vy in ((px,py-1),(px,py+1),(px+1,py),(px-1,py))) for px,py in protected):continue
                for vx,vy in rect:a.solid[vy,vx]=True
                taken.update(rect);dress_front((x,y-1),key,scale)
                return True
            return False
        # Script-only entrances in Lumiose lack model coordinates. Put a doorfront to the north only
        # when its whole footprint is blocked, or move the shopfront into the verge with a connected awning.
        for i,wv in enumerate(pred):
            x,y=wv['at'];to=wv['to']['map'];source=wv.get('source_warp','')
            if source=='matrix' or 'plaza' in to or 'lumiose_north' in to or 'lumiose_central' in to:continue
            target=([x,y-1],0.)
            if to in {'kalos_zone_'+str(n) for n in range(70,75)}:building='city_gate'
            elif 'center_' in to:building='center'
            elif 'lab_' in to or 'museum' in to:building='academy'
            elif 'station' in to:building='mart'
            elif 'tower' in to:building='gym'
            elif 'cafe' in to or 'restaurant' in to:building='home_red'
            else:building=('home_city','home_blue','home_red','home_green')[i%4]
            if build_front(x,y,building):continue
            pts=[]
            for dy in range(-11,9):
                for dx in range(-10,11):
                    vx=x+dx;vy=y+dy
                    if not (3<=vx<w-3 and 6<=vy<h-2):continue
                    if (vx,vy) in taken or walk[vy-3:vy+1,vx-2:vx+3].mean()>.05:continue
                    pts.append((dx*dx+dy*dy+(7 if dy>1 else 0),vx,vy))
            if pts:
                _,vx,vy=min(pts);dress_front((vx,vy),building,1.05)
                for ox in range(-4,5):
                    for oy in range(-3,3):taken.add((vx+ox,vy+oy))
            if not pts or abs(vx-x)+abs(vy-y)>2:
                # A narrow illuminated shop entrance mounted over its real trigger, with curb visible.
                x0=x*px;y0=y*px
                d.rounded_rectangle((x0-2,y0-10,x0+px+2,y0+4),2,fill='#765b52',outline='#454555')
                d.rectangle((x0+1,y0-7,x0+px-1,y0+4),fill='#536e76')
                for ox in range(-2,px+2,4):
                    d.rectangle((x0+ox,y0-10,x0+ox+3,y0-5),fill=('#de9876' if ox%8==-2%8 else '#f0d5a0'))
        # Native carriageways curve in much wider sweeps than the field viewport.
        # Add Emerald shop rows and tree-lined pavement where the raised frontage adjoins them.
        model_walk=a.walk.copy()
        clearance=ndimage.distance_transform_edt(~road)
        boundary=ndimage.distance_transform_edt(walk)
        for y in range(6,h-6,8):
            for x in range(5+((y//8)%2)*2,w-5,6):
                if not model_walk[y,x] or (x,y) in taken or (x,y) in protected:continue
                if road.any() and road[y,x] and boundary[y,x]>4 and (x//22+y//15)%3:continue
                if not road.any() and (x//10+y//8)%4==0:continue
                style=(x//6+2*y//8)%8
                if style in (1,2,4,6,7):
                    if build_front(x,y,('home_city','home_blue','home_red','academy')[(x//6+y//8)%4]):
                        fixture('flowers',(x-2,y));fixture('streetlamp',(x+2,y))
                elif style in (0,3,5) and max(abs(x-a.spawn[0]),abs(y-a.spawn[1]))<75:
                    # A narrow raised flowerbed and its shade tree, each with the same solid footprint.
                    area={(x,y),(x+1,y),(x+2,y)}
                    if area.intersection(protected|taken) or not all(model_walk[py,px] for px,py in area):continue
                    q=a.solid.copy()
                    for bx,by in area:q[by,bx]=True
                    for wp in a.warps:wx,wy=wp['at'];q[wy,wx]=True
                    groups,_=ndimage.label(~q);ax,ay=a.spawn;group=groups[ay,ax]
                    if not group or any(groups[py,px] not in (0,group) for px,py in protected):continue
                    if any(not any(0<=vx<w and 0<=vy<h and groups[vy,vx]==group for vx,vy in ((px,py-1),(px,py+1),(px+1,py),(px-1,py))) for px,py in protected):continue
                    for bx,by in area:a.solid[by,bx]=True
                    taken.update(area)
                    X,Y=x*px,y*px
                    d.rounded_rectangle((X-2,Y+2,X+3*px,Y+px),3,fill='#697763',outline='#849388')
                    d.rounded_rectangle((X-1,Y,X+3*px-1,Y+px-4),3,fill='#8baa79',outline='#c3b792')
                    fixture('tree',(x+1,y));fixture('flowers',(x+2,y))
        medians=road&((np.roll(road,-1,0)!=road)|(np.roll(road,1,1)!=road))
        points=np.argwhere(medians)
        for y,x in points:
            if x%6==0 and y%2==0 and (x,y) not in protected and (x,y) not in taken:
                d.line((x*px+1,y*px+px-2,(x+1)*px-2,y*px+px-2),fill='#ddcba6',width=2)
        # Checker-inlaid squares, flower borders and roadside greenery break up long avenues.
        for y in range(9,h-6,11):
            for x in range(8+y%7,w-6,12):
                if not walk[y,x] or max(abs(x-a.spawn[0]),abs(y-a.spawn[1]))>80:continue
                if road[y,x]:
                    X,Y=x*px,y*px
                    d.polygon([(X,Y-2),(X+3,Y),(X,Y+2),(X-3,Y)],fill='#d5cbb5')
                elif (x,y) not in protected:
                    px0=x*px;py0=y*px
                    for j in range(3):
                        d.rectangle((px0-3+3*j,py0-1,px0-2+3*j,py0+1),fill='#a8b7a5')
        # Freestanding lanterns and clipped boulevard trees stay off walking and warp tiles.
        edge=(ndimage.binary_dilation(walk)&~walk)&~excluded
        for y in range(4,h-2,5):
            for x in range(2,w-2,4):
                if edge[y,x]:fixture('streetlamp' if (x+y)%3 else 'tree',(x,y))
        if a.number==69:
            # Prism Tower is the meeting point of five streets in the middle of the city.
            tw=next((v for v in a.warps if v['to']['map']=='kalos_tower'),None)
            if tw:
                x,y=tw['at'];x=(x+.5)*px;y=y*px
                # Four buttresses form a walk-through arch below two observation decks.
                frames=[(0,3.1),(1.4,2.2),(3.0,1.62),(4.4,1.15),(6.3,.76),(8.4,.43)]
                for sign in (-1,1):
                    for (ha,wa),(hb,wb) in zip(frames,frames[1:]):
                        a1=(x+sign*wa*px,y-ha*px);b1=(x+sign*wb*px,y-hb*px)
                        a2=(a1[0]-sign*max(3,px*.65),a1[1]);b2=(b1[0]-sign*max(2,px*.48),b1[1])
                        d.line((a1,b1),fill='#415b6b',width=4);d.line((a2,b2),fill='#6d8a99',width=3)
                        d.line((a1,b2),fill='#84a2a6',width=2);d.line((a2,b1),fill='#b9c5b6',width=2)
                for ht,half,ht2 in [(2.9,1.82,.45),(6.1,.98,.42),(8.4,.73,.86)]:
                    t=y-ht*px;ww=half*px
                    d.rectangle((x-ww,t-ht2*px,x+ww,t),fill='#708c98',outline='#425767',width=2)
                    d.line((x-ww,t-ht2*px,x+ww,t-ht2*px),fill='#e2c998',width=2)
                    for col in range(-2,3):d.line((x+col*ww/3,t-ht2*px+2,x+col*ww/3,t-2),fill='#c8dbca',width=1)
                d.polygon(((x-4,y-9.1*px),(x,y-12*px),(x+4,y-9.1*px)),fill='#d7d4b1',outline='#657b89')
                d.ellipse((x-2,y-12*px-3,x+2,y-12*px+1),fill='#f4c483')
    a.img='gba_town_'+str(a.number)
    im.quantize(112,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).save(ROOT/'assets/kalos/maps'/(a.img+'.png'),optimize=True)
