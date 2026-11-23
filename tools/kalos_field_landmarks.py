"""Flat walk surfaces and pixel-art structures for Kalos's camera-heavy landmarks."""
import math
from functools import lru_cache
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from kalos_field_palette import pattern
from kalos_gym_rooms import sprite


def ground_mask(pic, mask, texture, p):
    if not mask.any():return
    c=np.asarray(texture.resize((p,p),Image.Resampling.NEAREST));size=pic.size
    # Paint the player plane before drawing its rails, thresholds and wall-mounted props.
    result=Image.fromarray(np.tile(c,(mask.shape[0],mask.shape[1],1)))
    pic.paste(result,(0,0),Image.fromarray(mask.astype('uint8')*255).resize(size,Image.Resampling.NEAREST))


def floor_tile(key):return Image.fromarray(pattern(key))


def display(pic,kind,x,y,p,scale=1):
    a=furniture_sprite(kind);w,h=round(a.width*p/16*scale),round(a.height*p/16*scale);a=a.resize((w,h),Image.Resampling.NEAREST)
    pic.paste(a,(round((x+.5)*p-w/2),round((y+1)*p-h)),a)


def interior_mask(m):
    s=np.asarray(m['physics']['collision'],bool)
    # Preserve secondary chambers separated by scripted stairs and teleports.
    return ~s


def rim(pic,walk,p,top,front):
    d=ImageDraw.Draw(pic)
    for y,x in np.argwhere(walk&~np.roll(walk,-1,axis=0)):
        X=int(x*p);Y=int((y+1)*p);d.rectangle((X,Y,X+p-1,Y+3),fill=front);d.line((X,Y,X+p-1,Y),fill=top)
    for y,x in np.argwhere(walk&~np.roll(walk,1,axis=0)):
        X=int(x*p);Y=int(y*p);d.line((X,Y-1,X+p-1,Y-1),fill=top)


def inlay(pic,walk,p,paint):
    # Limit railings and decorated floors to the correct side of the collision map.
    layer=Image.new('RGBA',pic.size);d=ImageDraw.Draw(layer);paint(d)
    alpha=np.asarray(layer.getchannel('A')).copy();alpha*=np.repeat(np.repeat(walk,p,axis=0),p,axis=1)
    pic.paste(layer,(0,0),Image.fromarray(alpha))


def window(d,x,y,w,h,scheme):
    x,y,w,h=map(int,(x,y,w,h));dark,light,glass=scheme
    d.rounded_rectangle((x,y,x+w,y+h),w//2,fill=dark,outline='#4d5361',width=2)
    d.rounded_rectangle((x+2,y+2,x+w-2,y+h-2),max(1,w//2-1),fill=glass)
    d.line((x+w//2,y+2,x+w//2,y+h-1),fill=light,width=2)
    d.line((x+2,y+h//2,x+w-2,y+h//2),fill=light,width=2)
    d.line((x+3,y+h//2-2,x+w//2-1,y+4),fill='#ece5ca')


def chamber(m,p):
    n=m['kalos_zone'];walk=interior_mask(m);h,w=walk.shape;Y,X=np.indices(walk.shape)
    scheme='champion' if n>=255 else 'flame' if n in (247,251) else 'tide' if n in (248,252) else 'iron' if n in (249,253) else 'dragon' if n in (250,254) else 'foyer'
    # Pools, furnace trenches, steel gratings and nave walls lie BELOW the walking deck.
    ink,trim,light,lower,accent={
        'flame':('#6c4f51','#a87758','#e7c892','#4d373b','#cb8057'),
        'tide':('#496c7d','#82a5aa','#d0ddc5','#447da4','#66afbc'),
        'iron':('#586070','#9a9996','#ddd3ac','#3e4752','#a5afba'),
        'dragon':('#635c72','#9f929c','#dbccb4','#4a485d','#ac97bc'),
        'champion':('#736976','#b8a6a4','#eee2bc','#5c6374','#be8492'),
        'foyer':('#5f6975','#aa9b86','#e7d6ac','#475261','#9d7c79')
    }[scheme]
    pic=Image.new('RGB',(w*p,h*p),lower);d=ImageDraw.Draw(pic)
    distance=ndimage.distance_transform_edt(~walk)
    ground_mask(pic,(~walk)&(distance<=3.8),floor_tile('aqua' if scheme=='tide' else 'ash' if scheme=='flame' else 'stone' if scheme!='champion' else 'marble'),p)
    if scheme=='tide':
        for y in range(p,h*p,p*2):
            for x in range(p+(y//p%3)*p,w*p,4*p):d.arc((x,y,x+p,y+4),8,158,fill='#94c3c7',width=2)
    if scheme=='flame':
        for y in range(p,h*p,2*p):
            for x in range((y//p%3)*p,w*p,3*p):d.line((x,y,x+4,y-3,x+9,y-2),fill='#e1a56a',width=2)
    ground_mask(pic,walk,floor_tile('marble' if scheme in ('champion','foyer','tide') else 'cobble' if scheme in ('flame','dragon') else 'tile'),p)
    # Centre a tiled medallion at the playable arena's reference point. Its surface
    # is limestone with an emblem inlay; the surrounding water and fire never cover it.
    sx,sy=m['spawn'];cx=(sx+.5)*p;cy=(sy+.5)*p;boss=m['kalos_anchors'].get('story',m['spawn']);bx,by=(v+.5 for v in boss)
    def carpet(d):
        for xx in (-1,1):
            d.line((cx+xx*1.45*p,int(min(cy,by*p)),cx+xx*1.45*p,int(max(cy,by*p))),fill=trim,width=3)
        if scheme=='flame':
            for radius,col in ((3.4,ink),(3.15,light),(2.9,accent)):
                points=[(cx+math.cos(i*math.pi/4)*radius*p,cy+math.sin(i*math.pi/4)*radius*p*.67) for i in range(8)]
                d.line(points+[points[0]],fill=col,width=3)
            d.polygon([(cx-p*.7,cy+p*.3),(cx-p*.83,cy-p*.1),(cx-p*.3,cy-p*.56),(cx-p*.3,cy-p*.1),(cx+p*.35,cy-p),(cx+p*.65,cy-p*.2),(cx+p*.4,cy+p*.5)],outline=accent,width=3)
        elif scheme=='iron':
            for off in (-2.6,2.6):
                x=cx+off*p;d.rectangle((x-3,cy-3*p,x+3,cy+3*p),outline=ink,width=2)
                for k in range(-3,4):d.ellipse((x-2,cy+k*p-2,x+2,cy+k*p+2),fill=light,outline=ink)
            d.polygon([(cx,cy-1.3*p),(cx+4,cy-p),(cx+3,cy+p*.5),(cx-3,cy+p*.5),(cx-4,cy-p)],outline=accent,width=2);d.line((cx-8,cy+p*.5,cx+8,cy+p*.5),fill=ink,width=2)
        elif scheme=='dragon':
            for mult in (1,2,3):
                d.line([(cx-3.2*p,cy+(mult-2)*p),(cx-1.7*p,cy+(mult-2.7)*p),(cx,cy+(mult-2)*p),(cx+1.7*p,cy+(mult-2.7)*p),(cx+3.2*p,cy+(mult-2)*p)],fill=accent,width=3)
        elif scheme=='champion':
            for j in range(8):
                a=j*math.pi/4;x=cx+math.cos(a)*1.42*p;y=cy+math.sin(a)*p
                d.ellipse((x-p*.71,y-p*.55,x+p*.71,y+p*.55),outline=accent,width=3)
            d.ellipse((cx-p*.64,cy-p*.53,cx+p*.64,cy+p*.53),outline=trim,width=3)
        else:
            for radius,col,width in [(3.25,ink,3),(3.08,light,3),(2.88,accent,4),(.96,accent,3)]:
                d.ellipse((cx-radius*p,cy-radius*.67*p,cx+radius*p,cy+radius*.67*p),outline=col,width=width)
            for yy in (-1,1):
                for j in range(-2,3):
                    x=cx+j*p;d.arc((x-p*.55,cy+yy*p*.9-3,x+p*.55,cy+yy*p*.9+4),2,170,fill=accent,width=2)
    inlay(pic,walk,p,carpet);rim(pic,walk,p,light,ink)
    # Cathedral glazing and the four chambers' recessed bays follow the north walls,
    # not the floor, with accurate public entry and return positions left clear.
    top=walk&~np.roll(walk,1,axis=0);occupied=[]
    for y,x in np.argwhere(top):
        if y<4 or x<2 or x>w-3 or walk[y-3:y,x-1:x+2].any() or any(abs(x-a)<4 and abs(y-b)<3 for a,b in occupied):continue
        occupied.append((x,y));X=int(x*p);Y=int(y*p)
        d.rectangle((X-p,Y-3*p,X+p-1,Y-1),fill=trim,outline=ink,width=2)
        if scheme=='champion':
            window(d,X-p+3,Y-3*p+2,p-1,2*p,(ink,light,'#b59fbd'));window(d,X+1,Y-3*p+2,p-1,2*p,(ink,light,'#8fbbbf'))
        elif scheme=='flame':
            d.polygon([(X-8,Y-p),(X-5,Y-2*p+2),(X,Y-2*p+7),(X+5,Y-3*p+4),(X+9,Y-p)],fill='#d57952',outline=ink)
            d.polygon([(X-4,Y-p),(X+3,Y-2*p+4),(X+6,Y-p)],fill='#f4d382');d.rectangle((X-9,Y-p,X+9,Y-p+4),fill=ink)
        elif scheme=='tide':
            window(d,X-8,Y-3*p+4,16,p*2,(ink,light,'#75abb9'));d.line((X-5,Y-2*p,X-5,Y-p+3),fill='#d4e6da',width=2)
        elif scheme=='iron':
            d.line((X-6,Y-p,X+5,Y-3*p+4),fill=light,width=3);d.line((X-8,Y-p-5,X+4,Y-p),fill=ink,width=3)
        else:display(pic,'statue',x,y-1,p,.85)
    for warp in m['warps']:
        x,y=warp['at'];d.rectangle((x*p+2,y*p+p-5,(x+1)*p-3,(y+1)*p-1),fill=accent,outline=ink)
    for kind,x,y,scale in m.get('kalos_furnishings',[]):display(pic,kind,x,y,p,scale)
    return pic


def laboratory(m,p):
    n=m['kalos_zone'];walk=interior_mask(m);h,w=walk.shape;pic=Image.new('RGB',(w*p,h*p),'#3c4c57');d=ImageDraw.Draw(pic)
    ground_mask(pic,walk,floor_tile('laboratory'),p);rim(pic,walk,p,'#d3ddbf','#788d8e')
    top=walk&~np.roll(walk,1,axis=0)
    for y,x in np.argwhere(top):
        X=int(x*p);Y=int(y*p);d.rectangle((X,Y-2*p,X+p-1,Y-1),fill='#b1bec1');d.rectangle((X,Y-5,X+p-1,Y-1),fill='#798d97');d.line((X,Y-p-2,X+p-1,Y-p-2),fill='#e6e6ca')
    # Actual field furniture is fitted by the same collision and doorway checks as residences.
    for kind,x,y,scale in m.get('kalos_furnishings',[]):display(pic,kind,x,y,p,scale)
    for row in m['warps']:
        x,y=row['at'];X=x*p;Y=y*p;d.rectangle((X,Y+1,X+p-1,Y+p-1),fill='#90a8ac',outline='#667b88');d.line((X+p//2,Y+2,X+p//2,Y+p-2),fill='#dbe4d1')
    return pic


def cave(pic,m,p):
    n=m['kalos_zone'];walk=interior_mask(m);water=np.asarray(m['physics'].get('water',np.zeros_like(walk)),bool)
    key='snow' if 313<=n<=317 else 'ash' if n==350 else 'ground' if n not in (319,) else 'marsh'
    # Walkable cave floors remain readable when source crystals, ceilings, and walls
    # project in front of the player. Rails are confined to the old mine galleries.
    ground_mask(pic,walk&~water,floor_tile(key),p);ground_mask(pic,walk&water,floor_tile('water'),p);rim(pic,walk,p,'#bac2b2' if key=='snow' else '#b1a182','#6a6b70')
    dist=ndimage.distance_transform_edt(~walk);d=ImageDraw.Draw(pic)
    for y,x in np.argwhere((dist>=1)&(dist<=2.5)&np.roll(walk,-1,axis=0)):
        if x%4 or y%2:continue
        X=int((x+.5)*p);Y=int((y+1)*p)
        if n in range(305,309) or 313<=n<=317:
            for a,b,ss in [(0,2,1),(-5,0,.55),(5,-1,.62)]:
                d.polygon([(X+a-4*ss,Y+b-2),(X+a-3*ss,Y+b-10*ss),(X+a+2*ss,Y+b-18*ss),(X+a+5*ss,Y+b-6*ss),(X+a+2*ss,Y+b)],fill='#9fc7cf' if n>=313 else '#9dabbf',outline='#668097');d.line((X+a,Y+b-2,X+a+2*ss,Y+b-13*ss),fill='#e5e5da')
        elif n in range(343,349) and x%8==0:
            d.rectangle((X-3,Y-p-2,X+3,Y-1),fill='#936f56',outline='#5f5652');d.rectangle((X-6,Y-p-3,X+6,Y-p+1),fill='#a58d66')
    return pic


def assembly(m,p):
    n=m['kalos_zone'];walk=interior_mask(m);h,w=walk.shape;pic=Image.new('RGB',(w*p,h*p),'#52646b');d=ImageDraw.Draw(pic)
    ground_mask(pic,~walk,floor_tile('steel'),p);ground_mask(pic,walk,floor_tile('tile'),p)
    # Three conveyor lines run parallel to the walkways. The conveyors are painted
    # only on the factory machinery's solid footprint, never under the player's feet.
    def lines(d):
        for x,y,r,b in [(6,6,30,8),(6,12,11,25),(22,15,31,17),(14,27,29,29)]:
            X,Y,R,B=x*p,y*p,(r+1)*p,(b+1)*p;d.rectangle((X,Y,R,B),fill='#657580',outline='#465761',width=3)
            for k in range(X+4,R,12):d.line((k,Y+3,k,B-3),fill='#a7b4af',width=3)
            for k in range(X+10,R,36):
                c=(Y+B)//2;d.ellipse((k-5,c-5,k+5,c+5),fill='#dfcfc2',outline='#414e56');d.pieslice((k-5,c-5,k+5,c+5),180,360,fill='#ba6c67',outline='#414e56');d.point((k,c),fill='#eee6c6')
    inlay(pic,~walk,p,lines);rim(pic,walk,p,'#eee1a9','#7a7e79')
    def floor_mark(d):
        # Painted worker aisles guide the path from the door around the assembly floor.
        for side in (-1,1):
            pts=[((9.5+side*.15)*p,30*p),((9.5+side*.15)*p,22*p),((17+side*.15)*p,22*p),((17+side*.15)*p,10*p),((25+side*.15)*p,10*p)]
            d.line(pts,fill='#cdac63' if side==1 else '#e5d6a0',width=2)
    inlay(pic,walk,p,floor_mark)
    for kind,x,y,scale in m.get('kalos_furnishings',[]):display(pic,kind,x,y,p,scale)
    return pic


def aquarium(pic,m,p):
    walk=interior_mask(m);water=np.asarray(m['physics'].get('water',np.zeros_like(walk)),bool)
    pic=Image.new('RGB',pic.size,'#758e9b');ground_mask(pic,~walk,floor_tile('tank'),p);ground_mask(pic,walk&~water,floor_tile('cobble'),p)
    rim(pic,walk,p,'#c9d3b9','#68858a');d=ImageDraw.Draw(pic)
    # Tanks are framed windows on the north wall. A visitor walks the dry tiled gallery below.
    for x,y,ww in [(8,9,5),(24,6,6),(25,15,4)]:
        X,Y=x*p,y*p;W=ww*p;H=2*p
        if walk[y,x]:continue
        d.rounded_rectangle((X-W//2,Y-H,X+W//2,Y),5,fill='#a2b8b4',outline='#4f6873',width=3)
        d.rounded_rectangle((X-W//2+4,Y-H+4,X+W//2-4,Y-4),4,fill='#79adbb',outline='#d7e2c6')
        for offset in (-.25,.18):
            a=X+int(W*offset);b=Y-H//2;d.ellipse((a-5,b-3,a+4,b+3),fill='#d49b77',outline='#866f70');d.polygon([(a+4,b),(a+9,b-4),(a+9,b+3)],fill='#be8d73')
        for i in range(4):d.ellipse((X-i*3,Y-H+6+i*3,X-i*3+2,Y-H+8+i*3),outline='#c2e2dc')
    for kind,x,y,scale in m.get('kalos_furnishings',[]):display(pic,kind,x,y,p,scale)
    return pic

@lru_cache(None)
def furniture_sprite(kind):
    if kind.startswith('xy_'):
        from kalos_exhibits import px_sprite
        return px_sprite(kind)
    if not kind.startswith('kalos_'):return sprite(kind)
    name=kind[6:];w={'conveyor':72,'packer':64,'tanks':74,'workbench':50,'samples':44,'cafe':40,'tea':40,'writing':42,'cupboard':36,'stove':30,'crate':40,'brazier':27,'sluice':32,'swordrack':32,'dragonpillar':32,'rosette':37}[name]
    h=56 if name in ('dragonpillar','rosette','sluice','swordrack','brazier') else 42 if name in ('packer','tanks','samples','stove','cupboard') else 30
    pic=Image.new('RGBA',(w,h));d=ImageDraw.Draw(pic);outline='#4a5660';blue='#8da8ac';cream='#dce0c5';wood='#aa8766'
    def box(b,col,border=outline):d.rectangle(b,fill=col,outline=border)
    def circle(b,col,border=outline):d.ellipse(b,fill=col,outline=border)
    if name in ('brazier','sluice','swordrack','dragonpillar','rosette'):
        c=w//2;box((4,h-8,w-5,h-1),'#9c9391');box((7,h-11,w-8,h-7),'#d4c4a2')
        if name=='brazier':
            box((c-4,30,c+4,h-12),'#9f8167');d.polygon([(2,25),(w-3,25),(w-7,33),(8,33)],fill='#ae876a',outline=outline)
            d.polygon([(5,25),(3,18),(8,10),(10,16),(16,2),(18,13),(22,9),(24,20),(21,25)],fill='#cc7957',outline='#9b6255')
            d.polygon([(9,25),(10,17),(12,20),(16,11),(19,21),(18,25)],fill='#f3d18a')
        if name=='sluice':
            box((5,7,w-6,h-11),'#95a8a8');box((8,11,w-9,h-16),'#5a889a');d.line((10,13,10,h-17),fill='#c5e2d9',width=2)
            for y in (14,24,34):d.line((8,y,w-8,y-1),fill='#81b7bd',width=2)
            d.rounded_rectangle((c-8,1,c+8,16),6,fill='#d1c8a5',outline=outline);circle((c-5,4,c+4,12),'#7199a0')
        if name=='swordrack':
            box((5,27,w-6,h-13),'#849099');d.polygon([(c,2),(c+4,9),(c+2,32),(c-2,32),(c-4,9)],fill='#c3d7d4',outline='#5b697e');d.line((c,5,c,30),fill=cream);box((c-9,30,c+9,33),'#bba474');box((c-2,33,c+2,41),'#746760')
        if name=='dragonpillar':
            box((11,28,21,h-13),'#b3a4aa');d.polygon([(4,24),(8,15),(6,6),(13,12),(19,2),(21,14),(28,17),(26,22),(18,21),(21,28),(11,31)],fill='#a18da5',outline='#66647e');d.line((19,3,16,15,20,19),fill='#d3bfc2',width=2);d.point((22,17),fill='#f5df99')
        if name=='rosette':
            box((7,20,w-8,h-12),'#d6c8c0');window(d,3,2,w-7,34,('#817a92','#e4cca8','#b99dc5'))
            for i in range(6):
                a=i*math.pi/3;x=c+round(6*math.cos(a));y=16+round(6*math.sin(a));circle((x-3,y-3,x+3,y+3),'#9ebbc5' if i%2 else '#deb4ad','#a79db3')
    elif name in ('conveyor','packer'):
        bottom=h-4;box((3,bottom-11,w-4,bottom+1),'#7e8b93');box((2,bottom-16,w-3,bottom-5),'#b5c1ba');box((5,bottom-14,w-6,bottom-7),'#536a76')
        for x in range(5,w-5,5):d.line((x,bottom-13,x+2,bottom-8),fill='#8b9fa7')
        for x in (6,w-12):box((x,bottom+1,x+5,h-1),'#636d73');d.point((x+2,bottom+3),fill=cream)
        for x in (15,w-19):
            b=(x-4,bottom-19,x+4,bottom-11);circle(b,'#e4decc');d.pieslice(b,180,360,fill='#bd6a62',outline=outline);d.point((x,bottom-15),fill='#f9edca')
        if name=='packer':
            box((20,2,40,bottom-16),'#aaaeb2');box((23,4,37,11),'#58767e');d.line((25,8,31,8,32,6,35,6),fill='#bfe1ce');box((29,12,32,bottom-12),'#76858c');d.line((35,15,35,19),fill='#d49d60');d.line((24,15,24,23),fill=cream)
    elif name=='tanks':
        box((3,7,w-4,h-3),'#88a09e');box((0,3,w-1,h-10),'#ced4bd');box((3,6,w-4,h-14),'#6ea7b6');d.line((5,8,w-6,8),fill='#b4d9ce',width=2)
        d.line((8,13,13,8),fill='#bde0da',width=2); d.line((w-16,12,w-11,8),fill='#bde0da',width=2)
        for x,col in ((13,'#c78c67'),(37,'#a5c886'),(54,'#cf9b82')):
            y=18+(x%5);d.polygon([(x-5,y),(x-6,y-3),(x-9,y-4),(x-8,y+2)],fill=col,outline='#697f81');circle((x-5,y-4,x+4,y+2),col,'#637d84');d.point((x+2,y-2),fill=outline)
        for x in (11,31,57):d.line((x,h-15,x-2,h-20,x,h-22),fill='#578c81',width=2)
        for x in (6,11,w-8):circle((x,12,x+2,14),'#afdbd4','#9dc7c9')
        d.line((6,h-7,w-7,h-7),fill='#edf0d1');box((w//2-6,h-8,w//2+6,h-5),cream)
    elif name in ('samples','workbench'):
        y=h-12;box((2,y,w-3,h-2),blue);box((0,y-5,w-1,y+2),'#e0ddbd');d.line((4,h-6,w-6,h-6),fill='#71888d')
        box((6,y-15,20,y-6),'#7a9097');box((8,y-13,18,y-8),'#546d7b');d.line((10,y-10,14,y-10,16,y-12),fill='#a7cdbf')
        if name=='samples':
            box((22,1,w-4,y-7),'#bac8bd');box((24,3,w-6,y-10),'#779d9c')
            for xx in (26,34):circle((xx,8,xx+5,15),'#c4c7a3','#607c83');d.line((xx+1,7,xx+4,7),fill=cream,width=2)
        else:
            box((28,y-13,37,y-8),'#b7b5a6');d.line((33,y-20,38,y-16,35,y-11),fill=outline,width=3);d.line((32,y-20,35,y-18),fill=cream,width=2)
    elif name in ('cafe','tea','writing'):
        for x in (5,w-9):box((x,17,x+3,h-2),'#896b53');d.line((x+1,18,x+1,h-3),fill='#cbaa82')
        d.rounded_rectangle((2,9,w-3,23),3,fill='#a38367',outline=outline)
        d.rounded_rectangle((1,6,w-2,19),3,fill='#d2b68c' if name!='cafe' else '#cbb1a1',outline='#786755')
        d.line((5,8,w-6,8),fill='#e7d8ad')
        if name=='writing':
            box((8,7,19,14),'#e8deba','#a39d88');d.line((11,10,16,10),fill='#9b9e99');d.line((24,15,29,8),fill='#657d83',width=2)
        else:
            for x in (9,25):circle((x,9,x+6,14),'#e4dec8','#a9a39b');circle((x+1,7,x+5,11),'#e3d6bb','#6a7373');d.point((x+3,8),fill='#8b6e58')
            if name=='tea':circle((16,10,22,16),'#a9b9a0');d.line((16,12,14,10),fill=outline)
    elif name=='cupboard':
        box((4,2,w-5,h-2),wood);box((6,4,w-7,h-8),'#76614f');
        for y in (9,19):
            for x in (8,14,20,26):box((x,y,x+3,y+5),('#b58572','#92aaa1','#a59ab2')[(x+y)%3],'#655d59')
            box((5,y+6,w-6,y+8),'#bd9d76')
        d.line((6,h-6,w-7,h-6),fill='#d0b081')
    elif name=='stove':
        box((5,2,11,h-17),'#8e9795');box((2,h-21,w-3,h-2),'#868c87');box((6,h-17,w-8,h-6),'#656464');d.polygon([(8,h-8),(11,h-15),(13,h-12),(17,h-18),(19,h-8)],fill='#d9a765');d.line((4,h-4,w-5,h-4),fill=cream)
    else:
        box((1,8,w-2,h-2),wood);box((2,5,w-1,12),'#cab18a');d.line((3,h-4,w-4,11),fill='#90735a',width=3);d.line((6,6,6,h-3),fill='#d6ba8d',width=2)
    return pic


def civic_floor(pic,m,p):
    """Stone alleys, museum parquet, and Prism Tower quiz platforms have distinct walk surfaces."""
    n=m['kalos_zone'];walk=interior_mask(m);sx,sy=m['spawn'];d=ImageDraw.Draw(pic)
    if 79<=n<=82:
        ground_mask(pic,walk,floor_tile('steel'),p)
        def circuits(d):
            for sign in (-1,1):
                pts=[((sx+sign*5)*p,(sy-4)*p),((sx+sign*5)*p,(sy+2)*p),((sx+sign*3)*p,(sy+4)*p),((sx+sign*3)*p,(sy+6)*p)]
                d.line(pts,fill='#657887',width=4);d.line(pts,fill='#bfd3c5',width=2)
            for row in m['warps']:
                x,y=row['at'];d.rounded_rectangle((x*p,y*p,(x+1)*p-1,(y+1)*p-1),3,fill='#819ca3',outline='#d1ddbc',width=2)
        inlay(pic,walk,p,circuits)
    if 104<=n<=106:
        ground_mask(pic,walk,floor_tile('floor'),p)
        def runner(d):
            for yy in (-1,1):
                y=(sy+yy*2.2)*p;d.line((0,y,pic.width,y),fill='#9b826f',width=2);d.line((0,y+3,pic.width,y+3),fill='#e4c9a4',width=2)
        inlay(pic,walk,p,runner)
    if 152<=n<=155:
        ground_mask(pic,walk,floor_tile('cobble'),p)
        def paving(d):
            for off in (-3,3):
                x=(sx+off)*p;d.line((x,0,x,pic.height),fill='#a5a28e',width=3);d.line((x+3,0,x+3,pic.height),fill='#e5d9b8',width=2)
            for i in range(sy-4,sy+6,3):d.rectangle(((sx+5)*p,i*p,(sx+5)*p+6,i*p+3),fill='#8c9388')
        inlay(pic,walk,p,paving)
    return pic


def coastal_route(pic,m,p):
    # The lower path runs right against a steep cliff. Give the whole traversable strip
    # a continuous dry beach, not just the one cell where a sloping mesh crossed sea level.
    water=np.asarray(m['physics']['water'],bool);walk=interior_mask(m)&~water
    shore=ndimage.distance_transform_edt(~water);dry=(shore<=4.4)&walk
    ground_mask(pic,dry,floor_tile('sand'),p);d=ImageDraw.Draw(pic)
    for y,x in np.argwhere(dry):
        X,Y=int(x*p),int(y*p)
        if y+1<water.shape[0] and water[y+1,x]:
            d.line((X,Y+p-2,X+p-1,Y+p-2),fill='#ceb68b',width=2);d.line((X,Y+p-1,X+p-1,Y+p-1),fill='#e5ddbb')
        if x and water[y,x-1]:d.line((X,Y,X,Y+p-1),fill='#d8cca5',width=2)
    return pic
