"""Walk post-Red rewards using a copy of a completed campaign save and real game controls."""
import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

from campaign_route import ROOT
from hgss_route import JohtoRoutes
from johto_item_route import back_to_field, cast, use
from test_johto_journey import JohtoPlayer


def fly(p, city):
    p.teach("飞翔",19)
    p.do("hm")
    for control in ["飞翔","使用飞翔",city]: p.do("click",label=control)


def run(p):
    assert "j2_red_defeated" in p.state["flags"] and len(p.state["badges"])==16
    togepi=next(i for i,m in enumerate(p.state["party"]) if m[1]==175)
    fly(p,"若叶镇")
    p.interact("johto_elms_lab",(2,1))
    p.milestone("j_everstone")
    for slot,item,key in [(togepi,"不变之石","EVERSTONE"),(0,"学习装置","EXP_SHARE")]:
        if p.state["held"][slot]!=key:
            p.do("equip",slot=slot,item=item)
        assert p.state["held"][slot]==key
        print("EQUIP",p.state["party"][slot][0],item,flush=True)

    lure=p.state["bag"].get("诱饵球",0)
    if lure:
        p.do("throw_with",item="诱饵球")
    cast(p,"route_32","破旧钓竿")
    if lure:
        assert p.state["bag"].get("诱饵球",0)<lure
        print("USED LURE BALL on a hooked fish",flush=True)
    p.do("mode",value="travel")
    fly(p,"浅葱市")
    cast(p,"olivine_city","好钓竿")
    cast(p,"route_12","厉害钓竿")

    fly(p,"桧皮镇")
    p.interact("johto_azalea_town",(4,1))
    assert p.state["bag"].get("白球果",0)>0
    p.interact("johto_kurts_house",(7,1))
    p.do("click",label="白球果")
    p.do("click",label="交给他 1 个")
    assert not p.state["bag"].get("白球果",0)
    print("ORDERED FAST BALL from a hand-picked White Apricorn",flush=True)
    if "j_gs_received" not in p.state["flags"]:
        fly(p,"满金市")
        p.enter("johto_goldenrod_pokecenter_1f")
        p.enter("johto_goldenrod_city")
        p.milestone("j_gs_received")
    fly(p,"桧皮镇")
    p.interact("johto_kurts_house",(7,1))
    assert not p.state["bag"].get("GS球",0)
    print("GAVE GS BALL TO KURT",flush=True)
    fly(p,"湛蓝市")
    p.teach("潮旋",250)
    p.teach("攀瀑",127)
    use(p,"银色之羽")
    p.enter("johto_whirl_island_lugia_chamber")
    assert any(k.startswith("whirl:johto_route_41:") for k in p.state["flags"]),"The approach should require removing a sea whirlpool"
    if "j_lugia" not in p.state["flags"]:
        assert p.state["bag"].get("大师球",0)>0,"this replay needs the one unspent Master Ball from Elm"
        p.do("throw_with",item="大师球",species=249)
        p.interact("johto_whirl_island_lugia_chamber",(1,5))
        p.milestone("j_lugia")
    assert 249 in p.state["dex"]
    p.do("mode",value="travel")
    p.do("save")


def following_day(p):
    fly(p,"桧皮镇")
    p.interact("johto_azalea_town",(3,2))
    p.milestone("j_gs_return")
    assert p.state["bag"].get("GS球",0)==1
    p.interact("johto_kurts_house",(7,1))
    assert p.state["bag"].get("速度球",0)==1
    p.enter("johto_ilex_forest")
    p.do("throw_with",item="速度球",species=251)
    p.interact("johto_ilex_forest",(4,11))
    p.do("click",label="放上去")
    p.milestone("j_celebi")
    assert not p.state["bag"].get("GS球",0) and not p.state["bag"].get("速度球",0)
    print("FOLLOWING-DAY CONTROLS PASS: received GS Ball and crafted Fast Ball; used both at Celebi",flush=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--save",required=True,type=Path)
    ap.add_argument("--pack",type=Path)
    ap.add_argument("--godot",default="godot")
    ap.add_argument("--result-save",type=Path)
    ap.add_argument("--following-day",action="store_true",help="Run on a saved post-Red item journey on its next real date")
    ap.add_argument("--previous-date-fixture",action="store_true",help="Only with --following-day: move the two pending orders to yesterday in the temporary copy")
    args=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-crystal-items-") as folder:
        save=Path(folder,"save.json")
        shutil.copyfile(args.save,save)
        if args.previous_date_fixture:
            if not args.following_day: ap.error("use --following-day with --previous-date-fixture")
            from datetime import date,timedelta
            yesterday=str(date.today()-timedelta(days=1))
            f=json.loads(save.read_text())
            f["j_gs_date"]=f["j_apricorn_order"]["date"]=yesterday
            save.write_text(json.dumps(f,ensure_ascii=False))
            print("DATE FIXTURE: only the temporary copy's two order dates are set to",yesterday,flush=True)
        cmd=[args.godot,"--headless","--fixed-fps","60"]+(
            ["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)])
        routes=JohtoRoutes()
        env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=folder)
        p=JohtoPlayer(routes,cmd,env,folder)
        try:
            if args.following_day:following_day(p)
            else:run(p)
        finally:
            p.finish()
        reopened=JohtoPlayer(routes,cmd,env,folder)
        try:
            for k in ["held","bag","flags","dex","party"]:
                if k in ("flags","dex"):
                    assert set(p.state[k])==set(reopened.state[k]),(k,set(p.state[k])^set(reopened.state[k]))
                else: assert p.state[k]==reopened.state[k],k
            result=json.loads(save.read_text())
            assert result["j_gs_date"] and result["flags"]["j_lugia"]
            if args.following_day:
                assert result["flags"]["j_gs_offered"] and result["flags"]["j_celebi"] and not result.get("j_apricorn_order")
            else:
                assert result["j_apricorn_order"]["fruit"]=="白球果" and result["j_apricorn_order"]["count"]==1
                print("SAVED",result["j_apricorn_order"],"GS Ball research date",result["j_gs_date"],flush=True)
            if args.result_save:shutil.copyfile(save,args.result_save)
            print("JOHTO POST-RED ITEMS RELOAD PASS",reopened.pos,flush=True)
        finally:reopened.finish()


if __name__=="__main__":main()
