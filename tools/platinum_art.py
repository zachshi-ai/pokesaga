"""Dress Platinum's sampled terrain and native prop anchors with Emerald artwork."""
from functools import lru_cache
from pathlib import Path
import json, math, re
import numpy as np
from PIL import Image,ImageDraw,ImageOps
from bake_emerald_field import Emerald, TOWN, CAVE, ICE, ROOM, CLINIC, pack
from johto_gba_outdoor import AUTOTILES, TILES, prop_kind
from platinum_layout import ROOT

class Art:
    def __init__(self, emerald, samples):
        self.e=Emerald(emerald); self.samples=samples
        self.ids={}; self.images=[Image.new('RGBA',(16,16))]
    @lru_cache(None)
    def tile(self, layout, mid):
        image=self.e.metatile(layout,mid)
        key=image.tobytes()
        if key not in self.ids:
            self.ids[key]=len(self.images); self.images.append(image)
        return self.ids[key]
    def sprite(self,image):
        key=image.tobytes()
        if key not in self.ids:
            self.ids[key]=len(self.images);self.images.append(image)
        return self.ids[key]
    @lru_cache(None)
    def shelf(self,mask,top):
        # The raised platforms expose a jagged, shaded cliff face toward the camera.
        src=self.e.metatile(CAVE,0x201 if top else 0x211)
        light=ImageOps.grayscale(src.convert('RGB'))
        image=ImageOps.colorize(light,black='#31334e' if top else '#181c32',white='#b4a4bd' if top else '#77708d').convert('RGBA')
        draw=ImageDraw.Draw(image)
        if mask&1: draw.line([(0,1),(4,1),(6,0),(13,0),(15,1)],fill='#d0b2c0')
        if mask&2: draw.line([(0,13),(4,14),(7,13),(10,14),(15,13)],fill='#57455d',width=2)
        if mask&4: draw.line([(15,1),(14,6),(15,10),(14,14)],fill='#8c748f',width=2)
        if mask&8: draw.line([(1,0),(1,4),(0,8),(1,14)],fill='#c4afbe')
        return self.sprite(image)
    @lru_cache(None)
    def shore(self,mask):
        # The Emerald General tileset's animated water is 0x170. The lake
        # metatiles at 0xa1 are flat light blue. Composite a grass bank using
        # the actual animated-water palette and original shoreline colours.
        image=self.e.metatile(TOWN,0x170).copy()
        clay='#88796e';lip='#b8ad7d';foam='#9cc1d5'
        d=ImageDraw.Draw(image)
        if mask&1:
            d.line([(0,1),(4,1),(6,0),(10,0),(12,1),(15,1)],fill=lip,width=3)
            d.line([(0,3),(5,3),(7,2),(11,2),(13,3),(15,3)],fill=clay)
            d.line([(1,4),(5,4),(7,3),(11,3)],fill=foam)
        if mask&2:d.line([(0,15),(5,14),(11,14),(15,15)],fill=lip,width=2)
        if mask&4:d.line([(15,0),(14,4),(15,8),(14,12),(15,15)],fill=clay,width=2)
        if mask&8:d.line([(0,0),(1,4),(0,8),(1,12),(0,15)],fill=lip,width=2)
        return self.sprite(image)
    @lru_cache(None)
    def section(self,land,area):
        return json.loads((self.samples/f'{land}_{area}.json').read_text())
    def save(self):
        path=ROOT/'assets/platinum_native/tiles.png'
        path.parent.mkdir(exist_ok=True)
        sheet=Image.new('RGBA',(16*16,math.ceil(len(self.images)/16)*16))
        for i,image in enumerate(self.images): sheet.paste(image,(i%16*16,i//16*16))
        sheet.save(path,optimize=True)
    def make(self,row,physical,warps):
        h,w=physical.shape
        header=row['header']; name=row['source_id'].lower()
        room=header['mapType']=='MAP_TYPE_INDOORS'
        cave=header['mapType']=='MAP_TYPE_CAVE' and not any(k in name for k in ('outside','spear_pillar','forest','lake','mountain_peak'))
        distortion='distortion_world' in name
        snow=any(k in name for k in ('snowpoint','acuity_lakefront','route_216','route_217'))
        gym='gym' in name; clinic='pokecenter' in name
        floor='gym' if gym else 'clinic' if clinic else 'room'
        kinds=np.full((h,w),'void',dtype=object); props=set(); coords=set()
        ox,oy=row.get('land_offset',[0,0])
        def put(kind,x,y):
            p=(int(x),int(y))
            if 0<=p[0]<w and 0<=p[1]<h: props.add((kind,*p))
        for (bx,by),land in row['rows'].items():
            cx=bx*32-row['origin'][0]+ox; cy=by*32-row['origin'][1]+oy
            data=self.section(land,row['area'])
            for i,(mat_id,r,g,b) in enumerate(data['surface']):
                x=cx+i%32; y=cy+i//32
                if not(0<=x<w and 0<=y<h): continue
                mat=data['materials'][mat_id]; word=int(physical[y,x]); block=bool(word&32768); behavior=word&255
                if distortion: tile='dist' if not block else 'distwall' if mat and ('criff' in mat or 'land' in mat) else 'void'
                elif behavior in (16,19,21): tile='waterfall' if behavior==19 else 'water'
                elif behavior in (2,3): tile='tall'
                elif behavior==32: tile='ice'
                elif behavior in (75,76): tile='climb'
                elif behavior in range(56,60): tile='ledge_'+str(behavior)
                elif 112<=behavior<=125: tile='bridge'
                elif behavior==33: tile='sand'
                elif not mat and (room or cave or block): tile='void'
                elif 'pastoria_city_gym' in name and ('gym01_1_' in mat or 'gym01_2_' in mat or 'gym01_3_' in mat): tile='water' if behavior==89 or block else 'bridge'
                elif gym and ('ike' in mat or 'water' in mat):tile='water'
                elif 'oreburgh_city_gym' in name:
                    if mat.startswith('gym03_02'):tile='plank'
                    elif mat.startswith('gym03_05'):tile='stairs'
                    elif block and mat.startswith('gym03_0'):tile='cliff'
                    elif mat.startswith('gym03_03'):tile='rockfloor'
                    else:tile='stonetile'
                elif 'eterna_city_gym' in name:
                    tile='flowers' if 'hana' in mat or 'flower' in mat else 'trail' if 'road' in mat else 'stairs' if 'kaidan' in mat else 'fence' if 'saku' in mat else 'grass'
                elif 'snowpoint_city_gym' in name:
                    tile='ice' if behavior==32 or b>r+30 else 'snow' if not block else 'cliff'
                elif 'hall_of_origin' in name and 'dun08_shin_' in mat:tile='stairs'
                elif room:
                    tile='wall' if 'wall' in mat else 'rug' if 'carpet' in mat else floor
                elif cave:
                    tile='cliff' if block and ('wall' in mat or 'criff' in mat or not mat) else 'rockfloor'
                elif any(n in mat for n in ('snow','sonw','yuki')) or snow and 'grass' not in mat: tile='snow'
                elif any(n in mat for n in ('criff','cliff','imped','wall','rock','iwa')): tile='cliff' if block else 'rockfloor'
                elif any(n in mat for n in ('tree','tshadow','grass','nectgr')): tile='grass'
                elif 'hana' in mat or 'flower' in mat: tile='flowers'
                elif any(n in mat for n in ('lake','river','water','seaside','wave')) and block: tile='water'
                elif 'sand' in mat or 'beach' in mat: tile='sand'
                elif re.match(r'c[0-9]+_(g|r|d|w|tile)',mat): tile='pave'
                elif any(n in mat for n in ('road','floor','pave','bld','tile','brick','seki')) or max(r,g,b)-min(r,g,b)<19 and r>100: tile='pave'
                elif any(n in mat for n in ('hage','land','ground','path','miti','soil','step','dirt')) or r>g+7 and r>b+18: tile='trail'
                else: tile='grass'
                kinds[y,x]=tile
            if not distortion and not room and not cave:
                for px,pz,_ in data['foliage']:
                    tx=cx+int(px//16);ty=cy+int((pz-1)//16)
                    if 0<=tx<w and 0<=ty<h and physical[ty,tx]&32768 and not any(abs(tx-xx)<2 and abs(ty-yy)<2 for xx,yy in coords):
                        put('tree',tx,ty); coords.add((tx,ty))
            for number,model,px,py in data['props']:
                x=cx+math.floor(px); y=cy+math.floor(py); kind=None
                if number==26:
                    put('berry_tree',x,y);continue
                if room:
                    for prefix,art in [('bed','ceilingbed'),('tv','tv'),('clock','clock'),('pc','pc'),('plant','plant_indoor'),('stair','woodstairs'),('book','bookshelf_home'),('shelf','bookshelf'),('sofa','carebench'),('table','desk'),('counter','officecounter'),('map','map'),('machine','console')]:
                        if model.startswith(prefix): kind=art; break
                    if model.startswith(('d_mat','sheet')) and 0<=x<w and 0<=y<h: kinds[y,x]='rug'
                elif not cave:
                    if 'fountain' in model or model=='funsui': kind='fountain'
                    elif 'flower' in model: kind='flowers'
                    elif 'lamp' in model or 'lightpole' in model: kind='streetlamp'
                    elif 'statue' in model: kind='statue'
                if kind: put(kind,x,y)
        # Use the target of each actual door to distinguish the Mart, Center, Gym and private houses.
        for warp in warps:
            x,y=warp['at']; to=warp['to']['map']
            if room or cave or distortion or warp['trigger'] not in ('door','up') or warp.get('source_warp') is None: continue
            kind=prop_kind(to)
            if kind=='cave' or 'gate_to' in to: continue
            if any(k in to for k in ('tv_','poketch_co','school','terminal','condominiums','museum','library')):kind='academy'
            if kind=='home':
                kind='home_blue' if 'rival_house' in to else 'home_red' if 'player_house' in to else 'home_city' if header['mapType']=='MAP_TYPE_TOWN_CITY' and '_city' in name else 'home_green'
            put(kind,x,y)
        if room:
            terrain=kinds!='void'
            # DS interiors have an upright back wall. Paint the north perimeter above the
            # sampled floor without extending unused world cells into a second room.
            for y,x in zip(*np.nonzero(terrain)):
                if y>0 and not terrain[y-1,x]:
                    kinds[y-1,x]='wall'
                    if y>1 and not terrain[y-2,x]:kinds[y-2,x]='walltop'
        if distortion:
            kinds[(physical&32768)==0]='dist'
            kinds[np.isin(physical&255,[16,17,18,19,20,21,25,34,42])]='water'
            for wrow in warps:
                x,y=wrow['at']; mech=wrow.get('mechanism','')
                if mech=='reversed_waterfall': kinds[y,x]='waterfall'
                elif mech=='distortion_lift':kinds[y,x]='lift'
                elif mech=='floating_ride':kinds[y,x]='plank'
        tiledefs=dict(TILES,plank=('PetalburgCity_Gym',0x201),stairs=(CAVE,0x204),stonetile=('RustboroCity_Gym',0x201),walltop=(ROOM,0x254),distwall=(CAVE,0x211),snow=('SootopolisCity',0x2d9),water=(TOWN,0xa1),trail=(TOWN,0x121),room=(ROOM,0x201),wall=(ROOM,0x20c),rug=(ROOM,0x2a9),clinic=(CLINIC,0x202),gym=('MossdeepCity_Gym',0x20a),climb=('FallarborTown',0x265),dist=('SkyPillar_1F',0x2bd),lift=('MauvilleCity_Gym',0x205))
        grid=np.zeros((h,w),np.uint16)
        for kind in sorted(set(kinds.ravel())):
            if kind=='void': continue
            mask=kinds==kind
            grid[mask]=self.tile(*tiledefs[kind])
            if kind in ('dist','distwall','water'):
                pad=np.pad(mask,1)
                edges=(~pad[:-2,1:-1]).astype('uint8')+2*(~pad[2:,1:-1])+4*(~pad[1:-1,2:])+8*(~pad[1:-1,:-2])
                for bits in np.unique(edges[mask]):
                    grid[mask&(edges==bits)]=self.shore(int(bits)) if kind=='water' else self.shelf(int(bits),kind=='dist')
                continue
            if kind=='room':
                yy,xx=np.indices(mask.shape)
                for variant,mid in enumerate([0x201,0x204,0x205,0x207]):
                    grid[mask&((xx+3*yy)%4==variant)]=self.tile(ROOM,mid)
            if kind not in AUTOTILES and kind!='rug': continue
            # Mixed shore/path/cave edge masks share a real, directional GBA 3x3 metatile set.
            edges=[[0x29b,0x29c,0x29d],[0x2a3,0x2a4,0x2a5],[0x2ab,0x2ac,0x2ad]] if kind=='rug' else AUTOTILES[kind] if kind!='cliff' else [[0x208,0x209,0x20a],[0x210,0x211,0x212],[0x218,0x219,0x21a]]
            padded=np.pad(mask,1,constant_values=True)
            dx=np.where(~padded[1:-1,:-2],0,np.where(~padded[1:-1,2:],2,1))
            dy=np.where(~padded[:-2,1:-1],0,np.where(~padded[2:,1:-1],2,1))
            for iy in range(3):
                for ix in range(3): grid[mask&(dx==ix)&(dy==iy)]=self.tile(CAVE if kind=='cliff' else ROOM if kind=='rug' else TOWN,edges[iy][ix])
        return {'s':[w,h],'t':pack(grid),'p':sorted(props,key=lambda a:(a[2],a[1],a[0])),'biome':'space' if distortion else 'interior' if room else 'cave' if cave else 'snow' if snow else 'grassland'}
