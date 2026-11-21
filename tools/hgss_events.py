"""Read pret/pokeheartgold's native map headers, matrices and zone event banks."""
import argparse
import json
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = "https://github.com/pret/pokeheartgold"
CELL = 32


def read_matrix(path):
    blob = path.read_bytes()
    width, height, has_headers, has_altitude, name_len = blob[:5]
    count = width*height
    pos = 5+name_len
    name = blob[5:pos].decode("ascii")
    heads = None
    if has_headers:
        heads = struct.unpack_from(f"<{count}H", blob, pos)
        pos += count*2
    heights = blob[pos:pos+count] if has_altitude else [0]*count
    if has_altitude: pos += count
    lands = struct.unpack_from(f"<{count}H",blob,pos)
    if pos+count*2 != len(blob): raise ValueError(f"Unexpected matrix size: {path}")
    return name, width, height, heads, heights, lands


def terrain(src, destination):
    # The normal HGSS land loader consumes the 0x1234 block and its optional
    # payload before reading the permission data (ov01_021F4AAC/ov01_021F4AE4).
    archive=(src/"files/a/0/6/5").read_bytes()
    if archive[:4] != b"NARC": raise ValueError("Expected the native land NARC")
    sections={}
    at=struct.unpack_from("<H",archive,12)[0]
    while at<len(archive):
        tag,length=struct.unpack_from("<4sI",archive,at)
        if length<8 or at+length>len(archive): raise ValueError("Invalid NARC section")
        sections[tag]=at+8
        at+=length
    table=sections[b"BTAF"]; base=sections[b"GMIF"]
    count=struct.unpack_from("<I",archive,table)[0]
    tiles=bytearray()
    for i in range(count):
        begin,end=struct.unpack_from("<II",archive,table+4+8*i)
        record=archive[base+begin:base+end]
        n, props, bmd, height, magic, prefix=struct.unpack_from("<4IHH",record)
        offset=20+prefix
        if magic!=0x1234 or n!=2*CELL*CELL or len(record)!=offset+n+props+bmd+height or record[offset+n+props:offset+n+props+4]!=b"BMD0":
            raise ValueError(f"Unrecognized land {i}")
        tiles.extend(record[offset:offset+n])
    destination.write_bytes(tiles)
    behavior_header=(src/"include/constants/metatile_behavior.h").read_text()
    members=re.search(r"enum TILE_BEHAVIOR\s*\{(.*?)\}",behavior_header,re.S)[1]
    names=re.findall(r"^\s*(TILE_BEHAVIOR_[A-Z_0-9]+)\s*[,=]",members,re.M)
    attrs=(src/"src/metatile_behavior.c").read_text()
    behavior_flags={name:mode for name,mode in re.findall(r"\[(TILE_BEHAVIOR_\w+)\]\s*=\s*(TILE_BEHAVIOR_FLAG_\w+)",attrs)}
    return {"file":destination.name,"land_count":count,"stride":n,"format":"u16le",
            "blocked_bit":15,"terrain_shift":8,"terrain_mask":127,"behavior_mask":255,
            "behavior_names":names,"surfable":[i for i,n in enumerate(names) if "SURFABLE" in behavior_flags.get(n,"")],
            "encounter":[i for i,n in enumerate(names) if "ENCOUNTER" in behavior_flags.get(n,"")]}


def encounter_banks(src):
    spec = (src/"include/constants/species.h").read_text()
    ids = dict((name,int(n)) for name,n in re.findall(r"^#define (SPECIES_\w+)\s+(\d+)\b",spec,re.M))
    def version(value):
        return value["HEARTGOLD"] if isinstance(value,dict) else value
    def species(name):
        return ids[version(name)]
    banks={}
    for bank in json.loads((src/"files/fielddata/encountdata/gs_enc_data.json").read_text())["encounters"]:
        land = bank["land"]
        surf = bank["surf"]
        timed = {}
        for period in ("morn","day","nite"):
            timed[period]=[{"species":species(row["species"][period]), "min":version(row["level"]), "max":version(row["level"]), "weight":w}
                           for row,w in zip(land["mons"],(20,20,10,10,10,10,5,5,4,4,1,1))]
        water=[{"species":species(row["species"]),"min":version(row["level"]["min"]),"max":version(row["level"]["max"]),"weight":w}
               for row,w in zip(surf["mons"],(60,30,5,4,1))]
        banks[bank["map"]]={"land":timed,"surf":water,"land_rate":land["rate"]/100,"surf_rate":surf["rate"]/100}
    return banks


def native(src):
    defs = (src/"include/constants/maps.h").read_text()
    ids = {key:(int(value),code) for key,value,code in re.findall(r"^#define (MAP_\w+)\s+(\d+)\s+// MAP_(\w+)",defs,re.M)}
    mdir = src/"files/fielddata/mapmatrix/map_matrix"
    matrices = {int(p.name[11:15]):read_matrix(p) for p in mdir.glob("map_matrix_*.bin")}
    banks={}
    for p in sorted((src/"files/fielddata/eventdata/zone_event").glob("*.json")):
        value=json.loads(p.read_text())
        banks[str(int(p.name[:3]))]={"source":p.name,**{k:value.get(k,[]) for k in ("bgs","objects","warps","coords")}}
    headers={}
    source=(src/"src/data/map_headers.h").read_text()
    for name,block in re.findall(r"\[(MAP_\w+)\]\s*=\s*\{(.*?)\},",source,re.S):
        fields=dict(re.findall(r"\.(\w+)\s*=\s*([a-zA-Z0-9_]+)",block))
        mid=int(re.search(r"_map_matrix_(\d+)",fields["matrixId"])[1])
        eid=int(re.search(r"_zone_event_(\d+)",fields["eventsBank"])[1])
        header_id,code=ids[name]
        tag,w,h,sections,heights,lands=matrices[mid]
        entries=[]
        for ordinal,land in enumerate(lands):
            if land==65535 or (sections is not None and sections[ordinal]!=header_id): continue
            entries.append({"section_id":ordinal,"column":ordinal%w,"row":ordinal//w,"land_id":land,"altitude":heights[ordinal]})
        if entries:
            x0=min(c["column"] for c in entries); z0=min(c["row"] for c in entries)
            x1=max(c["column"] for c in entries)+1; z1=max(c["row"] for c in entries)+1
        else:
            x0=z0=x1=z1=0
        if str(eid) not in banks: raise ValueError(f"Missing event bank {name} {eid}")
        headers[name]={"header_id":header_id,"code":code,"area_data_id":int(fields["areaDataBank"]),
                       "matrix_id":mid,"encounter_bank":fields["wildEncounterBank"].removeprefix("ENCDATA_"),"event_bank":eid,"map_section":fields["mapsec"],
                       "region":fields["regionNo"],"map_type":fields["mapType"],"camera":int(fields["cameraType"]),
                       "matrix_size":[w,h],"origin":[x0*CELL,z0*CELL],"size":[(x1-x0)*CELL,(z1-z0)*CELL],
                       "entries":entries}
    if len(headers)!=len(ids): raise ValueError(f"Incomplete headers: {set(ids)-set(headers)}")
    return headers,banks


def simple_alias(mid):
    short=mid.removeprefix("johto_").upper()
    short=re.sub(r"B(\d+)_F",r"B\1F",short)
    for old,new in (("_MART","_POKEMART"),("_CITY",""),("_TOWN",""),("DEPT_STORE","DEPARTMENT_STORE"),("TIN_TOWER","BELL_TOWER"),("TEAM_ROCKET_BASE","TEAM_ROCKET_HEADQUARTERS"),("RADIO_TOWER","GOLDENROD_RADIO_TOWER")):
        short=short.replace(old,new)
    if short.startswith("ROUTE_") and short.endswith("_GATE"): short += "HOUSE"
    return "MAP_"+short


def compile_catalog(src,out):
    headers,banks=native(src)
    changes=Path(__file__).with_name("hgss_map_aliases.json")
    reviewed=json.loads(changes.read_text()) if changes.exists() else {}
    aliases={}; alternatives={}; unbound={}
    for p in sorted((ROOT/"content/regions/johto/maps").glob("*.json")):
        mid=p.stem
        target=reviewed.get(mid,simple_alias(mid))
        if isinstance(target,list):
            if not all(t in headers for t in target): raise ValueError((mid,target))
            alternatives[mid]=target
        elif target in headers:
            aliases[mid]=target
        else:
            unbound[mid]=target if mid in reviewed else "no verified counterpart"
    # Crystal splits these into distinct maps. HGSS uses disconnected sections of
    # one native floor. Preserve the verified entrance anchors to disambiguate a save.
    merged = {}
    for short,anchor in (("nw",3),("ne",0),("sw",5),("se",9)):
        merged["johto_whirl_island_"+short] = {"header":"MAP_WHIRL_ISLANDS_1F","entry":anchor}
    for side,anchor in (("mahogany",0),("blackthorn",4)):
        merged["johto_ice_path_b2_f_"+side+"_side"] = {"header":"MAP_ICE_PATH_B2F","entry":anchor}
    for old,part in merged.items():
        native_header=headers[part["header"]]
        entrance=banks[str(native_header["event_bank"])]["warps"][part["entry"]]
        part["at"]=[entrance["x"]-native_header["origin"][0],entrance["z"]-native_header["origin"][1]]
        unbound.pop(old)
    revision=subprocess.check_output(["git","-C",str(src),"rev-parse","HEAD"],text=True).strip()
    out.parent.mkdir(parents=True,exist_ok=True)
    permissions=terrain(src,out.with_name("terrain.bin"))
    out.with_name("wild.json").write_text(json.dumps(encounter_banks(src),separators=(",",":"))+"\n")
    data={"permissions":permissions,"upstream":UPSTREAM,"revision":revision,"cell_size":CELL,
          "headers":headers,"banks":banks,"aliases":aliases,"split_maps":alternatives,"merged_maps":merged,"unbound":unbound}
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")
    print(f"{len(headers)} headers, {len(banks)} event banks, {len(aliases)} verified direct matches, {len(alternatives)} splits, {len(merged)} merged parts, {len(unbound)} other maps")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("--out",type=Path,default=ROOT/"content/hgss/events.json")
    args=parser.parse_args()
    compile_catalog(args.source,args.out)
