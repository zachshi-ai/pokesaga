#!/usr/bin/env python3
"""Compile the game's collision maps and landmark anchors into semantic field plans."""
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path
import os
import re
import zlib

import numpy as np
from PIL import Image
TERRAIN = ("grass", "woodland", "water", "trail", "flower", "mountain", "cliff",
           "roof", "door", "fence", "sand", "tall", "pave", "floor", "rug", "wall",
           "rockfloor", "ice", "lava", "bridge", "ash", "meadow", "deep", "marsh",
           "dune", "snow", "ruin", "gym", "surf", "stair", "empty", "urban", "marble", "civic", "clinic", "astral", "snowcliff")

ROOT = Path(os.environ.get("POKESAGA_PROJECT", Path(__file__).resolve().parents[1])).resolve()
META = ROOT / "content/emerald_maps"
N = dict(zip(TERRAIN, range(len(TERRAIN))))
INTERIORS = {"house","gate","mart","pokecenter","tower","elite_four_room","lighthouse","traditional_house","game_corner","facility","mansion","players_house","radio_tower","train_station","battle_tower_inside","players_room","pokecom_center","champions_room","lab"}
FLOOR = {"coast":"sand","forest":"woodland","highland":"mountain","garden":"meadow","snow":"snow","desert":"dune","cave":"rockfloor","city":"pave","interior":"floor","ruins":"ruin","marsh":"marsh","volcano":"ash","space":"deep"}
BUILDINGS = {"home","lab","gym","mart","center","ruin","treehouse"}


def profile(m, meta, key):
    if m.get("biome"): return m["biome"]
    tile = str(meta.get("tileset","")).lower()
    name = (key+" "+str(meta.get("secondary",""))).lower()
    if key=="kanto_main": return "grass"
    if tile in INTERIORS: return "interior"
    if tile in ("ice_path",): return "snow"
    if tile in ("underground","dark_cave","cave"): return "cave"
    if tile in ("ruins_of_alph","aerodactyl_word_room","alph_word_room"): return "ruins"
    if tile in ("park","forest"): return "forest"
    if tile in ("port",): return "coast"
    if re.search(r'forest|woods|viridianforest',name) and not re.search(r'gate|house',name): return "forest"
    if re.search(r'cave|tunnel|victoryroad|cavern|underground|diglett|altering',name): return "cave"
    if re.search(r'icefall|seafoam|frozen|ice_path',name): return "snow"
    if re.search(r'[1-9](f|b)\b|b\d+f|house|center|mart|gym|lobby|club|mansion|laboratory|condo|department|school|museum|gate|silph|ssanne|ss_anne|office|gamecorner|restaurant|league|daycare|tower',name): return "interior"
    if meta.get("primary") and re.search(r'building|indoor',meta["primary"].lower()): return "interior"
    if re.search(r'ruin|chamber|shrine|pillar|temple',name): return "ruins"
    if re.search(r'volcan|ember|magma',name): return "volcano"
    if re.search(r'mountain|mt_|canyon|cliff|plateau',name): return "highland"
    if re.search(r'beach|harbor|port|water|island|sea_|coast|shore',name): return "coast"
    if re.search(r'town|city|village',name): return "grass"
    return "grass"


def rgb_map(meta, w, h):
    if meta.get("png"):
        p=META/meta["png"]
        if p.exists():
            with Image.open(p) as im:return np.asarray(im.convert("RGB").resize((w,h), Image.Resampling.BOX)).astype(int)
    if meta.get("chunks"):
        dst=Image.new("RGB",(w,h))
        for chunk in meta["chunks"]:
            p=META/chunk["png"]
            if p.exists():
                with Image.open(p) as im:
                    dst.paste(im.convert("RGB").resize((im.width//16,im.height//16),Image.Resampling.BOX),tuple(chunk["at"]))
        return np.asarray(dst).astype(int)
    return None


def layer(meta, key, shape):
    a=np.array(meta.get(key,[]))
    return a.astype(bool) if a.shape==shape else np.zeros(shape,dtype=bool)


def old_ground(m, meta, key, biome, w, h):
    shape=(h,w);rgb=rgb_map(meta,w,h)
    solid=layer(meta,"collision",shape);water=layer(meta,"water",shape)
    floor=np.full(shape,N[FLOOR.get(biome,"grass")],np.uint8)
    if rgb is not None:
        r,g,b=rgb.transpose(2,0,1)
        warm=(r>g*1.07)&(r>b*1.25)
        grey=(abs(r-g)<14)&(abs(b-g)<17)
        blue=(b>r*1.38)&(b>g*1.05)
        green=(g>r*1.15)&(g>b*1.15)
        if biome in ("grass","forest","coast","city"):
            floor[warm]=N["trail"];floor[green]=N["grass" if biome!="forest" else "woodland"]
            floor[grey&~solid]=N["pave"]
            if "water" not in meta: water |= blue&solid
        if biome=="interior":
            floor[warm&~solid&(r>g*1.32)]=N["rug"]
            floor[blue&~solid]=N["gym"]
    if biome=="interior": floor[solid]=N["wall"]
    elif biome in ("cave","ruins","highland","snow","volcano","desert","space"):
        floor[solid]=N["cliff"]
    else: floor[solid]=N["woodland"]
    floor[layer(meta,"grass",shape)]=N["tall"];floor[water]=N["water"]
    floor[layer(meta,"deep",shape)]=N["deep"];floor[layer(meta,"slide",shape)]=N["ice"]
    floor[layer(meta,"waterfall",shape)]=N["surf"];floor[layer(meta,"hole",shape)]=N["rockfloor"]
    floor[layer(meta,"ledge",shape)&~water]=N["mountain"]
    if key=="kanto_main" and rgb is not None:
        # Areas outside the constituent maps are deliberately dark and impassable.
        floor[(rgb.max(2)<16)&solid]=N["empty"]
    return floor,solid


def logical_ground(m, biome, w, h):
    src=np.array(m.get("tiles",[]),dtype=np.uint8)
    if src.shape!=(h,w):return None,None
    table=np.array([N[FLOOR.get(biome,"grass")],N["woodland"],N["water"],N["trail"],N["flower"],N["mountain"],N["cliff"],N["roof"],N["door"],N["fence"],N["sand"],N["tall"],N["pave"],N["bridge"],N["rug"],N["wall"]],np.uint8)
    if biome in ("interior","space"):table[[0,5,6,12,13]]=[N["floor"],N["rockfloor"],N["wall"],N["gym"],N["floor"]]
    if biome in ("volcano","desert","highland","snow","ruins","cave"):table[1]=N["cliff"]
    if biome=="snow":table[11]=N["ice"]
    if biome=="marsh":table[2]=N["marsh"]
    return table[src.clip(0,len(table)-1)], np.isin(src,[1,2,6,7,9,15])


def doorway(target):
    if re.search(r'pok[eé](?:mon)?_?center|healing|pokecen',target):return "center"
    if re.search(r'mart|store|market',target):return "mart"
    if re.search(r'gym|league|arena',target):return "gym"
    if re.search(r'lab|museum|office|station|silph|school',target):return "lab"
    if re.search(r'cave|tunnel|mount|victory|mt_|ruin|chamber',target):return "ruin"
    if re.search(r'house|home|fan_?club|inn|condominium|center|gate|hut|hotel|mansion|building|tower',target):return "home"
    return ""


def compile_map(key, m, region=""):
    physical=m.get("emerald",""); path=META/(physical+".json")
    meta=json.loads(path.read_text()) if physical and path.exists() else {}
    w,h=map(int,meta.get("size",m.get("size",[0,0])))
    if w<1 or h<1:return None
    biome=profile(m,meta,key); floor=solid=None
    if meta:floor,solid=old_ground(m,meta,key,biome,w,h)
    if floor is None:floor,solid=logical_ground(m,biome,w,h)
    if floor is None:return None
    interior=biome in ("interior","space")
    if biome=="city":
        # Select material from a distinct civic plaza for each region.
        stone={"sinnoh":"urban","unova":"urban","paldea":"civic","kalos":"marble","galar":"urban",
               "armor":"marble","hisui":"trail","hoenn":"pave","alola":"pave","crown":"urban"}.get(region,"marble")
        floor[floor==N["pave"]]=N[stone]
    if biome=="space":
        floor[np.isin(floor,[N["floor"],N["rockfloor"],N["gym"]])]=N["astral"]
    if biome=="snow":floor[floor==N["cliff"]]=N["snowcliff"]
    clinic=bool(re.search(r'pokemon_?center|poke_?center|_pc_1f',key))
    if clinic:
        floor[np.isin(floor,[N["floor"],N["rug"],N["gym"]])]=N["clinic"]
    props=[]; claimed=np.zeros((h,w),bool)
    keep={tuple(s.get("at",[-1,-1])) for s in m.get("objects",[])+m.get("npcs",[])}
    warps={tuple(s["at"]) for s in m.get("warps",[]) if "at" in s}
    spawn=tuple(m.get("spawn",[0,0])); keep.add(spawn)
    def prop(kind,x,y,sw,sh,footprint=True):
        if not 0<=x<w or not 0<=y<h:return
        props.append([kind,int(x),int(y),round(sw,2),round(sh,2)])
        if footprint:
            sx=max(0,int(x-sw/2));ex=min(w,int(x+sw/2+1))
            sy=max(0,int(y-sh+1));claimed[sy:y+1,sx:ex]=True
    alias={"tower":"treehouse" if biome=="forest" else "lab","plant":"flowers","door":"home","stairs":"stairs","boulder":"rock"}
    for p in m.get("art_props",[]):
        x,y=p["at"];sw,sh=p.get("size",[2,2]);kind=alias.get(p["kind"],p["kind"])
        if kind in ("rock","shrine","flowers") and not solid[y,x]:
            sw,sh=min(sw,1.8),min(sh,1.6)
        if kind=="lab" and (region=="paldea" or "academy" in key):kind="academy"
        prop(kind,x,y,sw,sh)
        if biome=="city":
            area=np.array(m.get("tiles",[]))
            if area.shape==(h,w):
                sx=max(0,round(x-sw/2));ex=min(w,round(x+sw/2+1));sy=max(0,round(y-sh+1))
                patch=floor[sy:y+1,sx:ex]
                patch[np.isin(area[sy:y+1,sx:ex],[6,7,9])]=N[stone]
        if kind in BUILDINGS|{"academy"}:
            area=np.array(m.get("tiles",[]))
            if area.shape==(h,w):
                floor[claimed&np.isin(area,[6,7])]=N[stone] if biome=="city" else N["pave"]
    if meta:
        occupied=set()
        for warp in m.get("warps",[]):
            x,y=map(int,warp.get("at",[-1,-1]))
            if not 0<=x<w or not 0<=y<h or (x,y) in occupied:continue
            occupied.add((x,y))
            dest=str(warp.get("to",{}).get("map","")).lower()
            if interior or biome in ("cave","ruins"):
                if 0<y<h-1: floor[y,x]=N["stair"]
                else:floor[y,x]=N["rug" if interior else "trail"]
                continue
            if key=="littleroot_town" and (x,y) in {(5,8),(14,8),(7,16)}:
                continue
            building=doorway(dest)
            if not building or warp.get("edge"):continue
            if min(x,w-1-x,y,h-1-y)<1:continue
            if any(abs(x-ox)<=1 and y==oy for _,ox,oy,_,_ in props):continue
            # A small Crystal logical map uses an entire 32px block as one cell.
            compact=meta.get("source")=="pokecrystal"
            sw,sh=(2.6,2.15) if compact else (4.25,3.4)
            if building in ("center","lab","gym"):sw+=.55
            prop(building,x,y,sw,sh)
            floor[y,x]=N["door"]
    # The field actions (TV, wall map, bed and staircase) have fixed interaction coordinates.
    if key=="pallet_town_players_house_2f":
        props.clear();claimed[:]=False
        for a in [("pc",1,1,1.3,.95),("clock",4,1,.73,.74),("map",11,1,.86,.70),("woodstairs",10,2,1.3,1.5),
                  ("ceilingbed",2,6,2.18,1.47),("tv",6,5,1.95,1.55),("desk",7,2,2.3,1.92)]:
            prop(*a)
        floor[~solid]=N["floor"];floor[5:7,5:8]=N["rug"];floor[2,10]=N["stair"]
    if key=="pallettown_playershouse_1f":
        for a in [("woodstairs",10,2,1.2,1.5),("desk",6,5,2.3,1.85),("bookshelf",3,1,2.,1.3),("pc",8,1,1.32,.95)]:
            prop(*a)
    if clinic:
        for npc in m.get("npcs",[]):
            if npc.get("gfx") in ("nurse","nurse_joy") or "护士" in npc.get("name",""):
                x,y=npc["at"]
                if y+1<h:
                    prop("officecounter",x,y+1,4.3,1.2)
                    if w>10:
                        prop("carebench",2,y+2,1.6,.8)
                        prop("pc",w-3,y+1,1.3,1.2)
                break
    if key=="littleroot_town":
        for a in [("home",5,8,4.1,3.4),("home",14,8,4.1,3.4),("birch_lab",7,16,5.9,3.65)]:prop(*a)
    seed=int.from_bytes(hashlib.sha256(key.encode()).digest()[:4],"little")
    if interior:
        small=(w<12 or h<10)
        if key not in ("pallet_town_players_house_2f","pallettown_playershouse_1f") and not clinic:
            kind="desk" if re.search(r'lab|office|center|school|gym',key) else "bookshelf"
            spots=[(x,y) for y in range(min(1,h-1),max(2,min(h-1,4))) for x in range(1,w-1)
                   if solid[y,x] and (x,y) not in warps|keep and not claimed[y,x]]
            if spots:
                x,y=spots[seed%len(spots)];prop(kind,x,y,1.5 if small else 2.2,1.3 if small else 1.7)
    else:
        for y in range(h):
            for x in range(w):
                if not solid[y,x] or claimed[y,x] or (x,y) in warps or (x,y) in keep:continue
                ty=int(floor[y,x]);k=(seed+x*374761393+y*668265263)&0xffffffff
                if ty==N["woodland"]:
                    # Keep crowns rooted on blocked cells and leave doorways unobscured.
                    if (x+((y//2)&1))%2 or y%2:continue
                    if any((nx,ny) in warps for nx in range(x-1,x+2) for ny in range(y-2,y+1)):continue
                    prop("tree",x,y,1.82+(k%9)*.035,1.95+(k%7)*.055,False)
                elif ty==N["cliff"] and k%9==0:
                    prop("rock",x,y,1.1+(k%3)*.15,1.05,False)
    if not interior:
        for entry in m.get("objects",[]):
            if entry.get("kind")!="sign":continue
            x,y=entry.get("at",[-1,-1])
            if 0<=x<w and 0<=y<h and not claimed[y,x]:
                prop("sign",x,y,.78,.99,False)
    # Buildings should have a navigable entrance, including routes authored with an edge portal.
    if not meta:
        for x,y in warps:
            if 0<=x<w and 0<=y<h and floor[y,x]==N["door"]:
                floor[y,x]=N["stair" if interior else "trail"]
    result={"s":[w,h],"b":biome,"t":base64.b64encode(zlib.compress(floor.tobytes(),9)).decode(),"p":props}
    if key in ("pallet_town_players_house_2f","pallettown_playershouse_1f"):
        result["backdrop"]="room_ground"
    elif clinic:
        result["backdrop"]="clinic_ground"
    elif m.get("field_backdrop") in ("room_ground","clinic_ground"):
        result["backdrop"]=m["field_backdrop"]
    return result
