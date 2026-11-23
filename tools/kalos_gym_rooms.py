"""Adapt the camera-dependent X/Y gym puzzles to four-way Emerald tile movement."""
from pathlib import Path
from functools import lru_cache
import math
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree
from kalos_surfaces import FLOOR,VOID
from unova_art import K

ROOT=Path(__file__).resolve().parents[1]
FIELD=ROOT/'assets/emerald/field'
P=16
@lru_cache(None)
def tile(key):
    atlas=Image.open(ROOT/'assets/unova/tiles.png').convert('RGB')
    i=K[key];x=i%16*16;y=i//16*16
    return atlas.crop((x,y,x+16,y+16))
@lru_cache(None)
def sprite(name):
    return Image.open(FIELD/(name+'.png')).convert('RGBA')
def stamp(pic,name,x,y):
    art=sprite(name);pic.paste(art,(int((x+.5)*P-art.width/2),int((y+1)*P-art.height)),art)
def center(p):return tuple((i*P+P//2) for i in p)
def surround(x,y):return [(x+1,y),(x,y-1),(x-1,y),(x,y+1)]
class Room:
    def __init__(self,n,size,background):
        self.n=n;self.size=size;w,h=size
        self.pic=Image.new('RGB',(w*P,h*P),background);self.draw=ImageDraw.Draw(self.pic)
        self.floor=Image.new('1',size,0);self.ft=ImageDraw.Draw(self.floor)
        self.pads=[];self.fix={};self.return_gate=None;self.objects=[]
    def paths(self,points,key,width=3,edge=None):
        self.ft.line(points,fill=1,width=width)
        for x,y in points:self.ft.rectangle([x-width//2,y-width//2,x+width//2,y+width//2],fill=1)
        if edge:
            self.draw.line([center(p) for p in points],fill=edge,width=width*P+4,joint='curve')
        # Stamp a seamless cropped path on the precise collision raster.
        mask=Image.new('1',self.size,0);d=ImageDraw.Draw(mask);d.line(points,fill=1,width=width)
        for x,y in points:d.rectangle([x-width//2,y-width//2,x+width//2,y+width//2],fill=1)
        self.paint(mask,key)
    def paint(self,mask,key):
        yy,xx=np.where(np.array(mask))
        t=tile(key)
        for x,y in zip(xx,yy):self.pic.paste(t,(int(x)*P,int(y)*P))
    def rect(self,box,key):
        self.ft.rectangle(box,fill=1);m=Image.new('1',self.size,0);ImageDraw.Draw(m).rectangle(box,fill=1);self.paint(m,key)
    def pad(self,p,col):
        x,y=center(p);d=self.draw
        d.rounded_rectangle((x-8,y-7,x+7,y+6),3,fill='#49516a',outline='#353449',width=2)
        d.ellipse((x-6,y-6,x+5,y+3),fill=col,outline='#f5f0ce')
    def facing(self,point):return list(point)
    def layout(self,entrance,boss):
        self.entry=entrance;self.boss=boss
        self.return_gate=[entrance[0],entrance[1]+1];self.pad(self.return_gate,'#d88764')
    def anchors(self,area):
        a=np.asarray(self.floor,dtype=bool);area.kind=np.where(a,FLOOR,VOID);area.solid=~a
        area.walk=a;area.spots=np.argwhere(a)[:,::-1];area.tree=cKDTree(area.spots)
        area.spawn=list(self.entry);area.img='gba_gym_'+str(self.n)
        area.used={tuple(w['at']) for w in area.warps};area.arrivals={tuple(w['to']['at']) for w in area.warps if w['to']['map']==area.mid}
        area.arrivals|={tuple(self.entry),tuple(self.boss)}
        area.anchors={};area.finish_anchors()
        # Keep the actual leader and trainers on assigned platforms, even in separate fairy rooms.
        for key,pt in {'story':self.boss,**self.fix}.items():
            if key in area.anchors:
                old=area.anchors[key]
                other=next((k for k,v in area.anchors.items() if k!=key and v==list(pt)),None)
                if other:area.anchors[other]=old
                area.anchors[key]=list(pt)
        area.objects+=self.objects
        self.pic.quantize(120,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).save(ROOT/'assets/kalos/maps'/(area.img+'.png'),optimize=True)

def fairy():
    r=Room(203,(50,47),'#382f49')
    rooms=['nw','n','ne','w','c','e','sw','s','se'];cent={}
    palette=['#e7bad8','#e3c790','#c7c5df','#a6d0c7','#d8a5c0','#d4b5d5','#b1c6d5','#d8b6a7','#c2a4be']
    for i,key in enumerate(rooms):
        l=1+i%3*16;t=1+i//3*15;cent[key]=(l+7,t+7)
        r.draw.rounded_rectangle((l*P,t*P,(l+14)*P,(t+13)*P),7,fill=palette[i],outline='#574459',width=4)
        r.draw.rectangle((l*P+8,t*P+8,(l+14)*P-8,(t+2)*P),outline='#f6e1d5',width=3)
        for x in (l+3,l+9):
            r.draw.rectangle((x*P,t*P+9,(x+2)*P,(t+2)*P),fill='#6c7185',outline='#f2dfc4',width=3)
            r.draw.line(((x+1)*P,t*P+11,(x+1)*P,(t+2)*P-1),fill='#d7d6d5',width=2)
        r.rect((l+1,t+2,l+12,t+11),'wood')
        r.rect((l+4,t+4,l+9,t+9),'carpet')
        stamp(r.pic,'plant_indoor',l+1,t+2);stamp(r.pic,'flowers',l+12,t+2)
    pads={1:[('s',-4,-3),('c',5,-3)],2:[('s',5,-3),('sw',-4,4)],3:[('c',-4,4),('se',5,4)],
          4:[('c',5,4),('sw',-4,-3)],5:[('sw',5,4),('e',-4,4)],6:[('se',-4,4),('w',-4,-3)],
          7:[('se',-4,-3),('e',5,-3)],8:[('e',5,4),('nw',-4,4)],9:[('nw',5,-3),('w',-4,4)],
          10:[('w',5,4),('ne',5,4)],11:[('ne',-4,-3),('n',0,3)],12:[('s',0,-1),('n',-4,-3)]}
    for num,ends in pads.items():
        pair=[(cent[k][0]+dx,cent[k][1]+dy) for k,dx,dy in ends]
        for i,p in enumerate(pair):
            r.pad(p,'#9ccdd5' if num!=12 else '#e6bc6a')
            other=pair[1-i]
            arrive=(other[0],other[1]+1 if ends[1-i][2]<1 else other[1]-1)
            r.pads.append((p,arrive,num))
    r.layout((cent['s'][0],cent['s'][1]+3),(cent['n'][0],cent['n'][1]-2))
    for i,k in enumerate(('c','se','w','ne'),1):r.fix['trainer'+str(i)]=cent[k]
    return r

def web():
    r=Room(56,(49,51),'#22403b');d=r.draw
    o=(24,26)
    outer=[(13,8),(32,8),(44,18),(44,35),(32,46),(14,46),(4,35),(4,18)]
    for scale in (.30,.57,.80,1):
        ring=[(round(o[0]+(x-o[0])*scale),round(o[1]+(y-o[1])*scale)) for x,y in outer]
        d.line([center(p) for p in ring+[ring[0]]],fill='#7a8b81',width=3,joint='curve')
    for y in (7,44):
        for x in (2,9,17,35,40,47):stamp(r.pic,'tree',x,y)
    for p in outer+[(24,5),(24,46),(4,26),(44,26)]:d.line([center(o),center(p)],fill='#92998e',width=3)
    route=[o,(38,40),(32,46),(24,46),(24,41),(17,41),(8,33),(8,26),(4,26),(4,18),(10,12),(13,15),(17,11),(24,11),(24,5)]
    branch=[(13,15),(17,18),(13,21),(13,26),(8,26)]
    def strand(nodes):
        r.ft.line(nodes,fill=1,width=3)
        for x,y in nodes:r.ft.rectangle((x-1,y-1,x+1,y+1),fill=1)
        line=[center(p) for p in nodes]
        d.line(line,fill='#394c53',width=25,joint='curve')
        d.line(line,fill='#8ba9a3',width=17,joint='curve')
        d.line(line,fill='#d6e4c7',width=12,joint='curve')
        for a,b in zip(line,line[1:]):
            n=max(1,math.ceil(math.dist(a,b)/24))
            for j in range(n):
                x,y=(int(a[k]+(b[k]-a[k])*j/n) for k in (0,1));d.ellipse((x-2,y-2,x+2,y+2),fill='#f6f8d2')
    strand(route);strand(branch)
    for x,y in [o,(24,5),(13,26),(36,38),(24,11)]:
        r.rect((x-2,y-2,x+2,y+2),'wood')
    r.layout(o,(24,4));r.fix.update(trainer1=(36,38),trainer2=(13,26),trainer3=(24,10))
    stamp(r.pic,'plant_indoor',21,5);stamp(r.pic,'plant_indoor',27,5)
    return r

def adventure(n):
    # Platforms are separated by climbing holds, hanging ropes or paths of starlight.
    r=Room(n,(39,51),{160:'#705748',175:'#455f74',191:'#476344',215:'#22223e',226:'#41657b'}[n])
    d=r.draw
    if n in (160,191,215):
        stages={160:[(19,45),(9,41),(9,33),(16,33),(16,26),(27,26),(27,18),(18,18),(18,11),(20,6)],
                191:[(19,45),(19,39),(28,39),(28,30),(20,30),(20,24),(9,24),(9,15),(19,15),(19,6)],
                215:[(19,45),(19,40),(30,40),(30,31),(22,31),(22,25),(9,25),(9,17),(26,17),(26,10),(19,10),(19,6)]}[n]
        key={160:'rockfloor',191:'wood',215:'tiles'}[n]
        if n==191:
            for y in range(2,51,3):
                for x in range(1+y%4,38,3):stamp(r.pic,'tree',x,y)
        if n==160:
            for y in range(2,51,3):
                for x in range(y%3,39,3):stamp(r.pic,'boulder',x,y)
        if n==215:
            for i in range(300):
                x=int((i*9387.4)%(39*P));y=int((i*i*93.4)%(51*P));d.point((x,y),fill='#ddd4bc')
        for a,b in zip(stages,stages[1:]):
            r.paths([a,b],key,width=3,edge={160:'#a98470',191:'#b3a574',215:'#93c8de'}[n])
            pa,pb=center(a),center(b)
            if n==191:
                for e in (-13,13):
                    offset=(e,0) if a[0]==b[0] else (0,e)
                    d.line([(q[0]+offset[0],q[1]+offset[1]) for q in (pa,pb)],fill='#c6ac72',width=3)
            if n==160 and a[0]==b[0]:
                for y in range(min(pa[1],pb[1]),max(pa[1],pb[1]),12):
                    x=pa[0]+(y//12%3-1)*7;d.rounded_rectangle((x-3,y,x+3,y+3),1,fill='#bd927a',outline='#664d50')
        for i,(x,y) in enumerate(stages[1:-1:2],1):
            r.rect((x-2,y-2,x+2,y+2),key);r.fix['trainer'+str(i)]=(x+1,y)
        bx,by=stages[-1]
        r.rect((bx-4,by-3,bx+4,by+2),'wood' if n!=215 else 'tiles')
    elif n==175:
        # The loop encircles Korrina's dais. Each wheel point has space to fight a skater.
        loop=[(19,45),(9,43),(5,34),(5,19),(11,10),(27,10),(33,19),(33,34),(28,43),(19,45)]
        r.paths(loop,'pave',width=5,edge='#c6b383')
        for a,b in zip(loop,loop[1:]):d.line((center(a),center(b)),fill='#819bb1',width=2)
        r.paths([(19,45),(19,25)],'bridge',width=3,edge='#a2abac');r.rect((14,20,24,28),'tiles')
        for i,p in enumerate([(9,42),(6,23),(17,10),(32,30)],1):r.fix['trainer'+str(i)]=p
        bx,by=19,23
    else:
        # Four colour-coded cube banks and their switches surround the central ice bridge.
        for j,(x,y,col) in enumerate([(8,36,'#d598b9'),(30,36,'#849fcf'),(8,20,'#98bc96'),(30,20,'#d6c681')],1):
            r.rect((x-4,y-5,x+4,y+5),'ice');r.pad((x,y),col)
            r.fix['trainer'+str(j)]=(x+2,y-2)
            r.objects.append({'kind':'kalos_ice_switch','at':[x,y],'color':('pink','blue','green','yellow')[j-1],'native_fixture':True})
        for a,b in [((19,46),(19,6)),((8,36),(30,36)),((8,20),(30,20))]:r.paths([a,b],'ice',3,edge='#aad1d2')
        for x,y in [(8,36),(30,36),(8,20),(30,20)]:r.pad((x,y),{8:{36:'#d598b9',20:'#98bc96'},30:{36:'#849fcf',20:'#d6c681'}}[x][y])
        bx,by=19,6
        r.rect((15,3,23,9),'ice')
    r.rect((16,44,22,48),'tiles')
    r.layout((19,46),(bx,by))
    return r

def install(areas):
    by={a.number:a for a in areas}
    gyms=[web(),fairy(),*(adventure(n) for n in (160,175,191,215,226))]
    for r in gyms:
        a=by[r.n]
        for w in a.warps:w['at']=r.return_gate
        for other in areas:
            for w in other.warps:
                if w['to']['map']==a.mid:w['to']['at']=list(r.entry)
        for src,dst,num in r.pads:
            to={'region':'kalos','map':a.mid,'at':list(dst),'kalos_native':True}
            if num==12:to['kalos_requires']=['k_badge_6']
            a.warps.append({'at':list(src),'trigger':'step','to':to,'source_warp':'gym_teleporter_'+str(num)})
        r.anchors(a)
