"""Dress Johto's walkable cells and native furniture anchors with 16px GBA artwork."""
import argparse
import base64
import json
import re
from collections import Counter
import struct
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from bake_emerald_field import Emerald, normalized
from johto_gba_outdoor import Hns, climb_wall

ROOT=Path(__file__).resolve().parents[1]
FIELDS=ROOT/'content/hgss'
OUTPUT=ROOT/'assets/johto_gba/maps'
DONORS=ROOT/'content/emerald_maps'
PROPS=ROOT/'assets/emerald/field'
HOME='LittlerootTown_BrendansHouse_2F'
LAB='LittlerootTown_ProfessorBirchsLabWithTable'
EXTERIORS={'MAP_ILEX_FOREST','MAP_VIRIDIAN_FOREST','MAP_MOUNT_SILVER_CAVE_SUMMIT','MAP_BELL_TOWER_ROOF'}

def outdoor(header, hid):
    return header['matrix_id']==0 or header['map_type'] in ('MAP_TYPE_ROUTE','MAP_TYPE_CITY_TOWN') or hid in EXTERIORS

def read(path):return json.loads(path.read_text())

def archive(path):
    data=path.read_bytes()
    offset=data.index(b'GMIF')+8
    return [data[offset+a:offset+b] for a,b in (struct.unpack_from('<II',data,28+8*i) for i in range(struct.unpack_from('<H',data,24)[0]))]

class Placements:
    def __init__(self,source):
        self.land=archive(source/'files/a/0/6/5')
        self.models=[[self.name(b) for b in archive(source/'files'/p)] for p in ['a/1/4/8','a/0/4/0']]
        self.areas=archive(source/'files/a/0/4/2')

    @staticmethod
    def name(b):
        q=b.find(b'MDL0')
        return b[q+32:q+48].split(b'\0')[0].decode('ascii',errors='replace') if q>=0 else ''

    def room(self,h):
        models=self.models[int(bool(self.areas[h['area_data_id']][6]))]
        for e in h['entries']:
            d=self.land[e['land_id']]
            terrain,props,_,_=struct.unpack_from('<4I',d)
            offset=(20+struct.unpack_from('<H',d,18)[0] if d[16:18]==b'\x34\x12' else 16)+terrain
            for i in range(offset,offset+props,48):
                model,x,y,z=struct.unpack_from('<4i',d,i)
                if model < len(models):
                    yield models[model],e['column']*32-h['origin'][0]+16+x/65536,e['row']*32-h['origin'][1]+16+z/65536

def tile(sheet,x,y,w=1,h=1):
    return sheet.crop((x*16,y*16,(x+w)*16,(y+h)*16))

def sprite(img,background):
    """Remove only palette entries used by a verified native background."""
    rgba=np.array(img.convert('RGBA'))
    for _,color in background.convert('RGB').getcolors(1024) or []:
        mask=np.all(rgba[:,:,:3]==color,axis=2)
        rgba[mask,3]=0
    return Image.fromarray(rgba)

class RoomArt:
    def __init__(self,emerald,hns,semantics):
        self.e=Emerald(emerald)
        self.hns=Hns(hns)
        self.layouts={normalized(k):k for k in self.hns.layouts}
        self.semantics=semantics
        self.bed,self.living,self.lab=[Image.open(DONORS/(s+'.png')).convert('RGBA') for s in
            ('pallet_town_players_house_2f_frlg','pallet_town_players_house_1f_frlg','pallet_town_professor_oaks_lab')]
        self.props={p.stem:Image.open(p).convert('RGBA') for p in PROPS.glob('*.png') if p.stem not in ('tiles','kanto_puzzles')}
        self.props['chair']=sprite(self.living.crop((79,71,94,96)),tile(self.living,8,5))
        self.props['chair']=self.props['chair'].crop(self.props['chair'].getbbox())
        self.props['lab_heal']=sprite(self.lab.crop((16,48,48,96)),tile(self.lab,6,5))
        self.props['lab_bench']=sprite(self.lab.crop((128,60,177,90)),tile(self.lab,6,6))
        self.props['lab_bookcase']=self.props['bookshelf']
        self.props['town_tv']=self.props['tv']
        self.props['kitchen']=self.e.patch('LittlerootTown_BrendansHouse_1F',0,0,4,3)
        self.props['sofa']=self.props['carebench']
        self.props['tile_switch']=Image.open(PROPS/'kanto_puzzles.png').convert('RGBA').crop((0,0,16,16))
        self.water=self.e.metatile('LittlerootTown',0xa1)
        self.floor=self.e.metatile(HOME,0x201)
        self.wall=tile(self.bed,7,0);self.wainscot=tile(self.bed,7,1)
        self.lab_floor=tile(self.lab,6,6)
        self.lab_wall=tile(self.lab,4,0)
        self.stair=self.props['woodstairs']
        self.exit=self.living.crop((59,132,85,148))
        self.rug=self.e.patch(HOME,4,3,4,4)
        self.cave_name='GraniteCave_1F'
        self.cave_floor=self.e.metatile(self.cave_name,0x201)
        self.cave_wall=self.e.metatile(self.cave_name,0x211)
        self.ice=self.e.metatile('ShoalCave_LowTideIceRoom',0x38d)
        self.ledge=self.e.metatile('LittlerootTown',0x39)
        self.anchors=read(ROOT/'content/emerald_fields.json')['anchors']
        self.theme_source={}

    def donor(self,mid):
        old=mid.removeprefix('johto_').removeprefix('hgss_')
        key=normalized(old.replace('b1_f','b1f').replace('pokecenter_1f','pokemoncenter').replace('radio_tower','goldenrod_city_radio_tower'))
        for plain in ('city','town'):
            for suffix in ('gym1f','gym','mart','pokemoncenter','port','departmentstore'):
                if key.endswith(suffix):
                    name=key[:-len(suffix)]+plain+suffix.replace('gym1f','gym')
                    if name in self.layouts:return self.layouts[name]
        return self.layouts.get(key,'')

    @lru_cache(None)
    def gym_tile(self,layout,mat,solid):
        if 'Azalea' in layout:
            if 'kusa' in mat or 'tree' in mat:return self.e.metatile('LittlerootTown',1)
            if 'wall' in mat or 'ochi' in mat:return self.e.metatile('GraniteCave_1F',0x211)
            return self.e.metatile('FortreeCity',0x23c) if 'rope' in mat else self.e.metatile('GraniteCave_1F',0x201)
        if 'Violet' in layout:
            if mat in ('lm9','lm8'):return None
            if 'gym_f4' in mat or 'gym_p' in mat:return self.floor
            return self.e.metatile('SkyPillar_1F',0x241 if not solid else 0x244)
        if 'Goldenrod' in layout:
            return self.hns.metatile(layout,0x301 if not solid else 0x2f2)
        if 'Ecruteak' in layout:
            return self.floor if not solid else None
        if 'Blackthorn' in layout:
            return self.hns.metatile(layout,0x379) if ('r07' in mat or 'r08' in mat) else self.e.metatile('GraniteCave_1F',0x201 if not solid else 0x211)
        if 'Mahogany' in layout:
            return self.e.metatile('ShoalCave_LowTideIceRoom',0x38d if not solid else 0x381)
        if 'Olivine' in layout:
            return self.hns.metatile(layout,0x32d) if not solid else self.e.metatile('SkyPillar_1F',0x244)
        if 'Cianwood' in layout:
            return self.e.metatile('GraniteCave_1F',0x201 if not solid else 0x211)
        return self.e.metatile('MauvilleCity_Gym',0x201) if not solid else self.e.metatile('SkyPillar_1F',0x244)

    def surfaces(self,m,size):
        w,h=size; out=np.empty((h,w),object);out.fill('')
        colors={}
        for px,py,k in m['parts']:
            record=read(self.semantics/(k.replace(':','_')+'.json'))
            pix=np.array(record['surface'])
            for i,name in enumerate(record['materials']):
                if not name:continue
                mask=pix[:,0]==i
                if not np.any(mask):continue
                out[py:py+32,px:px+32][mask.reshape(32,32)]=name
                if name not in colors:colors[name]=tuple(map(int,np.median(pix[mask,1:],axis=0)))
        return out,colors

    def prop(self,kind):
        if kind.startswith(('d_mat','door_','sheet_','gym02rope','gym02lift','gym01_lift','kk_sky','radio_sky','stair','ladder','warp','g08_0','gym08lift','labo_select')):return None
        if kind.startswith(('table','counter_')): return 'lab_bench'
        if kind.startswith(('chair','sofa')):return 'chair' if kind.startswith('chair') else 'sofa'
        if kind.startswith('shelf'):return 'lab_bookcase' if '09' in kind else 'bookshelf_home'
        if kind.startswith(('plant','flower')):return 'plant_indoor'
        if kind.startswith(('clock','tv','bed','t_map','poster','sink','ref0','game_h','kaifuku')):
            return next(v for k,v in [('clock','clock'),('tv','town_tv'),('bed','ceilingbed'),('t_map','map'),('poster','map'),('sink','kitchen'),('ref0','bookshelf_home'),('game_h','console'),('kaifuku','lab_heal')] if kind.startswith(k))
        if kind.startswith(('pc','machine','game_machine','radio','labo_','aji_mech')):return 'pc'
        if kind.startswith(('gym02switch','card_key')):return 'tile_switch'
        if kind.startswith(('object0','gym04spot')):return 'statue'
        return None

    @staticmethod
    def place(im,s,x,y):
        if s is not None: im.alpha_composite(s,(round(x*16-s.width/2),round(y*16+7-s.height)))

    def base(self,mid,cave,lab):
        if cave:return self.cave_floor
        if lab:return self.lab_floor
        if 'pokecenter' in mid or 'pokemon_center' in mid:return self.e.metatile('PokemonCenter_1F',0x202)
        if any(k in mid for k in ('gym','power_plant','radio_tower','mart','department','dept_store','headquarters','rocket_base','station','league','room_of','airport','hotel')):return self.lab_floor
        return self.floor

    def paint(self,mid,h,m,models):
        w,hgt=m['size'];words=np.frombuffer(base64.b64decode(m['terrain']),'<u2').reshape(hgt,w)
        ok=(words&0x8000)==0;behavior=words&255
        for warp in m['warps']:
            x,y=warp['at'];ok[y,x]=True
        lab=('lab' in mid or 'professor' in mid)
        solid_stone='lighthouse' in mid
        tower=any(k in mid for k in ('tin_tower','bell_tower','sprout_tower','burned_tower','lighthouse'))
        cave=h['map_type'] in ('MAP_TYPE_CAVE','MAP_TYPE_UNDERGROUND') and not tower and not any(k in mid for k in ('ship','tunnel','radio','department','hideout','warehouse','base','headquarters','ruins_of','alph_','safari'))
        floor=self.base(mid,cave,lab)
        layout=self.donor(mid)
        names,colors=self.surfaces(m,(w,hgt))
        clinic='pokecenter' in mid or 'pokemon_center' in mid
        shop='mart' in mid or 'dept_store' in mid
        gym='_gym' in mid
        distinctive=(gym or shop or tower or cave or 'radio_tower' in mid or 'fast_ship' in mid or 'league' in mid or 'room' in mid)
        if cave or gym or tower:surface_model=(names!='')
        else:surface_model=None
        if cave: surface=ok.copy()
        else:
            surface=ndimage.binary_fill_holes(ndimage.binary_closing(np.pad(ok,3),structure=np.ones((3,3)))[3:-3,3:-3]) | ok
            for _,x,y in models:
                if 0<=int(x)<w and 0<=int(y)<hgt and np.any(ok[max(0,int(y)-3):int(y)+4,max(0,int(x)-3):int(x)+4]):
                    surface[int(y),int(x)]=True
            surface=ndimage.binary_fill_holes(surface)
        if surface_model is not None:surface |= surface_model
        surface |= np.isin(behavior,[75,76])
        if not np.any(surface): surface[m['spawn'][1],m['spawn'][0]]=True
        if mid in ('johto_players_house_2f','johto_players_house_1f','johto_elms_lab'):
            xmax,ymin,ymax={'johto_players_house_2f':(10,4,10),'johto_players_house_1f':(11,3,10),'johto_elms_lab':(12,4,14)}[mid]
            surface[:]=False;surface[ymin:ymax+1,1:xmax+1]=True
        im=Image.new('RGBA',(w*16,hgt*16))
        bounds=np.argwhere(surface)
        y0,x0=bounds.min(axis=0);y1,x1=bounds.max(axis=0)
        for y,x in bounds:
            b=int(behavior[y,x])
            ground=floor
            mat=names[y,x]
            if gym and mat:
                ground=self.gym_tile(layout or mid,mat,not bool(ok[y,x]))
                if ground is None:continue
            elif cave:
                ground=self.cave_wall if (not ok[y,x] or 'wall' in mat or 'cliff' in mat) else self.cave_floor
            elif tower:
                ground=self.e.metatile('SkyPillar_1F',0x241) if solid_stone else self.floor
            elif shop:
                ground=tile(self.lab,6,6)
            if b in (16,17,18,19,20,21,25,42,80,81,82,83): ground=self.water
            elif b==32:ground=self.ice
            im.alpha_composite(ground,(int(x)*16,int(y)*16))
        # North-facing walls occupy the two solid cells behind the walkable floor.
        for y,x in bounds:
            if gym or (y and surface[y-1,x]): continue
            for dy,texture in ((-2,self.lab_wall if lab else self.wall),(-1,self.wainscot)):
                if y+dy>=0 and not surface[y+dy,x]:
                    im.alpha_composite(self.cave_wall if cave else texture,(int(x)*16,int(y+dy)*16))
        if mid=='johto_players_house_2f':
            im.alpha_composite(self.rug,(4*16,6*16))
            self.place(im,self.props['pc'],7.0,4.6)
            self.place(im,self.props['map'],5.5,3.5)
            self.place(im,self.props['bookshelf_home'],1.8,4.5)
        if mid=='johto_players_house_1f':
            dining = self.e.patch('LittlerootTown_BrendansHouse_1F',1,5,6,4)
            im.alpha_composite(dining.crop((0,12,96,64)),(5*16,6*16+12))
        reserved=set()
        for name,x,y in sorted(models,key=lambda p:p[2]):
            if clinic and name.startswith(('pc01','machine_pc','counter_pc','sheet_pc','flower_pc')):continue
            key=self.prop(name)
            if not key or (x,y,key) in reserved or not (0<=x<w and 0<=y<hgt):continue
            if mid=='johto_players_house_1f' and key in ('chair','lab_bench'):continue
            if mid=='johto_players_house_2f' and key=='lab_bench':continue
            if mid=='johto_players_house_2f' and key=='clock':
                self.place(im,self.props[key],9.1,2.9);continue
            if key=='kitchen' and mid!='johto_players_house_1f':key='bookshelf_home'
            if key=='kitchen':im.alpha_composite(self.props[key],(int(x-2)*16,(int(y)-2)*16))
            else:self.place(im,self.props[key],x,y)
            reserved.add((x,y,key))
        if clinic and '2f' not in mid and 'b1' not in mid:
            center=self.e.patch('PokemonCenter_1F',0,0,14,9)
            cashier=next(((o['x']-h['origin'][0],o['z']-h['origin'][1]) for o in self.bank.get('objects',[]) if o['id'].endswith('_pcwoman1')),None)
            if cashier:
                nx,ny=cashier
                im.alpha_composite(center.crop((63,16,161,64)),(nx*16-48,(ny-1)*16))
                # Keep the exact service tile and the approach in front of the counter.
                self.place(im,self.props['pc'],nx+4.5,ny+1.5)
                self.place(im,self.props['carebench'],nx+4,ny+4.5)
        if mid=='johto_elms_lab':
            self.place(im,self.props['lab_bench'],8.5,4)
        for wr in m['warps']:
            if wr.get('edge') or wr.get('atlas'):continue
            x,y=wr['at']; trig=wr.get('trigger')
            if wr.get('ice_pit') or wr.get('field_drop'):
                im.alpha_composite(self.e.metatile(self.cave_name,0x206),(x*16,y*16))
            elif trig=='door':
                self.place(im,self.stair,x+0.5,y+0.5)
            elif trig=='down':
                self.place(im,self.exit,x+0.5,y+0.5)
            elif trig in ('step','left','right','up'):
                self.place(im,self.stair,x+0.5,y+0.5)
        if mid=='johto_azalea_gym':
            self.rails(im)
        box=im.getbbox()
        if not box:raise ValueError(('empty room',mid))
        dest=OUTPUT/mid;dest.mkdir(parents=True,exist_ok=True); png='room.png'
        im.crop(box).save(dest/png,optimize=True)
        (dest/'index.json').write_text(json.dumps({'pieces':[{'png':png,'at':list(box[:2])}],'bounds':list(box),'indoors':True},separators=(',',':'))+'\n')

    def rails(self,im):
        from PIL import ImageDraw
        book=read(FIELDS/'azalea.json');draw=ImageDraw.Draw(im)
        for path in book['paths'].values():
            points=[(x*16+8,z*16+5) for x,z in path]
            draw.line(points,fill=(87,64,51,255),width=3)
            draw.line([(x,y-1) for x,y in points],fill=(193,163,102,255),width=1)

if __name__=='__main__':
    cli=argparse.ArgumentParser(description=__doc__);cli.add_argument('emerald',type=Path);cli.add_argument('hgss',type=Path);cli.add_argument('--hns',type=Path,required=True);cli.add_argument('--semantics',type=Path,required=True);cli.add_argument('maps',nargs='*');args=cli.parse_args()
    art=RoomArt(args.emerald,args.hns,args.semantics);placements=Placements(args.hgss)
    field=read(FIELDS/'events.json');index=read(FIELDS/'map_index.json');count=0
    for mid,hid in index.items():
        h=field['headers'][hid]
        if not outdoor(h,hid) and (not args.maps or mid in args.maps):
            art.bank=field['banks'][str(h['event_bank'])]
            art.paint(mid,h,read(FIELDS/'maps'/(mid+'.json')),list(placements.room(h)));count+=1
    print(f'{count} interiors rendered')
