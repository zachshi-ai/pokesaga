"""Rebuild town frontages in Emerald tiles at each usable door and compile the Rotom regional chart."""
from functools import lru_cache
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage
from kalos_gym_rooms import tile,sprite
from kalos_surfaces import LAND,WATER,BLOCK,GRASS,WOOD,ROAD
TOWNS={'iki','hauoli','hauoli_outskirts','hauoli_marina','hauoli_beachfront','heahea','konikoni','paniola','malie','seafolk','tapu','po','royal','hano'}
FRONTS={'photo_hauoli':'home_blue','photo_konikoni':'home_blue','hauoli_police':'academy','ilima_room':'home_green','home_1f':'home_red','lab':'lab','school':'academy','royal_dome':'gym','hauoli_mall':'mart','hauoli_city_hall':'academy','festival_plaza':'ruin','thrifty_mart':'mart','mina_house':'home_blue','motel_2':'home_city','motel_8':'home_city','motel_13':'home_city','zygarde_lab':'lab','aether_house':'home_green','dimensional_lab':'lab','tide_song':'home_city','nursery':'home','seafolk_restaurant':'mart','shady_house':'gym','observatory':'lab','aether_base_8':'lab','seafolk_fishing_boat':'home_blue'}
def frontage(area):
    if not (area.out or area.mid=='po') or area.origin is None:return
    h,w=area.k.shape
    # A full 16 pixels per cell preserves the foliage and façades on the phone display.
    if area.px<16:
        area.pic=area.pic.resize((w*16,h*16),Image.Resampling.NEAREST);area.px=16
    p=area.px
    # Redraw the walkable grass verges, sand, tile and road in the original texture footprint.
    canvas=np.array(area.pic);grid=canvas.reshape(h,p,w,p,3).transpose(0,2,1,3,4)
    sample=grid.mean(axis=(2,3));r,g,b=sample.transpose(2,0,1)
    shade=(r+g+b)/3
    ground=area.walk
    chosen=[('ground',ground&(r>g*1.03)&(g>b*1.19)&(shade>104)),
            ('grass',ground&(g>r*1.12)&(g>b*1.08)),
            ('pave',ground&(abs(r-g)<11)&(abs(g-b)<14)&(shade>95)&(shade<217))]
    for key,take in chosen:
        if take.any():grid[take]=np.array(tile(key).resize((p,p),Image.Resampling.NEAREST))
    water=(area.k==WATER)&~area.s
    dry=~water
    pad=np.pad(dry,1)
    # North, south, east, west are the four shore edges in the Emerald atlas.
    edges=pad[:-2,1:-1].astype('uint8')+2*pad[2:,1:-1]+4*pad[1:-1,2:]+8*pad[1:-1,:-2]
    for edge in range(16):
        mask=water&(edges==edge)
        if mask.any():grid[mask]=np.array(tile('shore_'+str(edge)))
    paths=chosen[0][1] if area.mid not in ('hauoli_marina','seafolk','hano_beach','hauoli_beachfront') else np.zeros_like(ground)
    pad=np.pad(paths,1,constant_values=True)
    dx=np.where(~pad[1:-1,:-2],0,np.where(~pad[1:-1,2:],2,1))
    dy=np.where(~pad[:-2,1:-1],0,np.where(~pad[2:,1:-1],2,1))
    for iy in range(3):
        for ix in range(3):
            which=paths&(dx==ix)&(dy==iy)
            if which.any():grid[which]=np.array(tile('trail_'+str(iy)+str(ix)))
    area.pic=Image.fromarray(canvas)
    trees=area.s&(area.k!=WATER)&(g>r*1.15)&(g>b*1.08)&(shade>45)
    centers=np.argwhere(ndimage.maximum_filter(ndimage.distance_transform_edt(trees),size=3)==ndimage.distance_transform_edt(trees))
    planted=np.zeros_like(trees)
    tree=sprite('tree')
    for y,x in centers:
        if not trees[y,x] or planted[y,x] or y<3 or x<1 or x>=w-1:continue
        if area.walk[y-2:y+1,x-1:x+2].any():continue
        area.pic.paste(tree,((x-1)*p,(y-2)*p),tree)
        planted[y-1:min(h,y+3),x-1:min(w,x+3)]=True
    from alola_towns import paint,TOWNS
    if area.mid in TOWNS:
        area.pic=paint(area)
    protected=area.used|area.arrivals|{tuple(area.spawn)}
    occupied=set();srcwalk=area.walk.copy()
    def secure(rect):
        if rect&protected or rect&occupied or any(area.k[y,x]==WATER for x,y in rect):return False
        candidate=srcwalk.copy()
        for x,y in rect:candidate[y,x]=False
        lab,count=ndimage.label(candidate);sx,sy=area.spawn;label=lab[sy,sx]
        if label==0 or any(lab[y,x]!=label for x,y in protected if srcwalk[y,x]):return False
        return True
    for warp in area.warps:
        target=warp['to']['map'].removeprefix('alola_')
        name='center' if target.startswith('center_') else FRONTS.get(target)
        if not name:continue
        x,y=warp['at'];asset=sprite(name)
        for scale in (1,.75,.6):
            width=max(2,round(asset.width*scale/16));height=max(2,round(asset.height*scale/16))
            left=x-width//2;right=left+width;top=y-height
            if top<0 or left<0 or right>w:continue
            rect={(a,b) for a in range(left,right) for b in range(top+1,y)}
            if not secure(rect):continue
            # Use a complete retained façade, anchored with its front step against the map transition.
            art=asset.resize((width*p,height*p),Image.Resampling.NEAREST)
            area.pic.paste(art,(left*p,top*p),art)
            for a,b in rect:area.s[b,a]=True;area.k[b,a]=BLOCK;srcwalk[b,a]=False
            occupied|=rect
            break
    # Reserve a dry accessible floor for all remaining cast and pickups.
    area.set_walk(area.spawn)

def chart(cache,places,locs,dest):
    from alola_locations import LOCS
    from build_alola_surfaces import UNIT
    W,H=360,250
    board=Image.new('RGB',(W,H),'#619fbb');d=ImageDraw.Draw(board)
    for y in range(4,H,7):
        for x in range((y%5)*5,W,21):d.line([(x,y),(x+4,y)],fill='#72adc3')
    corners={'melemele':(5,4,150,105),'akala':(151,79,142,139),'ulaula':(192,2,162,115),'poni':(8,126,133,111)}
    positions={}
    for island,(x,y,w,h) in corners.items():
        native=[r for r in places.values() if r['island']==island and r.get('map')]
        arr=np.array([[r['map']['x'],r['map']['z']] for r in native])/UNIT
        raw=np.load(cache/'planes'/(island+'.npz'));orig=raw['origin']
        k=raw['kind'];s=raw['solid']
        pts=arr-orig
        low=np.minimum(pts.min(0)-12,pts.max(0));high=pts.max(0)+13
        left,top=low.astype(int);right,bottom=high.astype(int)
        rect=np.array([right-left,bottom-top])
        scale=min(w/rect[0],h/rect[1]);dst=(max(1,int(rect[0]*scale)),max(1,int(rect[1]*scale)))
        pos=(x+(w-dst[0])//2,y+(h-dst[1])//2)
        k=k[top:bottom,left:right];s=s[top:bottom,left:right]
        land=(k!=WATER)&(k!=0)
        land=ndimage.binary_closing(land,iterations=2);land=ndimage.binary_fill_holes(land)
        dmap=ndimage.distance_transform_edt(land)
        rgb=np.zeros((*k.shape,4),np.uint8);rgb[land]=[220,207,143,255]
        rgb[dmap>2]=[129,180,121,255];rgb[dmap>5]=[95,158,108,255]
        rgb[(dmap>5)&s]=[106,143,102,255];rgb[dmap>14]=[113,145,103,255]
        art=Image.fromarray(rgb).resize(dst,Image.Resampling.NEAREST);board.paste(art,pos,art)
        for r,pt in zip(native,pts):
            positions['alola_'+LOCS[r['id']]]=list(np.rint((np.array(pos)+(pt-[left,top])*scale)/[W,H]*100).astype(int))
    for l in locs:
        if l['id'] in positions:l['pos']=[int(v) for v in positions[l['id']]]
    board.quantize(64).convert('RGB').save(dest,lossless=True,method=6)
