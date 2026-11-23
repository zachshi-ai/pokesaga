#!/usr/bin/env python3
"""Play the four opening fields, their six house doors, both shops and v4.61 save migration."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from campaign_route import ROOT, read
from test_kalos_journey import KalosPlayer, KalosRoutes


def run(godot, pack=None):
    with tempfile.TemporaryDirectory(prefix="pokesaga-kalos-opening-") as tmp:
        folder=Path(tmp)
        env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp)
        project=["--main-pack",str(pack.resolve())] if pack else ["--path",str(ROOT)]
        command=[godot,"--headless","--fixed-fps","60",*project]
        plan=KalosRoutes()
        save=folder/"save.json"
        def launch(startup=()):
            return KalosPlayer(plan,command,env,folder,startup)
        def close(p):
            p.do("quit");assert p.process.wait(timeout=15)==0

        p=launch(["--","new-kalos","kalos-boxed","x"])
        args=argparse.Namespace(result_save=None,checkpoints=None,version="x",legend_party=False,stop_at="k_rules")
        try:
            p.run(args,folder)
            for dest,street in [("zone_6","vaniville"),("home_1f","vaniville"),("rival_home","vaniville"),
                                ("zone_9","aquacorde"),("zone_10","aquacorde"),("zone_11","aquacorde")]:
                mid="kalos_"+dest;outside="kalos_"+street
                p.enter(mid)
                entrance=next(w for w in plan.fields[outside].data["warps"] if w["to"]["map"]==mid)
                assert list(p.pos[1:])==entrance["to"]["at"] or dest=="home_1f",(mid,p.pos,entrance)
                if dest=="zone_9":p.nurse(mid)
                if dest in ("zone_10","zone_11"):
                    item,price=("伤药",300) if dest=="zone_10" else ("精灵球",200)
                    row=next(r for r in p.state["actors"] if r[3])
                    p.use_at(mid,row[0])
                    if "购买道具" in p.state["buttons"]:p.select("购买道具")
                    money=p.state["money"];count=p.state["bag"].get(item,0)
                    p.do("shop",item=item,amount=1)
                    assert p.state["money"]==money-price and p.state["bag"][item]==count+1
                    other="精灵球" if item=="伤药" else "伤药"
                    p.do("shop",item=other,amount=1)
                    assert p.state["money"]==money-price
                    p.do("back")
                exit_=next(w for w in plan.fields[mid].data["warps"] if w["to"]["map"]==outside)
                p.enter(outside)
                assert list(p.pos[1:])==exit_["to"]["at"],(p.pos,exit_)
                print("DOOR AND SERVICE",mid,outside,flush=True)
            at=next(r[0] for r in p.state["actors"] if r[2]=="散步的男士")
            count=p.state["bag"].get("伤药",0)
            for _ in range(2):
                p.use_at("kalos_aquacorde",at)
                assert p.state["bag"]["伤药"]==count+1
            p.do("save")
            template=read(save)
        finally:close(p)

        # Emulate the historical coordinate format without altering the earned party or flags.
        for area,old in [("vaniville",[30,11]),("1",[25,5]),("aquacorde",[63,53]),
                         ("2",[22,41]),("zone_9",[3,7]),("zone_10",[3,7]),("zone_11",[12,7])]:
            mid="kalos_"+area;d=dict(template,map=mid,pos=old)
            d.pop("kalos_opening_revision",None)
            save.write_text(json.dumps(d,ensure_ascii=False))
            p=launch()
            try:
                field=plan.fields[mid]
                assert p.pos[0]==mid
                x,y=p.pos[1:]
                assert not field.get("water",x,y) and not field.get("collision",x,y)
                assert not any(w["at"]==[x,y] for w in field.data["warps"])
                assert not any(row[0]==[x,y] for row in p.state["actors"])
                p.do("save")
                migrated=read(save)
                assert migrated["kalos_opening_revision"]==1 and migrated["pos"]==[x,y]
                assert migrated["party"]==template["party"] and migrated["chapters"]==template["chapters"]
            finally:close(p)
            p=launch()
            try:assert p.pos==(mid,x,y)
            finally:close(p)
            print("MIGRATED AND RELOADED",mid,old,"->",[x,y],flush=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",default="godot")
    parser.add_argument("--pack",type=Path,help="run Godot with the APK's extracted resource archive (.zip or .pck)")
    args=parser.parse_args()
    if args.pack and not args.pack.is_file():
        parser.error(f"resource archive does not exist: {args.pack}")
    run(args.godot,args.pack)
    print("KALOS OPENING PASS",flush=True)
