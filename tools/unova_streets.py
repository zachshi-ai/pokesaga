"""GBA street elevations fitted to the doors and foundations of the original Unova models."""
import json
import re
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from unova_art import K, ROOT

OUT = ROOT / 'assets/unova/facades'
FIELD = ROOT / 'assets/emerald/field'
# Roof shadows, mid-tones and ridge highlights are derived from the source sprite's shading.
FAMILIES = {
    'nuvema': ('home', '#365990', '#87b4d7'), 'aspertia': ('home', '#40765b', '#a4bd8c'),
    'floccesy': ('home_red', '#9b5c41', '#dfae78'), 'ranch': ('home_green', '#69683f', '#b0a874'),
    'city': ('home_city', '#6e6663', '#b5a792'), 'port': ('home_blue', '#456279', '#92aaba'),
    'warehouse': ('home_city', '#686060', '#b49b8a'), 'cafe': ('home_red', '#8e574a', '#cca484'),
    'station': ('home_blue', '#517965', '#91aa8e'), 'lab': ('lab', '#697a8c', '#b4c6d1'),
    'school': ('lab', '#8f7864', '#d5b997'), 'museum': ('academy', '#6c7074', '#bdc0a6'),
    'gym': ('gym', None, None), 'center': ('center', None, None),
}
ANCHORS = json.loads((ROOT/'content/emerald_fields.json').read_text())['anchors']


def family(model, town):
    if model == 'pc_01':return 'center'
    if 'gym' in model or model == 'c1_rest_01':return 'gym'
    if 'school' in model:return 'school'
    if 'labo' in model:return 'lab'
    if 'museum' in model:return 'museum'
    if 'cafe' in model:return 'cafe'
    if model == 'gate_01':return 'station'
    if not re.search('house|build', model):return None
    return {'unova_nuvema':'nuvema', 'unova_aspertia':'aspertia', 'unova_nacrene':'warehouse',
            'unova_ranch':'ranch', 'unova_floccesy':'floccesy', 'unova_virbank':'port'}.get(town,'city')


@lru_cache(None)
def facade(kind, width, mirror, door):
    source, low, high = FAMILIES[kind]
    img = Image.open(FIELD/(source+'.png')).convert('RGBA')
    anchor = ANCHORS[source][0]
    if low:
        pixels = np.array(img)
        rgb = pixels[:img.height//2+2,:,:3].astype(int)
        saturated = (rgb.max(2)-rgb.min(2)>19) & (pixels[:rgb.shape[0],:,3]>0)
        level = np.clip((rgb.max(2)-55)/174,0,1)[:,:,None]
        dark,light = (np.array(tuple(bytes.fromhex(v[1:]))) for v in (low,high))
        dye = np.round((dark+(light-dark)*level)/8)*8
        pixels[:rgb.shape[0],:,:3][saturated]=dye[saturated]
        img=Image.fromarray(pixels)
    # Nuvema's pitched blue entry porch and Aspertia's green dormer distinguish the
    # two home towns even at night. Their structural body is the full-sized Emerald house.
    if kind in ('nuvema','aspertia'):
        d=ImageDraw.Draw(img)
        if kind=='nuvema':
            x=anchor; y=img.height
            d.polygon([(x-15,y-27),(x,y-41),(x+15,y-27)], fill='#506983')
            d.line([(x-15,y-27),(x,y-41),(x+15,y-27)],fill='#344b67',width=2)
            d.line([(x-12,y-28),(x,y-38),(x+12,y-28)],fill='#bbc8bf',width=2)
            d.line((x-14,y-26,x+14,y-26),fill='#d6d3ba',width=2)
            for post in (x-12,x+11):
                d.rectangle((post,y-24,post+2,y-1),fill='#627981')
                d.line((post,y-22,post,y-4),fill='#dddbc5')
        else:
            d.rectangle((24,11,47,24),fill='#3e5758')
            d.rectangle((26,14,45,22),fill='#88abb1')
            d.line((35,14,35,22),fill='#496476',width=2)
            d.line((26,18,44,18),fill='#5e8691',width=1)
            d.polygon([(21,13),(25,8),(47,8),(50,13)],fill='#426954')
            d.line((25,8,46,8),fill='#a6bc92',width=2)
    if mirror:
        img=img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        anchor=img.width-anchor
    # A readable upright door and lintel, aligned to the walking cell on every facade.
    if source not in ('center','gym'):
        d=ImageDraw.Draw(img); x,y=anchor,img.height
        d.rectangle((x-8,y-22,x+7,y-1),fill='#424858')
        d.rectangle((x-6,y-20,x+5,y-3),fill='#967b61')
        d.rectangle((x-4,y-18,x+3,y-12),fill='#688e9a')
        d.line((x-3,y-17,x+2,y-17),fill='#afc1b9')
        d.line((x+3,y-8,x+4,y-8),fill='#e1c993')
        d.line((x-7,y-2,x+6,y-2),fill='#adac9c')
    if width != img.width:
        anchor=round(anchor*width/img.width)
        height=max(48,round(img.height*width/img.width))
        img=img.resize((width,height),Image.Resampling.NEAREST)
    suffix=''
    if anchor!=door:
        # Adapt the two wings independently. The central sixteen pixels keep the door,
        # knob, and threshold at full width even when a side entry sits at the wing's end.
        joined=Image.new('RGBA',img.size)
        segments=((0,anchor-8,0,door-8),(anchor-8,anchor+8,door-8,door+8),
                  (anchor+8,width,door+8,width))
        for x0,x1,xx0,xx1 in segments:
            if x1>x0 and xx1>xx0:
                piece=img.crop((x0,0,x1,img.height)).resize((xx1-xx0,img.height),Image.Resampling.NEAREST)
                joined.paste(piece,(xx0,0))
        img=joined
        anchor=door
        suffix='_at'+str(door)
    name=f"{kind}_{width}{'_w' if mirror else ''}{suffix}.png"
    OUT.mkdir(parents=True,exist_ok=True)
    img.save(OUT/name,optimize=True)
    return 'res://assets/unova/facades/'+name, [anchor,img.height]


@lru_cache(None)
def grass_tile(key):
    i=K[key];x=i%16*16;y=i//16*16
    with Image.open(ROOT/'assets/unova/tiles.png') as atlas:
        return np.array(atlas.convert('RGBA').crop((x,y,x+16,y+16)))


def path_texture(texture):
    # Authored DS path edges include a fuzzy, seasonal grass border. Keep their course
    # but use discrete material labels for a crisp Emerald lawn/dirt boundary.
    rgb=texture[:,:,:3].astype(int)
    r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    dirt=(r>=g-3)&(r>b+7)
    mapped=texture.copy()
    mapped[:,:,:3]=np.where(dirt[:,:,None],(245,4,197),(2,253,218))
    return mapped


def finish_ground(im, street):
    from scipy.ndimage import binary_closing, binary_erosion
    p=np.array(im)
    rgb=p[:,:,:3]
    rd=np.all(rgb==(245,4,197),axis=2); lawn=np.all(rgb==(2,253,218),axis=2)
    # Adjacent DS road polygons have sub-pixel cracks after orthographic projection.
    # Closing two-pixel gaps keeps junctions readable without changing their width.
    rd |= binary_closing(rd,iterations=2) & (rd | lawn | np.all(p[:,:,:3]<210,axis=2))
    lawn &= ~rd
    for mask,kind in ((lawn,'grass'),(rd,'ground')):
        y,x=np.where(mask)
        p[y,x]=grass_tile(kind)[y%16,x%16]
    # Draw a two-shade, one-pixel GBA rim only where the paths meet bare lawn.
    edge=rd&~binary_erosion(rd,iterations=1)
    y,x=np.where(edge)
    p[y,x,:3]=np.where(((x+y)%3==0)[:,None],(170,170,115),(183,182,127))
    out=Image.fromarray(p)
    pen=ImageDraw.Draw(out)
    for x,y in street.thresholds if street else ():
        x=x*16;y=y*16
        pen.rectangle((x+1,y,x+14,y+5),fill='#777b7c')
        pen.rectangle((x+2,y,x+13,y+2),fill='#c6c6b4')
        pen.line((x+2,y+5,x+13,y+5),fill='#8d9289')
        pen.rectangle((x+1,y+6,x+14,y+8),fill='#a5aa9e')
        pen.line((x+1,y+6,x+14,y+6),fill='#dbdac4')
    for x,y in street.side_entries if street else ():
        left,top=x*16,y*16
        # The upper entrances share a one-cell stair between the two solid warehouse walls.
        for step in range(0,45,5):
            pen.rectangle((left+1,top+step,left+14,top+step+4),fill='#9e9689')
            pen.line((left+1,top+step,left+14,top+step),fill='#d2c5ae')
            pen.line((left+1,top+step+4,left+14,top+step+4),fill='#786f68')
        for rail in (left-1,left+16):
            pen.line((rail,top,rail,top+44),fill='#60686a',width=2)
            for z in (2,22,42):pen.line((rail-1,top+z,rail+1,top+z),fill='#bab5a8')
    return out


def foundation(collision, x, y):
    if not (0<=y<collision.shape[0] and 0<=x<collision.shape[1]):return 0,0
    left=right=0
    while x-left>0 and left<5 and collision[y,x-left-1]:left+=1
    while x+right+1<collision.shape[1] and right<6 and collision[y,x+right+1]:right+=1
    return left,right


def elevation(kind, x, y, collision):
    # Door step is in front of the wall. Keep the facade's base on the contiguous solid row.
    left,right=foundation(collision,x,y-1)
    source=FAMILIES[kind][0]
    with Image.open(FIELD/(source+'.png')) as img:
        wide=img.width
    width=max(40,min(wide,(left+right+1)*16)) if left+right else min(wide,48)
    old=ANCHORS[source][0]
    def overflow(anchor):
        return max(0,anchor-8-left*16)+max(0,width-anchor-8-right*16)
    mirror=overflow(round((wide-old)*width/wide))<overflow(round(old*width/wide))
    door=round((wide-old if mirror else old)*width/wide)
    door=max(width-(right*16+8),min(door,left*16+8))
    art,anchor=facade(kind,width,mirror,door)
    return [art,x,y-1,anchor]


@lru_cache(None)
def side_door():
    # The entrance is in a side wing adjoining the main warehouse on its west.
    im=Image.new('RGBA',(48,34));p=ImageDraw.Draw(im)
    p.rectangle((0,11,47,32),fill='#666463')
    p.rectangle((1,12,46,30),fill='#a69883')
    for y in (15,21,27):
        p.line((1,y,46,y),fill='#897967')
        for x in range(3+(y%4)*2,47,12):p.line((x,y-4,x,y-1),fill='#897967')
    p.polygon([(0,1),(40,1),(47,11),(47,13),(0,13)],fill='#686362')
    for x in range(3,40,5):p.line((x,2,x+5,11),fill='#98918b')
    p.line((1,13,46,13),fill='#bbb3a0')
    p.rectangle((16,13,32,33),fill='#555652')
    p.rectangle((18,15,30,30),fill='#796d59')
    p.rectangle((19,16,29,22),fill='#587682')
    p.line((20,17,28,17),fill='#a4b6bc')
    p.rectangle((16,31,32,33),fill='#bcb49f')
    OUT.mkdir(parents=True,exist_ok=True)
    im.save(OUT/'warehouse_stairs.png',optimize=True)
    return 'res://assets/unova/facades/warehouse_stairs.png',[24,34]


class Streets:
    def __init__(self, area):
        self.mid=area['z']['mid']
        self.collision=np.asarray(area['collision'],dtype=bool)
        self.sites=[]
        for w in area['warps']:
            dest=w['to']['map']
            if w['trigger'] != 'step' or dest==self.mid or w.get('atlas'):continue
            if dest in ('unova_aspertia_lookout','unova_dreamyard','unova_castelia','unova_b2_zone_614','unova_b2_zone_517'):continue
            self.sites.append((tuple(w['at']),dest))
        self.side_entries={point for point,dest in self.sites if self.mid=='unova_nacrene'
                           and any(name==dest and other[1]>point[1] for other,name in self.sites)}
        self.models=[]
        self.thresholds=set()

    def collect(self, kind, x, y):
        self.models.append((kind,x/16,y/16))

    def sprites(self):
        # First match every doorway to its closest real architecture, then place decorative houses.
        result=[]; assigned={};claimed=set()
        choices=[]
        for i,(kind,mx,my) in enumerate(self.models):
            for j,((x,y),dest) in enumerate(self.sites):
                if (x,y) in self.side_entries:continue
                distance=(mx-(x+.5))**2+(my-(y-1))**2
                if distance<=25:choices.append((distance,i,j))
        for distance,i,j in sorted(choices):
            if i in assigned or j in claimed:continue
            xy,dest=self.sites[j]
            kind,mx,my=self.models[i]
            # Gates can span a horizontal road: keep their door at the correct end.
            assigned[i]=xy;claimed.add(j)
            self.thresholds.add(xy)
        w,h=self.collision.shape[1],self.collision.shape[0]
        for i,(kind,mx,my) in enumerate(self.models):
            if i in assigned:x,y=assigned[i]
            else:
                x,y=int(mx),round(my+1)
                if any(abs(x-sx)<3 and abs(y-sy)<3 for sx,sy in self.side_entries):continue
            if 0<=x<w and 0<y<=h:result.append(elevation(kind,x,y,self.collision))
        for j,((x,y),dest) in enumerate(self.sites):
            if j in claimed or x in (0,w-1) or y in (0,h-1):continue
            if (x,y) in self.side_entries:
                # The warehouses' alternate entrances sit above the main street, at real side stairs.
                path,anchor=side_door()
                result.append([path,x,y-1,anchor]);self.thresholds.add((x,y))
            if self.mid=='unova_ranch' and 0<y<h and self.collision[y-1,x]:
                self.thresholds.add((x,y))
                result.append(elevation('ranch',x,y,self.collision))
        return sorted(result,key=lambda p:(p[2],p[1]))
