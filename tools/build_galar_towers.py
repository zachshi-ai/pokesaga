"""Build the ten connected Tower of Two Fists floors at Emerald's 16-pixel scale."""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import pack
from island_metatiles import piece
from kalos_gym_rooms import sprite

ROOT=Path(__file__).resolve().parents[1]
MAPS=ROOT/"content/regions/armor/maps"
ART=ROOT/"assets/galar/towers"
EXIT=[7,11]
UP=[12,3]

def save(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")

def warp(cell,mid,landing,direction):
    return {"at":cell,"trigger":direction,"to":{"region":"armor","map":mid,"at":landing}}

def floor(style,level,outside,door):
    name="恶之塔" if style=="dark" else "水之塔"
    mid=f"armor_{style}_floor_{level}"
    w,h=16,13
    image=Image.new("RGB",(w*16,h*16))
    d=ImageDraw.Draw(image)
    ink="#4f4644" if style=="dark" else "#42585d"
    edge="#a07d62" if style=="dark" else "#6eabb3"
    accent="#a55145" if style=="dark" else "#3d788b"
    base=piece("arena_wood")
    walls=np.zeros((h,w),np.uint8)
    walls[:2,:]=1;walls[-1,:]=walls[:,0]=walls[:,-1]=1
    for y in range(h):
        for x in range(w):
            image.paste(base,(x*16,y*16))
    d.rectangle((0,0,w*16,32),fill="#9c8067",outline=ink,width=2)
    for x in range(10,w*16,29):
        d.rectangle((x,4,x+21,23),fill="#d8c99e",outline=ink,width=2)
        d.line((x+11,6,x+11,23),fill=edge);d.line((x+2,14,x+19,14),fill=edge)
    for x in (0,53,150,246):
        d.rectangle((x,0,x+8,35),fill=ink)
        d.line((x+2,1,x+2,33),fill=edge,width=2)
    # Golden mat from the Emerald Battle Arena. Rings and paired stripes are painted into it.
    mat=piece("dojo_mat");image.paste(mat,(64,67))
    for x in (61,194):
        d.line((x,68,x,145),fill=accent,width=2)
    for x in (23,216):
        d.polygon([(x,19),(x+13,19),(x+13,53),(x+6,59),(x,53)],fill=accent,outline=ink)
        for i in range(level):d.line((x+3,26+i*4,x+10,26+i*4),fill="#e4d0a3")
    def stamp(key,x,y):
        im=sprite(key);image.paste(im,(x*16+8-im.width//2,(y+1)*16-im.height),im);walls[y,x]=1
    stamp("plant_indoor" if style=="water" else "statue",2,4)
    stamp("statue" if level==5 else "bookshelf",14,7)
    def stairs(at,up):
        x,y=(i*16 for i in at)
        d.rectangle((x,y,x+15,y+15),fill=ink)
        for i in range(4):
            ex=x+2+i if up else x+2
            d.line((ex,y+3+i*3,x+13,y+3+i*3),fill="#d4c4a3",width=2)
        walls[at[1],at[0]]=0
    stairs(EXIT,False)
    if level<5:stairs(UP,True)
    else:
        d.rectangle((102,19,154,51),fill=accent,outline=ink,width=3)
        d.rectangle((107,22,149,48),fill="#d8c6a0",outline=edge)
        if style=="dark":d.line([(118,41),(128,27),(126,36),(137,28)],fill=ink,width=3)
        else:
            for offset in (0,4,8):d.line([(116,33+offset),(123,29+offset),(131,34+offset),(140,30+offset)],fill=accent,width=2)
    namefile=ART/(mid+".png");image.save(namefile,optimize=True)
    warps=[warp(EXIT,outside if level==1 else f"armor_{style}_floor_{level-1}",[door[0],door[1]+1] if level==1 else [UP[0],UP[1]+1],"down")]
    if level<5:warps.append(warp(UP,f"armor_{style}_floor_{level+1}",[7,10],"up"))
    save(MAPS/(mid+".json"),{"name":f"{name}・{level}层","size":[w,h],"spawn":[7,10],
        "biome":"interior","style":"interior","tiles":walls.tolist(),"npcs":[],"objects":[],"warps":warps,
        "tower_style":style,"tower_floor":level,"hoenn_art":{"s":[w,h],"t":pack(np.zeros(walls.shape,dtype="<u2")),"p":[],
        "scene":[f"res://assets/galar/towers/{mid}.png",0,0]}})
    return mid

def main():
    ART.mkdir(exist_ok=True,parents=True)
    index=MAPS.parent/"region.json";region=json.loads(index.read_text())
    eventfile=ROOT/"content/galar_expansion.json";events=json.loads(eventfile.read_text())
    for style,outside in (("dark","armor_towers"),("water","armor_water_tower")):
        op=MAPS/(outside+".json");hub=json.loads(op.read_text())
        default_door={'dark': [16, 6], 'water': [18, 8]}[style]
        door=next((w["at"] for w in hub["warps"] if w["to"]["map"]==f"armor_{style}_floor_1"),default_door)
        if not any(w["to"]["map"]==f"armor_{style}_floor_1" for w in hub["warps"]):
            hub["warps"].append(warp(door,f"armor_{style}_floor_1",[7,10],"up"))
            hub["objects"].append({"kind":"sign","at":[door[0]+1,door[1]],"text":"双拳塔入口。带着熊徒弟来挑战五层。"})
        hub["tiles"][door[1]][door[0]]=0;hub["tiles"][door[1]+1][door[0]]=0
        save(op,hub)
        for level in range(1,6):
            mid=floor(style,level,outside,door)
            if mid not in region["maps"]:region["maps"].append(mid)
            evt=next(e for e in events if e["id"]==f"dlc_{style}{level}")
            evt.update(map=mid,at=[8,5])
    save(index,region);eventfile.write_text(json.dumps(events,ensure_ascii=False,indent=1)+"\n")
if __name__=="__main__":main()
