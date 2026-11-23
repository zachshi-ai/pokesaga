"""Kalos furnishings tied to the original gym quiz, gallery, town and route identity."""
from functools import lru_cache
from pathlib import Path
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
QUIZZES=((25,),(661,),(515,),(12,666,414))


def exhibition(n,m):
    x,y=m['spawn'];rows=[]
    def add(kind,dx,dy,width=2):rows.append(('xy_'+kind,1,x+dx,y+dy,width))
    if n in range(79,83):
        add('quiz'+str(n-79),0,-2,5);add('lift',-4,1);add('lift',4,1)
    if n in (104,105,106):
        i=n-104;add('picture'+str(i*2),-3,-1,3);add('picture'+str(i*2+1),3,-1,3);add('gallerybench',-3,3,3)
    if n in (135,136,137,138,139):
        add('floorsign'+str(n-134),3,-2,2);add('luggage' if n in (135,137) else 'cart',-4,1,3)
    if 152<=n<=155:
        add(('galette','awning','flowercart','lampstand')[n-152],-3,-1,3);add('lampstand' if n!=155 else 'flowercart',4,-2,2);add('luggage' if n==154 else 'gallerybench',4,3,3)
    if n in (287,294):
        add('topiary' if n==287 else 'picture6',-4,-1,3);add('topiary' if n==287 else 'vase',4,-1,3)
        add('gallerybench' if n==287 else 'picture7',-4,4,3)
    if n in (260,263,267,268,273,278,282):
        kind={260:'berryshrub',263:'topiary',267:'crag',268:'menhir',273:'stump',278:'snowcrag',282:'foresttree'}[n]
        for dx,dy in ((-4,-1),(4,-2),(-6,-9),(6,9),(-7,10),(7,-12)):
            add(kind,dx,dy,2 if n not in (267,278) else 3)
    if n in (305,306,307,308,314,315,316,317,319,322,323,324,325,326,327,328,343,344,345,346,347,348,350):
        kind='cavemirror' if 305<=n<=308 else 'icepeak' if 314<=n<=317 else 'minebeam' if 343<=n<=348 else 'crag' if n<350 else 'monolith'
        for dx,dy in ((-4,-2),(5,1),(-5,7),(4,-9)):add(kind,dx,dy,2 if kind!='crag' else 3)
    if n==341:add('flareconsole',-3,0,4);add('flareconsole',4,-2,4);add('powercore',0,-5,3)
    return rows


def px_sprite(kind):
    return draw(kind.removeprefix('xy_'))

@lru_cache(None)
def draw(k):
    w,h=(80,48) if k.startswith('quiz') else (48,47) if k.startswith('picture') or k in ('galette','awning','flowercart','flareconsole') else (44,52) if k in ('topiary','icepeak','menhir','crag','snowcrag','foresttree','cavemirror','monolith','minebeam','powercore') else (40,42)
    a=Image.new('RGBA',(w,h));d=ImageDraw.Draw(a);c=w//2;ink='#4c5663';bright='#ece4c9';brass='#bfa377'
    def rect(box,col,edge=ink):d.rectangle(box,fill=col,outline=edge)
    def ell(box,col,edge=ink):d.ellipse(box,fill=col,outline=edge)
    def poly(points,col,edge=ink):d.polygon(points,fill=col,outline=edge)
    if k.startswith(('quiz','picture','floorsign')):
        if k.startswith('quiz'):
            question=int(k[-1]);families=QUIZZES[question];rect((6,h-9,w-7,h-2),'#818b99');rect((1,2,w-2,h-10),'#677f8b');rect((3,4,w-4,h-13),'#b0ccca');rect((5,6,w-6,h-15),'#8ca6b3');d.line((6,7,w-8,7),fill='#d3e4ce')
            for i,n in enumerate(families):
                im=Image.open(ROOT/'assets/mon'/(str(n)+'.png')).convert('RGBA');im=im.crop(im.getbbox());im.thumbnail((23,25),Image.Resampling.NEAREST);shape=Image.new('RGBA',im.size,'#414b65');shape.putalpha(im.getchannel('A'));a.alpha_composite(shape,((i+1)*(w//(len(families)+1))-im.width//2,7+(24-im.height)//2))
            for i in range(question+1):ell((8+i*6,h-8,10+i*6,h-6),'#f2d991')
        elif k.startswith('picture'):
            n=int(k[-1]);rect((8,h-8,w-9,h-2),'#a79780');rect((2,3,w-3,h-8),brass);rect((4,5,w-5,h-10),'#796e69');rect((6,7,w-7,h-12),('#9cbac1','#b6c69b','#c2a5b0','#9daac1')[n%4]);d.line((6,7,w-7,7),fill=bright)
            # Miniatures depict the region's coast, mountains, gardens and architecture.
            if n%4==0:
                poly([(7,24),(19,14),(28,22),(34,17),(w-8,24),(w-8,32),(7,32)],'#7f9b90');d.line((8,28,18,27,29,29,39,26),fill='#dce3c7',width=2)
            elif n%4==1:
                for x,y,col in ((11,26,'#ce947b'),(19,19,'#a39bb8'),(29,25,'#e3c480'),(35,17,'#c48781')):d.line((x,y,x-2,32),fill='#67856b',width=2);ell((x-3,y-3,x+3,y+2),col,'#a8ae8e')
            elif n%4==2:
                for x,height in ((10,13),(18,19),(26,12),(32,16)):rect((x,33-height,x+5,32),'#8c8192');poly([(x-1,33-height),(x+2,29-height),(x+6,33-height)],'#aa8c8a')
            else:
                ell((25,10,33,18),'#e9d6ab');poly([(7,31),(15,19),(22,24),(28,15),(w-8,27),(w-8,32)],'#928ca3')
        else:
            rect((6,h-9,w-7,h-2),'#9d987f');rect((c-3,13,c+3,h-9),'#a79579');d.rounded_rectangle((2,1,w-3,25),4,fill=brass,outline=ink,width=2)
            d.text((c-5,7),k[-1]+'F',fill='#544e56')
    elif k in ('galette','awning','flowercart'):
        rect((6,22,w-7,h-6),'#b59a74');rect((4,23,w-5,28),'#dcc29a')
        for x in (7,w-10):rect((x,7,x+2,h-4),'#947b61');ell((x-3,h-9,x+5,h-1),'#7d7771')
        for x in range(2,w-3,7):rect((x,5,x+6,11),'#d79581' if (x//7)%2==0 else '#eadab3')
        d.line((1,12,w-2,12),fill=ink)
        for x in (12,22,32):
            if k=='galette':ell((x,19,x+8,23),'#d2ad75','#92735c');d.point((x+2,20),fill=bright)
            elif k=='flowercart':ell((x,17,x+8,23),'#83a171');ell((x+1,15,x+4,20),'#df9aa0','#aa8d86')
            else:rect((x,16,x+6,23),'#b3c0ae')
    elif k in ('gallerybench','cart','luggage'):
        rect((4,h-12,w-5,h-4),'#a58b72');d.line((5,h-11,w-6,h-11),fill=bright,width=2)
        for x in (5,w-10):rect((x,h-6,x+3,h-2),'#71645a')
        if k=='gallerybench':rect((4,h-20,w-5,h-15),'#baa387');d.line((6,h-20,w-8,h-20),fill=bright)
        else:
            for x,y,col in ((6,17,'#a5b6b4'),(16,13,'#bd9585'),(24,21,'#aaa286')):rect((x,y,x+10,h-13),col);d.arc((x+2,y-4,x+9,y+2),170,360,fill=ink,width=2)
    elif k in ('lampstand','vase','lift','flareconsole','powercore'):
        rect((c-10,h-9,c+10,h-2),'#8d999b');rect((c-5,h-18,c+5,h-8),'#afbbad')
        if k=='lampstand':rect((c-2,7,c+2,h-10),'#6e8385');poly([(c-7,7),(c,1),(c+7,7),(c+5,17),(c-5,17)],'#ead6a0')
        elif k in ('lift','flareconsole'):rect((4,8,w-5,28),'#889fa5');rect((7,10,w-8,23),'#526879');d.line((9,18,14,18,16,14,w-11,14),fill='#c78c7d' if k=='flareconsole' else '#afdbbc',width=2);ell((w-12,24,w-8,27),'#ddc887')
        elif k=='powercore':poly([(c,3),(c+10,20),(c+3,36),(c-9,29),(c-11,14)],'#cf967e');d.line((c,4,c-3,20,c+3,35),fill='#f4c8a5',width=2)
        else:ell((c-10,14,c+10,31),'#a8acbc');rect((c-5,12,c+5,16),'#ccbfac')
    elif k in ('topiary','berryshrub','foresttree','stump'):
        if k=='foresttree':
            from kalos_gym_rooms import sprite
            return sprite('tree')
        rect((c-4,h-22,c+4,h-3),'#987c65');ell((c-10,h-7,c+10,h-1),'#83967e')
        if k=='stump':ell((c-9,h-23,c+9,h-15),'#b09372');d.arc((c-6,h-21,c+4,h-17),20,340,fill=ink)
        else:
            for y,size in ((h-24,14),(h-33,10)):
                d.rounded_rectangle((c-size,y-7,c+size,y+7),6,fill='#76a16b',outline='#516f60',width=2);d.line((c-size+4,y-6,c+2,y-6),fill='#b0c78d',width=2)
            if k=='berryshrub':
                for x,y in [(12,h-24),(18,h-19),(25,h-28)]:ell((x,y,x+4,y+4),'#c58e85','#886e6c')
    elif k=='minebeam':
        for x in (10,29):rect((x,14,x+5,h-2),'#a58260');d.line((x+1,16,x+1,h-4),fill='#c4a07a')
        rect((6,9,w-7,17),'#b79872');ell((c-3,18,c+3,25),'#e4c988')
    else:
        dark,mid,edge=('#64859a','#a1c3ce','#dfebe2') if k in ('icepeak','cavemirror','snowcrag') else ('#6a655e','#a49b8a','#cabc9e') if k!='monolith' else ('#655c73','#968b9f','#c3aeb9')
        if k in ('menhir','monolith'):points=[(c-8,h-3),(c-10,21),(c-2,3),(c+6,5),(c+10,16),(c+8,h-4)]
        elif k in ('icepeak','cavemirror'):points=[(c-12,h-3),(c-11,25),(c-4,7),(c+2,22),(c+7,13),(c+11,32),(c+9,h-3)]
        else:points=[(2,h-8),(5,h-21),(13,h-27),(20,h-26),(25,h-33),(34,h-29),(w-3,h-14),(w-5,h-4),(8,h-2)]
        poly(points,mid,dark);d.line(points[:4],fill=edge,width=2);d.line((c-3,h-5,c+1,h-20,c+7,h-24),fill=dark,width=2)
        if k in ('icepeak','cavemirror','snowcrag'):d.line((c-7,h-13,c-3,h-22),fill='#edf3e3',width=2)
    return a
