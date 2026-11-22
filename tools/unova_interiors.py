"""Bake landmark models into orthographic GBA-sized scenery, using Emerald palette colors."""
import ctypes
import hashlib
import io
import json
from functools import lru_cache
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import unquote
import numpy as np
from PIL import Image, ImageOps
from unova_art import ROOT, glb

@lru_cache(None)
def raster():
    src=ROOT/'tools/unova_raster.c'
    lib=Path(tempfile.gettempdir())/('pokesaga-unova-raster-'+hashlib.sha1(src.read_bytes()).hexdigest()[:12]+'.so')
    if not lib.exists():
        path=lib.with_name(lib.name+'.'+str(__import__('os').getpid()))
        subprocess.run(['cc','-O3','-shared','-fPIC',str(src),'-o',str(path)],check=True);path.replace(lib)
    fn=ctypes.CDLL(str(lib)).draw_triangles
    ptr=ctypes.c_void_p;integer=ctypes.c_int
    fn.argtypes=[ptr,ptr,integer,integer,ptr,ptr,integer,ptr,integer,integer];fn.restype=None
    return fn

def values(doc,bin,idx):
    acc=doc['accessors'][idx];view=doc['bufferViews'][acc['bufferView']]
    dtype=np.dtype({5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[acc['componentType']])
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[acc['type']]
    return np.ndarray((acc['count'],n),dtype=dtype,buffer=bin,offset=view.get('byteOffset',0)+acc.get('byteOffset',0),strides=(view.get('byteStride',n*dtype.itemsize),dtype.itemsize))

@lru_cache(256)
def picture(path):
    im=Image.open(path).convert('RGBA')
    return np.ascontiguousarray(im)

def texture(folder,g,binary,material):
    pbr=material.get('pbrMetallicRoughness',{})
    k=pbr.get('baseColorTexture',{}).get('index')
    if k is not None:
        img=g['images'][g['textures'][k]['source']]
        if 'uri' in img:
            p=folder/unquote(img['uri'])
            if p.exists():return picture(p)
        elif 'bufferView' in img:
            v=g['bufferViews'][img['bufferView']];off=v.get('byteOffset',0);sz=v['byteLength']
            return np.ascontiguousarray(Image.open(io.BytesIO(binary[off:off+sz])).convert('RGBA'))
    color=pbr.get('baseColorFactor')
    if color is None:return None
    return np.array([[np.array(color)*255]],dtype='uint8')

def render_mesh(path,offset,rotation,pixels,depth):
    g,b=glb(path);ox,oy,oz=offset
    ct=np.cos(rotation);st=np.sin(rotation)
    h,w=depth.shape
    for mesh in g['meshes']:
        for pr in mesh['primitives']:
            attrs=pr['attributes']
            if 'indices' not in pr or 'material' not in pr or 'TEXCOORD_0' not in attrs:continue
            mat=g['materials'][pr['material']];name=mat.get('name','').lower()
            if any(k in name for k in ('kage','shadow','hikari','hlight','sky_','skybox','_sky','smoke','cloud','kemuri')):continue
            tex=texture(path.parent,g,b,mat)
            if tex is None:continue
            xyz=values(g,b,attrs['POSITION']);uv=values(g,b,attrs['TEXCOORD_0'])
            x=xyz[:,0]*ct+xyz[:,2]*st+ox;z=xyz[:,2]*ct-xyz[:,0]*st+oz;y=xyz[:,1]+oy
            a=np.ascontiguousarray(np.column_stack((x,z-y*.36,z*.36+y,uv)),dtype=np.float32)
            inds=np.ascontiguousarray(values(g,b,pr['indices']).ravel(),dtype=np.uint32)
            raster()(pixels.ctypes.data,depth.ctypes.data,w,h,a.ctypes.data,inds.ctypes.data,len(inds)//3,tex.ctypes.data,tex.shape[1],tex.shape[0])

@lru_cache(None)
def palette():
    from collections import Counter
    colors=Counter()
    for f in ('home_red','gym','rock','ceilingbed','officecounter','lab','tree','flowers','carebench','bookshelf_home','center'):
        img=Image.open(ROOT/f'assets/emerald/field/{f}.png').convert('RGBA')
        colors.update(tuple(px[:3]) for px in img.getdata() if px[3]>150)
    # Hoenn's artwork uses 5-bit RGB. Add its battle halls' dark violets, gold and silver.
    a=Image.open(ROOT/'assets/emerald/field/tiles.png').convert('RGB').quantize(192)
    p=a.getpalette()[:576];p+=list(sum([tuple(c) for c,_ in colors.most_common(64)],()))
    im=Image.new('P',(1,1));im.putpalette((p+[0]*768)[:768]);return im

def landmark(z):
    return ('gym' in z['key'] or 'gym' in z['mid'] or 'ns_castle' in z['place']
        or z['place'] in ('pokemon_league','plasma_frigate') or z['i'] in (390,391,392,396,428,429,489,495,604,19,17,193,552,566) or 'film' in z['mid'])

def bake(src,a):
    z=a['z']
    if not landmark(z):return None
    w,h=a['size'];ox,oz=a['origin'];pixels=np.zeros((h*16,w*16,4),'uint8');depth=np.full(pixels.shape[:2],-1e10,'float32')
    for (bx,bz),model in a['blocks'].items():
        path=src.visual_model(z,bx,bz,model)
        if not path:continue
        x=(bx*32-ox)*16+256;y=(bz*32-oz)*16+256
        render_mesh(path,(x,0,y),0,pixels,depth)
        same=z if src.era=='b2' else src.companion.zones[z['i']]
        area=src.area_info(same['area']);kind='exterior' if area['exterior'] else 'interior';bundle=src.prop_bundle(z)
        directory=src.field/'props'/kind/'models'/str(area['prop_bundle']).lower().removeprefix('field_props_'+kind+'_')
        if src.era=='b2':
            g,_=glb(path);props=[(int(n['name'].split('_')[-1]),n['translation'],2*np.arctan2(n.get('rotation',[0,0,0,1])[1],n.get('rotation',[0,0,0,1])[3])) for n in g['nodes'] if n.get('name','').startswith('bw2_prop_')]
        else:
            import struct
            raw=src.raw_models[model];off=struct.unpack_from('<I',raw,{b'WB':12,b'GC':16,b'NG':8,b'RD':12}[raw[:2]])[0]
            props=[((hi<<8)|lo,(px/4096,py/4096,-pz/4096),rot*2*np.pi/65536) for px,py,pz,rot,hi,lo in struct.iter_unpack('<iiiHBB',raw[off+4:])]
        for pid,(px,py,pz),rot in props:
            if pid not in bundle:continue
            prop=directory/bundle[pid]/'model.glb'
            if prop.exists():render_mesh(prop,(x+px,py,y+pz),rot,pixels,depth)
    from unova_landmark_models import placements
    for model,(x,y,zp) in placements(src,z):
        render_mesh(model,(x-ox*16,y,zp-oz*16),0,pixels,depth)
    im=Image.fromarray(pixels);bbox=im.getbbox()
    if not bbox:return None
    im=im.crop(bbox)
    # Crisp two-pixel source motifs survive a DS-to-GBA palette reduction.
    quant=im.convert('RGB').quantize(palette=palette(),dither=Image.Dither.NONE)
    quant.putpalette(quant.getpalette());quant=quant.convert('RGBA');quant.putalpha(im.getchannel('A'))
    out=ROOT/'assets/unova/landmarks'/src.era;out.mkdir(parents=True,exist_ok=True)
    file=out/(z['mid']+'.png');quant.save(file,optimize=True)
    return ['res://'+str(file.relative_to(ROOT)),bbox[0],bbox[1]]
