#!/usr/bin/env python3
"""Continue an earned Kalos save using ordinary field, party, bag and battle inputs."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

from campaign_route import ROOT
from test_kalos_journey import KalosPlayer, KalosRoutes


class KalosSidePlayer(KalosPlayer):
    def talk(self, key):
        row = next(r for r in self.rows if r["id"] == key)
        mid = row["map"]
        self.enter(mid)
        actor = next(a for a in self.state["actors"] if a[1] == "kalos_side_"+key)
        self.use_at(mid, actor[0])
        print("TALK", key, mid, actor[0], self.state["buttons"][:5], flush=True)

    def save_progress(self, folder):
        self.do("save")
        if self.result_save:
            shutil.copyfile(folder/"save.json", self.result_save)

    def postgame(self, folder):
        assert "k_champion" in self.state["flags"]
        if "k_train_pass" not in self.state["flags"]:
            self.talk("train")
            assert "k_train_pass" in self.state["flags"]
        if "ks_maison_played" not in self.state["flags"]:
            self.talk("maison")
            assert self.select("单打")
            for _ in range(3):
                choices=[b for b in self.state["buttons"] if "Lv." in b]
                assert choices, self.state["buttons"]
                self.do("click", label=choices[0])
            assert self.select("开始下一场")
            if self.state["buttons"]:
                self.select("暂时休息")
            assert "ks_maison_played" in self.state["flags"]
        self.save_progress(folder)
        self.nurse("kalos_center_kiloude")
        if "ks_rival" not in self.state["flags"]:
            self.talk("rival")
            assert "ks_rival" in self.state["flags"]
        if "ks_sundial" not in self.state["flags"]:
            self.talk("sundial")
            assert "ks_sundial" in self.state["flags"]
        self.save_progress(folder)
        for key in ["case1", *("ticket%d"%i for i in range(1,6)), "case2",
                    *("alley%d"%i for i in range(4)), "emma", "mimi", "tourist",
                    *("gang%d"%i for i in range(3)), "museum_case", "canvas",
                    *("suit%d"%i for i in range(3)), "hotel_tip", "malva",
                    *("lab%d"%i for i in range(6)), "notes",
                    *("essentia%d"%i for i in range(4)), "letter", "last_witness", "farewell"]:
            if "ks_"+key in self.state["flags"]:
                continue
            if key in ["alley0","gang0","suit0","malva","lab0","lab3","essentia0","essentia2"]:
                self.nurse("kalos_lumiose_center_magenta")
            self.talk(key)
            if key=="mimi":
                assert self.select("跳舞")
            assert "ks_"+key in self.state["flags"], (key,self.state["dialog"])
            self.save_progress(folder)
        print("KALOS POSTGAME JOURNEY PASS Maison, rival, sundial, five tickets, Looker chapters 1-6",
              self.state["steps"], self.state["turns"], flush=True)

    def reminders(self, folder):
        mid="kalos_8"
        self.enter(mid)
        field=self.routes.fields[mid]
        at=field.data["kalos_anchors"]["side10"]
        self.use_at(mid, at)
        assert self.state["bag"].get("心之鳞片",0)>0, self.state["dialog"]
        self.talk("reminder")
        name=self.state["party"][0][0]
        assert self.select(name)
        learned=self.state["buttons"][0]
        self.do("click", label=learned)
        if self.state["buttons"]:
            self.do("click", label=self.state["buttons"][0])
        self.talk("deleter")
        assert self.select(name) and self.select(learned) and self.select("确认遗忘")
        self.save_progress(folder)
        assert self.state["bag"].get("心之鳞片",0)==0
        print("KALOS REMINDER JOURNEY PASS",name,learned,self.state["steps"],flush=True)

    def places(self, folder):
        for key in ["parallel", "dash", "backflip", "spin", "cosmic"]:
            self.talk("trick_"+key)
            assert "ks_trick_"+key in self.state["flags"]
        self.talk("coupon")
        self.talk("boutique_santalune")
        assert self.select("宝蓝") and self.select("使用折价券")
        self.nurse("kalos_center_couriway")
        self.talk("inver")
        assert self.select("开始对战")
        self.save_progress(folder)
        saved=json.loads((folder/"save.json").read_text())
        assert saved["kalos_inver_date"] and saved["flags"]["ks_cap"]=="blue"
        assert self.state["bag"].get("折价券",0)==0
        print("KALOS CITY JOURNEY PASS five tricks, discounted boutique and Inver", self.state["steps"],self.state["turns"],flush=True)

    def fossil_and_stone(self, folder):
        assert "k_mega_ring" in self.state["flags"]
        self.talk("aerodactylite")
        assert self.state["bag"].get("化石翼龙进化石", 0)==1
        self.talk("fossils")
        which=next(k for k in self.state["buttons"] if k in ("颚之化石","鳍之化石"))
        assert self.select(which)
        recovered=696 if which=="颚之化石" else 698
        assert any(int(m[1])==recovered for m in self.state["party"])
        self.talk("hm1")
        assert "k_hm_1" in self.state["flags"]
        self.talk("berries")
        self.talk("soil0")
        assert self.select("1　空地") and self.select("橙橙果")
        self.do("key_item",item="莲叶童子喷壶")
        assert self.select("第一垄") and self.select("1　橙橙果") and self.select("用莲叶童子喷壶浇水")
        while self.state["buttons"]:
            self.do("back")
        classic = next((i for i, m in enumerate(self.state["party"]) if m[1] in [4,5,6]),None)
        assert classic is not None, "This replay requires the Charmander branch from Sycamore's lab"
        stone=next(s for s in self.state["bag"] if s.startswith("喷火龙进化石"))
        self.do("equip",slot=classic,item=stone)
        self.do("lead",slot=classic)
        if self.state["party"][0][1]==5:
            self.train_at("kalos_10",36,"kalos_center_geosenge")
        assert self.state["party"][0][1]==6,self.state["party"]
        self.train_at("kalos_10",self.state["party"][0][2]+1,"kalos_center_geosenge")
        self.do("save")
        saved=json.loads((folder/"save.json").read_text())
        mon=next(m for m in saved["party"] if m and int(m.get("species_id",0))==6)
        assert mon["held"]=="CHARIZARDITE_"+self.version.upper() and not mon.get("form"),mon
        assert any("CHARIZARD_MEGA_"+self.version.upper() in k for k in saved["dex_variants"]),saved["dex_variants"]
        assert saved["kalos_garden"]["0"]["berry"]=="oran" and saved["kalos_garden"]["0"]["water"]
        print("KALOS SIDE JOURNEY PASS",which,recovered,stone,mon["level"],"steps",self.state["steps"],"turns",self.state["turns"],flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",default="godot")
    parser.add_argument("--pack",type=Path)
    parser.add_argument("--reminder", action="store_true")
    parser.add_argument("--places", action="store_true")
    parser.add_argument("--postgame", action="store_true")
    parser.add_argument("--resume",type=Path,required=True)
    parser.add_argument("--result-save",type=Path)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="kalos-side-") as tmp:
        folder=Path(tmp)
        shutil.copyfile(args.resume,folder/"save.json")
        source=["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        game=[args.godot,"--headless","--fixed-fps","60",*source]
        p=KalosSidePlayer(KalosRoutes(),game,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp),folder)
        try:
            p.version=json.loads(args.resume.read_text())["flags"].get("k_version","x")
            p.rows=json.loads((ROOT/"content/kalos_side.json").read_text())["events"]
            p.result_save=args.result_save
            p.checkpoints=None
            p.save_slot=folder/"save.json"
            if args.reminder:
                p.reminders(folder)
            elif args.places:
                p.places(folder)
            elif args.postgame:
                p.postgame(folder)
            else:
                p.fossil_and_stone(folder)
            if args.result_save:shutil.copyfile(folder/"save.json",args.result_save)
        finally:p.finish()


if __name__=="__main__":
    main()
