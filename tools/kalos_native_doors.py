"""Reconcile a native X/Y threshold with a north-facing door in the 2D engine."""
import argparse
from collections import defaultdict
import json
from pathlib import Path

import numpy as np
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[1]
MAPS=ROOT/"content/regions/kalos/maps"
# These have explicit meshes and movement modes (surf, shallow marsh, the
# mastery tower approach and badge hall). Their dedicated adapters own them.
SPECIAL_ZONES={357,273,172,321}

def read(path):
    return json.loads(path.read_bytes())
def write(path,d):
    path.write_text(json.dumps(d,ensure_ascii=False,separators=(",",":"))+"\n")

def reconcile(maps,raw):
    zones=raw["zones"];fronts={};shifts=defaultdict(list)
    for mid,m in maps.items():
        if not m.get("kalos_image","").startswith(("xy_","field_")):continue
        zone=m["kalos_zone"]
        if zone in SPECIAL_ZONES:continue
        raw_doors=zones[str(zone)]["warps"]
        terrain=np.array(m["physics"]["collision"],bool)
        wet=np.array(m["physics"].get("water",np.zeros_like(terrain)),bool)
        floor=~(terrain|wet)
        doors={tuple(w["at"]) for w in m["warps"]}
        actors={tuple(a["at"]) for a in m["npcs"]}
        anchors=set(map(tuple,m["kalos_anchors"].values()))
        for w in m["warps"]:
            key=w.get("source_warp","")
            if not key.startswith("xy_"):continue
            idx=int(key[3:])
            original=raw_doors[idx]
            dest=maps.get(w["to"]["map"],{})
            if original[0] is None or not dest or dest is m:continue
            if dest["kalos_zone"] in SPECIAL_ZONES or dest["kalos_zone"]!=original[3]:continue
            reciprocal=[t for t in dest["warps"] if t.get("source_warp")=="xy_"+str(original[4]) and t["to"]["map"]==mid]
            if len(reciprocal)!=1:continue
            x=int(original[0]//18-m["kalos_origin"][0]);y=int(original[2]//18-m["kalos_origin"][1])
            h,width=terrain.shape
            if not (0<x<width-1 and 0<y<h-1 and terrain[y,x] and floor[y+1,x]):continue
            at=(x,y);foot=(x,y+1);old=tuple(w["at"])
            if w.get("trigger")=="door" and old==at:
                fronts[mid,idx]=foot
                continue
            if w.get("trigger")!="step" or max(abs(old[0]-x),abs(old[1]-y))!=1:continue
            occupied=(doors-{old})|actors|anchors
            if at in occupied or foot in occupied:continue
            # No facing field exists in this atlas. Infer north entry only
            # where the retail shell is closed north/west/east and open south.
            # Centres have a known southern frontage, even with a wide sill.
            if not dest.get("kalos_center") and (floor[y-1,x] or floor[y,x-1] or floor[y,x+1]):continue
            viable=floor.copy()
            for u,v in (doors-{old})|actors:viable[v,u]=False
            labels,_=ndimage.label(viable);sx,sy=m["spawn"]
            if not labels[sy,sx] or labels[y+1,x]!=labels[sy,sx]:continue
            fronts[mid,idx]=foot
            shifts[mid].append((old,foot,at))
            doors.remove(old);doors.add(at)
            w["at"]=list(at);w["trigger"]="door"
    changed=set(shifts)
    # Use the original target-warp index, not nearest map-centre distance.
    for mid,m in maps.items():
        if "kalos_zone" not in m or m["kalos_zone"] in SPECIAL_ZONES:continue
        source=zones[str(m["kalos_zone"])]["warps"]
        for w in m["warps"]:
            key=w.get("source_warp","")
            if not key.startswith("xy_"):continue
            idx=int(key[3:])
            foot=fronts.get((w["to"]["map"],source[idx][4]))
            if foot and (list(foot)!=w["to"]["at"] or w["to"].get("facing")!="down"):
                w["to"]["at"]=list(foot);w["to"]["facing"]="down"
                changed.add(mid)
    return changed,shifts

def repair_existing_paint(source,maps,shifts):
    """Rebuild only the former five-pixel sills from the native mesh, so the
    remainder of the already published field art stays pixel-identical."""
    from kalos_field_art import TOWNS,render,FieldModel
    from PIL import Image
    for mid,rows in shifts.items():
        m=maps[mid];n=m["kalos_zone"]
        if n not in TOWNS and n not in (188,309,355):continue
        moved=[(old,foot) for old,foot,_ in rows if old!=foot]
        if not moved:continue
        art=ROOT/m["hoenn_art"]["scene"][0].removeprefix("res://")
        with Image.open(art) as old:
            field=old.convert("RGB");px=field.width//m["size"][0]
            parts=list(FieldModel(source/f"view-{m['kalos_matrix']}.glb.gzip").parts())
            native=render(source,parts,m)
            for former,foot in moved:
                for x,y in [former,foot]:
                    box=(x*px+1,(y+1)*px-5,(x+1)*px-1,(y+1)*px)
                    field.paste(native.crop(box),box[:2])
            field.quantize(palette=old,dither=Image.Dither.NONE).save(art,optimize=True)
        if mid=="kalos_geosenge":
            # These two views are rendered separately. Keep their building sills
            # outside the changing central plaza in the same place in all phases.
            phases=read(ROOT/"content/kalos_geosenge.json")
            for phase in ("weapon","crater"):
                path=ROOT/"assets/kalos/maps"/(phases[phase]["art"]+".png")
                with Image.open(path) as old:
                    field=old.convert("RGB")
                    for _,foot in moved:
                        x,y=foot;box=(x*px+1,(y+1)*px-5,(x+1)*px-1,(y+1)*px)
                        field.paste(native.crop(box),box[:2])
                    field.quantize(palette=old,dither=Image.Dither.NONE).save(path,optimize=True)
        print("Repainted",mid,len(moved),flush=True)

def install(source,paint=False):
    maps={p.stem:read(p) for p in MAPS.glob("*.json")}
    changed,shifts=reconcile(maps,read(source/"map.json"))
    for mid in changed:write(MAPS/(mid+".json"),maps[mid])
    if paint:repair_existing_paint(source,maps,shifts)
    return shifts

if __name__=="__main__":
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cache",type=Path)
    ap.add_argument("--paint",action="store_true",help="correct old sills on already-rendered maps")
    args=ap.parse_args();result=install(args.cache,args.paint)
    print(sum(map(len,result.values())),"native thresholds",len(result),"fields")
