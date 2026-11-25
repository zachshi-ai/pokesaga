"""Join the playable 3DS area walk to XY's original warp targets and SM zone/scene catalog."""
import argparse
from collections import Counter
import csv
import json
import zipfile
from pathlib import Path

import numpy as np
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[1]

def read(path):
    return json.loads(path.read_bytes())

def number(value):
    return str(value) if value is not None else ""

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xy",required=True,type=Path,help="XY guide library cache with map.json")
    parser.add_argument("--sm",required=True,type=Path,help="SM guide library cache with geometry, scenes and locations")
    parser.add_argument("--walk",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--apk",type=Path,help="Read the tested runtime map files directly from this Android package")
    args=parser.parse_args()
    raw=read(args.xy/"map.json")["zones"]
    geo={z["zone"]:z for z in read(args.sm/"geometry.json")["zones"]}
    scenes={z:s["world"] for s in read(args.sm/"scenes.json")["scenes"] for z in s["zones"]}
    locations={z:l["slug"] for l in read(args.sm/"locations.json") for z in l["zones"]}
    def runtime_data(content):
        limits = read(content / "alola_map_access.json")
        maps = {Path(p.name).stem:read(p) for region in ("kalos","alola","aether","ultra")
                for p in (content/"regions"/region/"maps").iterdir() if p.name.endswith(".json")}
        return limits, maps
    if args.apk:
        with zipfile.ZipFile(args.apk) as archive:
            limits, maps = runtime_data(zipfile.Path(archive, "assets/content/"))
    else:
        limits, maps = runtime_data(ROOT/"content")
    with args.walk.open() as walk,args.output.open("w") as output:
        reader=csv.DictReader(walk,delimiter="\t")
        writer=csv.writer(output,delimiter="\t",lineterminator="\n")
        writer.writerow(["region","map_id","name","size","source_basis","source_zones","source_scene",
                        "xy_indexed_destinations_matched","xy_indexed_destinations_count","xy_other_destination",
                        "xy_entrance_at_original_tile","xy_known_entrance_coordinates","max_shift_tiles","shift_context",
                        "versions","require","closes","floor_walk","crossed","returned","failures"])
        for row in reader:
            region,mid=row["region"],row["map_id"]
            m=maps[mid];native=m.get(region+"_native");basis="自建跨区连接"
            ids=scene="";matched=count=on_tile=pos_count=max_shift=None;different=[];reasons=Counter()
            if region=="kalos" and native:
                n=m["kalos_zone"];r=raw[str(n)];ids=str(n);scene=str(r["view"])
                assert int(r["view"])==int(m["kalos_matrix"]),(mid,scene,m["kalos_matrix"])
                basis="XY 分区及模型；门位按下列数字核对"
                if m["kalos_image"].startswith(("gba_","opening_")):
                    basis="XY 分区；本作室内、道馆或开场平面适配"
                matched=count=on_tile=pos_count=0
                collision=np.array(m["physics"]["collision"],bool)
                water=np.array(m["physics"].get("water",np.zeros_like(collision)),bool)
                walk=~(collision|water)
                doors={tuple(w["at"]) for w in m["warps"]}
                occupied=doors|set(map(tuple,m["kalos_anchors"].values()))
                for x,y in doors:walk[y,x]=False
                for npc in m["npcs"]:
                    x,y=npc["at"];walk[y,x]=False
                groups,_=ndimage.label(walk)
                sx,sy=m["spawn"];origin_group=groups[sy,sx]
                for w in m["warps"]:
                    source=w.get("source_warp","")
                    if not source.startswith("xy_"):continue
                    index=int(source[3:]);entry=r["warps"][index]
                    count+=1
                    target=w["to"]["map"]
                    if maps.get(target,{}).get("kalos_zone")==entry[3]:
                        matched+=1
                    else:different.append(f"{index}>{entry[3]}:{target}")
                    if entry[0] is None:continue
                    orig=(int(entry[0]//18)-m["kalos_origin"][0],int(entry[2]//18)-m["kalos_origin"][1])
                    shift=max(abs(orig[i]-w["at"][i]) for i in range(2))
                    pos_count+=1
                    on_tile+=shift==0
                    max_shift=max(max_shift or 0,shift)
                    if shift:
                        x,y=orig;h,width=walk.shape
                        if m["kalos_image"].startswith(("gba_","opening_")):reason="改绘平面坐标"
                        elif not (0<=x<width and 0<=y<h):reason="图外"
                        elif water[y,x]:reason="水域"
                        elif collision[y,x]:reason="模型实体"
                        elif (x,y) in occupied:reason="重叠门或锚点"
                        elif groups[y,x]!=origin_group:reason="主路隔断"
                        else:reason="可通行，需目视核对"
                        reasons[reason]+=1
            if region=="alola" and native:
                zs=[z for z in m["alola_zones"] if z>=0]
                ids=",".join(map(str,zs))
                available=set(z for z in zs if z in scenes or z in geo or z in locations)
                if available:
                    basis="SM 分区或实景；连接为平面适配"
                    if (m.get("alola_image","").startswith("center") or not zs):basis="地点与通路改绘"
                    scene=",".join(sorted({str(scenes.get(z,geo.get(z,{}).get("world",""))) for z in available} - {""}))
                    if not scene:basis="SM 地点目录；通路改绘"
                else:
                    basis="按地点用途重绘；缺原场景坐标"
                if mid.startswith("alola_malie_library"):
                    basis="四版本两层通路；缺原室内格坐标"
            rule=limits.get(mid,{})
            writer.writerow([region,mid,m["name"],"×".join(map(str,m["size"])),basis,ids,scene,
                             number(matched),number(count),",".join(different),number(on_tile),number(pos_count),number(max_shift),
                             ",".join(f"{k}:{v}" for k,v in sorted(reasons.items())),
                             ",".join(rule.get("versions",[])),rule.get("require",""),rule.get("closes",""),
                             row["longest_floor_walk"],row["crossed"],row["walked_back"],row["failures"]])
if __name__=="__main__":main()
