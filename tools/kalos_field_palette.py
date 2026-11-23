"""Emerald field materials for Kalos architecture and terrain at walking scale."""
from functools import lru_cache
import re
import numpy as np
from PIL import Image, ImageDraw
from kalos_gym_rooms import tile

# A material has a visible pattern at a single walking step. Shape and contact
# shadows come from X/Y's meshes; the brushes use Emerald's actual metatiles.
BRUSHES = {
    'grass':'grass', 'path':'ground','cobble':'pave','stone':'stone','wall':'wall','ground':'rockfloor',
    'sand':'sand','water':'water','snow':'snow','ice':'ice','bridge':'wood', 'wood':'wood',
    'leaves':'grass','autumn':'grass','frost':'snow','marsh':'darkgrass','tall':'tall', 'flower':'flowers',
    'redflower':'flowers','purpleflower':'flowers','yellowflower':'flowers','rock':'cliff','mirror':'ice',
    'floor':'floor','plaster':'wall','brick':'stone','roof':'wood','glass':'ice','door':'wood',
    'redroof':'wood','blueroof':'wood','greenroof':'wood','tile':'tiles','laboratory':'clinic',
    'carpet':'carpet','silk':'carpet','metal':'tiles','copper':'wood','gold':'wood','tank':'water',
    'marble':'pave','ash':'rockfloor','magma':'rockfloor','aqua':'water','steel':'tiles','dragon':'stone',
    'vine':'darkgrass','coal':'rockfloor','rail':'wood','step':'stairs','lamp':'ice','timber':'wood',
}
NAMES = ['void',*BRUSHES]
IDS = {key:i for i,key in enumerate(NAMES)}
# Ink, midtone, sunlit edge. Keep adjacent materials within the original GBA contrast range.
RAMPS={
 'grass':('#488c60','#75bc77','#b2df8c'),'leaves':('#34634e','#529a59','#9bd272'),
 'autumn':('#815342','#c77a46','#eeb85c'),'frost':('#779ba6','#b7d3d3','#edf4e6'),
 'marsh':('#50665a','#7c9764','#acc08a'),'path':('#a6896a','#d8c295','#f0dba7'),
 'sand':('#ba9c73','#e2cb91','#fbebb0'),'cobble':('#9b968a','#c4bb9d','#e9dfc1'),
 'stone':('#757e87','#a5a6a0','#d3d1bc'),'rock':('#655b57','#a28e75','#c9b593'),
 'ground':('#736b60','#aca087','#cbbd9a'),'mirror':('#66869e','#a6c6d5','#edf3de'),
 'ice':('#6c9cb7','#a3cfdd','#e7f1e8'),'snow':('#9ab7bf','#d4e2de','#f5f6e8'),
 'water':('#476ea0','#669ac5','#9ad1dc'),'bridge':('#756451','#b49870','#dec28c'),
 'wood':('#927459','#c4a982','#e6d1a9'),'timber':('#675147','#987352','#c49b69'),
 'wall':('#85726b','#baa48d','#e7d6bd'),'plaster':('#928987','#cfc3ae','#f1e4c7'),
 'brick':('#91695d','#b68f76','#debc9a'),'roof':('#666875','#9396a0','#bdc2bc'),
 'redroof':('#88565c','#b97868','#dcaa84'),'blueroof':('#48647c','#7392a5','#adc9c8'),
 'greenroof':('#4f746d','#74a697','#aad0b1'),'glass':('#496377','#7da8b4','#c7e2da'),
 'door':('#68514c','#92705a','#b99a73'),'floor':('#9a7f62','#c9b28b','#e9d8b4'),
 'tile':('#7c9097','#b4c6bd','#e3ebd5'),'laboratory':('#769798','#b5d4ca','#e3eddc'),
 'carpet':('#914f62','#bd7782','#e6afa5'),'silk':('#8c879e','#c4b0ce','#e8daea'),
 'metal':('#5c707b','#95a4a5','#ccd1c4'),'copper':('#906855','#c28a65','#ebc39a'),
 'gold':('#92764c','#cdb079','#f4dfa3'),'tank':('#426e80','#79b8ba','#c4e8d5'),
 'marble':('#9b97a1','#d1cbd0','#f4ede2'),'ash':('#544b52','#827072','#ab9386'),
 'magma':('#a14843','#db7950','#ffd679'),'aqua':('#446f91','#75abc1','#b5e0da'),
 'steel':('#586475','#8d9ba7','#c4c8c3'),'dragon':('#6d5c72','#978298','#c5acb0'),
 'vine':('#476750','#718959','#a2b96d'),'coal':('#45444c','#6e6c73','#989389'),
 'rail':('#67646b','#989394','#c5bdab'),'step':('#82796d','#baa98f','#e4d4b4'),
 'lamp':('#ac8555','#dbb870','#fff2c2'),
}

def rgb(hexcol):
    return np.array(tuple(bytes.fromhex(hexcol[1:])),dtype=float)

@lru_cache(None)
def pattern(key):
    if key=='void':return np.full((16,16,3),(37,46,50),np.uint8)
    src=np.asarray(tile(BRUSHES[key]),dtype=float)
    if key in ('tall','flower','yellowflower','redflower','purpleflower'):
        a=src.copy()
        if key.endswith('flower') and key!='flower':
            bloom=(a[:,:,0]>a[:,:,1]*1.03)
            colors={'yellowflower':(246,207,78),'redflower':(217,90,103),'purpleflower':(173,115,188)}
            a[bloom]=colors[key]
        return a.astype(np.uint8)
    dark,mid,light=map(rgb,RAMPS[key]);lum=src.mean(2)
    v=(lum-np.median(lum))/max(35,np.ptp(lum)/1.65)
    v=np.clip(v,-.85,.85)[:,:,None]
    pix=np.clip(mid+np.maximum(v,0)*(light-mid)+np.minimum(v,0)*(mid-dark),0,255).astype(np.uint8)
    pic=Image.fromarray(pix);d=ImageDraw.Draw(pic)
    ink=tuple((dark*.68+mid*.32).astype(int));edge=tuple((light*.64+mid*.36).astype(int))
    if key in ('marble','laboratory','tile','steel'):
        d.line((0,15,15,15),fill=ink);d.line((15,0,15,15),fill=ink)
        d.line((1,0,14,0),fill=edge);d.point((1,1),fill=tuple(light.astype(int)))
    if key in ('roof','redroof','blueroof','greenroof'):
        for y in (3,9,15):
            d.line((0,y,15,y),fill=ink);d.line((0,y-1,15,y-1),fill=edge)
            x=3 if y==9 else 10;d.line((x,y-4,x,y-2),fill=ink)
    if key=='brick':
        for i,y in enumerate((4,10,15)):
            d.line((0,y,15,y),fill=ink);x=4+7*(i%2);d.line((x,y-4,x,y),fill=ink)
    if key in ('bridge','timber'):
        d.line((0,7,15,7),fill=ink);d.line((0,15,15,15),fill=ink);d.point((2,6),fill=edge)
    if key=='glass':
        d.line((1,12,11,2),fill=edge,width=2);d.line((10,11,14,7),fill=edge)
    if key=='rail':
        d.line((2,0,2,15),fill=ink,width=2);d.line((13,0,13,15),fill=edge,width=2)
    if key in ('rock','mirror','coal','ash'):
        d.line((1,12,5,9,9,9),fill=ink);d.line((4,8,8,7,10,8),fill=edge)
    # Large continuous surfaces need quiet joinery at field scale. Save the
    # bright facets for the ice faces and crystals, and keep cliff floors matte.
    if key in ('laboratory','marble','tile','steel','floor','silk','carpet','plaster','wall','mirror','ice','metal','ash','magma','aqua','lamp','water','tank'):
        base=tuple(mid.astype(int));pic=Image.new('RGB',(16,16),base);d=ImageDraw.Draw(pic)
        seam=tuple((dark*.34+mid*.66).astype(int));glint=tuple((light*.39+mid*.61).astype(int))
        if key in ('laboratory','marble','tile','steel','metal'):
            d.line((0,15,15,15),fill=seam);d.line((15,0,15,15),fill=seam)
            d.line((0,0,14,0),fill=glint);d.point((1,1),fill=glint)
            if key=='marble':d.line((2,10,5,9,7,9),fill=glint)
        elif key in ('floor','plaster','wall'):
            for y in (7,15):d.line((0,y,15,y),fill=seam)
            d.line((2,9,6,9),fill=glint);d.point((12,3),fill=seam)
        elif key in ('silk','carpet'):
            for xy in ((1,2),(9,10)):d.point(xy,fill=seam)
        elif key in ('mirror','ice'):
            d.line((2,8,6,4),fill=glint);d.line((8,7,9,6),fill=glint)
        elif key in ('ash','magma'):
            d.line((1,10,5,9,7,11),fill=seam);d.point((12,2),fill=glint)
        elif key in ('water','tank','aqua'):
            d.line((2,10,5,11,8,10),fill=glint);d.line((11,3,14,3),fill=seam)
    return np.asarray(pic)


def matches(pattern, name):return bool(re.search(pattern,name))


def room_style(n):
    if n in (247,251):return 'ash','magma'
    if n in (248,252):return 'marble','aqua'
    if n in (249,253):return 'coal','steel'
    if n in (250,254):return 'marble','dragon'
    if n in (255,256,257):return 'marble','gold'
    if n in (245,246):return 'marble','carpet'
    if 288<=n<=301 or 14<=n<=16 or 329<=n<=333:return 'marble','gold'
    if n in range(77,83) or n in (49,83,84,85,109,236,310,311,312) or 94<=n<=103 or 335<=n<=342:return 'laboratory','metal'
    if n in (48,):return 'tile','tank'
    if n in (104,105,106,241,242):return 'marble','silk'
    if n in (88,93,117,119,120,122,125,126,129,130,131,132,140,141,146):return 'wood','carpet'
    if 135<=n<=139:return 'marble','carpet'
    if n in (57,89,90,166,206,218,227):return 'wood','silk'
    if n in (181,182,183,184,185,186,321):return 'cobble','stone'
    return 'floor','carpet'


def stone_style(n):
    if 313<=n<=317 or n in (222,278):return 'ice'
    if 305<=n<=308:return 'coal'
    if 343<=n<=348 or n==349:return 'coal'
    if n in (272,267):return 'sand'
    return 'rock'


def material(node,name,outdoor,n):
    s=name.lower();node=node.lower()
    if matches(r'^(projection|white$)|shadow|kokage|_kage|_sya|_ref0|_hikari|_kasan|kirakira|camera|farbuild|kakiwari|_sky|_sora|_mist|dummy|_glow|_kiri|_enkei|bloom|_aura|_ray|_kaze|_light|^light$|_reiki|_ref[0-9]|_sdw|_lg[0-9]|_r_light|com_ent_light',s):return None
    floor,feature=room_style(n)
    if matches(r'(?:waterfall|_taki|_awa|bubble)',s):return 'aqua'
    if matches(r'(?:funsui|hunsui)',s):return 'marble'
    if matches(r'(?:_mizu|water|_river|bm_w_|_umi|_ike|_pond|_sea)',s):return 'water' if n!=48 else 'tank'
    if matches(r'(?:htree|_tree|kinoha|platan|itosugi|_leaf|_hedge|sigemi|_bush|_koke|_kusa|^kusa|_shiba)',s):
        if matches('tree|kinoha|platan|itosugi|_hedge|sigemi|bush|leaf',s):return 'frost' if n in (222,278,313) else 'autumn' if n in (29,275,276,279) else 'leaves'
        return 'marsh' if n in (273,281) else 'grass'
    if matches(r'_cri|_cryst|minera|nazomacine|_jewel|_hous|(?:ice|koori)',s):return 'mirror' if n not in (313,314,315,316,317) else 'ice'
    if matches('snow|yuki',s):return 'snow'
    if matches(r'ohana|hana|flower|barra|_rose',s):return 'flower'
    if n in (313,314,315,316,317) and matches('zimen|jimen|yuki',s):return 'snow'
    if matches(r'gake|_cliff|(?:(?:^|_)iwa)|_rock|_bould|_dan[0-9]',s):return stone_style(n)
    if matches(r'kaidan|_stair|_step|ladder',s):return 'step'
    if matches(r'bridge|_hashi|_brg|_hasi',s):return 'bridge'
    if matches(r'railway|_track|_rail|_line0',s):return 'rail'
    if matches(r'_(?:lamp|gaitoh|light|glow)',s):return 'lamp'
    if matches(r'_(?:mado|glass|window|mirror|moni|screen)|monitor',s):return 'glass'
    if matches(r'_key|_door|_tobira',s):return 'door'
    if matches(r'_yane|roof',s):return 'roof'
    if matches(r'jimen|_zimen|_dirt|floor|yuka|_jmen|_ground',s):
        return stone_style(n) if (303<=n<=308 or 313<=n<=317 or 322<=n<=328 or n==334 or 343<=n<=348) else floor if not outdoor else 'cobble' if n in (356,182,301) or 'floor' in s else 'ground'
    if 'carpet' in s or matches('_mat[0-9_]|_carp',s):return feature
    if matches(r'michi|road|_path|_trail',s):return 'sand' if n in (266,272) else 'path'
    if matches(r'sand|suna|_saba',s):return 'sand'
    if matches(r'yuka|tairu|_tile|ishidatami|isidatami',s):return 'cobble' if outdoor else floor
    if matches(r'_wood|_ita[0-9]|_moku|_bench|_desk|_shelf|_tana|_ta_deco|_chest|_table|chair|_isu|_sofa',s):return 'timber'
    if matches(r'_kabe|_wall|jouheki|renga',s):return 'brick' if outdoor else stone_style(n) if (303<=n<=308 or 313<=n<=317 or 322<=n<=328 or 343<=n<=348) else 'metal' if feature=='metal' else 'plaster'
    if matches(r'_hasira|_pillar|_waku|_frame|_fence|_saku|_metal|_pipe|_belt|_machin',s):return feature if n>=245 and n<=257 else 'metal' if not outdoor or 'fence' in s else 'timber'
    if matches(r'_pika|_kazari|fossil|statue|zou|_stand',s):return feature if not outdoor else 'stone'
    if node.endswith('_grass'):return 'tall'
    # A single atlas can contain an entire house, a train, a wardrobe, or a monument.
    # Split its coloured patches into roof, stone, glazing, timber and metal inks below.
    return 'atlas'
