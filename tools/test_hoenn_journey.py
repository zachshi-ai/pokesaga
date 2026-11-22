#!/usr/bin/env python3
"""Play Emerald from the moving van to the Hall of Fame through the ordinary game inputs."""
import argparse
import json
import os
import tempfile
from pathlib import Path

from campaign_collection import Habitat, pace
from campaign_route import ROOT, VECTORS, Routes
from test_kanto_journey import Player


class EmeraldPlayer(Player):
    def __init__(self, *args, **kwargs):
        self.events = json.loads((ROOT / "content/hoenn_campaign.json").read_text())["events"]
        self.checkpoint = None
        super().__init__(*args, **kwargs)

    def enter(self, mid):
        if self.pos[0] != mid:
            field = self.routes.fields[mid]
            arrivals = {(mid, x, y) for y in range(field.h) for x in range(field.w)
                        if not field.get("collision", x, y)}
            self.go(arrivals)

    def use_at(self, mid, at):
        self.enter(mid)
        at = tuple(map(int,at))
        field = self.routes.fields[mid]
        goals = {}
        for direction, (dx, dy, *_) in VECTORS.items():
            x, y = at[0] - dx, at[1] - dy
            if not (0 <= x < field.w and 0 <= y < field.h):
                continue
            if field.get("counter", x, y):
                x, y = x-dx, y-dy
            if 0 <= x < field.w and 0 <= y < field.h and not field.get("collision", x, y):
                goals[mid, x, y] = direction
        self.go(goals)
        self.do("face", dir=goals[self.pos])

    def select(self, text):
        button = next((b for b in self.state["buttons"] if text in b), None)
        if button:
            self.do("click", label=button)
        return button is not None

    def scene(self, event):
        mid, trigger = event["map_id"], event["trigger"]
        self.enter(mid)
        if event["id"] in self.state["flags"]:
            return
        kind = trigger["kind"]
        if kind in ("talk", "field"):
            actors = [r for r in self.state["actors"] if len(r) > 8 and r[8] == trigger.get("actor")]
            self.use_at(mid, actors[0][0] if actors else trigger["at"])
            if event["id"] == "h_rescued":
                if not self.select("水跃鱼"):
                    raise AssertionError(("starter selector", self.state["buttons"]))
            if event["id"] == "h_wallace_origin":
                assert self.select("天空之柱"), self.state["buttons"]
        elif kind == "step":
            l, t, r, b = trigger["area"]
            self.go({(mid,x,y) for x in range(l,r) for y in range(t,b)},until_flag=event["id"])
        elif kind != "enter":
            raise ValueError(trigger)
        if event["id"] not in self.state["flags"]:
            raise AssertionError((event["id"], self.pos, self.state["dialog"], self.state["buttons"], self.state["party"]))

    def train(self, mid, level, center):
        if self.state["party"][0][2] >= level: return
        field = self.routes.fields[mid]
        cells = {(x,y) for x in range(field.w) for y in range(field.h)
                 if field.get("grass",x,y) and not field.get("collision",x,y)}
        cells = {at for at in cells if any((at[0]+dx,at[1]+dy) in cells for dx,dy,*_ in VECTORS.values())}
        patch = Habitat(mid, mid, cells, {}, level)
        nurse = next(n for n in self.routes.fields[center].data["npcs"] if n.get("name") == "护士")
        while self.state["party"][0][2] < level:
            mon = self.state["party"][0]
            if mon[3] <= max(6,mon[4]*.65) or sum(mon[6]) < 6:
                self.use_at(center, nurse["at"])
                assert self.state["party"][0][3] == self.state["party"][0][4], ("nurse", self.pos)
            self.go({(mid,*at) for at in cells})
            try:
                purpose = "collect" if len(self.state["party"]) < 4 and self.state["bag"].get("精灵球",0) and self.state["steps"]%3 == 0 else "train"
                pace(self, patch, purpose, 14)
            except RuntimeError:
                if self.pos[0] == mid:
                    cells.discard(self.pos[1:])
                if not cells: raise
        self.use_at(center,nurse["at"])
        self.do("mode",value="travel")

    def play(self, folder, stop):
        for event in self.events:
            if event.get("repeat") or event["id"] in self.state["flags"]: continue
            print("TARGET", event["id"], self.pos, flush=True)
            if event["id"] == "h_rescued": self.do("mode",value="train")
            if event["id"] == "h_may103":
                self.train("route101",8,"em_oldale_town_pokemon_center_1f")
            if event["id"] == "h_badge_1":
                self.train("hoenn_116",16,"em_rustboro_city_pokemon_center_1f")
            training = {
                "h_badge_2": ("hoenn_granite",25,"em_dewford_town_pokemon_center_1f"),
                "h_may110": ("hoenn_110",27,"em_slateport_city_pokemon_center_1f"),
                "h_badge_3": ("hoenn_117",30,"em_mauville_city_pokemon_center_1f"),
                "h_badge_4": ("hoenn_113",36,"em_fallarbor_town_pokemon_center_1f"),
                "h_weather": ("hoenn_118",40,"em_mauville_city_pokemon_center_1f"),
                "h_badge_6": ("hoenn_120",47,"em_fortree_city_pokemon_center_1f"),
                "h_badge_7": ("hoenn_121",52,"em_lilycove_city_pokemon_center_1f"),
                "h_wally_road": ("hoenn_victory",62,"em_ever_grande_city_pokemon_center_1f"),
                "h_league": ("hoenn_victory",72,"em_ever_grande_city_pokemon_center_1f"),
            }
            from hoenn_field_route import prepare
            if event["id"] not in ("h_weather","h_league"): prepare(self,event)
            if event["id"] in training: self.train(*training[event["id"]])
            if event["id"] in ("h_weather","h_league"): prepare(self,event)
            from hoenn_story_route import prepare as prepare_story
            prepare_story(self,event)
            from hoenn_gym_route import prepare as solve_gym
            solve_gym(self,event)
            if event["id"] in ("h_chimney_tabitha","h_badge_4","h_magma_gate"):
                self.use_at("em_route112_cable_car_station",(6,6))
                assert self.select("烟囱山"), self.state["buttons"]
            self.scene(event)
            self.milestone(event["id"])
            if self.checkpoint:
                self.checkpoint.write_bytes((folder/"save.json").read_bytes())
            if os.environ.get("POKESAGA_CHECKPOINT_DIR"):
                archive = Path(os.environ["POKESAGA_CHECKPOINT_DIR"])
                archive.mkdir(exist_ok=True,parents=True)
                (archive/(event["id"]+".json")).write_bytes((folder/"save.json").read_bytes())
            if event["id"] == stop: break


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",default="godot")
    parser.add_argument("--pack",type=Path)
    parser.add_argument("--resume",type=Path)
    parser.add_argument("--transfer",choices=["carried","boxed"],help="Start a new Emerald chapter within the --resume save")
    parser.add_argument("--result-save",type=Path)
    parser.add_argument("--stop-at",default="h_champion")
    args=parser.parse_args()
    routes=Routes(("hoenn",))
    with tempfile.TemporaryDirectory(prefix="pokesaga-emerald-") as temp:
        folder=Path(temp)
        cmd=[args.godot,"--headless","--fixed-fps","60"]
        cmd+=["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=temp)
        if args.resume: (folder/"save.json").write_bytes(args.resume.read_bytes())
        startup=("--","hoenn-"+args.transfer) if args.transfer else (() if args.resume else ("--","new-hoenn"))
        player=EmeraldPlayer(routes,cmd,env,temp,startup=startup)
        try:
            if args.transfer:
                old=json.loads(args.resume.read_text())
                count=len([m for m in old["party"] if m])
                assert player.pos == ("em_inside_of_truck",2,2)
                assert len(player.state["party"]) == (count if args.transfer=="carried" else 0)
                assert not any(f.startswith("h_badge_") for f in player.state["flags"])
            if not args.resume:
                assert player.pos==("em_inside_of_truck",2,2) and not player.state["party"], ("fresh start",player.pos)
            player.checkpoint=args.result_save
            player.play(folder,args.stop_at)
            assert args.stop_at in player.state["flags"], args.stop_at
            if args.stop_at == "h_champion":
                assert all("h_badge_"+str(i) in player.state["flags"] for i in range(1,9))
                assert player.state["hall"].get("hoenn")
            if args.transfer:
                new=json.loads((folder/"save.json").read_text())
                assert all(new["hall_of_fame"].get(k)==v for k,v in old["hall_of_fame"].items())
                assert new["origin"]==old["origin"] and new["chapters"]["hoenn"]==args.transfer
                if new["flags"].get("h_partner"):
                    assert new["flags"]["h_starter"]==258
                    if count==12 and args.transfer=="carried":
                        assert any(m and m.get("species_id")==258 for b in new["boxes"] for m in b["mons"])
        finally:
            player.finish()
        restored=EmeraldPlayer(routes,cmd,env,temp)
        try:
            for key in ("pos","badges","party","hall","bag"):
                assert restored.state[key] == player.state[key], key
            assert set(restored.state["flags"]) == set(player.state["flags"]), (set(restored.state["flags"]) ^ set(player.state["flags"]))
            print("EMERALD PLAYTHROUGH AND RELOAD PASS",args.stop_at,player.state["steps"],player.state["turns"],flush=True)
        finally:
            restored.finish()

if __name__ == "__main__":
    main()
