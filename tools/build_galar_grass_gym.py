"""Build Turffield's reception, four pasture pens and grass pitch on the Emerald field grid."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np
from kalos_gym_rooms import tile, sprite
from bake_emerald_field import pack

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / 'content/regions/galar/maps'
OUT = ROOT / 'assets/galar/grass_gym'
FIELD = ROOT / 'assets/emerald/field'
LOBBY, MISSION, PITCH = ('galar_turffield_'+s for s in ('pitch_room','mission','pitch'))
PENS = [(45,11),(32,8),(19,15),(6,11)]
STARTS = [(5,8),(9,10),(14,8),(17,10)]

def write(p,d):
    p.write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n')

def warp(at,mid,to):
    return {'at':list(at),'to':{'region':'galar','map':mid,'at':list(to)}}

def save(mid,name,img,tiles,spawn,warps,more=None):
    path = MAPS/(mid+'.json')
    data = json.loads(path.read_bytes()) if path.exists() else {}
    w,h=tiles.shape[1],tiles.shape[0]
    png=OUT/(mid+'.png');img.save(png,optimize=True)
    data.update(name=name,size=[w,h],spawn=list(spawn),warps=warps,npcs=[],objects=[],tiles=tiles.tolist(),
                hoenn_art={'s':[w,h],'p':[],'t':pack(np.zeros((h,w),dtype='<u2')),
                          'scene':['res://'+str(png.relative_to(ROOT)),0,0]})
    data.update(more or {})
    write(path,data)

def tiled(w,h,kind):
    im=Image.new('RGB',(w*16,h*16))
    for y in range(h):
        for x in range(w):im.paste(tile(kind),(x*16,y*16))
    return im

def post(im,x,y,w=16):
    d=ImageDraw.Draw(im)
    d.rectangle((x,y+4,x+w-1,y+6),fill='#72513b')
    d.line((x,y+3,x+w-1,y+3),fill='#d3ad77')
    d.rectangle((x+3,y,x+6,y+12),fill='#876343',outline='#654c3e')
    d.line((x+4,y+1,x+4,y+10),fill='#cea675')

def stamp(im,art,at):
    x,y=at;im.paste(art,(x*16+8-art.width//2,(y+1)*16-art.height),art)

def mascots():
    sheep=Image.open(ROOT/'assets/galar/postwick/wooloo.png').convert('RGBA')
    art=Image.new('RGBA',(37,29))
    mini=sheep.resize((13,13),Image.Resampling.NEAREST)
    for p in [(6,0),(21,0),(0,9),(24,9),(12,16)]:art.alpha_composite(mini,p)
    art.save(FIELD/'galar_wooloo_flock.png',optimize=True)
    hay=Image.open(ROOT/'assets/switch_fields/props/hay.png').convert('RGBA')
    hay.resize((22,16),Image.Resampling.NEAREST).save(FIELD/'galar_straw_gate.png',optimize=True)
    im=Image.new('RGBA',(22,19));d=ImageDraw.Draw(im)
    d.ellipse((1,13,20,18),fill='#809368');d.ellipse((3,5,19,15),fill='#92683d',outline='#564a3d')
    d.rectangle((5,12,7,16),fill='#b88346');d.rectangle((14,12,16,16),fill='#aa7440')
    d.ellipse((2,3,12,12),fill='#e4af53',outline='#62583b');d.polygon([(3,7),(2,0),(6,4)],fill='#846740');d.polygon([(8,4),(11,0),(11,7)],fill='#826541')
    d.point((4,7),fill='#383e3d');d.point((9,7),fill='#383e3d');d.rectangle((5,9,7,10),fill='#584b36')
    d.ellipse((10,7,13,13),fill='#eff0a0');d.polygon([(17,7),(19,4),(17,1),(21,3),(20,7)],fill='#efe574')
    im.save(FIELD/'galar_yamper.png',optimize=True)

def lobby():
    path=MAPS/(LOBBY+'.json');data=json.loads(path.read_bytes());w,h=data['size']
    im=tiled(w,h,'clinic');d=ImageDraw.Draw(im);cells=np.zeros((h,w),int);cells[[0,h-1],:]=1;cells[:,[0,w-1]]=1
    d.rectangle((0,0,w*16-1,28),fill='#315d56');d.rectangle((0,22,w*16,29),fill='#5f9273')
    for x in [19,42,144,169]:
        d.rectangle((x,6,x+14,18),fill='#d4e9bb',outline='#213d37')
    d.rectangle((82,0,125,25),fill='#637868',outline='#293d38');d.rectangle((88,2,120,25),fill='#1f3832')
    d.rectangle((86,26,121,127),fill='#6e9b68');d.line((90,26,90,127),fill='#dace94');d.line((118,26,118,127),fill='#dace94')
    for x in [2,3,4]:
        cells[4,x]=1;d.rectangle((x*16,64,x*16+15,78),fill='#537461',outline='#3c514b');d.rectangle((x*16,64,x*16+15,69),fill='#c1c6a1')
    for x in [9,10]:
        stamp(im,Image.open(ROOT/'assets/switch_fields/props/bench.png').convert('RGBA'),(x,6));cells[6,x]=1
    a=[v for v in data['warps'] if v['to']['map']=='galar_turffield']
    for v in a:cells[v['at'][1],v['at'][0]]=0
    cells[0,6]=0
    a.append(warp((6,0),MISSION,(11,57)))
    save(LOBBY,'草路竞技场・接待大厅',im,cells,(6,8),a)

def mission():
    w,h=25,60
    im=tiled(w,h,'grass');cells=np.zeros((h,w),int);d=ImageDraw.Draw(im)
    for y in range(h):
        for x in range(w):
            if x in (0,1,w-2,w-1) or y in (0,h-1):
                cells[y,x]=1;im.paste(tile('darkgrass'),(x*16,y*16))
            elif (y//2)%2==0:
                d.line((x*16+1,y*16+12,x*16+3,y*16+11),fill='#86b86b')
    for y in range(h):
        for x in (1,w-2):
            post(im,x*16,y*16,16)
        if y%4==0:
            stamp(im,sprite('flowers'),(0,y))
            stamp(im,sprite('flowers'),(24,y))
    pens=[]
    for i,(top,gate) in enumerate(PENS):
        floor_y=top+1
        for x in range(2,w-2):
            if abs(x-gate)<=2: continue
            cells[top,x]=1;post(im,x*16,top*16+3)
        d.rounded_rectangle(((gate-2)*16,floor_y*16,(gate+3)*16-1,(floor_y+2)*16-1),radius=4,fill='#acb876',outline='#ece1ac',width=2)
        for x in range(gate-2,gate+3):
            d.line((x*16+8,(floor_y+1)*16+4,x*16+8,(floor_y+1)*16-4),fill='#e8dba3',width=2)
        # Each stage has its own hedge island; its two passages can be walked around.
        island_x=[20,13,7,17][i]
        for x in range(island_x,island_x+2):
            for y in range(top+5,top+7):
                cells[y,x]=1;im.paste(tile('darkgrass'),(16*x,16*y))
                d.rounded_rectangle((16*x,16*y+3,16*x+15,16*y+14),3,fill='#447d4b',outline='#386847')
                d.line((x*16+3,y*16+4,x*16+10,y*16+4),fill='#91ae68')
        pens.append({'gate':[gate,top],'flocks':[[x,top+dy] for x,dy in STARTS],
                     'trainer':([3,top+6] if i else []),'dogs':[[19,top+5],[6,top+4]] if i==3 else ([[18,top+5]] if i else [])})
    for y in [0,h-1]:
        cells[y,11]=0;im.paste(tile('ground'),(11*16,y*16))
    save(MISSION,'草路竞技场・牧场任务',im,cells,(11,57),[warp((11,59),LOBBY,(6,1)),warp((11,0),PITCH,(14,24))],{'galar_pens':pens})

def pitch():
    w,h=29,27
    im=tiled(w,h,'grass');cells=np.zeros((h,w),int);d=ImageDraw.Draw(im)
    cells[:6,:]=1;cells[:,0:3]=1;cells[:,w-3:]=1;cells[h-1,:]=1
    for y in range(6):
        d.rectangle((0,y*16,w*16,(y+1)*16-1),fill=['#6b8a77','#48615c'][y%2])
        d.line((0,y*16+13,w*16,y*16+13),fill='#b8bd95',width=2)
    # Battle Dome seats and individual spectators share the same 16-pixel Emerald grid.
    bench=Image.open(ROOT/'assets/island_landmarks/dome_seats.png').convert('RGB')
    people=[Image.open(ROOT/'assets/npc'/(key+'.png')).convert('RGBA').crop((0,10,16,31))
            for key in ['camper','aroma_lady','youngster','gentleman','lass','picnicker','breeder']]
    for y in range(0,90,24):
        for x in range(0,w*16,96):im.paste(bench,(x,y))
        for x in range(3,w*16,16):
            if (x//16+3*y)%13 in [0,5]:continue
            person=people[(x//16*3+y)%len(people)]
            im.paste(person,(x,y+2),person)
    # Yellow stair aisles and a rail separate spectators from the pitch.
    for cx in (38,218,400):
        d.rectangle((cx,0,cx+13,90),fill='#b4a76f',outline='#56675a')
        for sy in range(4,88,7):d.line((cx+2,sy,cx+11,sy),fill='#e0d5a0')
    d.rectangle((0,89,w*16,99),fill='#4c796c',outline='#324f4d')
    for x in range(0,w*16,32):
        d.rectangle((x+1,91,x+29,96),fill='#a5c79b')
    for y in range(100,(h-1)*16):
        if ((y-100)//32)%2==0:
            row=np.asarray(im.crop((48,y,(w-3)*16,y+1))).astype(np.int16)
            row=np.clip(row+np.array([[-7,3,-10]]),0,255).astype(np.uint8)
            im.paste(Image.fromarray(row),(48,y))
    # Turf border, team markings and the players' tunnel.
    for x in [2,w-3]:
        for y in range(7,h-1):im.paste(tile('stone'),(x*16,y*16))
    d.rectangle((190,391,274,415),fill='#658873',outline='#476c62')
    for y in [395,403,411]:d.line((201,y,263,y),fill='#abc1a0',width=2)
    d.rectangle((62,104,401,382),outline='#e6e7b6',width=3);d.line((64,243,398,243),fill='#e6e7b6',width=3)
    d.ellipse((172,185,291,303),outline='#f1eccb',width=4);d.ellipse((183,196,280,292),outline='#b7cf99',width=2)
    d.polygon([(209,263),(211,230),(248,217),(246,246),(228,261)],fill='#547c55',outline='#e3e1ae');d.line((210,267,242,224),fill='#dacc92',width=3)
    for x in (1,27):
        for y in (7,11,15,19,23):stamp(im,sprite('banner'),(x,y))
    cells[26,14]=0;im.paste(tile('stone'),(14*16,26*16))
    save(PITCH,'草路竞技场・对战草坪',im,cells,(14,24),[warp((14,26),MISSION,(11,1))],{'galar_power_spot':True})

def uniform():
    # Keep Brendan's hair, headband, bag and the surfing Pokémon in their original palette.
    for source,target,cut in [('player_emerald','walk',22),('player_surf','surf',16)]:
        im=Image.open(ROOT/'assets'/(source+'.png')).convert('RGBA')
        frame=im.width//(9 if target=='walk' else 3)
        for x in range(im.width):
            for y in range(cut, min(cut+9,im.height)):
                if target=='surf' and not 9<=x%frame<=22: continue
                r,g,b,a=im.getpixel((x,y))
                palette={(197,65,65):(83,156,85),(255,98,90):(145,207,99),
                         (16,32,57):(201,219,184),(123,65,65):(74,106,71)}
                if a and (r,g,b) in palette:im.putpixel((x,y),(*palette[r,g,b],a))
        im.save(OUT/('uniform_'+target+'.png'),optimize=True)

def main():
    OUT.mkdir(parents=True,exist_ok=True);uniform();mascots();lobby();mission();pitch()
    p=MAPS.parent/'region.json';reg=json.loads(p.read_bytes())
    for key in [MISSION,PITCH]:
        if key not in reg['maps']:reg['maps'].append(key)
    write(p,reg)

if __name__=='__main__':main()
