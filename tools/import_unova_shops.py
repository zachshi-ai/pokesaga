"""Extract the two Black-version Poké Marts, including the script assigned to each clerk."""
import argparse
import json
import re
import struct
from pathlib import Path
from import_unova_side import ROOT, constants, narc

def black(stock, sequel):
    asm = (stock/"asm/overlay_021_02187F00.s").read_text()
    def packed(label):
        block = re.search(r"^_"+label+r":\n((?:\s*\.byte[^\n]+\n)+)", asm, re.M)
        return bytes(int(n,16) for n in re.findall(r"0x([\dA-F]{2})",block[1]))
    ptr = re.search(r"^_021DE1A8:\n((?:\s*\.word[^\n]+\n)+)",asm,re.M)
    order = re.findall(r"ADDR_([\dA-F]+)_o21",ptr[1])
    lengths = packed("021D95DE")
    items = constants(sequel/"generated/items.txt","ITEM_")
    menus = [[items[n[0]] for n in struct.iter_unpack("<H",packed(label)[:2*length])] for label,length in zip(order,lengths)]
    assert len(menus)==26 and len(menus[-1])==lengths[25]
    banks=narc(stock/"files/a/0/5/7")
    headers=list(struct.iter_unpack("<BBHHHHH4HHHHHHHHHiii",narc(stock/"files/a/0/1/2")[0]))
    actors={}
    for file in (ROOT/"content/unova_native/bw").glob("*.json"):
        room=json.loads(file.read_text())
        raw=banks[headers[room["unova_zone_id"]][4]]
        starts=[]
        for entry in range(0,len(raw)-3,4):
            if raw[entry:entry+2]==b"\x13\xfd":break
            pos=entry+4+struct.unpack_from("<I",raw,entry)[0]
            if pos>=len(raw):break
            starts.append(pos)
        ends=sorted(set(starts+[len(raw)]))
        for row in room["unova_cast"]:
            index=row["script"]-1
            if not 0<=index<len(starts):continue
            start=starts[index]
            end=ends[ends.index(start)+1]
            match=re.search(rb"\x2a\x00\x00\x80(..)\x2a\x00\x01\x80..\x1c\x00\x7e\x27",raw[start:end],re.S)
            if match:
                code=int.from_bytes(match[1],"little")
                if code==255 or code<len(menus)-6:actors.setdefault(file.stem,{})[str(row["local_id"])]=code
    return {"badge_tiers":list(packed("021D946C")[:9]),"badge_marts":menus[:6],"marts":menus[6:],"actors":actors}

def black2(source):
    markets=json.loads((source/"res/field/shops/shops.json").read_text())
    result={key:[[item.removeprefix("ITEM_") for item in row] for row in markets[key]] for key in ("badge_marts","marts")}
    result.update(badge_tiers=[0,1,1,2,2,3,3,4,5],actors={})
    for file in (ROOT/"content/unova_native/b2").glob("*.json"):
        room=json.loads(file.read_text())
        script=source/"res/field/scripts"/(room["unova_zone"]+".s")
        if not script.exists():continue
        scripts=dict(re.findall(r"^Script_(\d+):\n([\s\S]*?)(?=^\w+:|\Z)",script.read_text(),re.M))
        for row in room["unova_cast"]:
            match=re.search(r"WorkSet 0x8000, (\d+)\s+WorkSet 0x8001, \d+\s+RTCallGlobal 10110",scripts.get(str(row["script"]),""))
            if match:
                code=int(match[1])
                if code==255 or code<len(result["marts"]):result["actors"].setdefault(file.stem,{})[str(row["local_id"])]=code
    return result

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bw",type=Path,required=True)
    parser.add_argument("--b2",type=Path,required=True)
    args=parser.parse_args()
    out={"bw":black(args.bw,args.b2),"b2":black2(args.b2)}
    (ROOT/"content/unova_shops.json").write_text(json.dumps(out,ensure_ascii=False,separators=(",",":"))+"\n")
