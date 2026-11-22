"""Import Platinum Frontier trainer pools and their fixed Pokémon sets."""
import argparse
import json
import re
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def main(source):
    folder=source/"res/trainers/frontier"
    species=(source/"generated/species.txt").read_text().splitlines()
    moves=(source/"generated/moves.txt").read_text().splitlines()
    indices=(source/"generated/frontier_trainers.txt").read_text().splitlines()
    sets={}
    for path in sorted((folder/"pokemon").glob("*.json")):
        row=json.loads(path.read_text())
        sid=species.index(row["species"])
        if not sid:continue
        ev=[k for k,yes in row["evFlags"].items() if yes]
        sets[path.stem]={"species":sid,"moves":[moves.index(m) for m in row["moves"] if m!="MOVE_NONE"],
                         "held":row["item"][5:],"nature":row["nature"][7:],"ev":ev,"form":row.get("form",0)}
    trainers={}
    for path in sorted((folder/"data").glob("*.json")):
        row=json.loads(path.read_text());key=path.stem
        trainers[key]={"name":row["name"],"sets":[n for n in row["availableSets"] if n in sets],
                       "index":indices.index("FRONTIER_TRAINER_"+key.upper())}
    scripts=(source/"src/scrcmd.c").read_text()
    prices_source=(source/"src/overlay007/shop_menu.c").read_text().split("static const u16 itemToBpPrice[][2] =",1)[1].split("};",1)[0]
    prices=dict((k,int(v)) for k,v in re.findall(r"\{ ITEM_(\w+), (\d+) \}",prices_source))
    shops={}
    for side in ("Left","Right"):
        stock=scripts.split(f"BattleFrontier{side}ExchangeServiceCorner[] = {{",1)[1].split("};",1)[0]
        shops[side.lower()]=[[k,prices[k]] for k in re.findall(r"ITEM_(\w+),",stock) if k in prices]
    bp={}
    for kind in ("tower","factory","castle","arcade","hall"):
        cf=source/"src"/("battle_tower.c" if kind=="tower" else f"overlay104/battle_{kind}.c")
        marker="soloBattlePoints" if kind=="tower" else "sBPPerRoundSolo"
        row=re.search(marker+r"\[[^\]]*\]\s*=\s*\{([^}]+)\}",cf.read_text())
        bp[kind]=list(map(int,row[1].split(",")))
    # The Hall has an independent pool and orders the opponents by four difficulty groups.
    narc=(source/"res/prebuilt/battle/b_pl_stage/pl_bsdpm.narc").read_bytes()
    base=narc.index(b"GMIF")+8
    count=struct.unpack_from("<H",narc,24)[0]
    natures=(source/"generated/natures.txt").read_text().splitlines()
    items=(source/"generated/items.txt").read_text().splitlines()
    stats=["hp","attack","defense","speed","special_attack","special_defense"]
    hall={}
    for i in range(1,count):
        start,end=struct.unpack_from("<II",narc,28+(i*8))
        sid,*payload=struct.unpack("<5H2B2H",narc[base+start:base+end])
        mask,nature,item,form=payload[4:]
        hall["hall_"+str(i)]={"species":sid,"moves":[m for m in payload[:4] if m],"held":items[item][5:],
                             "nature":natures[nature][7:],"ev":[s for j,s in enumerate(stats) if mask&(1<<j)],"form":form}
    target=ROOT/"content/platinum_native/frontier.json"
    target.write_text(json.dumps({"sets":sets,"trainers":trainers,"shops":shops,"bp":bp,"hall":hall},separators=(",",":"))+"\n")
    print(len(sets),"sets;",len(trainers),"Frontier trainers")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("source",type=Path);main(p.parse_args().source)
