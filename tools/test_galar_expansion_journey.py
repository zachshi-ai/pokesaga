"""Walk the two Galar expansions with a previously earned shared save."""
import argparse
import os
from pathlib import Path
import shutil
import tempfile

from campaign_route import Field, ROOT, read
from campaign_collection import Habitat, pace
from test_galar_journey import GalarRoutes, GalarPlayer
from test_kanto_journey import league_heal


class ExpansionRoutes(GalarRoutes):
    def __init__(self):
        super().__init__()
        self.regions = ("galar", "armor", "crown")
        self.book["gates"].update(read(ROOT/"content/galar_later_campaign.json")["gates"])
        for region in ("armor", "crown"):
            for path in (ROOT / "content/regions" / region / "maps").glob("*.json"):
                m = read(path)
                grid = m["tiles"]
                physics = m.get("physics") or {
                    "collision": [[tile in (1, 2, 6, 7) for tile in row] for row in grid],
                    "water": [[tile == 2 for tile in row] for row in grid],
                    "grass": [[tile == 11 for tile in row] for row in grid],
                }
                self.fields[path.stem] = Field(m, physics)


class ExpansionPlayer(GalarPlayer):
    def room_in_party(self, limit):
        while len(self.state["party"]) > limit:
            slot=len(self.state["party"])-1
            self.do("deposit",slot=slot,box_index=3)
            assert len(self.state["party"])==slot, "PC did not deposit the selected member"

    def retrieve(self, species):
        if any(m[1]==species for m in self.state["party"]):return
        self.room_in_party(11)
        save=self.saved()
        for page,box in enumerate(save["boxes"]):
            members=[m for m in box["mons"] if m]
            for index,m in enumerate(members):
                if int(m["species_id"])==species:
                    self.do("withdraw",slot=index,box_index=page)
                    assert any(m[1]==species for m in self.state["party"])
                    return
        raise ValueError(f"{species} is not in the collection")

    def doubles_team(self, trio):
        self.room_in_party(8)
        for sid in trio:self.retrieve(sid)
        for target in [1,2,0]:
            sid=trio[target]
            index=next(i for i,m in enumerate(self.state["party"]) if int(m[1])==sid)
            if index==target:continue
            if index:self.do("lead",slot=index)
            if target:self.do("lead",slot=target)
        assert [int(m[1]) for m in self.state["party"][:3]]==list(trio)
        for slot in range(3):
            if self.state["held"][slot]=="" and self.state["bag"].get("吃剩的东西",0):
                self.do("equip",slot=slot,item="吃剩的东西")

    def check_reins(self):
        self.room_in_party(10)
        self.retrieve(898)
        def king(save):
            return next(m for m in save["party"] if m and m["species_id"]==898)
        captured=king(self.saved())
        mount=int(captured["fused_part"]["species_id"])
        mounted_form=captured["form"]
        self.do("key_item",item="牵绊缰绳")
        self.close_menus()
        unmounted=self.saved()
        assert not king(unmounted).get("fused_part") and any(m and int(m["species_id"])==mount for m in unmounted["party"])
        self.do("key_item",item="牵绊缰绳")
        self.click_exact("雪暴马" if mount==896 else "灵幽马")
        self.close_menus()
        remounted=king(self.saved())
        assert remounted["form"]==mounted_form and int(remounted["fused_part"]["species_id"])==mount
        print("REINS dismounted / remounted",mounted_form,mount,flush=True)

    def stone(self):
        if self.state["held"][0]=="EVERSTONE":return
        if not self.state["bag"].get("不变之石"):
            self.transfer("伽勒尔")
            self.use_at("galar_turffield",[30,22])
            assert self.state["bag"].get("不变之石")==1
        self.do("equip",slot=0,item="不变之石")
        assert self.state["held"][0]=="EVERSTONE"
        self.station("crown")

    def find_ice(self):
        if not any(int(m[1])==615 for m in self.state["party"]):
            self.room_in_party(11)
            mid="crown_tree"
            f=self.routes.fields[mid]
            grass={(x,y) for y in range(f.h) for x in range(f.w) if f.get("grass",x,y)}
            self.enter(mid)
            self.go({(mid,x,y) for x,y in grass})
            for _ in range(200):
                self.do("throw_with",item="精灵球",species=615,soften=False)
                pace(self,Habitat(mid,mid,grass,{},12),"throw",36)
                if any(int(m[1])==615 for m in self.state["party"]):break
        slot=next(i for i,m in enumerate(self.state["party"]) if int(m[1])==615)
        self.do("lead",slot=slot)

    def practice_kubfu(self):
        cub=lambda: next(m for m in self.state["party"] if m[1]==891)
        target=70 if "g_champion" in self.state["flags"] else 28
        if cub()[2]>=target:return
        self.transfer("伽勒尔")
        self.nurse("galar_turffield")
        mid="galar_wild_north" if "g_champion" in self.state["flags"] else "galar_5"
        f=self.routes.fields[mid]
        grass={(x,y) for y in range(f.h) for x in range(f.w) if f.get("grass",x,y)}
        patch=Habitat(mid,mid,grass,{},14)
        self.go({(mid,x,y) for x,y in grass})
        for batch in range(650):
            if cub()[2]>=target:break
            if batch%20==0:
                self.snapshot("kubfu_training",self.options)
                print("KUBFU LEVEL",cub()[2],flush=True)
            if max(self.state["party"][0][6])<2:
                self.nurse("galar_turffield")
                self.go({(mid,x,y) for x,y in grass})
            pace(self,patch,"train")
        assert cub()[2]>=target, cub()
        self.do("mode",value="travel")
        self.nurse("galar_turffield")
        self.station("armor")

    def buy_balls(self):
        if not self.pos[0].startswith("crown_"):self.station("crown")
        self.enter("crown_freezington")
        a=next(a for a in self.state["actors"] if a[3])
        self.use_at(self.pos[0],a[0])
        self.do("shop",item="精灵球",amount=150)
        if self.state["money"]>80000:self.do("shop",item="高级球",amount=60)
        self.do("back")

    def station(self, target):
        if self.pos[0].split("_")[0] != "galar":
            self.transfer("伽勒尔")
        self.enter("galar_wedgehurst_station_room")
        agent = next(r for r in self.state["actors"] if r[1] == "dlc_station")
        self.use_at(self.pos[0], agent[0])
        self.click_exact({"armor":"铠岛 · 揖礼原野","crown":"王冠雪原 · 滑溜坡"}[target])
        assert self.pos[0].startswith(target), self.pos

    def event(self, e, tower):
        key, mid = e["id"], e["map"]
        if self.pos[0].split("_")[0] != mid.split("_")[0]:
            if mid.startswith("galar_"):
                self.transfer("伽勒尔")
            else:
                self.station(mid.split("_")[0])
        self.enter(mid)
        actor = next((a for a in self.state["actors"] if a[1] == key), None)
        assert actor and actor[0] == e["at"], (key, self.pos, self.state["actors"])
        wild = next((s["battle"]["team"][0]["species"] for s in e["steps"] if s.get("battle",{}).get("wild")),None)
        if key == "dlc_king_capture":
            wild = 898
        if key == "dlc_split":
            wild = 894
        if wild:
            ball = next((k for k in ["高级球","超级球","精灵球","大师球"] if self.state["bag"].get(k,0)>=(1 if wild==79 else 10)), "大师球" if self.state["bag"].get("大师球",0) else "精灵球")
            if wild!=79:
                ball="大师球" if wild==898 and self.state["bag"].get("大师球") else "高级球" if self.state["bag"].get("高级球",0)>5 else "精灵球"
            assert ball, self.state["bag"]
            self.do("throw_with", item=ball, species=wild, soften=wild==79)
        raid_count=len(self.state["galar_raids"])
        self.use_at(mid, actor[0])
        if key=="dlc_honey":
            assert self.state["galar_raids"][raid_count:]==[["stadium",416,[]]],self.state["galar_raids"][raid_count:]
        swap_round=0
        for _ in range(30):
            buttons = self.state["buttons"]
            if not buttons:
                break
            if key=="dlc_split" and "检查石像" in buttons:
                for lamp in [1,2,3,5,7,8,9]:self.do("lamp",slot=lamp)
                self.click_exact("检查石像")
                continue
            preferences = ["雷电兽","煤炭龟","美纳斯","赤面龙","保留租借伙伴",
                           "杰尼龟","恶之塔 · 一击流" if tower=="dark" else "水之塔 · 连击流",
                           "播种","吹响口哨","电纹 · 雷吉艾勒奇","武道熊师","赫普"]
            if key in ("dlc_lair","dlc_beast"):
                if "换用刚才的宝可梦" in buttons:swap_round+=1
                swap="保留租借伙伴" if key=="dlc_lair" and swap_round==3 else "换用刚才的宝可梦"
                preferences=["巨沼怪","煤炭龟","暴雪王","赤面龙",swap]+preferences
            label = next((x for x in preferences if x in buttons), None)
            assert label, (key, buttons)
            self.click_exact(label)
        if wild:
            for attempt in range(12):
                if key in self.state["flags"]:break
                print("RETRY",key,attempt+1,self.state["fights"],flush=True)
                if self.pos[0].startswith("crown"):self.nurse("crown_freezington")
                elif self.pos[0].startswith("galar"):self.nurse("galar_motostoke")
                else:league_heal(self)
                self.enter(mid)
                self.do("throw_with",item="高级球" if self.state["bag"].get("高级球",0)>5 else "精灵球",species=wild,soften=False)
                self.use_at(mid,actor[0])
                if "吹响口哨" in self.state["buttons"]:self.click_exact("吹响口哨")
        assert key in self.state["flags"], (key, self.pos, self.state["fights"], self.state["dialog"])
        self.do("mode", value="travel")
        assert all(a[1] != key for a in self.state["actors"]), (key, "actor remained")

    def snapshot(self, key, args):
        self.do("save")
        if args.checkpoints:
            args.checkpoints.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.save_slot, args.checkpoints / (key+".json"))
        print("DLC", key, self.pos, self.state["steps"], self.state["turns"], flush=True)


def run(args):
    routes = ExpansionRoutes()
    rows = read(ROOT / "content/galar_expansion.json")
    with tempfile.TemporaryDirectory(prefix="pokesaga-dlc-") as temp:
        folder = Path(temp)
        slot = folder/"save.json"
        shutil.copyfile(args.resume,slot)
        initial = read(slot)
        assert initial["flags"].get("g_badge_1"), "supply an earned Galar save"
        godot = [args.godot,"--headless","--fixed-fps","60"]
        godot += ["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        p=ExpansionPlayer(routes,godot,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=temp),folder)
        p.save_slot=slot
        p.options=args
        try:
            if not initial["flags"].get("dlc_pass"):p.room_in_party(4)
            if args.region=="star":
                assert initial["flags"].get("dlc_mustard") and initial["flags"].get("dlc_report") and initial["flags"].get("g_hop_final")
                if p.pos[0].split("_")[0]!="galar":p.transfer("伽勒尔")
                invite=next(e for e in rows if e["id"]=="dlc_star_invite")
                for trio in [(58,245,889),(898,245,889),(57,898,245),(889,25,898),(898,97,57)]:
                    p.doubles_team(trio)
                    p.nurse("galar_wyndon")
                    p.enter("galar_stadium")
                    try:
                        if invite["id"] not in p.state["flags"]:
                            p.event(invite,args.tower)
                            p.snapshot("dlc_star_invite",args)
                        else:
                            pair=next(a for a in p.state["actors"] if a[1]=="dlc_star")
                            p.use_at(p.pos[0],pair[0])
                            p.click_exact("赫普")
                        break
                    except AssertionError:
                        if not any(f[3]=="b" for f in p.state["fights"]):raise
                        print("STAR TOURNAMENT RETRY",trio,p.state["fights"],flush=True)
                result=p.saved()
                assert int(result["flags"]["dlc_star_wins"])>int(initial["flags"].get("dlc_star_wins",0)),p.state
                p.snapshot("dlc_star_wins",args)
                if args.result_save:shutil.copyfile(slot,args.result_save)
                print("GALAR EXPANSION PASS star dlc_star_wins",flush=True)
                return
            for e in rows:
                k = e["id"]
                if k != "dlc_pass" and args.region=="armor" and not (e["map"].startswith("armor_") or k.startswith("dlc_urshifu")):continue
                if k != "dlc_pass" and args.region=="crown" and not (e["map"].startswith("crown_") or k in ("dlc_zapdos","dlc_moltres")):continue
                if (e.get("branch") and e["branch"][1]!=args.tower) or k=="dlc_plot_shadow":continue
                if k not in p.state["flags"]:
                    if k in ("dlc_view1","dlc_tower_choice","dlc_dark1","dlc_water1"):
                        p.retrieve(891)
                    if k.startswith(("dlc_dark","dlc_water")) and k[-1].isdigit():
                        p.practice_kubfu()
                        league_heal(p)
                    if k in ("dlc_king_capture","dlc_articuno","dlc_steel") and (p.state["bag"].get("精灵球",0)<125 or p.state["bag"].get("高级球",0)<5):
                        p.buy_balls()
                    if k=="dlc_rock":p.stone()
                    if k=="dlc_ice":p.find_ice()
                    if k=="dlc_split":
                        p.room_in_party(8)
                        for sid in [377,378,379]:p.retrieve(sid)
                        assert {377,378,379}<={int(m[1]) for m in p.state["party"]}
                    if k == "dlc_urshifu_soup":
                        p.enter("armor_cave")
                        a=next(a for a in p.state["actors"] if a[1]=="dlc_forage")
                        p.use_at(p.pos[0],a[0])
                    for retry in range(8):
                        try:
                            p.event(e,args.tower)
                            break
                        except AssertionError:
                            if k not in ("dlc_lair","dlc_beast") or retry==7 or not any(f[3]=="b" for f in p.state["fights"]):raise
                            print("RENTAL PARTY RETURNED, RETRY",k,retry+1,flush=True)
                    if k=="dlc_king_capture":p.check_reins()
                    p.snapshot(k,args)
                if k==args.stop_at:break
            assert args.stop_at in p.state["flags"], args.stop_at
            if args.result_save:
                shutil.copyfile(slot,args.result_save)
            print("GALAR EXPANSION PASS",args.region,args.stop_at,flush=True)
        finally:
            if p.process.poll() is None:p.finish()


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",default="godot")
    parser.add_argument("--pack",type=Path)
    parser.add_argument("--resume",required=True,type=Path)
    parser.add_argument("--region",choices=["armor","crown","star"],required=True)
    parser.add_argument("--tower",choices=["dark","water"],default="dark")
    parser.add_argument("--stop-at",required=True)
    parser.add_argument("--checkpoints",type=Path)
    parser.add_argument("--result-save",type=Path)
    run(parser.parse_args())
