#!/usr/bin/env python3
"""Extract original facility pools, Brain teams, judges, nature styles, and BP schedules."""
import argparse
import json
import re
import subprocess
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("source",type=Path)
src=parser.parse_args().source
root=Path(__file__).resolve().parents[1]/"content"
bank=src/"src/data/battle_frontier"
moves={k:int(v) for k,v in re.findall(r"^#define MOVE_(\w+)\s+(\d+)",(src/"include/constants/moves.h").read_text(),re.M)}
species={row["key"]:row["id"] for row in json.loads((root/"species.json").read_text())}
species.update(CASTFORM=351,DEOXYS=386)
def fixed_sets(text, prefix):
    rows={}
    for key,block in re.findall(r"\["+prefix+r"_MON_(\w+)\]\s*=\s*\{(.*?)\n    \},?", text,re.S):
        mon=species[re.search(r"\.species = SPECIES_(\w+)",block)[1]]
        item=re.search(r"\.itemTableId = BATTLE_FRONTIER_ITEM_(\w+)",block)[1]
        rows[key]=dict(species=mon,moves=[moves[k] for k in re.findall(r"MOVE_(\w+)",block) if k!="NONE"],held=item,nature=re.search(r"NATURE_(\w+)",block)[1],
                       ev=re.findall(r"F_EV_SPREAD_(\w+)",block))
    return rows
result={}
text=subprocess.check_output(["cc","-E","-P","-x","c",str(bank/"battle_frontier_trainer_mons.h")],text=True)
def trainers(src_text,pools,prefix):
    out=[]
    for name,body in re.findall(r"\["+prefix+r"_TRAINER_(\w+)\]\s*=\s*\{(.*?)\n    \}",src_text,re.S):
        label=re.search(r"\.monSet\s*=\s*(\w+)",body)[1]
        out.append(dict(name=name.title(),pool=pools[label]))
    return out
sets=fixed_sets((bank/"battle_frontier_mons.h").read_text(),"FRONTIER")
pools={}
for label,v in re.findall(r"const u16 (gBattleFrontierTrainerMons_\w+)\[\]\s*=\s*\{([^}]+)",text):
    pools[label]=re.findall(r"FRONTIER_MON_(\w+)",v)
result["main"]={"sets":sets,"trainers":trainers((bank/"battle_frontier_trainers.h").read_text(),pools,"FRONTIER")}
tent=(bank/"battle_tent.h").read_text()
for location in ("Slateport","Verdanturf","Fallarbor"):
    prefix=location.upper()+"_TENT"
    pools={k:re.findall(prefix+r"_MON_(\w+)",v) for k,v in re.findall(r"(\w+Mons_\w+)\[\]\s*=\s*\{([^}]+)",tent)}
    result[location.lower()]={"sets":fixed_sets(tent,prefix),"trainers":trainers(tent,pools,prefix)}
for name,pack in result.items():
    assert all(t["pool"] and all(k in pack["sets"] for k in t["pool"]) for t in pack['trainers']),name
util=(src/"src/frontier_util.c").read_text()
brains={}
for facility, v in re.findall(r"\[FRONTIER_FACILITY_(\w+)\]\s*=\s*\n    \{(.*?)\n    \},",util.split("sFrontierBrainsMons")[1].split("static const",1)[0],re.S):
    rows=[]
    for mon,item,iv,nature,ev,mv in re.findall(r"\.species = SPECIES_(\w+),\s*\.heldItem = ITEM_(\w+),\s*\.fixedIV = (\w+),\s*\.nature = NATURE_(\w+),\s*\.evs = \{([^}]+)\},\s*\.moves = \{([^}]+)\}",v,re.S):
        rows.append(dict(species=species[mon],held=item,nature=nature,iv=31 if iv=="MAX_PER_STAT_IVS" else int(iv),evs=list(map(int,ev.split(","))),moves=[moves[k] for k in re.findall("MOVE_(\\w+)",mv) if k!="NONE"]))
    assert len(rows)==6,(facility,len(rows))
    brains[facility.lower()]=[rows[:3],rows[3:]]
assert len(brains)==7
result["brains"]=brains
bp=util.split("sBattlePointAwards[][NUM_FRONTIER_FACILITIES][FRONTIER_MODE_COUNT]")[1].split("};",1)[0]
result["bp"]=[[list(map(int,re.findall(r"\d+",group))) for group in re.findall(r"\{([\d ,]+)\}",ln)] for ln in bp.splitlines() if "}, {" in ln]
arena=(src/"src/battle_arena.c").read_text().split("sMindRatings[MOVES_COUNT]")[1].split("};",1)[0]
result["mind"]={moves[k]:int(v) for k,v in re.findall(r"\[MOVE_(\w+)\] = (-?\d+)",arena)}
nature=(src/"src/battle_script_commands.c").read_text()
result["nature"]={k:list(map(int,group.split(","))) for k,group in re.findall(r"\[NATURE_(\w+)\]\s*= PALACE_STYLE\(([\d, ]+)\)",nature)}
def source_text(path):
    candidate=src/path
    if candidate.exists():
        return candidate.read_text()
    return subprocess.check_output(["git","-C",str(src),"show","HEAD:"+path],text=True)

move_data=source_text("src/data/battle_moves.h")
palace={}
for k,block in re.findall(r"\[MOVE_(\w+)\]\s*=\s*\{(.*?)\n    \}",move_data,re.S):
    target=re.search(r"\.target = MOVE_TARGET_(\w+)",block)
    power=re.search(r"\.power = (\d+)",block)
    if target and power:
        typ=target[1]
        palace[moves[k]]=1 if typ=="USER" else (2 if typ in ("DEPENDS","OPPONENTS_FIELD") or int(power[1])==0 else 0)
result["move_groups"]=palace
tutor=source_text("src/data/pokemon/tutor_learnsets.h")
master={}
for mon,block in re.findall(r"\[SPECIES_(\w+)\]\s*=\s*([^,]+),",tutor,re.S):
    if mon not in species:continue
    for key in re.findall(r"TUTOR\(MOVE_(\w+)\)",block):
        if key in moves:master.setdefault(moves[key],[]).append(species[mon])
assert len(master)>=30
result["learn"]=master
raw=source_text("src/data/pokemon/level_up_learnsets.h")
level_sets={name:[[int(level),moves[attack]] for level,attack in re.findall(r"LEVEL_UP_MOVE\(\s*(\d+), MOVE_(\w+)\)",body)] for name,body in re.findall(r"(s\w+LevelUpLearnset)\[\] = \{(.*?)\};",raw,re.S)}
pointers=source_text("src/data/pokemon/level_up_learnset_pointers.h")
result["level_moves"]={species[key]:level_sets[name] for key,name in re.findall(r"\[SPECIES_(\w+)\] = (s\w+LevelUpLearnset)",pointers) if key in species}
assert len(result["level_moves"])>=380
prizes=source_text("data/maps/BattleFrontier_ExchangeServiceCorner/scripts.inc")
result["prices"]={key:int(cost) for cost,key in re.findall(r"setvar VAR_0x8008, (\d+)\s+setvar VAR_0x8009, (\w+)",prizes)}
def wild_pools(text, pattern):
    groups = []
    for body in re.findall(pattern + r"\[\]\s*=\s*\{(.*?)\n\};", text, re.S):
        group = []
        for row in re.findall(r"\{([^{}]*\.species.*?\.moves\s*=\s*\{[^}]*\})",body,re.S):
            mon = re.search(r"SPECIES_(\w+)",row)[1]
            lv = int(re.search(r"\.(?:lvl|levelDelta) = (\d+)",row)[1])
            attacks = [moves[key] for key in re.findall(r"MOVE_(\w+)",row) if key!="NONE"]
            group.append([species[mon],lv,attacks])
        groups.append(group)
    return groups
pike = source_text("src/battle_pike.c")
for mode, stem, filename in [("fixed","Lvl50","level_50"),("open","LvlOpen","open_level")]:
    result["pike_"+mode] = wild_pools(pike, "s"+stem+r"_Mons\d+")
    text = source_text("src/data/battle_frontier/battle_pyramid_"+filename+"_wild_mons.h")
    result["pyramid_"+mode] = wild_pools(text, r"s\w+WildMons_Round\d+")
    assert [len(x) for x in result["pike_"+mode]] == [3]*4
    assert [len(x) for x in result["pyramid_"+mode]] == [8]*20
assert len(result["nature"])==25 and len(sets)>=850
(root/"emerald_frontier.json").write_text(json.dumps(result,separators=(",",":"))+"\n")
