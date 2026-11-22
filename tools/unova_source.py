"""Read Black's field archives and Black 2's exported zone data (no ROM at runtime)."""
from collections import Counter, defaultdict
from functools import lru_cache
from pathlib import Path
import csv
import json
import struct
import numpy as np


def read(path):
    return json.loads(path.read_bytes())


def names(src, key, prefix):
    return [line.partition('=')[0].strip()[len(prefix):].lower()
            for line in (src/'generated'/(key+'.txt')).read_text().splitlines() if line.startswith(prefix)]


def archive(src, path):
    raw=(src/'files/a'/path).read_bytes()
    count=struct.unpack_from('<I',raw,24)[0]
    blob=raw.index(b'GMIF',28+count*8)+8
    return [raw[blob+x:blob+y] for x,y in struct.iter_unpack('<II',raw[28:28+count*8])]


def bwa_events(raw):
    if len(raw)<8:return [],[],[],[]
    bg,npc,warp,trigger=raw[4:8]
    signs=[]
    for i in range(bg):
        script,condition,direction,rail,x,z,y=struct.unpack_from('<4H3i',raw,8+20*i)
        if not rail: signs.append(dict(script=script,grid=dict(x=x,y=z,z=y)))
    offset=8+bg*20
    npcs=[]
    for i in range(npc):
        row=struct.unpack_from('<12HI8s',raw,offset+i*36)
        if row[12]:
            component,front,side=struct.unpack_from('<HHh',row[13])
            position={'rail':dict(component=component,front=front,side=side)}
        else:
            x,z,y=struct.unpack('<HHi',row[13])
            position={'grid':dict(x=x,z=z,y=y)}
        facing={0:'DIR_UP',1:'DIR_DOWN',2:'DIR_LEFT',3:'DIR_RIGHT'}.get(row[6],'DIR_DOWN')
        npcs.append({'id':row[0],'model':row[1],'flag':row[4],'script':row[5],'direction':facing,**position})
    offset+=npc*36
    warps=[]
    for i in range(warp):
        zone,idx,unk,move,rail,coords=struct.unpack_from('<HHBBH12s',raw,offset+i*20)
        if rail:
            comp,front,side,w,h,param=struct.unpack('<HHhHHH',coords)
            loc={'rail':{'component':comp,'front':front,'side':side}}
        else:
            x,y,z,w,h,param=struct.unpack('<6H',coords)
            loc={'grid':{'x':x,'z':z,'width':w,'height':h}}
        warps.append(dict(zone=zone,warp=idx,transition=move,**loc))
    triggers=[]
    for i in range(trigger):
        script,val,var,kind,rail,x,z,w,h,y,extra=struct.unpack_from('<5H4HhH',raw,offset+20*warp+22*i)
        if not rail:triggers.append(dict(script=script,value=val,var=var,grid=dict(x=x,z=z,width=w,height=h,y=y)))
    return npcs,warps,triggers,signs


def raw_matrix(data):
    zoned,_,w,h=struct.unpack_from('<4H',data)
    grid=np.frombuffer(data,dtype='<i4',offset=8,count=w*h).reshape(h,w)
    owners=np.frombuffer(data,dtype='<i4',offset=8+w*h*4,count=w*h).reshape(h,w) if zoned else None
    return grid,owners


class UnovaSource:
    def __init__(self, bw, b2, era):
        self.bw,self.b2,self.era=bw,b2,era
        self.field=b2/'res/field'
        self.places=names(b2,'places','PLACE_')
        self.zones=[]
        if era=='b2':
            order=read(self.field/'events/order.json')
            self.zone_names=names(b2,'zones','ZONE_')
            self.matrices=names(b2,'map_matrices','MAP_MATRIX_')
            for i,key in enumerate(self.zone_names):
                z=read(self.field/'zones'/(key+'.json'))
                scene=read(self.field/'events'/(key+'.json'))
                self.zones.append(dict(i=i,key=key,place=z['place'][6:].lower(),parent=self.zone_names.index(z['parent'][5:].lower()),matrix=self.matrices.index(z['matrix'][11:].lower()),
                    fly=(z['fly']['x'],z['fly']['z']),cycling=z['cycling'],fly_from=z['fly_from'],
                    encounters=z['encounters'][11:].lower() if z['encounters'] else '',bank=order.index('ZONE_'+key.upper()) if 'ZONE_'+key.upper() in order else i,
                    triggers=scene['triggers'],bg=scene['bg_events'],npcs=scene['npcs'],warps=scene['warps'],bgm=z['bgm'],area=z['area']))
            by_name={n:i for i,n in enumerate(self.zone_names)}
            for z in self.zones:
                for w in z['warps']:
                    if isinstance(w['zone'],str):w['zone']=by_name.get(w['zone'][5:].lower(),-1)
        else:
            model=archive(bw,'0/0/8');self.raw_models=model
            self.matrices=archive(bw,'0/0/9')
            headers=archive(bw,'0/1/2')[0]; entities=archive(bw,'1/2/5')
            counts=Counter()
            for i,r in enumerate(struct.iter_unpack('<BBHHHHH4HHHHHHHHHiii',headers)):
                place=self.places[r[14]&1023]
                counts[place]+=1
                key=place+('_'+str(counts[place]) if counts[place]>1 else '')
                npcs,warps,triggers,signs=bwa_events(entities[r[12]])
                self.zones.append(dict(i=i,key=key,place=place,parent=r[13],matrix=r[3],fly=(r[-3],r[-1]),cycling=bool(r[16]&1024),fly_from=bool(r[16]&8192),
                    encounters=r[11]&255 if r[11]!=65535 else '',bank=r[12],npcs=npcs,warps=warps,triggers=triggers,bg=signs,bgm=r[7],area=r[2]))
        self.by_id={z['i']:z for z in self.zones}

    @lru_cache(None)
    def matrix(self,idx):
        if self.era=='bw': return raw_matrix(self.matrices[idx])
        d=read(self.field/'matrices'/(self.matrices[idx]+'.json'))
        grid=[[v[10:].lower() if v else None for v in row] for row in d['maps']]
        owners=[[self.zone_names.index(v[5:].lower()) if v else -1 for v in row] for row in d['zones']] if 'zones' in d else None
        return grid,owners

    @lru_cache(None)
    def terrain(self,model):
        lower=self.surface(model,0)
        upper=self.surface(model,1)
        if lower is None or upper is None:return lower
        lower=lower.copy()
        if lower.shape!=upper.shape:return lower
        # The GBA renderer has one walk plane. Preserve the upper logs and bridges
        # where the original lower plane contains a wall or the water underneath.
        lifted=((lower&0x30000)!=0) & ((upper&0x30000)==0) & ((upper&0xffff)!=255)
        lower[lifted]=upper[lifted]
        return lower

    @lru_cache(None)
    def surface(self,model,layer):
        if self.era=='bw':
            raw=self.raw_models[model];fmt=raw[:2]
            if fmt==b'NG' or (layer==1 and fmt!=b'GC'):return None
            o=struct.unpack_from('<I',raw,8+4*layer)[0]
            w,h=struct.unpack_from('<HH',raw,o)
            size=24 if fmt==b'RD' else 8
            return np.ndarray((h,w),dtype='<u4',buffer=raw,offset=o+size,strides=(size*w,size))&0x7fffffff
        f=self.field/'maps/models'/model/('terrain_%d.csv'%layer)
        if not f.exists():return None
        with f.open() as fh:col=fh.readline().strip().split(',').index('tile_type')
        arr=np.loadtxt(f,delimiter=',',skiprows=1,usecols=(0,1,col),dtype='uint32')
        return arr[:,2].reshape(1+arr[:,1].max(),1+arr[:,0].max())

    @lru_cache(None)
    def blocks(self,zone_id):
        z=self.by_id[zone_id];blocks={}
        grid,owners=self.matrix(z['matrix'])
        for y,row in enumerate(grid):
            for x,key in enumerate(row):
                if key is None or key==-1 or (owners is not None and owners[y][x]!=zone_id):continue
                blocks[x,y]=key
        return blocks

    @lru_cache(None)
    def model_props(self,model):
        raw=self.raw_models[model]
        i={b'WB':12,b'GC':16,b'NG':8,b'RD':12}[raw[:2]]
        start=struct.unpack_from('<I',raw,i)[0]
        return [((high<<8)|low,int((x/4096+256)//16),int((-z/4096+256)//16)) for x,y,z,r,high,low in struct.iter_unpack('<iiiHBB',raw[start+4:])]

    def visual_model(self,z,bx,by,model):
        if self.era=='b2':return self.field/'maps/models'/model/'model.glb'
        if hasattr(self,'black_glbs'):
            return next((self.black_glbs/('%d_%d'%(model,z['area']))).glob('*.glb'),None)
        counterpart=self.companion
        if z['i']<len(counterpart.zones):
            other=counterpart.blocks(z['i']).get((bx,by))
            if other:return self.field/'maps/models'/other/'model.glb'
        return None

    def prop_bundle(self,z):
        from unova_art import prop_catalog
        other=z if self.era=='b2' else self.companion.zones[z['i']]
        area=self.area_info(other['area'])
        kind= 'exterior' if area['exterior'] else 'interior'
        k=(area['prop_bundle'] or '').lower().removeprefix('field_props_'+kind+'_')
        return prop_catalog(self.field/'props'/kind/'models'/k)

    @lru_cache(None)
    def area_info(self,key):
        return read(self.field/'areas'/(key[5:].lower()+'.json'))
