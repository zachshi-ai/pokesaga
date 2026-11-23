"""Author the second through eighth stadiums on Emerald's 16-pixel field grid."""
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageOps
from kalos_gym_rooms import tile, sprite
from build_galar_grass_gym import pack, stamp, warp, write
from galar_gym_architecture import wings, floor, pitch_edges

ROOT=Path(__file__).resolve().parents[1]
MAPS=ROOT/'content/regions/galar/maps'
OUT=ROOT/'assets/galar/league_gyms'
PROPS=ROOT/'assets/emerald/field'
SW=ROOT/'assets/switch_fields/props'
LAND=ROOT/'assets/island_landmarks'
FACILITIES={
 2:('galar_hulbury',(6,8),'水舟竞技场','水流控制室','#296f91','#89cee1','arena_mint'),
 3:('galar_motostoke_stadium',(5,3),'机擎竞技场','捕捉竞赛场','#ad523e','#edaa62','arena_clay'),
 4:('galar_stow',(16,8),'溯传竞技场','旋转座椅赛道','#9b714a','#dfa464','arena_brown'),
 5:('galar_ballonlea_fairy_room',(6,3),'舞姿竞技场','选拔剧场','#a16c88','#e4bad5','arena_mauve'),
 6:('galar_circhester',(12,8),'战竞竞技场','陷阱探测场','#707d85','#bdd6d9','arena_ice'),
 7:('galar_spikemuth_club_room',(6,3),'尖钉镇道馆','封锁商店街','#626075','#bd99a8','office_tile'),
 8:('galar_hammerlocke_castle_room',None,'拳关竞技场','宝物库训练厅','#4e7882','#beaa73','ruin_tile')}
def data(path):return json.loads(path.read_bytes())
def mid(n,part):return 'galar_gym_%d_%s'%(n,part)
def texture(name):
    return Image.open(LAND/(name+'.png')).convert('RGB').crop((0,0,16,16))
def bitmap(tiles,ground,wall):
    h,w=tiles.shape;im=Image.new('RGB',(w*16,h*16))
    for y in range(h):
        for x in range(w):im.paste(wall if tiles[y,x] else ground,(x*16,y*16))
    return im
def art(im,name,xy,group=SW):
    im2=Image.open(group/(name+'.png')).convert('RGBA');stamp(im,im2,xy)
def save(n,part,im,tiles,spawn,warps,meta):
    name=mid(n,part);png=OUT/(name+'.png');im.save(png,optimize=True)
    w,h=tiles.shape[1],tiles.shape[0]
    obj={'name':FACILITIES[n][2]+'・'+(FACILITIES[n][3] if part=='mission' else ('地下舞台' if n==7 else '对战场')),
         'size':[w,h],'spawn':spawn,'tiles':tiles.tolist(),'biome':'city','style':'gym','npcs':[],'objects':[],
         'galar_facility':{'number':n,'part':part,**meta},'galar_power_spot':part=='pitch' and n!=7,'warps':warps,
         'hoenn_art':{'s':[w,h],'p':[],'t':pack(np.zeros((h,w),dtype='<u2')),'scene':['res://'+str(png.relative_to(ROOT)),0,0]}}
    write(MAPS/(name+'.json'),obj)
def little_props():
    # Raised valves, shutters and arrows are actor-sized sprites, so their collision follows their state.
    def icon(name,w,h,draw):
        im=Image.new('RGBA',(w,h));draw(ImageDraw.Draw(im));im.save(PROPS/('galar_gym_'+name+'.png'),optimize=True)
    for key,c in [('red','#df6757'),('yellow','#efd65f'),('blue','#59afdc')]:
        for active in [False,True]:
            def valve(d):
                d.rounded_rectangle((1,13,18,23),2,fill='#687f82',outline='#3e5558')
                d.ellipse((0,5,18,17),fill='#9caeab',outline='#3c5659')
                d.ellipse((3,1,16,13),fill=c,outline='#455d55',width=2)
                d.line((5,7,14,7),fill='#fcf4c2',width=2)
                if active:d.line((9,3,9,12),fill='#fcf4c2',width=2)
            icon(key+('_on' if active else '_off'),20,24,valve)
    def stream(d):
        d.rectangle((0,0,15,24),fill='#6799ac');d.rectangle((0,20,15,27),fill='#92d3e0')
        for x in [1,4,9,12]:d.line((x,0,x,23-(x%4)),fill='#c4edf3',width=2)
        d.line((0,27,16,27),fill='#e0f6df',width=2)
    icon('water',16,28,stream)
    def barrier(d):
        d.rectangle((1,7,14,16),fill='#755e53',outline='#48494a')
        d.line((1,6,15,6),fill='#e3bb72',width=3)
        for x in [2,11]:d.rectangle((x,1,x+2,17),fill='#8a705c',outline='#59544c')
    icon('rail',16,18,barrier)
    def pit(d):
        d.ellipse((0,4,18,17),fill='#8d8274',outline='#514f4b')
        d.ellipse((2,5,16,14),fill='#413f43');d.line((4,15,12,16),fill='#bba68b')
    icon('pit',19,18,pit)
    directions=[(0,-1),(1,0),(0,1),(-1,0)]
    for index,(dx,dy) in enumerate(directions):
        def cup(d):
            d.ellipse((0,12,25,26),fill='#624f61',outline='#453f4e')
            d.pieslice((1,1,24,23),0,180,fill='#c99c71',outline='#795c51',width=2)
            d.ellipse((1,4,23,14),fill='#6b7183',outline='#eed7a2',width=2)
            x,y=12+dx*7,9+dy*5
            d.line((12-dx*4,9-dy*3,x,y),fill='#eee9bc',width=3)
            d.polygon([(x+dx*2,y+dy*2),(x-dx*3-dy*3,y-dy*3+dx*3),(x-dx*3+dy*3,y-dy*3-dx*3)],fill='#eee9bc')
        icon('cup'+str(index),26,27,cup)
def connect(n):
    source,at,*_=FACILITIES[n];file=MAPS/(source+'.json');d=data(file);tiles=d['tiles']
    if at is None:
        walk=[(x,y) for y in range(1,len(tiles)//2) for x,c in enumerate(tiles[y][1:-1],1) if c not in (1,2,6,7) and tiles[y+1][x] not in (1,2,6,7)]
        at=min(walk,key=lambda p:abs(p[0]-len(tiles[0])//2)+p[1])
    x,y=at
    assert not any(tuple(w['at'])==at and w['to']['map']!=mid(n,'mission') for w in d['warps']), (source,at)
    d['warps']=[w for w in d['warps'] if w['to']['map']!=mid(n,'mission')]
    d['warps'].append(warp(at,mid(n,'mission'),[14,40]))
    props=d['hoenn_art']['p'];marker='res://assets/galar/league_gyms/entry_%d.png'%n
    props[:]=[p for p in props if p[0]!=marker]
    if n in [2,4,6]:
        im=Image.open(SW/'pitch.png').convert('RGBA');colors=np.array(im);c=np.array(tuple(bytes.fromhex(FACILITIES[n][4][1:])))
        mask=(colors[:,:,1].astype(int)>colors[:,:,0].astype(int)+14)&(colors[:,:,3]>0)
        colors[:,:,:3][mask]=(0.4*colors[:,:,:3][mask]+.6*c).astype('uint8')
        im=Image.fromarray(colors)
        for yy in range(y-2,y+1):
            for xx in range(x-2,x+3):tiles[yy][xx]=1
        im.save(OUT/('entry_%d.png'%n));props.append([marker,x,y,[im.width//2,im.height-1]])
    else:
        im=Image.new('RGBA',(22,14));dr=ImageDraw.Draw(im);dr.rounded_rectangle((0,2,21,13),2,fill=FACILITIES[n][4],outline='#40505a')
        dr.polygon([(5,10),(11,4),(17,10),(11,7)],fill=FACILITIES[n][5]);im.save(OUT/('entry_%d.png'%n));props.append([marker,x,y,[11,13]])
    tiles[y][x]=0;tiles[y+1][x]=0;write(file,d);return (source,at)
def mission(n,src,at):
    w,h=29,43;g=np.zeros((h,w),int);g[:2,:]=1;g[:,[0,1,-1,-2]]=1;g[-1,:]=1;g[1,14]=0;g[-1,14]=0
    base=texture(FACILITIES[n][6]);wall=tile('stone')
    m={'trainers':[],'gates':[]};sets=[];lines=[];patches=[]
    def row(y,x,style='stone',stage=None):
        g[y,2:w-2]=1;g[y,x-1:x+2]=0;lines.append((y,x,style))
        if stage is not None:m['gates'].append({'x':x,'y':y,'stage':stage})
    def prop(x,y,what,kind=SW,block=True):
        if block:g[y,x]=1
        sets.append((x,y,what,kind))
    if n==2:
        m['valves']=[[7,38,'red'],[22,30,'yellow'],[7,22,'blue'],[21,14,'red']]
        for i,(y,x,c,on) in enumerate([(34,8,'red',True),(26,21,'yellow',True),(18,8,'blue',True),(10,20,'red',False)]):
            g[y-1,x+(3 if x<13 else -3)]=1
            row(y,x,'water');m['gates'].append({'x':x,'y':y,'color':c,'open_on':on})
            for xx in ([5,18] if i%2 else [12,21]):prop(xx,y+2,'trough',LAND)
        m['trainers']=[[12,35],[17,27],[13,19]]
    elif n==3:
        m['pens']=[[6,30],[21,23],[9,14]];m['trainers']=[[5,28],[22,21],[8,12]]
        for x,y in m['pens']:
            for xx in range(x-3,x+4):
                for yy in range(y-2,y+3):patches.append((xx,yy,'darkgrass'))
            prop(x+3,y+1,'braziers',LAND);prop(x-3,y-1,'hay')
        row(8,14,'brick',5);prop(5,35,'camp');prop(23,32,'barn');prop(15,17,'crate')
    elif n==4:
        m['cups']=[]
        for i,(y,x,spin,endx) in enumerate([(34,8,1,21),(23,20,3,8),(12,9,1,19)]):
            row(y,x,'rail');g[y,x-1:x+2]=1
            m['cups'].append({'at':[x,y+3],'goal':spin,'track':[[x,y+2],[endx,y+2],[endx,y-2]],'landing':[endx,y-2]})
            m['trainers'].append([endx,y-3]);row(y-5,endx,'rail',i+1)
            prop(4 if i%2==0 else 24,y+1,'coil');prop(24 if i%2==0 else 4,y+1,'barrel',LAND)
    elif n==5:
        for i,(y,x) in enumerate([(33,10),(22,19),(11,9)]):
            row(y,x,'curtain',i+1);m['trainers'].append([x,y+2])
            for xx in [4,23]:prop(xx,y+1,'bulb');prop(xx,y+4,'festival_gate',LAND)
    elif n==6:
        m['traps']=[];m['traps_shield']=[];m['checkpoints']=[[14,40],[8,28],[21,17],[12,8]]
        for i,(y,x) in enumerate([(30,8),(19,21),(9,12)]):
            row(y,x,'ridge');m['gates'].append({'x':x,'y':y,'checkpoint':i+1})
            # Each chamber has a winding safe channel and a few optional safe dead ends.
            below=40 if i==0 else [0,28,17][i]
            for yy in range(y+2,below):
                safe=round(([14,8,21][i]*(yy-y)+x*(below-yy))/(below-y))+round(2*math.sin(yy*.7))
                for xx in range(3,w-3):
                    if abs(xx-safe)>=2 and (xx*9+yy*7)%7!=2:m['traps'].append([xx,yy])
                    ice_route=safe+round(2*math.sin(yy*1.1))
                    if abs(xx-ice_route)>=2 and (xx*3+yy)%9!=3:m['traps_shield'].append([xx,yy])
            prop(3,y+3,'cairn');prop(25,y+2,'cairn')
        m['trainers']=[[14,37],[8,26],[16,21],[13,12]]
        for tx,ty in m['trainers']:
            for key in ['traps','traps_shield']:
                m[key]=[p for p in m[key] if abs(p[0]-tx)+abs(p[1]-ty)>1]
    elif n==7:
        for i,(y,x) in enumerate([(35,9),(28,20),(21,8),(14,19),(7,12)]):
            row(y,x,'shutter',i+1);m['trainers'].append([x+2,y+2])
            prop(3,y+1,'shutter');prop(24,y+1,'shutter');prop(4 if i%2==0 else 23,y+4,'crate')
    else:
        for i,(y,x) in enumerate([(33,12),(22,17),(11,12)]):
            row(y,x,'brass',i+1);m['trainers'].append([x,y+2])
            prop(4,y+1,'columns');prop(24,y+1,'columns')
            prop(7,y+5,'archive' if i!=1 else 'amethyst',LAND);prop(21,y+5,'ruin_idol',LAND)
    wings(n,g)
    im=bitmap(g,base,wall);floor(im,n,m);d=ImageDraw.Draw(im)
    for xx,yy,k in patches:im.paste(tile(k),(xx*16,yy*16))
    for y,x,style in lines:
        c=FACILITIES[n][4];light=FACILITIES[n][5]
        for xx in range(2,w-2):
            if abs(xx-x)<=1:continue
            rect=(xx*16,y*16,xx*16+15,y*16+15)
            d.rectangle(rect,fill=c,outline='#4a5258')
            d.line((rect[0]+2,rect[1]+2,rect[2]-1,rect[1]+2),fill=light,width=2)
            if style=='water':d.line((rect[0],rect[1]+8,rect[2],rect[1]+8),fill='#99c4c9',width=2)
            if style in ['curtain','shutter']:d.line((rect[0]+4,rect[1]+4,rect[0]+4,rect[3]-1),fill=light)
    for c in m.get('cups',[]):
        pts=[(x*16+8,y*16+8) for x,y in [c['at'],*c['track']]]
        d.line(pts,fill='#666875',width=9);d.line(pts,fill='#d5c0a1',width=3)
        xx,yy=c['track'][1];d.ellipse((xx*16+1,yy*16+1,xx*16+15,yy*16+15),fill='#b37364',outline='#e8d69d',width=2)
    if n==6:
        for x,y in m['checkpoints']:d.rectangle((x*16+1,y*16+2,x*16+14,y*16+12),outline='#b97846',width=2)
    for x,y,name,group in sorted(sets,key=lambda p:p[1]):art(im,name,(x,y),group)
    for x,y in [(14,1),(14,h-1)]:d.polygon([(x*16+2,y*16+11),(x*16+8,y*16+4),(x*16+14,y*16+11)],fill=FACILITIES[n][5])
    save(n,'mission',im,g,[14,40],[warp((14,h-1),src,(at[0],at[1]+1)),warp((14,1),mid(n,'pitch'),(14,24))],m)
def pitch(n):
    g=np.zeros((27,29),int);g[:6,:]=1;g[:,0:3]=1;g[:,-3:]=1;g[-1,:]=1;g[-1,14]=0
    old=Image.open(ROOT/'assets/galar/grass_gym/galar_turffield_pitch.png').convert('RGB');im=old.copy()
    c1=FACILITIES[n][4];c2=FACILITIES[n][5]
    for y in range(6,27):
        for x in range(3,26):
            im.paste(texture(FACILITIES[n][6]),(x*16,y*16))
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((63,108,400,376),12,outline=c2,width=3);d.line((64,238,400,238),fill=c2,width=2)
    d.ellipse((177,183,287,293),outline=c2,width=3)
    cx,cy=232,239
    symbols={2:[(0,-19),(13,2),(11,14),(0,20),(-12,14),(-14,2)],3:[(-14,14),(-12,-6),(-3,0),(3,-22),(12,-5),(17,10),(5,21)],4:[(-17,7),(-13,-11),(-6,-9),(-3,-17),(3,-16),(8,-10),(15,-9),(17,4),(6,15),(-12,14)],5:[(0,-21),(6,-6),(18,-3),(8,7),(10,19),(0,12),(-13,20),(-10,7),(-19,-3),(-5,-7)],6:[(0,-20),(17,-1),(8,17),(-9,17),(-17,-2)],7:[(-15,17),(-4,-15),(2,-3),(14,-18),(7,13),(0,7)],8:[(-17,10),(-9,-8),(9,-19),(5,-6),(19,-3),(9,15),(-4,20),(1,8)]}
    d.polygon([(cx+x,cy+y) for x,y in symbols[n]],fill=c1,outline=c2,width=2)
    if n==7:
        for k in (3,25):art(im,'shutter',(k,4))
        for x in [2,26]:art(im,'concert',(x,8))
    if n==8:
        for x in (2,26):
            for y in (8,16,24):art(im,'columns',(x,y))
    pitch_edges(im,n)
    save(n,'pitch',im,g,[14,24],[warp((14,26),mid(n,'mission'),(14,2))],{})
def gear():
    variants={'water':'538ab9','fire':'cf6d4a','fighting':'a76a4c','ghost':'826797','fairy':'ce9cae','rock':'aa956b','ice':'80b9bf','dark':'665d77','dragon':'6b80a1'}
    for key,rgb in variants.items():
        c=np.array(tuple(bytes.fromhex(rgb)))
        for cut in ['walk','surf']:
            im=Image.open(ROOT/'assets/galar/grass_gym'/('uniform_'+cut+'.png')).convert('RGBA');pix=np.array(im)
            for color,level in [((83,156,85),.86),((145,207,99),1.22),((201,219,184),1.48),((74,106,71),.6)]:
                mask=np.all(pix[:,:,:3]==color,axis=2)&(pix[:,:,3]>0)
                pix[:,:,:3][mask]=np.clip(c*level,0,255)
            Image.fromarray(pix).save(OUT/('uniform_'+key+'_'+cut+'.png'),optimize=True)
    for number,name in [(37,'vulpix'),(850,'sizzlipede'),(607,'litwick')]:
        im=Image.open(ROOT/'assets/mon'/(str(number)+'.png')).convert('RGBA')
        im=im.crop(im.getbbox());im.thumbnail((24,26),Image.Resampling.NEAREST)
        im.save(PROPS/('galar_gym_'+name+'.png'),optimize=True)
def version_fields():
    for n in [4,6]:
        for part in ['mission','pitch']:
            f=OUT/(mid(n,part)+'.png');im=Image.open(f).convert('RGB')
            arr=np.asarray(im).astype('float32');lum=arr[:,:,0]*.21+arr[:,:,1]*.67+arr[:,:,2]*.12
            if n==4:dark,light=np.array([48,43,67]),np.array([192,165,203])
            else:dark,light=np.array([43,84,108]),np.array([213,236,237])
            graded=dark[None,None,:]+((light-dark)[None,None,:]*lum[:,:,None]/255)
            converted=np.clip(graded*.75+arr*.25,0,255).astype('uint8')
            if part=='pitch':converted[:100,:,:]=np.array(im)[:100,:,:]
            Image.fromarray(converted).save(OUT/(mid(n,part)+'_shield.png'),optimize=True)
def main():
    OUT.mkdir(exist_ok=True,parents=True);little_props();gear()
    for n in FACILITIES:
        entrance,at=connect(n);mission(n,entrance,at);pitch(n)
    version_fields()
    path=MAPS.parent/'region.json';r=data(path)
    for n in FACILITIES:
        for part in ['mission','pitch']:
            k=mid(n,part)
            if k not in r['maps']:r['maps'].append(k)
    write(path,r)
if __name__=='__main__':main()
