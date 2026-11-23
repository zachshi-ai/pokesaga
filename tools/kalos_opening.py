"""Stage the X/Y opening at Emerald's native 16 px scale, preserving the original warp graph.

python tools/kalos_opening.py --emerald-source /path/to/pret/pokeemerald
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

from asset_paths import source_path
from bake_emerald_field import Emerald, cut_background
from unova_art import encode
from kalos_gym_rooms import tile

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "content/regions/kalos/maps"
ART = ROOT / "assets/kalos/maps"
PROPS = ROOT / "assets/emerald/field"
ANCHORS = json.loads((ROOT / "content/emerald_fields.json").read_text())["anchors"]

# The last two coordinates are the safe side of the threshold, for return journeys.
DOORS = {
    "vaniville": {"home_1f":(18,10,18,11), "zone_6":(5,10,5,11),
                  "rival_home":(25,9,25,10), "1":(13,1,13,2)},
    "1": {"vaniville":(7,14,7,13), "aquacorde":(7,1,7,2)},
    "aquacorde": {"zone_9":(25,14,25,15), "zone_10":(25,23,25,24),
                  "zone_11":(5,21,5,22), "1":(15,31,15,30), "2":(15,1,15,2)},
    "2": {"aquacorde":(12,35,12,34), "forest":(9,1,9,2)},
    "zone_9":{"aquacorde":(7,10,7,9)}, "zone_10":{"aquacorde":(6,10,6,9)},
    "zone_11":{"aquacorde":(6,10,6,9)},
}
# Landmarks from the 4.61 mesh projection. A save on a doorway belongs on its public side.
LEGACY = {
    "vaniville":[(30,11,18,11),(38,11,25,10),(15,12,5,11),(25,5,13,2),(39,26,17,13)],
    "1":[(25,34,7,13),(25,5,7,2),(38,20,7,8)],
    "aquacorde":[(71,51,25,15),(71,57,25,24),(55,54,5,22),(65,84,15,30),(63,15,15,2),
                 (63,28,15,6),(63,53,15,18),(54,51,8,16)],
    "2":[(22,41,9,2),(23,91,12,34),(23,85,12,28),(19,48,10,8)],
    "zone_9":[(3,7,7,9),(7,8,8,7)],"zone_10":[(3,7,6,9),(7,8,7,8)],
    "zone_11":[(12,7,6,9),(8,8,7,8)],
}


def write(path, value):
    path.write_text(json.dumps(value,ensure_ascii=False,separators=(",",":"))+"\n")


class Field:
    def __init__(self, key, size, spawn, emerald):
        self.key, self.size, self.spawn = key, size, spawn
        w,h=size
        self.e = emerald
        self.cells = np.full((h,w), "grass", dtype=object)
        self.solid = np.zeros((h,w), dtype=np.uint8)
        self.water = np.zeros_like(self.solid)
        self.counter = np.zeros_like(self.solid)
        self.props = []
        self.npcs = []
        self.signs = []
        self.actors = {}
        self.special = {}
        self.chips = {}
        self.base = None

    def rect(self, x, y, right, bottom, material, blocked=False):
        self.cells[y:bottom+1,x:right+1] = material
        self.solid[y:bottom+1,x:right+1] = blocked
        self.water[y:bottom+1,x:right+1] = material=="water"

    def prop(self, name, x, y, width=1, left=0, depth=1):
        self.props.append([name,x,y,ANCHORS[name]])
        self.solid[y-depth+1:y+1,max(0,x-left):x-left+width] = 1

    def sign(self,x,y,text):
        self.prop("sign",x,y)
        self.signs.append({"kind":"sign","at":[x,y],"text":text})

    def house(self,name,x,y):
        # The warp shares the source façade door column, even for an off-centre door.
        w,h=Image.open(PROPS/(name+".png")).size
        left=ANCHORS[name][0]//16
        self.prop(name,x,y,w//16,left,h//16-1)
        self.solid[y,x]=0
        self.cells[y,x]="pave"

    def trees(self,points):
        for x,y in points:
            self.prop("tree",x,y,2,0,2)

    def fence(self,x,y,right,bottom):
        self.rect(x,y,right,bottom,"rail",True)

    def grass_rim(self,skip_north=(),skip_south=()):
        w,h=self.size
        self.solid[[0,-1],:]=1
        self.solid[:,[0,-1]]=1
        self.trees([(x,2) for x in range(0,w-1,2) if x not in skip_north])
        self.trees([(x,h-1) for x in range(0,w-1,2) if x not in skip_south])
        for y in range(4,h-1,2):
            self.trees([(0,y),(w-2,y)])
        for x in skip_north:
            self.solid[1:3,x:x+2]=0
        for x in skip_south:
            self.solid[h-2:h-1,x:x+2]=0

    def gates(self,m):
        # All three stones of each open road mouth are live thresholds.
        m["warps"]=[w for w in m["warps"] if not w.get("opening_lane")]
        for dest,(x,y,_,_) in DOORS[self.key].items():
            warp=next(w for w in m["warps"] if w["to"]["map"]=="kalos_"+dest)
            warp["at"]=[x,y]
            assert not self.solid[y,x] and not self.water[y,x],(self.key,dest)
            if self.key in ("1","2") or dest in ("1","2") and self.key in ("vaniville","aquacorde"):
                for offset in (-1,1):
                    other=deepcopy(warp)
                    other["at"]=[x+offset,y]
                    other["opening_lane"]=offset
                    self.solid[y,x+offset]=0
                    self.cells[y,x+offset]=self.cells[y,x]
                    m["warps"].append(other)
                # Fence the rest of the map boundary with real trees. This keeps
                # every opening navigable and avoids walking behind a step warp.
                self.trees([(x-3,y+1 if y==1 else y),(x+2,y+1 if y==1 else y)])

    def terrain(self):
        w,h=self.size
        if self.base is not None:
            return self.base
        pic=Image.new("RGB",(w*16,h*16))
        # Shore and path corners follow their semantic masks, including inside bends.
        for y in range(h):
            for x in range(w):
                key=self.cells[y,x]
                def has(dx,dy,value):
                    a,b=x+dx,y+dy
                    return 0<=a<w and 0<=b<h and self.cells[b,a]==value
                if key=="trail":
                    col=0 if not has(-1,0,key) else 2 if not has(1,0,key) else 1
                    row=0 if not has(0,-1,key) else 2 if not has(0,1,key) else 1
                    chip=tile(f"trail_{row}{col}")
                elif key=="water":
                    # North, west, east and south banks from Emerald's General tileset.
                    col=0 if x>0 and not has(-1,0,key) else 2 if x<w-1 and not has(1,0,key) else 1
                    row=0 if y>0 and not has(0,-1,key) else 2 if y<h-1 and not has(0,1,key) else 1
                    chip=self.e.metatile("Route104",[[0xb0,0xb1,0xb2],[0xb8,0xa1,0xba],[0xc8,0xc9,0xca]][row][col]).convert("RGB")
                    # The native lake metatile animates only with its VRAM palette.
                    # Bake the matching first-frame ripples into static river water.
                    water=np.asarray(chip).copy()
                    bare=np.asarray(self.e.metatile("Route104",0xa1).convert("RGB"))[8,8]
                    open_water=(water==bare).all(axis=2)
                    waves=np.asarray(self.e.metatile("Route104",0x170).convert("RGB"))
                    water[open_water]=waves[open_water]
                    chip=Image.fromarray(water)
                elif key in self.chips:
                    chip=self.chips[key]
                elif key in self.special:
                    zone,col,row=self.special[key]
                    chip=self.e.metatile(zone,self.e.grid(zone)[row,col])
                else:
                    chip=tile(key)
                pic.paste(chip,(x*16,y*16))
        return pic

    def finish(self,m):
        self.gates(m)
        physics={"size":list(self.size),"collision":self.solid.tolist()}
        for key,mask in (("water",self.water),("grass",self.cells=="tall"),("counter",self.counter)):
            if mask.any():physics[key]=mask.astype(np.uint8).tolist()
        walk=~(self.solid | self.water).astype(bool)
        taken={self.spawn}
        for x,y,a,b in DOORS[self.key].values():
            walk[y,x]=False
            taken.update([(x,y),(a,b)])
        for warp in m["warps"]:
            x,y=warp["at"];walk[y,x]=False;taken.add((x,y))
        for npc in self.npcs:
            x,y=npc["at"];walk[y,x]=False;taken.add((x,y))
        labels,_=ndimage.label(walk)
        group=labels[self.spawn[1],self.spawn[0]]
        assert group
        available={(int(x),int(y)) for y,x in zip(*np.where(labels==group))}-taken
        # Only the actors assigned by the campaign are spawned. Keep its independent
        # trainer/side slots on reachable standing cells, away from every threshold.
        anchors={}
        for key in sorted(m["kalos_anchors"],key=lambda k:k not in self.actors):
            preferred=self.actors.get(key,self.spawn)
            point=min(available,key=lambda p:((p[0]-preferred[0])**2+(p[1]-preferred[1])**2,p))
            anchors[key]=list(point)
            # Small original shop interiors have fewer tiles than generic unused slots.
            if len(available)>1:available.remove(point)
        scene_name="opening_"+self.key
        self.terrain().save(ART/(scene_name+".png"),optimize=True)
        m.update(size=list(self.size),spawn=list(self.spawn),physics=physics,npcs=self.npcs,objects=self.signs,
                 kalos_anchors=anchors,kalos_image=scene_name,kalos_opening_revision=1,
                 kalos_legacy_points=LEGACY[self.key],
                 hoenn_art={"s":list(self.size),"t":encode(np.zeros_like(self.solid)),"p":self.props,
                            "scene":["res://assets/kalos/maps/"+scene_name+".png",0,0]})
        room_names={"zone_9":"名水镇・休息之家","zone_10":"名水镇・伤药店","zone_11":"名水镇・精灵球店"}
        if self.key in room_names:m["name"]=room_names[self.key]
        return m


def village(e):
    f=Field("vaniville",(31,22),(17,13),e)
    f.special["rail"]=("Route104",15,27)
    f.rect(11,0,15,12,"trail");f.rect(3,10,27,14,"trail")
    f.rect(16,9,20,13,"trail");f.rect(24,9,26,12,"trail")
    f.grass_rim(skip_north=(12,14))
    f.house("home_red",5,10);f.house("home",18,10);f.house("home_blue",25,9)
    for x,y in [(3,4),(5,4),(7,5),(18,4),(24,3),(27,4),(28,16),(3,16)]:
        f.trees([(x,y)])
    for x,y in [(8,11),(15,11),(27,10),(9,17),(21,16)]:
        f.rect(x,y,x+1,y,"flowers")
    f.fence(19,15,27,15);f.fence(19,19,27,19)
    f.rect(19,16,19,18,"rail_side",True);f.rect(27,16,27,18,"rail_side",True)
    f.special["rail_side"]=("RustboroCity",6,18)
    f.rect(20,16,26,18,"trail")
    icon=Image.open(e.source/"graphics/pokemon/rhyhorn/icon.png").convert("RGBA").crop((0,0,32,32))
    icon.save(ART/"opening_rhyhorn.png",optimize=True)
    f.props.append(["res://assets/kalos/maps/opening_rhyhorn.png",23,17,[16,29]])
    f.solid[17,23]=1
    f.rect(5,16,8,17,"flowers");f.prop("planter",13,16,3,1)
    f.sign(11,5,"往北经过１号道路，可到名水镇。")
    f.npcs=[{"at":[16,13],"name":"地区领航员","gfx":"sailor","transit":True}]
    f.actors={"story":(18,12),"guest1":(16,14)}
    return f


def avenue(e):
    f=Field("1",(15,16),(7,8),e)
    f.special["rail"]=("Route104",15,27)
    f.rect(5,0,9,15,"trail")
    f.grass_rim(skip_north=(6,8),skip_south=(6,8))
    for x in (3,11):
        for y in (4,9):
            f.rect(x,y,x,y+2,"flowers")
        f.prop("streetlamp",x,7)
    return f


def riverside(e):
    f=Field("aquacorde",(31,33),(11,19),e)
    f.special={"rail":("RustboroCity",30,7),"step":("SootopolisCity",12,21),
               "terrace":("SootopolisCity",8,20),"promenade":("RustboroCity",18,10)}
    # Join the middle halves of the two Route 104 bridge tiles. Tiling their
    # ends directly would put blue gaps across the pedestrian deck.
    planks=e.patch("Route104",24,12,2,1).crop((8,0,24,16)).convert("RGB")
    f.chips["bridge_deck"]=planks
    iron=e.patch("RustboroCity",30,7,1,1)
    railing=cut_background(iron,[e.metatile("RustboroCity",0x2bb)]).rotate(90)
    for side,left in [("west",True),("east",False)]:
        chip=e.metatile("Route104",0x170).convert("RGBA")
        start=8 if left else 0
        chip.paste(planks.crop((start,0,start+8,16)),(start,0))
        chip.alpha_composite(railing if left else railing.transpose(Image.Transpose.FLIP_LEFT_RIGHT))
        f.chips["bridge_"+side]=chip
    f.rect(2,10,28,27,"pave");f.rect(12,0,18,31,"pave")
    f.grass_rim(skip_north=(14,16),skip_south=(14,16))
    f.rect(0,4,30,9,"water")
    f.rect(13,4,17,9,"bridge_deck")
    f.rect(12,4,12,9,"bridge_west",True);f.rect(18,4,18,9,"bridge_east",True)
    for x in (3,20):f.fence(x,10,x+7,10)
    for x,y in [(11,10),(19,10),(12,23),(18,23),(12,29),(18,29)]:
        f.prop("streetlamp",x,y)
    f.rect(12,17,18,17,"promenade")
    f.rect(14,10,16,26,"promenade")
    f.prop("fountain",15,16,3,1,3)
    # Friends meet at the western terrace overlooking the fountain.
    f.prop("desk",8,15,3,2,1)
    f.prop("planter",7,12,3,1)
    f.house("home_green",25,14);f.house("mart",5,21);f.house("home_red",25,23)
    f.sign(8,21,"精灵球专卖店　每个２００元。");f.sign(27,23,"伤药专卖店　每瓶３００元。")
    for x in (5,25):
        f.prop("planter",x,26,3,1)
    f.fence(2,27,11,27);f.fence(19,27,28,27)
    # Continuous stone risers on the south terrace; its single stair flight stays open.
    f.rect(2,28,12,28,"terrace",True);f.rect(18,28,28,28,"terrace",True)
    f.rect(13,27,17,28,"step")
    f.npcs=[{"at":[22,25],"name":"散步的男士","gfx":"gentleman","kalos_intro_potion":True}]
    f.actors={"story":(7,16),"guest1":(5,15),"guest2":(9,16),"guest3":(8,14)}
    return f


def meadow(e):
    f=Field("2",(23,37),(12,28),e)
    f.rect(10,25,14,36,"trail");f.rect(7,23,14,26,"trail")
    f.rect(7,16,10,25,"trail");f.rect(8,14,15,17,"trail")
    f.rect(13,8,16,16,"trail");f.rect(8,7,16,9,"trail");f.rect(8,0,11,8,"trail")
    f.grass_rim(skip_north=(8,10),skip_south=(10,12))
    for x,y,r,b in [(3,8,6,14),(6,10,12,13),(4,20,7,24),(12,18,19,23),
                    (15,26,18,31),(5,28,9,32)]:
        f.rect(x,y,r,b,"tall")
    for x,y in [(2,5),(4,5),(5,6),(3,18),(18,8),(20,9),(18,15),(18,25),(2,30),(4,29),(17,34)]:
        f.trees([(x,y)])
    for x,y in [(3,15),(5,15),(14,24),(15,24),(19,32),(3,27)]:
        f.rect(x,y,x,y,"flowers")
    f.sign(11,5,"２号道路　前方是白檀森林。");f.prop("rock",18,16)
    f.actors={"story":(12,32),"guest1":(10,31),"trainer1":(11,9)}
    return f


def room(key,e):
    healer=key=="zone_9"
    name="HouseWithBed" if healer else "Mart"
    layout=e.layouts[name]
    w,h=layout["width"],layout["height"]
    words=np.fromfile(e.source/layout["blockdata_filepath"],"<u2").reshape(h,w)
    f=Field(key,(17,15),(8,9),e)
    f.solid[:]=1
    ox,oy=3,3
    f.solid[oy:oy+h,ox:ox+w]=((words>>10)&3)!=0
    f.base=Image.new("RGB",(17*16,15*16),"#26353b")
    f.base.paste(e.patch(name,0,0,w,h),(ox*16,oy*16))
    if healer:
        f.npcs=[{"at":[7,6],"name":"照顾宝可梦的女士","gfx":"woman_1","heal":True}]
    else:
        f.npcs=[{"at":[4,6],"name":"精灵球店店员" if key=="zone_11" else "伤药店店员",
                 "gfx":"clerk","shop":True,"kalos_shop":True,"facing":"right"}]
        f.counter[6,5]=1
        item="精灵球" if key=="zone_11" else "伤药"
        num=json.loads((ROOT/"content/ui_item_icons.json").read_text())[item]
        atlas=Image.open(ROOT/"assets/ui/field/bag_icons.png").convert("RGBA")
        x,y=num%16*24,num//16*24
        bottle=atlas.crop((x,y,x+24,y+24))
        bottle=bottle.crop(bottle.getbbox())
        bottle.thumbnail((12,13),Image.Resampling.NEAREST)
        for x in (9,10,12):
            f.base.paste(bottle,(x*16,4*16-2),bottle)
    return f


def install(source):
    e=Emerald(source)
    fields=[village(e),avenue(e),riverside(e),meadow(e),*(room("zone_"+str(i),e) for i in (9,10,11))]
    maps={f.key:f for f in fields}
    for path in MAPS.glob("*.json"):
        m=json.loads(path.read_text())
        key=m.get("id","").removeprefix("kalos_")
        changed=key in maps
        if changed:m=maps[key].finish(m)
        for w in m.get("warps",[]):
            dest=w["to"]["map"].removeprefix("kalos_")
            if dest in DOORS and key in DOORS[dest]:
                at=list(DOORS[dest][key][2:])
                if w.get("opening_lane") and dest in ("vaniville","1","aquacorde","2"):
                    at[0]+=w["opening_lane"]
                w["to"]["at"]=at
                changed=True
        if changed:write(path,m)
    world_path=ROOT/"content/world_destinations.json"
    world=json.loads(world_path.read_text());reg=world["regions"]["kalos"]
    for loc in reg["locations"]:
        key=loc["map"].removeprefix("kalos_")
        if key in maps:loc["at"]=list(maps[key].spawn)
    reg["hub"].update(at=list(maps["vaniville"].spawn),npc_at=maps["vaniville"].npcs[0]["at"])
    write(world_path,world)
    path=MAPS.parent/"region.json";reg=json.loads(path.read_text())
    reg["start"]["at"]=list(maps["vaniville"].spawn);write(path,reg)
    # Original events whose coordinates are baked near a door must follow the
    # same door on standalone rebuilds, too.
    from build_kalos_campaign import place_cast
    path=ROOT/"content/kalos_campaign.json"
    book=json.loads(path.read_text())
    place_cast([event for event in book["events"] if event["map"].removeprefix("kalos_") in maps])
    path.write_text(json.dumps(book,ensure_ascii=False,indent=1)+"\n")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emerald-source",type=Path,default=Path(source_path("emerald")))
    install(parser.parse_args().emerald_source)
