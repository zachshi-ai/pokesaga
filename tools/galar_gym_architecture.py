"""Pixel architecture for each Galar mission, aligned to the 16 px collision grid."""
from random import Random
from PIL import ImageDraw

def edged(d, points, dark, light, width):
    d.line(points, fill=dark, width=width)
    d.line([(x-1,y-1) for x,y in points], fill=light, width=max(1,width-3))

def water(d, box, seed):
    x,y,r,b=box
    d.rectangle(box, fill='#347e9a',outline='#546a76',width=3)
    d.rectangle((x+4,y+4,r-4,b-4),fill='#5aaac0',outline='#b1d4cb',width=2)
    rng=Random(seed)
    for _ in range((r-x)*(b-y)//140):
        a=rng.randint(x+5,r-14);h=rng.randint(y+6,b-5)
        d.line([(a,h),(a+4,h),(a+5,h-1),(a+10,h-1)],fill=rng.choice(['#8ac9d4','#4b9bb7','#b5dada']))

def checker(d,x,y,w):
    for i in range(w//5):
        for j in range(2):
            d.rectangle((x+5*i,y+4*j,x+5*i+4,y+4*j+3), fill='#d8cab1' if (i+j)%2 else '#655961')

def wings(n,g):
    # Solid elements occupy exactly these side bays. Decorations on the walking lanes are floor markings.
    if n in (2,3,4,5,7,8):
        for left,right,y1,y2 in bays(n):
            g[y1:y2+1,left:right+1]=1

def bays(n):
    if n==2:return [(2,4,4,9),(24,26,12,17),(2,4,21,25),(24,26,29,34),(2,4,37,40)]
    if n==3:return [(2,3,4,8),(24,26,6,11),(2,3,18,24),(25,26,32,38)]
    if n==4:return [(2,3,y,y+3) for y in (6,17,28)]+[(25,26,y,y+3) for y in (8,21,33)]
    if n==5:return [(2,4,y,y+4) for y in (4,15,26,35)]+[(24,26,y,y+4) for y in (4,15,26,35)]
    if n==7:return [(2,5,y,y+3) for y in (3,10,17,24,31,37)]+[(23,26,y,y+3) for y in (3,10,17,24,31,37)]
    if n==8:return [(2,3,y,y+3) for y in (4,15,26,36)]+[(25,26,y,y+3) for y in (4,15,26,36)]
    return []

def stage(d,x,y,r,b,tone):
    d.rectangle((x,y,r,b),fill=tone,outline='#543f51',width=2)
    for i in range(x+3,r,6):
        d.line((i,y+2,i,b-3),fill='#96617b');d.line((i+2,y+3,i+2,b-6),fill='#d098a2')
    d.polygon([(x,y),(r,y),(r-2,y+7),((x+r)//2,y+15),(x+1,y+8)],fill='#684d68')
    d.line([(x,y+6),((x+r)//2,y+13),(r,y+6)],fill='#d8b786',width=2)
    d.ellipse((x+4,b-13,x+14,b-5),fill='#f1d992',outline='#60506b',width=2)
    d.ellipse((r-14,b-13,r-4,b-5),fill='#f1d992',outline='#60506b',width=2)

def storefront(d,box,idx):
    x,y,r,b=box;c=['#737a85','#97726e','#707d89','#927c79'][idx%4]
    d.rectangle(box,fill=c,outline='#403d4b',width=2)
    d.polygon([(x,y+8),(x+3,y),(r-3,y),(r,y+8)],fill='#6b5e72',outline='#484754')
    d.rectangle((x+2,y+9,r-2,y+18),fill='#4f4356')
    sign=['#cf8c80','#ab96bd','#8db3a9'][idx%3]
    for i in range(x+5,r-10,11):
        d.line([(i,y+15),(i+3,y+11),(i+6,y+15)],fill=sign,width=1)
    d.rectangle((x+4,y+20,r-4,b-6),fill='#7d8187',outline='#484855',width=2)
    for yy in range(y+23,b-7,5):d.line((x+5,yy,r-5,yy),fill='#555764')
    d.rectangle((x+1,b-5,r-1,b),fill='#5f5864',outline='#4c4956')

def masonry(d,x,y,r,b):
    d.rectangle((x,y,r,b),fill='#7c6e75',outline='#524d59',width=2)
    for yy in range(y+4,b-3,7):
        d.line((x+2,yy,r-2,yy),fill='#6b626d')
        for xx in range(x+5+(yy//7%2)*5,r-2,11):d.line((xx,yy,xx,yy+5),fill='#6b626d')

def stone(d,cx,cy,rx,ry,palette):
    dark,mid,light=palette
    pts=[(cx-rx,cy+2),(cx-rx+3,cy-ry//2),(cx-2,cy-ry),(cx+rx-3,cy-ry+3),(cx+rx,cy+1),(cx+rx-6,cy+ry//2),(cx-7,cy+ry//2)]
    d.polygon(pts,fill=mid,outline=dark)
    d.line(pts[1:4],fill=light,width=2);d.line((cx+3,cy-ry+3,cx-1,cy-1,cx+5,cy+2),fill=dark)

def floor(im,n,m):
    d=ImageDraw.Draw(im);rng=Random(n*131);w,h=im.size
    # Header walls with depth; the northern doorway stays exactly one tile wide.
    palettes={2:('#4e7381','#b7ccba'),3:('#8c5349','#d7ac76'),4:('#6d5b60','#cf9a62'),
              5:('#79556c','#d7adbd'),6:('#816e5e','#ccac81'),7:('#50495c','#aa95a5'),8:('#56696c','#c2ab78')}
    shade,light=palettes[n]
    for x,r in [(0,223),(240,w-1)]:
        d.rectangle((x,0,r,30),fill=shade,outline='#484852',width=2)
        for xx in range(x+5,r-6,24):
            d.rectangle((xx,3,xx+11,12),fill=light,outline='#595363')
            d.line((xx+1,21,xx+18,21),fill=light)
        d.line((x,28,r,28),fill=light,width=2)
    for x1,x2,y1,y2 in bays(n):
        x=x1*16;y=y1*16;r=(x2+1)*16-1;b=(y2+1)*16-1
        if n==2:
            water(d,(x,y,r,b),x+y);px=x+8 if x1<5 else r-8
            edged(d,[(px,y-7),(px,y+17),(px+(-5 if x1<5 else 5),y+19)],'#486575','#bacac0',6)
        if n==3:
            masonry(d,x,y,r,b)
            for yy in range(y+5,b-15,20):
                d.ellipse((x+4,yy,r-5,yy+16),fill='#493e45',outline='#d69c66',width=2)
                cx=(x+r)//2;d.polygon([(cx-6,yy+12),(cx-7,yy+6),(cx-2,yy+8),(cx+2,yy+2),(cx+6,yy+11)],fill='#eab46a')
        if n==4:
            masonry(d,x,y,r,b)
            for yy in range(y+5,b-9,13):
                d.polygon([(x+4,yy+4),(x+11,yy),(r-3,yy),(r-9,yy+5)],fill='#d3ae66')
        if n==5:stage(d,x,y,r,b,'#9f667f')
        if n==7:storefront(d,(x,y,r,b),y1+x1)
        if n==8:
            masonry(d,x,y,r,b)
            d.rectangle((x+4,y+4,r-4,b-7),fill='#477575',outline='#c2ac77',width=2)
            d.polygon([(x+8,b-18),(x+11,y+14),(r-8,y+7),(r-12,y+18),(r-6,y+17),(r-13,b-14)],fill='#bfa679')
    if n==2:
        # Raised service catwalk, valves and paired overhead return pipes.
        points=[(14*16+8,41*16),(14*16+8,38*16),(8*16+8,38*16),(8*16+8,31*16),(21*16+8,31*16),(21*16+8,23*16),(8*16+8,23*16),(8*16+8,15*16),(20*16+8,15*16),(20*16+8,7*16),(14*16+8,7*16),(14*16+8,2*16)]
        d.line(points,fill='#889d9b',width=38);d.line(points,fill='#c0c9b5',width=33)
        for (a,b),(u,v) in zip(points,points[1:]):
            if a==u:
                for z in range(min(b,v)+2,max(b,v),8):d.line((a-14,z,a+14,z),fill='#acb9ad')
            else:
                for z in range(min(a,u)+2,max(a,u),8):d.line((z,b-14,z,b+14),fill='#acb9ad')
        for j,gate in enumerate(m['gates']):
            x=gate['x']*16+8;y=gate['y']*16;offset=48 if x<210 else -48
            water(d,(x+offset-12,y-26,x+offset+12,y+1),700+j)
            edged(d,[(x+offset,y-22),(x+offset,y-27),(x,y-27),(x,y-18)],'#516d7a','#c2d2c7',6)
    elif n==3:
        for i,(cx,cy) in enumerate(m['pens']):
            x,y=cx*16,cy*16
            d.rounded_rectangle((x-63,y-44,x+78,y+55),radius=16,fill='#ac965f',outline='#755c49',width=3)
            for dx in range(-52,69,12):
                if abs(dx)>12:
                    d.rectangle((x+dx,y+50,x+dx+6,y+53),fill='#ddd2a1')
        for x in (87,377):
            for y in (69,157,305,505):
                d.line((x-14,y,x-8,y-4,x+13,y-4),fill='#b58564',width=2)
    elif n==4:
        for cup in m['cups']:
            x,y=cup['at'];x=x*16+8;y=y*16+8;end=cup['landing'][0]*16+8
            d.rounded_rectangle((min(x,end)-17,y-61,max(x,end)+17,y+13),radius=10,fill='#827269',outline='#504c55',width=2)
            for xx in range(min(x,end)-13,max(x,end)+13,12):
                d.line((xx,y-56,xx,y+7),fill='#998778')
            checker(d,x-16,y+16,30);checker(d,end-16,y-60,30)
    elif n==5:
        xs=[232,168,312,152,232];ys=[650,536,360,184,30]
        pts=list(zip(xs,ys));d.line(pts,fill='#d4a37e',width=37);d.line(pts,fill='#a46f92',width=32)
        for i,(cx,cy) in enumerate(m['trainers']):
            x,y=cx*16+8,cy*16+8
            for rad,color in [(39,'#b589a5'),(33,'#d7aec3'),(29,'#af88a5')]:
                d.ellipse((x-rad,y-rad//2,x+rad,y+rad//2),fill=color)
            for side in [-1,1]:
                for j in range(3):
                    px=x+side*(48+j*9);d.line((px,y+1,px+side*3,y-3),fill='#e7c6aa',width=2)
    elif n==6:
        # Rock version gets sediment bands and fissures; grading translates them into snow ridges in Shield.
        d.rectangle((32,32,w-33,h-17),fill='#b9a287')
        for _ in range(1060):
            x=rng.randrange(34,w-38);y=rng.randrange(34,h-20)
            d.line([(x,y),(x+2,y-1),(x+6,y-1)],fill=rng.choice(['#b29b81','#c6b194','#bfa88d']))
        for y in (80,228,406,554):
            for x in (6,17,w-18,w-5):stone(d,x,y+rng.randint(-13,13),rng.randint(8,15),13,('#695f5b','#948575','#b5a290'))
        for cx,cy in m['checkpoints']:
            cx=cx*16+8;cy=cy*16+8
            d.line((cx-22,cy,cx+22,cy),fill='#c6b18e',width=9)
    elif n==7:
        d.rectangle((100,36,w-101,h-18),fill='#777583',outline='#565361',width=3)
        for x in (108,w-109):
            for y in range(42,h-30,19):d.line((x,y,x,y+10),fill='#c0ac99',width=2)
        for y in (63,169,300,461,583):
            x=138 if y%2 else 332
            d.ellipse((x,y,x+16,y+10),outline='#575662',width=2)
            d.line((x+4,y+4,x+12,y+4),fill='#99909a')
    elif n==8:
        d.rectangle((86,34,w-87,h-18),fill='#a28c77',outline='#735f63',width=3)
        for yy in range(41,h-20,16):
            for xx in range(89+(yy//16%2)*11,w-101,22):
                d.line((xx,yy,xx+13,yy),fill='#ad9981');d.line((xx,yy,xx,yy+6),fill='#968473')
        # A processional carpet connects the three weather galleries; each uses its own inlaid brass medallion.
        pts=[(232,660),(232,579),(200,548),(200,460),(280,395),(280,300),(200,232),(200,124),(232,82),(232,32)]
        d.line(pts,fill='#cbb685',width=38);d.line(pts,fill='#5d7d79',width=33)
        for idx,(cx,cy) in enumerate(m['trainers']):
            x,y=cx*16+8,cy*16+8
            d.ellipse((x-26,y-14,x+26,y+14),fill='#856e63',outline='#d3ba87',width=2)
            if idx==0:d.polygon([(x-7,y),(x-1,y-8),(x+2,y-2),(x+7,y+2),(x+2,y+6),(x-4,y+6)],fill='#b6cacc')
            elif idx==1:d.ellipse((x-6,y-6,x+6,y+6),fill='#dbc186')
            else:
                for a,b in [(7,0),(4,5),(-4,5)]:d.line((x-a,y-b,x+a,y+b),fill='#d9dac6',width=2)

def pitch_edges(im,n):
    d=ImageDraw.Draw(im);w,h=im.size
    colors={2:('#406a85','#8bbfcc'),3:('#95564b','#d9a16d'),4:('#816650','#c5a375'),5:('#87667f','#caa6bd'),6:('#77746e','#c3ad89'),7:('#514d5c','#a58d9a'),8:('#506777','#b1a57e')}
    shadow,light=colors[n]
    for x,r in [(0,45),(w-46,w-1)]:
        d.rectangle((x,99,r,h-1),fill=shadow,outline='#4e525b',width=2)
        for y in range(107,h-12,29):
            d.rectangle((x+4,y,r-4,y+14),fill='#616770',outline=light)
            for xx in range(x+7,r-5,7):d.line((xx,y+4,xx+2,y+7),fill=light,width=2)
    for x,r in [(48,219),(245,w-48)]:
        d.rectangle((x,h-14,r,h-1),fill=shadow,outline=light,width=2)
    if n==7:
        # Underground concert stage: no stadium spectators, and no Dynamax spot.
        d.rectangle((0,0,w,99),fill='#383846')
        for x in range(10,w,44):
            d.line((x,5,x,27),fill='#80717d',width=2)
            d.rectangle((x-6,27,x+7,35),fill='#706774',outline='#a39b9b')
            d.line((x-3,35,x+3,35),fill='#d6bc8d',width=2)
        for x in (22,76,w-76,w-22):
            d.rectangle((x-16,43,x+16,99),fill='#555461',outline='#998a95',width=2)
            for y in (57,82):
                d.ellipse((x-10,y-10,x+10,y+10),fill='#413f4b',outline='#8c8085',width=2)
                d.ellipse((x-4,y-4,x+4,y+4),fill='#a18d91')
        d.polygon([(188,74),(203,49),(219,66),(240,36),(236,64),(262,53),(252,78),(225,88)],fill='#a67e92',outline='#caa4aa',width=2)
