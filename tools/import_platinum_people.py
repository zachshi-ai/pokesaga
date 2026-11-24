"""Index Platinum field speakers by event script and trainers by their original battle ID."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text())


def pages(raw):
    # Text which needs a dynamic script variable belongs to that script's handler.
    raw = raw.replace("[0103,0000]", "小悠").replace("[0103,0001]", "小悠")
    if "[" in raw or not raw.strip():
        return []
    raw=raw.replace("Ｘ键","START 键").replace("Ｘ按钮","START 键")
    return [p.replace("\n","").strip() for p in re.split(r"\\[fr]\s*",raw) if p.strip()]


def trainer_book(pt, cn, events):
    names=(pt/"generated/trainers.txt").read_text().splitlines()
    classes=(pt/"generated/trainer_classes.txt").read_text().splitlines()
    order_text=(pt/"tools/dataproc/src/trainerproc.c").read_text()
    order={key:int(i) for key,i in re.findall(r"\[(TRAINER_\w+)\]\s*=\s*(\d+)",order_text)}
    selected={n["trainer"]["id"] for data in events for n in data.get("object_events",[]) if n.get("trainer")}
    def translated(bank):
        return [s["translation"] for s in read(cn/"Pt/zh_Hans"/(bank+".json"))]
    labels,titles,messages=map(translated,["trname","trtype","trmsg"])
    raw_species=(pt/"generated/species.txt").read_text().splitlines()
    raw_moves=(pt/"generated/moves.txt").read_text().splitlines()
    cursor=0
    out={}
    for idx in sorted(range(len(names)),key=lambda i:(order.get(names[i],65535),i)):
        key=names[idx]
        file=pt/"res/trainers/data"/(key[8:].lower()+".json")
        if not file.exists(): continue
        row=read(file)
        dialogs={}
        for entry in row["messages"]:
            lines=pages(messages[cursor]) if cursor<len(messages) else []
            cursor+=1
            if lines: dialogs[entry["type"]]=lines
        if key not in selected: continue
        team=[]
        for mon in row["party"]:
            unit={"species":raw_species.index(mon["species"]),"level":mon["level"]}
            if mon.get("moves"):
                unit["moves"]=[raw_moves.index(move) for move in mon["moves"] if move!="MOVE_NONE"]
            held=mon.get("item")
            if held and held!="ITEM_NONE":
                if held.endswith("_BERRY"): unit["berry"]=held[5:-6].lower()
                else: unit["held"]=held[5:]
            team.append(unit)
        name=titles[classes.index(row["class"])]+" "+labels[idx]
        out[key]={"name":name,"party":team,"lines":dialogs.get("TRMSG_PRE_BATTLE",[]),
                  "post":dialogs.get("TRMSG_POST_BATTLE",[]),"double":row.get("double_battle",False)}
    assert len(out)==len(selected)
    assert "对上眼" in "".join(out["TRAINER_YOUNGSTER_TRISTAN"]["lines"])
    return out


def speakers(pt,cn,folders):
    banks=(pt/"generated/text_banks.txt").read_text().splitlines()
    files={int(i):(game,name[:-4]) for i,game,name in
           (l.split() for l in (cn/"Pt/messages_list.txt").read_text().splitlines() if l.strip())}
    out={}
    for folder in folders:
        header=read(folder/"header.json")
        bank=header.get("textBank","")
        script=folder/"scripts.s"
        if bank not in banks or not script.exists():continue
        ix=banks.index(bank)
        # Field banks retain order across localizations. The US build inserts one
        # early bank and six by Route 201. Reject differing message counts.
        offset=1 if 23<=ix<=311 else 6 if 466<=ix<=605 else None
        if offset is None or ix-offset not in files:continue
        game,stem=files[ix-offset]
        path=cn/game/"zh_Hans"/(stem+".json")
        en=pt/"res/text"/(bank[10:].lower()+".json")
        if not en.exists() or not path.exists():continue
        originals=read(en)["messages"]
        translated=read(path)
        if len(translated)!=len(originals):continue
        localized={m["id"]:pages(t.get("translation","")) for m,t in zip(originals,translated)}
        blocks=re.split(r"(?m)^(\w+):\s*\n",script.read_text())
        for name,body in zip(blocks[1::2],blocks[2::2]):
            # A plain speaker or sign can be played verbatim. Stateful scripts
            # keep the bespoke game handler and do not announce unearned items.
            if re.search(r"(?m)^\s*(?:GoTo|CallIf|Give|SetFlag|Remove|CheckItem|StartTrainerBattle|ShowYesNoMenu|AddVar)\w*\b",body):continue
            refs=re.findall(r"(?m)^\s*(?:NPCMessage|EventMessage|Message|ShowArrowSign|ShowLandmarkSign|ShowScrollingSign|ShowTrainerTipsSign)\s+(\w+_Text_\w+)",body)
            if refs and all(localized.get(ref) for ref in refs):
                out[name]=[line for ref in refs for line in localized[ref]]
    return out


def main(pt,translate):
    cn=translate/"texts"
    folders=sorted(p.parent for p in (pt/"res/field/maps").glob("*/events.json") if (p.parent/"header.json").exists())
    trainers=trainer_book(pt,cn,[read(p/"events.json") for p in folders])
    speeches=speakers(pt,cn,folders)
    (ROOT/"content/platinum_native/people.json").write_text(json.dumps(
        {"trainers":trainers,"speeches":speeches},ensure_ascii=False,separators=(",",":"))+"\n")
    from platinum_library_text import export as export_library
    export_library(pt,cn,ROOT/"content/platinum_native/library.json")
    print(len(trainers),"trainers;",len(speeches),"field scripts")


if __name__=="__main__":
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("platinum",type=Path)
    ap.add_argument("translation",type=Path)
    args=ap.parse_args()
    main(args.platinum,args.translation)
