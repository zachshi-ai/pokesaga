"""Join actual controller/viewport results with original DS event banks and matrix dimensions."""
import argparse
import csv
import json
from pathlib import Path

from PIL import Image, ImageDraw

from build_unova_maps import event_point, rail_data, read
from platinum_layout import ROOT, catalog
from unova_locations import assign
from unova_rails import black_rails
from unova_source import UnovaSource

SETS={"hgss": "hgss/maps", "crystal":"regions/johto/maps", "platinum":"platinum_native/maps",
      "flower":"platinum_native/flower", "sinnoh_transit":"regions/sinnoh/maps",
      "bw":"unova_native/bw", "b2":"unova_native/b2","unova_transit":"regions/unova/maps"}


def params():
    parser=argparse.ArgumentParser(description=__doc__)
    for arg in ("walks","views","hgss","platinum","bw","b2"):
        parser.add_argument(arg,type=Path)
    return parser.parse_args()


def original(era,doc,sources):
    source,origin,events,destinations="",[0,0],[],{}
    if era=="hgss":
        hdr=sources["heart"]["headers"][doc["header"]]
        raw=sources["heart_events"][hdr["event_bank"]]
        rows=read(raw).get("warps",[]) if raw else []
        source=f'{doc["header"]}@{hdr["matrix_id"]}/{hdr["event_bank"]}'
        origin=hdr["origin"]
        destinations=sources["heart_ids"]
        events=[([r["x"],r["z"]],r["header"]) for r in rows]
        assert hdr["size"]==doc["size"]
    elif era in ("platinum","flower"):
        hdr=sources["platinum"][doc["source_id"]]
        source=doc["source_id"]
        origin=hdr["origin"]
        events=[([r["x"],r["z"]],r["dest_header_id"]) for r in hdr["bank"].get("warp_events",[])]
        destinations=sources["platinum_ids"]
        if doc["size"]!=hdr["size"]:
            source+=f" [matrix {hdr['size']}, field {doc['size']}]"
    elif era in ("bw","b2"):
        src=sources[era]
        idx=doc["unova_zone_id"]
        if idx>=len(src.zones):
            return f"scripted instance {idx}",0,0,0
        zone=src.zones[idx]
        source=f'{idx}:{zone["key"]}@{zone["matrix"]}'
        origin=doc["unova_origin"]
        destinations={z["i"]:z["mid"] for z in src.zones}
        for r in zone["warps"]:
            pos=event_point(rail_data(src,zone),r,True)
            if pos is not None:events.append((pos,r["zone"]))
    else:return "project legacy / interregional passage",0,0,0
    exact=near=0
    for pos,dest in events:
        local=[int(pos[i]-origin[i]) for i in (0,1)]
        ds=[sum(abs(a-b)for a,b in zip(w["at"],local))for w in doc["warps"] if w["to"]["map"]==destinations.get(dest)]
        if ds:
            exact+=min(ds)==0
            near+=min(ds)<=1
    return source,len(events),exact,near


def main():
    p=params()
    sources={"heart":read(ROOT/"content/hgss/events.json"),"platinum":catalog(p.platinum)}
    sources["heart_ids"]={value:key for key,value in read(ROOT/"content/hgss/map_index.json").items()}
    sources["platinum_ids"]={k:v["id"] for k,v in sources["platinum"].items()}
    banks={int(file.name[:3]):file for file in (p.hgss/"files/fielddata/eventdata/zone_event").glob("[0-9]*.json")}
    sources["heart_events"]={k:banks.get(k) for k in range(1000)}
    for era in ("b2","bw"):
        src=UnovaSource(p.bw,p.b2,era)
        assign(src)
        rails=src.field/"rails"
        src.rails=black_rails(src) if era=="bw" else [read(rails/f"{h['rail']:03}.json") for h in read(rails/"headers.json")["headers"]]
        sources[era]=src
    rows=[]
    out=ROOT/".github/preview/v4.68/ds"
    out.mkdir(parents=True,exist_ok=True)
    for era,folder in SETS.items():
        records=sorted((json.loads(line) for line in (p.walks/(era+".jsonl")).read_text().splitlines()),key=lambda r:r["map_id"])
        for index,r in enumerate(records):
            mid=r["map_id"]
            d=read(ROOT/"content"/folder/(mid+".json"))
            src,total,exact,near=original(era,d,sources)
            seq=index%90
            if not seq:
                page=Image.new("RGB",(10*128,((min(90,len(records)-index)+9)//10)*100),(32,35,38))
                pen=ImageDraw.Draw(page)
                filename=f"{era}-{index//90+1:02}.webp"
            with Image.open(p.views/era/(mid+".png")) as pic:
                x,y=seq%10*128,seq//10*100
                page.paste(pic.resize((126,84),Image.Resampling.NEAREST),(x,y))
                pen.text((x+3,y+85),str(index+1),fill="white")
            if seq==89 or index==len(records)-1:page.save(out/filename,quality=88,method=4)
            results=r["gates"]
            note=d.get("unova_technical_reason","")
            if era=="hgss" and mid in {f"hgss_safari_zone_{j:02}" for j in (3,5,9,10,11,12)}:
                note="狩猎地带区域配置机；本次六槽 [3,5,9,10,11,12]"
            rows.append([era,r["region"],mid,d.get("name",""),src,total,exact,near,r["spawn_steps"],r["walk_steps"],r["unique_cells"],
                sum(results.values()),results.get("pass",0),results.get("local",0),results.get("cycling_deck",0),
                results.get("dynamic",0),results.get("npc_at_threshold",0),str(r["issues"]).replace("\t"," "),
                filename,index+1,note])
    target=ROOT/"doc/field-audit/ds.tsv"
    target.parent.mkdir(exist_ok=True,parents=True)
    with target.open("w") as file:
        writer=csv.writer(file,delimiter="\t",lineterminator="\n")
        writer.writerow("era region map_id name original_header_or_zone native_events native_same_tile_and_target native_within_one_tile_and_target default_spawn_steps exercised_steps visited_cells active_passages exact_transfer field_movement cycling_deck scripted_redirect actor_at_threshold observations capture_sheet capture_number version_or_instance".split())
        writer.writerows(rows)
    print(len(rows),target)

if __name__=="__main__": main()
