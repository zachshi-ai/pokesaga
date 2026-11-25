"""GBA street frontages, domestic interiors and Kalos-specific landmark pixel drawings."""
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage
from kalos_field_palette import pattern, room_style
from kalos_gym_rooms import sprite
from kalos_locations import TOWNS
from kalos_field_landmarks import chamber, cave, laboratory, aquarium, assembly, furniture_sprite, civic_floor, coastal_route
from kalos_exhibits import exhibition

# In X/Y many ordinary houses share just one interior model. Give the physical
# room its own purpose, using native chairs, shelves and desks on solid feet.
DOMESTIC_VIEWS={11,12,13,14,28,52,65,66,72,117,118,119,120,121,122,123,124,125,126,127,135,
    136,137,138,139,146,147,148,149,150,153,154,155,156,157,159,160,161,166,167,168,169,170,
    171,174,175,176,180,194,202,203,204,205,208,213}
SHOP={57,89,90,117,118,119,122,123,128,134,165,166,206,218,227}
COFFEE={88,93,117,120,121,125,129,130,131,132,133,142,143,147,148,150,151}


def fixture(pic,kind,x,y,p,scale=1):
    source=furniture_sprite(kind);w=max(1,round(source.width*p/16*scale));h=max(1,round(source.height*p/16*scale))
    img=source.resize((w,h),Image.Resampling.NEAREST);pic.paste(img,(round((x+.5)*p-w/2),round((y+1)*p-h)),img)


def mask_paint(pic,mask,patch,p):
    chip=patch.resize((p,p),Image.Resampling.NEAREST)
    for y,x in np.argwhere(mask):pic.paste(chip,(int(x)*p,int(y)*p))


def domestic(m,p,parts):
    n=m['kalos_zone'];view=m['kalos_matrix'];w,h=m['size'];phys=m['physics'];free=~np.asarray(phys['collision'],bool)
    from kalos_room_models import room_surfaces
    inside, carpet, stairs, heights, native_fixtures = room_surfaces(m,parts,free,p)
    by,bx=np.where(inside)
    pic=Image.new('RGB',(w*p,h*p),'#28323b');d=ImageDraw.Draw(pic)
    if not len(by):return pic
    bank=n in (192,193) or view in (124,125,126,194)
    office=94<=n<=103 or 83<=n<=85 or view in (135,136,137,159,160)
    cafe=n in COFFEE or view in (127,213)
    shop=n in SHOP
    wall,trim=(('#b3cbd0','#597689') if office or bank else ('#c2b3c7','#8b6786') if shop else ('#e0c19e','#98715c') if cafe else ('#c2cbb5','#6a897e') if n%3==1 else ('#e2cab2','#967d71'))
    floor=Image.fromarray(pattern('laboratory' if office else 'marble' if bank or shop else 'wood' if cafe else 'floor'))
    mask_paint(pic,inside,floor,p)
    top=inside&~np.roll(inside,1,axis=0); top[0]=inside[0]
    # North edges of the original ground mesh are the wall line.
    for yy,xx in np.argwhere(top):
        x=int(xx*p);y=int(yy*p)
        d.rectangle((x,y-2*p,x+p-1,y-1),fill=wall)
        d.rectangle((x,y-2*p,x+p-1,y-2*p+2),fill=trim)
        d.rectangle((x,y-5,x+p-1,y-1),fill=trim)
        d.line((x,y-7,x+p-1,y-7),fill='#ebe0c9')
    side=ndimage.binary_dilation(inside)&~inside
    for yy,xx in np.argwhere(side):
        if yy>0 and inside[yy-1,xx]:
            X,Y=int(xx*p),int(yy*p);d.rectangle((X,Y,X+p-1,Y+3),fill=trim)
    door_cells={tuple(w['at']) for w in m['warps']};occupied=set(door_cells)
    front=[(int(x),int(y)-1) for y,x in np.argwhere(top) if y>=2]
    # Windows are wall-mounted; shelves, furniture and machines go only on blocked floor.
    def props_at(positions, kinds, spacing, perspective=1):
        if not positions:return
        for x,y in sorted(positions,key=lambda q:(q[1],q[0])):
            if x<=0 or y<=0 or x>=w-1 or y>=h-1 or not phys['collision'][y][x]:continue
            if any(abs(x-a)+abs(y-b)<spacing for a,b in occupied):continue
            k=kinds[(len(occupied)+n+2*x)%len(kinds)];fixture(pic,k,x,y,p,perspective);occupied.add((x,y))
    # Wall decoration belongs on the principal rear wall; narrow walkable gaps
    # between wardrobes are not separate rows of room furniture.
    median_back=int(np.quantile(by,.15))-1
    wall_row=sorted([(x,y) for x,y in front if y<=median_back and not stairs[min(h-1,y+1),x] and len([k for k in (-1,1) if (x+k,y) in front])==2])
    windows=[]
    for frac in (.29,.7):
        if wall_row:
            xx=bx.min()+(bx.max()-bx.min())*frac
            window=min(wall_row,key=lambda q:abs(q[0]-xx)+abs(q[1]-median_back)*.5)
            if window not in windows:windows.append(window)
    for x,y in windows:
        X=x*p;Y=y*p;d.rectangle((X-3,Y-8,X+p+3,Y+2),fill=trim)
        d.rectangle((X-1,Y-6,X+p+1,Y),fill='#90bbca');d.line((X+1,Y-6,X+1,Y-1),fill='#d7ebdd')
        d.line((X+p//2,Y-7,X+p//2,Y+1),fill='#ebe3c4');occupied.add((x,y))
    decor=['clock','map'] if bank or office else ['clock','bookshelf_home']
    if wall_row:
        props_at([wall_row[0],wall_row[-1]],decor,2)
    # Preserve the source rug pattern including the weave and outside border.
    cloth = Image.fromarray(carpet)
    pic.paste(cloth,(0,0),cloth)
    labels, runs = ndimage.label(stairs)
    for run in range(1,runs+1):
        group = labels == run
        # The surface normal determines whether a flight ascends north or east.
        horizontal = group[:,1:] & group[:,:-1]
        vertical = group[1:,:] & group[:-1,:]
        xrise = np.mean(np.abs(np.diff(heights,axis=1))[horizontal]) if horizontal.any() else 0
        yrise = np.mean(np.abs(np.diff(heights,axis=0))[vertical]) if vertical.any() else 0
        # Stretch one Emerald stair tread across the in-model flight. Repeating
        # an outdoor stair tile here would draw a separate border on every step.
        wood = sprite('woodstairs')
        chip = Image.new('RGB',(p,p),wood.getpixel((18,14))[:3])
        drawer = ImageDraw.Draw(chip)
        for at in range(0,p,max(4,p//2)):
            drawer.rectangle((0,at,p-1,at+1),fill=wood.getpixel((17,9))[:3])
            drawer.line((0,at+2,p-1,at+2),fill=wood.getpixel((16,11))[:3])
        if xrise > yrise:chip=chip.transpose(Image.Transpose.ROTATE_90)
        mask_paint(pic,group,chip,p)
    furnishings = native_fixtures + list(m.get('kalos_furnishings', []))
    for kind,x,y,scale in sorted(furnishings, key=lambda item: item[2]):
        fixture(pic,kind,x,y,p,scale)
    for warp in m['warps']:
        x,y=warp['at'];X=x*p;Y=y*p
        if 'lift' in warp.get('kalos_label','') or '电梯' in warp.get('kalos_label',''):
            d.rectangle((X,Y+2,X+p-1,Y+p-1),fill='#81949d',outline='#556a77');d.line((X+p//2,Y+3,X+p//2,Y+p-2),fill='#beccbd')
        else:
            d.rectangle((X,Y+p-6,X+p-1,Y+p-1),fill='#a05e66');d.line((X+1,Y+p-5,X+p-2,Y+p-5),fill='#d3a18d')
    return pic


def furnish(m,arrivals):
    """Place furniture with a physical base, protecting every real entry and actor.

    Use a fitted case at the rear of a store or the sidewall of an office, and
    put a domestic sofa/tea table near the side of the rug. Keep the entrance
    axis broad enough for a travelling party and all existing story positions.
    """
    exhibits=exhibition(m['kalos_zone'],m)
    if not exhibits and ((m['kalos_matrix'] not in DOMESTIC_VIEWS and m['kalos_zone'] not in (48,49,83,84,85,251,252,253,254,256,310)) or m['kalos_zone'] in (192,193,181)):return
    n=m['kalos_zone'];view=m['kalos_matrix'];solid=np.asarray(m['physics']['collision'],bool)
    # A second build starts from the same underlying source collision.
    for x,y in m.get('kalos_furniture_feet',[]):solid[y,x]=False
    m['kalos_furniture_feet']=[];m['kalos_furnishings']=[]
    water=np.asarray(m['physics'].get('water',np.zeros_like(solid)),bool)
    blocked=solid|water;gates=[tuple(w['at']) for w in m['warps']];spawn=tuple(m['spawn']);w,h=m['size']
    protected={spawn,*arrivals,*gates,*map(tuple,m['kalos_anchors'].values()),*(tuple(o['at']) for o in m['objects']+m['npcs'])}
    for x,y in gates:blocked[y,x]=True
    lab,_=ndimage.label(~blocked);walk=lab==lab[spawn[1],spawn[0]];ys,xs=np.where(walk)
    if len(xs)<28:return
    left,right=int(xs.min()),int(xs.max());back,front=int(ys.min()),int(ys.max())
    layers=[('plant_indoor',.9,left,front-1,1)]
    sx,sy=spawn
    if exhibits:layers=exhibits
    elif n in (251,252,253,254,256):
        kind={251:'kalos_brazier',252:'kalos_sluice',253:'kalos_swordrack',254:'kalos_dragonpillar',256:'kalos_rosette'}[n];layers=[(kind,1,sx-4,sy-1,2),(kind,1,sx+4,sy-1,2),(kind,1,sx-4,sy-8,2),(kind,1,sx+4,sy-8,2)]
    elif n==48:layers=[('kalos_tanks',1,sx+3,sy-2,5),('kalos_tanks',1,sx-4,sy+1,5),('kalos_tanks',1,right-3,back+2,5),('plant_indoor',1,left+1,front-2,1)]
    elif n==310:layers=[('kalos_packer',1,sx+3,sy-1,4),('kalos_conveyor',1,sx-3,sy+2,4),('kalos_packer',1,sx-4,sy-5,4),('kalos_conveyor',1,sx+3,sy+6,4),('kalos_crate',1,left+3,back+3,3),('kalos_crate',1,right-3,front-3,3)]
    elif n in (49,83,84,85):layers=[('kalos_workbench',1,sx-4,sy+1,3),('kalos_samples',1,sx+3,sy-2,3),('kalos_cupboard',1,right-2,back+1,2),('pc',1,left+2,back+2,1),('plant_indoor',1,left,front-2,1)]
    elif n in SHOP:layers+=[('officecounter_compact',.9,left+2,back+2,3),('bookshelf',1,right-1,back+2,2)]
    elif n in COFFEE or view in (127,213):layers+=[('desk',.7,left+2,front-2,3),('desk',.7,right-2,back+2,3)]
    elif 94<=n<=103 or view in (135,136,137,159,160):layers+=[('desk',.8,right-2,back+2,3),('pc',1,left+2,back+1,1)]
    elif view in (124,125,126,194):layers+=[('carebench',1,left+2,back+2,2),('tv',1,right-1,back+1,1)]
    elif n in (5,7) or view in (118,161,174,175):layers+=[('ceilingbed',.84,right-2,back+2,2),('desk',.66,left+2,back+2,2)]
    else:layers+=[('carebench',1,left+2,back+2,2),('desk',.7,right-2,back+2,3)]
    exterior=next((w['to'] for w in m['warps'] if w['to']['map'].startswith('kalos_')),None)
    if exterior and not exhibits and n not in (48,49,83,84,85,251,252,253,254,256,310):
        # Homes facing the west/east ends of a town keep their common exit axis,
        # with reading corners and sideboards oriented towards their side of the street.
        ex,ey=exterior['at'];rotate=(ex//3+ey//5)%4
        if rotate & 1:layers=[(k,sc,right-(x-left),y,wd) for k,sc,x,y,wd in layers]
        if rotate & 2:layers=[(k,sc,x,front-(y-back) if j==1 else y,wd) for j,(k,sc,x,y,wd) in enumerate(layers)]
        if n==274:layers=[('kalos_stove',1,left+2,back+2,2),('kalos_writing',1,sx+3,sy-2,3),('kalos_cupboard',1,left+2,front-2,2)]
        else:
            top='kalos_cafe' if n in COFFEE else 'kalos_workbench' if view in (135,136,137) else 'kalos_tea' if (ex+ey)%3==1 else 'kalos_writing'
            layers=[(top if k=='desk' else k, 1 if k=='desk' else sc,x,y,wd) for k,sc,x,y,wd in layers]
    occupied=set(); targets=[(x,y) for x,y in protected if walk[y,x]]
    approaches=[(x,y) for x,y in protected if any(0<=a<w and 0<=b<h and walk[b,a] for a,b in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)))]
    for kind,scale,tx,ty,width in layers:
        for _,x,y in sorted((abs(x-tx)+abs(y-ty),x,y) for y in range(max(1,ty-4),min(h-1,ty+5)) for x in range(max(1,tx-4),min(w-1,tx+5))):
            l=x-(width-1)//2;r=l+width
            if l<1 or r>=w or not walk[y+1,l:r].any():continue
            feet={(a,y) for a in range(l,r)}
            if water[y,l:r].any() or feet & protected or any(abs(a-c)+abs(b-e)<3 for a,b in feet for c,e in occupied):continue
            cl=blocked.copy();cl[y,l:r]=True;labels,_=ndimage.label(~cl);group=labels[spawn[1],spawn[0]]
            if any(labels[b,a]!=group for a,b in targets):continue
            if any(not any(0<=a<w and 0<=b<h and labels[b,a]==group for a,b in ((c+1,e),(c-1,e),(c,e+1),(c,e-1))) for c,e in approaches):continue
            m['kalos_furnishings'].append([kind,x,y,scale]);m['kalos_furniture_feet'].extend([a,b] for a,b in sorted(feet) if not solid[b,a]);solid[y,l:r]=True;blocked=cl;occupied.update(feet);break
    m['physics']['collision']=solid.astype('uint8').tolist()


def sundial(pic,p):
    # The crystal stands above the stepped circular plinth, aligned with the
    # Timer1 body (99,87) and the support at (100,101) in the X/Y field model.
    d=ImageDraw.Draw(pic);x,y=100*p,100*p
    def poly(points,fill,outline=None):d.polygon([(int(x+a*p),int(y+b*p)) for a,b in points],fill=fill,outline=outline,width=max(1,p//7))
    def bar(box,col):d.rectangle((int(x+box[0]*p),int(y+box[1]*p),int(x+box[2]*p),int(y+box[3]*p)),fill=col)
    poly([(-4,.2),(-3,-.6),(3,-.6),(4,.2),(3,.9),(-3,.9)],'#7b7973','#53606a')
    bar((-2.7,-1.7,2.7,-.1),'#cbc5ae');bar((-3,-.6,3,-.25),'#f3ddab');bar((-.72,-4,.72,-1.3),'#9fa9a9')
    poly([(-3.3,-1.5),(-4.5,-5),(-3.3,-8),(-1.3,-7.6),(-2.85,-5.2),(-1.8,-2.3)],'#c3b48f','#6c716e')
    poly([(1.7,-2),(3.7,-5.1),(2.4,-8.1),(4,-7.2),(5,-5),(3.6,-1.6)],'#c6b58e','#6d6c66')
    tip=(-.8,-14.6);bottom=(.1,-3.1);left=(-4.2,-8.9);right=(3.6,-7.7);crest=(.7,-7.4)
    poly([tip,left,bottom,crest],'#cb8f9b','#716887');poly([tip,crest,right],'#f0b7ba','#947d96');poly([crest,bottom,right],'#a590b5','#766c91')
    poly([tip,(-1.5,-9.7),crest],'#f6d8ce');poly([left,(-1.5,-9.7),tip],'#dda4ba');poly([(-3.4,-8.65),(-1.6,-9.3),(-.4,-7.7)],'#e4c4d2')


def frontage(pic,m,p):
    n=m['kalos_zone'];w,h=m['size'];solid=np.asarray(m['physics']['collision'],bool);water=np.asarray(m['physics'].get('water',np.zeros_like(solid)),bool)
    doors={tuple(w['at']) for w in m['warps']};built=set()
    for warp in m['warps']:
        name=warp['to']['map'].removeprefix('kalos_');x,y=warp['at']
        if name.isdigit() or name.startswith(('pass_','lumiose_','crystals')) or warp.get('source_warp','').startswith('matrix'):continue
        if name.startswith('center_'):art='center'
        elif 'station' in name or 'shop' in name:art='mart'
        elif 'hotel' in name:art='home_city'
        elif n==53 and name.startswith('zone_'):continue
        elif name.startswith('zone_'):art=('home_city','home_green','home_blue','home_red')[(n+x)%4]
        elif name.startswith('gym_') or name in ('shabboneau_castle','mastery','battle_maison','ambrette_aquarium'):continue  # unique X/Y model
        elif 'lab' in name:art='lab'
        else:continue
        # Use a native front on a fitted doorway only when it covers an actual solid
        # building. Skip side entrances and overlapping thresholds instead of adding a fake door.
        size={'lab':(7,5)}.get(art,(4,4));width,height=size;l=x-(1 if width==4 else 3);b=y-1;t=b-height+2
        if t<1 or l<0 or l+width>w:continue
        footprint={(xx,yy) for xx in range(l,l+width) for yy in range(t,b+1)}
        if any(pt in doors|built for pt in footprint) or water[t:b+1,l:l+width].any():continue
        base=solid[b,l:l+width];has_wall=solid[t:b+1,l:l+width]
        if not base.all() or has_wall.mean()<.74:continue
        src=sprite(art);left=l*p;top=(b+1)*p-src.height*p//16
        src=src.resize((src.width*p//16,src.height*p//16),Image.Resampling.NEAREST);pic.paste(src,(left,top),src);built.update(footprint)


def dress(pic,m,p,parts):
    n=m['kalos_zone'];v=m['kalos_matrix']
    if n==266:return coastal_route(pic,m,p)
    if n in (*range(79,83),104,105,106,*range(152,156)):return civic_floor(pic,m,p)
    if 245<=n<=257:return chamber(m,p)
    if n in (49,83,84,85):return laboratory(m,p)
    if n==48:return aquarium(pic,m,p)
    if n==310:return assembly(m,p)
    if n in (*range(303,309),*range(314,318),319,*range(322,329),334,*range(343,349),350,351):return cave(pic,m,p)
    if v in DOMESTIC_VIEWS and n not in (192,193,181):return domestic(m,p,parts)
    if n in TOWNS or n==188:frontage(pic,m,p)
    if n==356:sundial(pic,p)
    return pic
