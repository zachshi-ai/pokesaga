"""Walk the optional Bill, Kenya and Shuckie quest lines on a genuine shared campaign save."""
import argparse
import os
import shutil
import tempfile
from pathlib import Path

from campaign_route import ROOT
from hgss_route import JohtoRoutes
from test_johto_journey import JohtoPlayer
from test_johto_item_journey import fly

def run(p):
    p.do("mode",value="travel")
    fly(p,"圆朱市")
    p.enter("johto_ecruteak_pokecenter_1f")
    p.milestone("js_bill_met")
    p.enter("johto_ecruteak_city")
    fly(p,"满金市")
    p.interact("johto_bills_familys_house",(1,1))
    p.do("click",label="接受")
    p.milestone("js_bill_home")
    p.interact("johto_route_35_goldenrod_gate",(0,2))
    p.do("click",label="接受");p.milestone("js_kenya")
    p.interact("johto_route_31",(8,3))
    choice=next(b for b in p.state["buttons"] if "KENYA" in b)
    p.do("click",label=choice);p.milestone("js_letter")
    p.interact("johto_route_35_goldenrod_gate",(0,2));p.milestone("js_kenya_thanks")
    p.enter("johto_goldenrod_city")
    fly(p,"湛蓝市")
    p.interact("johto_manias_house",(1,2));p.do("click",label="照看壶壶");p.milestone("js_shuckie")
    assert p.state["bag"]["城都招式学习器 50"]==1
    return p.state["steps"],p.state["turns"]

if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--save",type=Path,required=True)
    cli.add_argument("--godot",default="godot")
    cli.add_argument("--result-save",type=Path)
    cli.add_argument("--pack",type=Path)
    args=cli.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-crystal-optional-") as temp:
        save=Path(temp)/"save.json";shutil.copyfile(args.save,save)
        opt=["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        cmd=[args.godot,"--headless","--fixed-fps","60",*opt]
        env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=temp)
        routes=JohtoRoutes()
        p=JohtoPlayer(routes,cmd,env,temp)
        try:steps,turns=run(p)
        finally:p.do("quit");p.process.wait()
        q=JohtoPlayer(routes,cmd,env,temp)
        try:
            assert p.state["party"]==q.state["party"] and set(p.state["flags"])==set(q.state["flags"]) and p.state["bag"]==q.state["bag"]
            if args.result_save:shutil.copyfile(save,args.result_save)
            print("CRYSTAL OPTIONAL JOURNEY AND RELOAD PASS",steps,turns)
        finally:q.do("quit");q.process.wait()
