#!/usr/bin/env python3
"""Replay a new game from Pallet Town through the Sevii network-machine repair."""
import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

from campaign_route import ROOT, VECTORS, Routes


class Player:
    def __init__(self, routes, godot_args, env, folder, startup=()):
        self.routes = routes
        self.process = subprocess.Popen([*godot_args, "--script", str(ROOT / "tools/campaign_player.gd"), *startup],
                                        cwd=folder, env=env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.puzzles = json.loads((ROOT / "content/regions/kanto/puzzles.json").read_text()) if "kanto" in routes.regions else {}
        self.last_flags = None
        self.receive()

    def receive(self):
        for line in self.process.stdout:
            if not line.startswith("STATE "):
                if "ERROR:" in line: raise RuntimeError(line.strip())
                continue
            self.state = json.loads(line[6:])
            self.pos = tuple(self.state["pos"])
            self.routes.occupied[self.pos[0]] = {tuple(r[0]) for r in self.state["actors"]}
            self.routes.history = self.state["history"]
            badges = self.state["badges"]
            field_badges = {15: "蓝色徽章", 57: "粉红徽章", 70: "彩虹徽章", 249: "金色徽章"}
            if self.pos[0].startswith("johto_"):
                field_badges = {15:"昆虫徽章", 57:"魅影徽章", 70:"标准徽章", 250:"冰川徽章", 127:"升龙徽章"}
            moves = frozenset(move for member in self.state["party"] for move in member[5]
                              if field_badges.get(move) in badges)
            if self.routes.field_moves != moves:
                self.routes.field_moves = moves
                self.routes.edges.cache_clear()
            flags = frozenset(self.state["flags"])
            if flags != self.last_flags:
                self.routes.occupied = {self.pos[0]: self.routes.occupied[self.pos[0]]}
                for mid, rules in self.puzzles.items():
                    for rule in rules:
                        for variant in rule["variants"]:
                            if set(variant["flags"]) <= flags:
                                for x,y,_,_,blocked in variant["cells"]:
                                    self.routes.fields[mid].grid["collision"][y*self.routes.fields[mid].w+x] = int(blocked)
                self.routes.edges.cache_clear()
                self.last_flags = flags
            for name, mon, level, result in self.state["fights"]:
                print("FIGHT", name or "wild", mon, level, result, flush=True)
            if self.state["problem"]:
                raise RuntimeError(self.state["problem"])
            return self.state
        raise RuntimeError("Godot stopped before reporting state")

    def do(self, action, **opts):
        self.process.stdin.write(json.dumps(dict(action=action, **opts), ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        if action != "quit":
            return self.receive()

    def go(self, goals):
        self.routes.denied.clear()
        for attempt in range(250):
            if self.pos in goals: return
            plan = self.routes.path(self.pos, goals)
            for i in range(0, len(plan), 24):
                batch = plan[i:i+24]
                previous = self.pos
                self.do("walk", legs=[[k, end] for _, k, end in batch])
                if self.pos == batch[-1][2]: continue
                event = self.state["obstruction"]
                stuck = (tuple(event[0]), event[1], tuple(event[2])) if event else None
                if not stuck: break  # a story cutscene or a remembered door changed position
                _, key, end = stuck
                field = self.routes.fields[self.pos[0]]
                dx, dy, _, _ = VECTORS[key]
                x, y = self.pos[1] + dx, self.pos[2] + dy
                if (self.pos == stuck[0] and 0 <= x < field.w and 0 <= y < field.h and
                        (field.get("water",x,y) or (x,y) in field.blockers)):
                    self.do("face", dir=key)
                    if self.pos!=stuck[0]: break  # Waterfall moves the player as part of pressing A.
                    for options in [("冲浪", "好", "使用居合斩"), ("好",)]:
                        choice = next((b for b in options if b in self.state["buttons"]), None)
                        if choice: self.do("click", label=choice)
                    self.do("walk", legs=[[key, end]])
                    if self.pos != stuck[0]: break
                self.routes.denied.add((stuck[0],key))
                if len(self.routes.denied)<12: print("BLOCK",stuck,self.state["dialog"][-1:], self.state["buttons"][:4],flush=True)
                if len(self.routes.denied) % 20 == 0:
                    print("Replanning", previous, self.pos, self.state["dialog"][-2:], flush=True)
                break
        raise RuntimeError(f"Cannot reach {goals} from {self.pos}")

    def visit(self, mid, xy, face=None):
        self.go({(mid,*xy)})
        if face: self.do("face",dir=face)

    def interact(self, mid, xy):
        f = self.routes.fields[mid]
        goals = {}
        for key,(dx,dy,_,_) in VECTORS.items():
            near = (xy[0]-dx,xy[1]-dy)
            if not (0 <= near[0] < f.w and 0 <= near[1] < f.h): continue
            if f.get("collision",*near) and near not in f.blockers:
                far = (near[0]-dx,near[1]-dy)
                if not (0 <= far[0] < f.w and 0 <= far[1] < f.h): continue
                if f.get("collision",*far): continue
                near = far
            goals[(mid,*near)] = key
        self.go(goals)
        self.do("face", dir=goals[self.pos])
        print("TALK", mid, xy, self.state["dialog"][-3:], flush=True)

    def milestone(self, name):
        assert name in self.state["flags"] or name in self.state["badges"], (name,self.pos,self.state)
        self.do("save")
        print("PROGRESS",name,self.pos,"steps",self.state["steps"],"turns",self.state["turns"],flush=True)

    def finish(self):
        self.do("quit")
        if self.process.wait(timeout=15):
            raise RuntimeError("Campaign controller failed")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot",default="godot")
    ap.add_argument("--pack",type=Path)
    ap.add_argument("--result-save",type=Path,help="Copy the completed save for Android device verification")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-journey-") as folder:
        env = dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=folder)
        cmd = [args.godot,"--headless","--fixed-fps","60"]
        cmd += ["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        subprocess.run([*cmd,"--script",str(ROOT/"tools/test_first_chapter.gd"),"--","play"],
                       cwd=folder,env=env,check=True)
        player = Player(Routes(),cmd,env,folder)
        try:
            play_campaign(player)
        finally:
            player.finish()
        with Path(folder,"save.json").open() as saved_file:
            saved=json.load(saved_file)
        assert saved["flags"]["sevii_network_online"] and len(saved["hall_of_fame"]["kanto"]) > 0
        reopened=Player(player.routes,cmd,env,folder)
        try:
            assert tuple(saved["pos"]) == reopened.pos[1:] and saved["map"] == reopened.pos[0]
            for field in ("badges","dex","hall","bag"):
                assert reopened.state[field] == player.state[field], field
            assert "sevii_network_online" in reopened.state["flags"]
            if args.result_save:
                args.result_save.write_bytes(Path(folder,"save.json").read_bytes())
            print("KANTO SEVII RELOAD PASS", reopened.pos, flush=True)
        finally:
            reopened.finish()


def train_at_moon(p):
    from campaign_collection import supplies
    supplies(p, 15)
    mid = "mt_moon_1f"
    center = "route4_pokemon_center_1f"
    p.do("mode",value="collect")
    p.visit(center,(7,4),"u")
    p.visit(mid,(18,35))
    p.do("walk", legs=[leg for _ in range(45) for leg in [("u",[mid,18,34]),("d",[mid,18,35])]])
    p.do("mode",value="travel")
    p.visit(center,(7,4),"u")
    for i in range(210):
        if p.state["party"][0][2] >= 16:
            p.visit(center,(7,4),"u")
            return
        p.visit(mid,(18,35))
        p.do("mode",value="train")
        p.do("walk",legs=[leg for _ in range(6) for leg in [("u",[mid,18,34]),("d",[mid,18,35])]])
        p.do("mode",value="travel")
        lead = p.state["party"][0]
        if lead[3] < lead[4] * 0.75 or max(lead[6][:2]) < 6 or sum(lead[6][:2]) < 12:
            p.visit(center,(7,4),"u")
    raise RuntimeError(("Moon training",p.state["party"]))


def earned(p, flag):
    return flag in p.state["flags"] or flag in p.state["badges"]


def talk(p, mid, xy, flag):
    if not earned(p, flag):
        p.interact(mid, xy)
        p.milestone(flag)


def step(p, mid, xy, flag):
    if not earned(p, flag):
        p.visit(mid,xy)
        p.milestone(flag)


def clinic(p, city):
    p.do("mode",value="travel")
    p.visit(city+"_pokemoncenter_1f",(7,4),"u")
    assert all(m[3] == m[4] for m in p.state["party"]), (p.pos, p.state["dialog"])


def wild_training(p, habitat, until, center):
    from campaign_collection import habitats, enter_patch, pace
    patch = next(h for h in habitats() if h.name == habitat)
    for i in range(400):
        lead = p.state["party"][0]
        if lead[3] < lead[4]*0.75 or sum(lead[6][:2]) < 10:
            clinic(p, center)
        if max(m[2] for m in p.state["party"]) >= until: break
        if p.pos[0] != patch.mid or p.pos[1:] not in patch.grass: enter_patch(p,patch)
        pace(p, patch, "train", 16)
    p.do("mode",value="travel")
    clinic(p, center)


def cerulean(p):
    if not earned(p,"rival_bridge"):
        clinic(p,"ceruleancity")
        wild_training(p,"ROUTE4",20,"ceruleancity")
        step(p,"kanto_main",(287,46),"rival_bridge")
    mid="route25_sea_cottage"
    if not earned(p,"ss_ticket"):
        p.interact(mid,(10,6))
        p.visit(mid,(4,6),"u")
        p.interact(mid,(3,4))
        p.milestone("ss_ticket")
    # Returning to Cerulean refreshes the officer who has moved away from the house.
    if not earned(p,"beat_cerulean_rocket"):
        p.visit("kanto_main",(287,46))
    talk(p,"kanto_main",(297,46),"beat_cerulean_rocket")
    clinic(p,"ceruleancity")
    talk(p,"ceruleancity_gym",(8,6),"蓝色徽章")


def learn_hm(p, name, move_id, slot=0):
    if any(move_id in m[5] for m in p.state["party"]): return
    mon = p.state["party"][slot]
    p.do("hm")
    p.do("click",label=name)
    p.do("click",label=mon[0])
    if p.state["buttons"]:
        moves = json.loads((ROOT/"content/moves.json").read_text())
        by_id = {int(row["id"]):row for row in moves}
        old = min((by_id[int(i)] for i in mon[5] if int(i) not in (15,57,70)), key=lambda m:m.get("power",0))
        p.do("click",label=old["name"])
    assert move_id in p.state["party"][slot][5], (name,p.state["buttons"],p.state["dialog"])


def vermilion(p):
    from campaign_collection import habitats,enter_patch,pace
    clinic(p,"vermilioncity")
    talk(p,"vermilioncity_pokemoncenter_1f",(6,4),"got_vs_seeker")
    fishing_gift(p,"vermilion_city_house1",(4,5),"破旧钓竿")
    step(p,"s_s_anne_2_f_corridor",(31,6),"rival_anne")
    talk(p,"s_s_anne_captains_office",(5,4),"anne_cut")
    learn_hm(p,"居合斩",15,1)
    if not earned(p,"橙色徽章"):
        patch=next(h for h in habitats() if h.mid=="digletts_cave_b1f")
        enter_patch(p,patch)
        for lap in range(8):
            pace(p,patch,"collect",24)
            if 51 in p.state["dex"]: break
        clinic(p,"vermilioncity")
        mid="vermilioncity_gym"
        bins=p.puzzles[mid][0]["controls"]
        if not earned(p,"surge_open"):
            p.interact(mid,bins[0])
            if not earned(p,"surge_first"):
                p.interact(mid,bins[int(p.state["bins"][0])])
            p.interact(mid,bins[int(p.state["bins"][1])])
            p.milestone("surge_open")
        talk(p,mid,(5,2),"橙色徽章")


def celadon(p):
    from campaign_collection import supplies, habitats, enter_patch, pace
    if not earned(p,"彩虹徽章"):
        clinic(p,"celadoncity")
        supplies(p,18)
        garden = next(h for h in habitats() if h.name == "ROUTE7")
        enter_patch(p,garden)
        pace(p,garden,"collect",40)
        clinic(p,"celadoncity")
        wild_training(p,"ROUTE7",36,"celadoncity")
    if not earned(p,"saffron_tea"): clinic(p,"celadoncity")
    talk(p,"celadon_city_condominiums_1f",(2,9),"saffron_tea")
    talk(p,"route7_east_entrance",(6,2),"saffron_gates_open")
    mid="celadon_city_game_corner"
    talk(p,mid,(11,2),"poster_grunt_win")
    talk(p,mid,(11,1),"hideout_stairs")
    base="rocket_hideout_b4f"
    talk(p,base,(4,2),"lift_grunt_win")
    talk(p,base,(3,2),"lift_key")
    if not earned(p,"hideout_guard_1_win"):
        p.visit("rocket_hideout_elevator",(0,3),"u")
        p.do("click",label="B4F")
    for xy, flag in [((16,14),"hideout_guard_1_win"),((19,14),"hideout_guard_2_win"),((19,4),"hideout_boss_win"),((20,5),"silph_scope")]:
        talk(p,base,xy,flag)
    if p.pos[0] in [base,"rocket_hideout_elevator"]:
        p.visit("rocket_hideout_elevator",(0,3),"u")
        p.do("click",label="B1F")
    clinic(p,"celadoncity")
    talk(p,"celadoncity_gym",(6,4),"彩虹徽章")


def lavender(p):
    clinic(p,"lavendertown")
    talk(p,"pokemontower_2f",(16,5),"rival_tower")
    step(p,"pokemontower_6f",(11,15),"tower_mother")
    for i,xy in enumerate([(9,10),(13,8),(9,6)],1):
        talk(p,"pokemontower_7f",xy,f"beat_tower_grunt_{i}")
    talk(p,"pokemontower_7f",(11,4),"rescued_fuji")
    talk(p,"lavender_town_volunteer_pokemon_house",(3,3),"poke_flute")
    for road, xy in [(16,(163,143)),(12,(398,220))]:
        flag = f"FLAG_HIDE_ROUTE_{road}_SNORLAX"
        if not earned(p,flag):
            clinic(p,"celadoncity" if road == 16 else "vermilioncity")
            p.do("mode",value="collect")
            p.interact("kanto_main",xy)
            p.milestone(flag)
            p.do("mode",value="travel")


def safari_training(p):
    from campaign_collection import habitats,enter_patch,pace,supplies
    if max(m[2] for m in p.state["party"]) >= 42: return
    clinic(p,"fuchsiacity")
    supplies(p,26)
    safari=next(h for h in habitats() if h.name=="safarizone_center")
    enter_patch(p,safari)
    pace(p,safari,"collect",60)
    wild_training(p,"safarizone_center",42,"fuchsiacity")


def saffron(p):
    safari_training(p)
    clinic(p,"saffroncity")
    step(p,"silph_co_5f",(22,21),"card_key")
    talk(p,"silph_co_3f",(21,13),"silph_door_3_2")
    talk(p,"silph_co_7f",(2,6),"rival_silph")
    if not earned(p,"story_silph_lapras"):
        talk(p,"silph_co_7f",(0,7),"story_silph_lapras")
    talk(p,"silph_co_11f",(5,16),"silph_door_11_1")
    talk(p,"silph_co_11f",(6,11),"freed_silph")
    talk(p,"silph_co_11f",(9,9),"story_silph_master_ball")
    clinic(p,"saffroncity")
    talk(p,"saffroncity_gym",(14,11),"金色徽章")


def fishing_gift(p, house, xy, rod):
    if not p.state["bag"].get(rod, 0):
        p.interact(house, xy)
        p.do("click", label="好")
    assert p.state["bag"].get(rod, 0) == 1, rod


def fuchsia(p):
    clinic(p,"fuchsiacity")
    fishing_gift(p,"route12_fishing_house",(4,4),"厉害钓竿")
    fishing_gift(p,"fuchsia_city_house2",(6,5),"好钓竿")
    step(p,"safarizone_west",(28,14),"gold_teeth")
    talk(p,"safari_zone_secret_house",(6,5),"safari_surf")
    talk(p,"fuchsia_city_wardens_house",(3,5),"warden_strength")
    talk(p,"fuchsiacity_gym",(7,13),"粉红徽章")
    learn_hm(p,"冲浪",57)


def cinnabar(p):
    clinic(p,"cinnabarisland")
    from campaign_mansion import acquire_key
    acquire_key(p)
    mid="cinnabarisland_gym"
    for i,(rule,answer) in enumerate(zip(p.puzzles[mid],["是","否","否","否","是","否"]),1):
        flag=f"cinnabar_quiz_{i}"
        if not earned(p,flag):
            p.interact(mid,rule["controls"][0])
            p.do("click",label=answer)
            p.milestone(flag)
    talk(p,mid,(5,4),"深红徽章")


def league_supplies(p):
    clinic_map="indigo_plateau_pokemon_center_1f"
    p.visit(clinic_map,(13,12),"u")
    p.interact(clinic_map,(0,7))
    for name,target,price in [("活力碎片",8,1500),("厉害伤药",12,1200)]:
        amount=min(target-int(p.state["bag"].get(name,0)),int(p.state["money"])//price)
        if amount>0: p.do("shop",item=name,amount=amount)
    p.do("back")


def league_heal(p):
    for slot,mon in enumerate(p.state["party"]):
        hp, max_hp = mon[3:5]
        if hp == 0 and p.state["bag"].get("活力碎片",0):
            p.do("use",item="活力碎片",slot=slot)
            hp = p.state["party"][slot][3]
        if 0 < hp < max_hp * .75:
            for item in ["厉害伤药","全满药","全复药","好伤药","伤药"]:
                if p.state["bag"].get(item,0):
                    p.do("use",item=item,slot=slot)
                    break


def play_campaign(p):
    from campaign_collection import prepare_party, collect_kanto
    from campaign_islands import detour, postgame
    from campaign_league_path import viridian_gym, victory_road
    p.milestone("灰色徽章")
    if not earned(p,"moon_fossil_chosen"):
        train_at_moon(p)
        talk(p,"mt_moon_b2f",(13,11),"moon_nerd_win")
        talk(p,"mt_moon_b2f",(13,7),"moon_fossil_chosen")
    cerulean(p)
    vermilion(p)
    celadon(p)
    lavender(p)
    saffron(p)
    fuchsia(p)
    for number, house, npc in [(2, "route16_house", (4,2)), (5, "route2_east_building", (4,6))]:
        item = f"秘传学习器 {number:02d}"
        if not p.state["bag"].get(item, 0):
            p.interact(house, npc)
        assert p.state["bag"].get(item, 0) == 1, item
    cinnabar(p)
    detour(p)
    clinic(p,"viridiancity")
    viridian_gym(p)
    step(p,"kanto_main",(33,195),"rival_route22_final")
    prepare_party(p)
    learn_hm(p,"怪力",70,1)
    victory_road(p)
    league_supplies(p)
    for r in json.loads((ROOT/"content/regions/kanto/campaign.json").read_text())["league"]:
        league_heal(p)
        xy=(6,8) if "lances" in r["room"] or "champions" in r["room"] else (6,5)
        talk(p,r["room"],xy,r["flag"])
    step(p,"pokemon_league_hall_of_fame",(5,12),"kanto_champion")
    collect_kanto(p)
    postgame(p)
    p.milestone("sevii_network_online")
    print("KANTO SEVII JOURNEY PASS",p.state["badges"],"caught",len(p.state["dex"]))


if __name__ == "__main__":
    main()
