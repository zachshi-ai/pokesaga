"""Emerald tiles and furnishings for Alola interiors and Ultra locations without a source mesh."""
from functools import lru_cache
from pathlib import Path
import hashlib
import numpy as np
from PIL import Image,ImageDraw
from kalos_gym_rooms import tile,sprite
from kalos_surfaces import FLOOR,ROAD,LAND,WOOD,STONE,ROUGH,GRASS,WATER,BLOCK
from kalos_rooms import physics
from unova_art import K
P=16
ROOT=Path(__file__).resolve().parents[1]
THEMES={
 'home':'bedroom','home_1f':'living','lab':'lab','school':'school','dimensional_lab':'lab','aether_lab_b':'lab','zygarde_lab':'lab',
 'aether_house':'living','mina_house':'living','seafolk_restaurant':'restaurant','thrifty_mart':'shop','hauoli_mall':'shop',
 'hauoli_city_hall':'hall','royal_dome':'arena','league':'hall','champion_room':'arena','festival_plaza':'plaza',
 'megalopolis':'megacity','megalo_tower':'tower','poni_wormhole':'wormhole',
 'plains_grotto':'cave','ultra_deep_sea':'deep','ultra_forest':'grove','ultra_jungle':'grove','ultra_plant':'electric','ultra_desert':'desert','ultra_crater':'crater','ultra_ruin':'ruin','ultra_space_wilds':'grove',
 'hauoli_police':'lab','ilima_room':'living','photo_hauoli':'studio','photo_konikoni':'studio','aether_docks':'dock','aether_entrance':'atrium','aether_conservation':'atrium','aether_mansion':'mansion','aether_lab':'lab',
}
def theme(mid):
    if mid.startswith('center_'):return 'center'
    if mid.startswith('e4_'):return 'arena'
    if mid.startswith('rr_'):return 'castle'
    if 'beach' in mid:return 'beach'
    if 'marina' in mid:return 'dock'
    if mid.startswith('motel') or mid=='tide_song':return 'hotel'
    if 'forest' in mid or 'meadow' in mid or 'valley' in mid:return 'grove'
    if mid.startswith('lake_'):return 'lake'
    return THEMES.get(mid,'hall')
def design(mid):
    style=theme(mid)
    if style=='center':
        k,solid=physics(3,(26,26));k=np.where(solid,BLOCK,FLOOR)
        from kalos_alola_centers import scene
        return k,solid,scene('alola')
    outdoors=style in ['dock','plaza','megacity','beach','lake','grove','crater','desert','deep','electric','ruin','wormhole','cave']
    W,H={'bedroom':(16,12),'living':(23,15),'arena':(29,24),'shop':(28,18),'megacity':(33,33),'dock':(33,20),'hall':(26,18),'castle':(32,24),'grove':(31,23),'beach':(31,20),'deep':(29,23)}.get(style,(23,18))
    im=Image.new('RGB',(W*P,H*P),'#1b2834');draw=ImageDraw.Draw(im)
    k=np.full((H,W),BLOCK,np.int16);solid=np.ones((H,W),bool)
    def region(l,t,r,b,key,code=FLOOR,blocked=False):
        tx=tile(key)
        for y in range(t,b+1):
            for x in range(l,r+1):im.paste(tx,(x*P,y*P))
        k[t:b+1,l:r+1]=code;solid[t:b+1,l:r+1]=blocked
    def prop(name,x,y,foot=1):
        a=sprite(name);im.paste(a,(int((x+.5)*P-a.width/2),int((y+1)*P-a.height)),a)
        if foot: solid[y,x]=True;k[y,x]=BLOCK
    bg={'bedroom':'wood','living':'wood','hotel':'wood','restaurant':'wood','lab':'clinic','shop':'pave','school':'wood','hall':'stone','arena':'stone','castle':'stone','tower':'stone','mansion':'wood','atrium':'clinic'}.get(style,'stone')
    if not outdoors:
        region(1,1,W-2,H-2,bg)
        region(1,1,W-2,2,'wall',BLOCK,True)
        region(1,2,W-2,2,'wallcap',BLOCK,True)
        region(1,H-1,W-2,H-1,'wallcap',BLOCK,True)
    else:
        region(0,0,W-1,H-1,'water' if style in ['beach','dock','lake'] else 'rockfloor' if style in ['cave','deep','crater','wormhole'] else 'sand' if style=='desert' else 'grass',WATER if style in ['beach','dock','lake'] else LAND)
        solid[:]=False;solid[[0,-1],:]=True;solid[:,[0,-1]]=True
    if style=='studio':
        region(6,3,W-7,8,'carpet')
        region(7,3,W-8,4,'clinic')
        prop('streetlamp',5,8);prop('streetlamp',W-6,8)
        prop('console',W//2,9);prop('planter',3,4);prop('bookshelf_home',W-4,4)
    elif style=='bedroom':
        # Keep Brendan's mattress, rug, desktop and stairs at their native metatile scale.
        src=Image.open(ROOT/'assets/kalos/maps/gba_bedroom.png').convert('RGB')
        def cut(tx,ty,x,y,w,h):
            im.paste(src.crop((tx*P,ty*P,(tx+w)*P,(ty+h)*P)),(x*P,y*P))
        for y in range(3,H-1):
            for x in range(1,W-1):cut(11,13,x,y,1,1)
        for x in range(1,W-1):cut(12,3,x,1,1,2)
        cut(8,3,3,1,2,2);cut(12,9,6,6,4,4);cut(6,9,2,6,2,3)
        cut(10,4,10,1,2,3);cut(16,4,5,2,2,2);cut(20,4,12,7,3,3)
        solid[6:9,2:4]=True;solid[3,5:7]=True;solid[3,10:12]=True
        prop('map',7,3);prop('plant_indoor',13,3)
    elif style in ['living','hotel','mansion','restaurant','school']:
        prop('bookshelf_home',3,3);prop('clock',W-4,3)
        for x in [5,W-7]:prop('desk',x,H//2);prop('planter',x+1,3)
        region(W//2-1,H-5,W//2+1,H-3,'carpet')
        if style=='school':
            for x in [6,11,16]:prop('desk',x,H-5)
        if style=='hotel':prop('ceilingbed',3,H-4)
    elif style in ['lab','atrium','shop','hall','castle']:
        for x in [4,W-5]:
            prop('bookshelf' if style=='shop' else 'console' if style=='lab' else 'statue' if style=='castle' else 'planter',x,4)
            prop('officecounter' if style in ['lab','shop'] else 'desk',x,H//2)
        if style=='atrium':prop('fountain',W//2,H//2)
        region(W//2-1,H//2+1,W//2+1,H-2,'carpet')
    elif style in ['arena','tower']:
        r=5;cx,cy=W//2,H//2;region(cx-r,cy-r,cx+r,cy+r,'tiles')
        color={'e4_fighting':'#d99350','e4_rock':'#c39b58','e4_ghost':'#9874bb','e4_flying':'#7aaaca','megalo_tower':'#79cad1'}.get(mid,'#a4d4bd')
        draw.ellipse(((cx-r)*P,(cy-r)*P,(cx+r+1)*P-1,(cy+r+1)*P-1),outline=color,width=4)
        for x in [3,W-4]:prop('statue',x,5)
    elif style in ['beach','dock','lake']:
        region(1,2,W-2,H-6,'sand' if style!='dock' else 'pave',ROAD)
        region(W//2-2,H-6,W//2+2,H-3,'bridge',WOOD)
        for x in [4,W-6]:prop('tree' if style=='beach' else 'rock',x,5)
        prop('sign',W//2+4,H-7)
    elif style in ['grove','desert','crater','cave','ruin','deep','electric','wormhole']:
        for x in range(3,W-3,5):
            for y in (4,H-4):prop('tree' if style=='grove' else 'boulder' if style!='electric' else 'streetlamp',x,y)
        region(W//2-2,3,W//2+2,H-3,'rockfloor' if style in ['deep','crater','cave','ruin','wormhole'] else 'ground',ROAD)
        if style=='grove':region(4,H//2-1,8,H//2+2,'tall',GRASS);prop('flowers',W-6,H//2)
        if style=='wormhole':
            for y in [5,9,13]:draw.ellipse(((W//2-2)*P,y*P,(W//2+3)*P,(y+2)*P),outline='#9bdded',width=4)
        if style in ['deep','crater','electric','ruin']:
            tint={'deep':'#5c3794','crater':'#b34530','electric':'#36bba5','ruin':'#665648'}[style]
            im=Image.blend(im,Image.new('RGB',im.size,tint),.26)
    else:
        region(2,2,W-3,H-3,'pave',STONE)
        for x in [4,W-5]:prop('streetlamp',x,6);prop('planter',x,H-5)
        if style=='megacity':
            for x in [5,12,23]:prop('lab',x,8)
            im=Image.blend(im,Image.new('RGB',im.size,'#542999'),.31)
        elif style=='plaza':prop('ruin',W//2,6)
    return k,solid,im
