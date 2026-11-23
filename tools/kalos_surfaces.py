"""Turn X/Y model materials into field surfaces at the game's 18-unit stepping grid."""
import ctypes as ct
from pathlib import Path
import re
import subprocess
from tempfile import gettempdir
import numpy as np

ROOT=Path(__file__).resolve().parent
VOID,LAND,ROAD,STONE,WATER,GRASS,YELLOW,RED,PURPLE,ROUGH,SNOW,SAND,STAIR,BLOCK,WOOD,FLOOR,ICE,BRIDGE=range(18)
FOREST=18
def library(name):
    src=ROOT/(name+'.c')
    path=Path(gettempdir())/(name+'-'+str(src.stat().st_mtime_ns)+'.so')
    if not path.exists():
        import os
        tmp=path.with_name(path.name+'.'+str(os.getpid()))
        subprocess.run(['cc','-O3','-shared','-fPIC',str(src),'-o',str(tmp)],check=True)
        tmp.replace(path)
    return ct.CDLL(str(path))
SURFACE=library('kalos_raster').surfaces
DRAW=library('unova_raster').draw_triangles
def ptr(a):return a.ctypes.data_as(ct.c_void_p)
def put(height,ids,pos,idx,code,origin):
    h,w=height.shape
    SURFACE(ptr(height),ptr(ids),w,h,ptr(pos),ptr(idx),len(idx),code,*map(int,origin))
def paint(rgba,height,vertices,idx,texture):
    h,w=height.shape; th,tw=texture.shape[:2]
    DRAW(ptr(rgba),ptr(height),w,h,ptr(np.ascontiguousarray(vertices,dtype=np.float32)),ptr(idx),len(idx),ptr(texture),tw,th)

def classify(node,name,outdoor):
    n=name.lower()
    if re.search(r'^(projection|blc0$|white$)|(?:shadow|kokage|_kage|_light|_sya|_ref0|fallshadow|_hikari|_kasan|kirakira|camera|farbuild|kakiwari|_sky|_sora|_mist|dummy|kage0|_glow)',n):return VOID
    if re.search(r'hairenai|gake|_cliff|roof|yane|tree|kinoha|platan|_ork|_wall|_kabe|_hasira|_pillar|_fence|_saku|_bush|sigemi|_rock|_iwa|^iwa|_bed|_desk|_tana|shelf|table|_chair|_sofa|_tv|_object|_obj|_mado|_moni|_door|_bld|_bill|build|_sign|_stand|_van|_hei|_pole|_iwa|bench|_lamp|inshadow',n):return BLOCK
    if re.search(r'bridge|hashi|_brg',n):return BRIDGE
    if re.search(r'water|river|mizu|umi|bm_w_|sea_c|_pond|ike01',n):return WATER
    if re.search(r'flower|hana|ohanas',n) or node.endswith('_grass'):
        if re.search(r'(?i)yellow|_ye|_k[0-9]|kiiro',n):return YELLOW
        if re.search('purple|_pu|murasaki',n):return PURPLE
        if re.search('red|_rd|aka',n):return RED
        return GRASS
    if re.search(r'stair|kaidan|step|ladder|slope|_saka',n):return STAIR
    if re.search(r'snow|yuki',n):return SNOW
    if re.search(r'_ice|koori',n):return ICE
    if re.search(r'sand|suna',n):return SAND
    if re.search(r'kusa|lawn|grass|shiba',n):return LAND
    if re.search(r'michi|road|path|trail|dou|pebble',n):return ROAD
    if re.search(r'renga|stone|brick|tile|tairu|ishi',n):return STONE
    if re.search(r'wood|ita_|carpet|mat[0-9]|_bridge',n):return WOOD
    if re.search(r'ground|_jimen|floor|yuka|_yk|_flr|carpet|_carp|_moya|_web|_net|cushion|_dirt',n):return LAND if outdoor else FLOOR
    if node.endswith('_placed'):return BLOCK
    # Include flat, low planes that use packed room/terrain texture sheets.
    return LAND if outdoor else FLOOR

def bounds(parts):
    arr=np.concatenate([p[2] for p in parts if len(p[2])])
    lo=np.floor(arr[:,[0,2]].min(0)/18).astype(int)-2
    hi=np.ceil(arr[:,[0,2]].max(0)/18).astype(int)+3
    return lo,hi

def raster(parts,origin,end,outdoor):
    w,h=end-origin
    heights=np.full((3,h,w),-32768.,np.float32)
    ids=np.zeros((3,h,w),np.int16)
    for node,name,p,uv,idx,tex,mat in parts:
        code=classify(node,name,outdoor)
        if code==VOID:continue
        if code==BLOCK:
            put(heights[1],ids[1],p,idx,BLOCK,origin)
        else:
            put(heights[0],ids[0],p,idx,code,origin)
        put(heights[2],ids[2],p,idx,code,origin)
    floors,obst,top=heights
    cells=ids[0].copy()
    # A flat roof or piece of furniture (an atlas can also include floors on the same texture)
    # must not become a second walkable floor. Ignore tiny rugs and shadows beneath the feet.
    blocked=(cells==VOID)|(obst>floors+4)
    return cells,blocked,floors,top
