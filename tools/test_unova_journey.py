#!/usr/bin/env python3
"""Play both chapters of Unova from a fresh, shared save using the regular field and battle controls."""
import argparse
from collections import deque
from functools import lru_cache
import os
from pathlib import Path
import tempfile

import numpy as np
from scipy.ndimage import label

import unova_gym_route
from campaign_collection import Habitat, pace
from campaign_route import ROOT, Field, Routes, VECTORS, read
from test_hoenn_journey import EmeraldPlayer
from test_kanto_journey import league_heal


class UnovaRoutes(Routes):
    def __init__(self):
        super().__init__(())
        self.regions = ("unova",)
        self.book = read(ROOT / "content/unova_campaign.json")
        self.era = ""
        self.flags = set()
        self.avoid = set()
        self.set_era("bw")

    def set_era(self, era):
        if self.era == era:
            return
        self.era = era
        self.fields.clear()
        self.occupied.clear()
        self.denied.clear()
        self.edges.cache_clear()
        self.components={}
        for p in (ROOT / "content/unova_native" / era).glob("*.json"):
            data = read(p)
            if "physics" in data:
                field=Field(data,data["physics"])
                field.holes={(x,y) for y,row in enumerate(data["physics"].get("hole",[])) for x,v in enumerate(row) if int(v)}
                self.fields[p.stem]=field

    @lru_cache(maxsize=200000)
    def edges(self, loc):
        def passable(dest):
            if isinstance(dest,dict):return True
            mid,x,y=dest
            return dest not in self.avoid and ((x,y) not in self.fields[mid].holes or f"hole:{mid}:{x},{y}" in self.flags)
        return [(key,dest) for key,dest in Routes.edges.__wrapped__(self,loc) if passable(dest)]

    def projection(self, dest):
        phase=3 if "u2_champion" in self.flags else 2 if "u2_ship_ice" in self.flags else 1 if "u2_mchn" in self.flags else 0
        if dest.get("unova_dock_returns"):
            dest={**dest,**dest["unova_dock_returns"].get(str(phase),{})}
        docks=("unova_frigate_driftveil","unova_frigate_seaside","unova_frigate_giant","unova_frigate_p2")
        if self.era=="b2" and dest.get("map") in docks and dest["map"]!=docks[phase]:return None
        gates = self.book["gates"]["1" if self.era == "bw" else "2"]
        if not set(dest.get("unova_requires", [])) <= self.flags:
            return None
        if not set(gates.get(dest.get("map"), {}).get("require", [])) <= self.flags:
            return None
        return super().projection(dest)

    def local_path(self, start, goals):
        pending = deque([start])
        prev = {start: None}
        while pending:
            node = pending.popleft()
            if node in goals:
                steps = []
                while prev[node]:
                    previous, key = prev[node]
                    steps.append((previous, key, node))
                    node = previous
                return steps[::-1]
            for key, dest in self.edges(node):
                if (node,key) in self.denied:continue
                if isinstance(dest, dict):
                    dest = self.projection(dest)
                    if not dest or (dest[0]!=node[0] and dest not in goals):continue
                if dest[1:] in self.occupied.get(dest[0],()) or dest in prev:continue
                prev[dest]=(node,key)
                pending.append(dest)
        return None

    def path(self, start, goals):
        target = next(iter(goals))[0]
        if target == start[0]:
            result = self.local_path(start, goals)
            if result is not None:return result
        # A map can contain disjoint caves: dropping into the closest coordinate without
        # accounting for its floor can strand the player in a different exit of the ruins.
        surf=57 in self.field_moves
        filled=frozenset(key for key in self.flags if key.startswith("hole:"))
        component_state=(surf,filled)
        if component_state not in self.components:
            grids={}
            for mid,f in self.fields.items():
                blocked=np.asarray(f.grid["collision"],dtype=bool).reshape(f.h,f.w)
                if not surf and "water" in f.grid:
                    blocked=blocked | np.asarray(f.grid["water"],dtype=bool).reshape(f.h,f.w)
                if f.holes:
                    blocked=blocked.copy()
                    for x,y in f.holes:
                        if f"hole:{mid}:{x},{y}" not in filled:blocked[y,x]=True
                grids[mid]=label(~blocked)[0]
            self.components[component_state]=grids
        grids=self.components[component_state]
        def region(mid,x,y):
            g=grids[mid]
            return mid,int(g[int(y),int(x)]) if 0<=x<g.shape[1] and 0<=y<g.shape[0] else 0
        target_nodes={region(*p) for p in goals}
        target_nodes={n for n in target_nodes if n[1]}
        reverse={}
        origin=region(*start)
        adjacent=[]
        for mid,field in self.fields.items():
            for warp in field.data["warps"]:
                dest=self.projection(warp["to"])
                if not dest:continue
                x, y = warp["at"]
                # A wall doorway's reachable component is on its south side.
                # The trigger tile itself is solid in a native Kalos façade.
                left = region(mid, x, y+1 if warp.get("trigger") == "door" else y)
                right = region(*dest)
                if not left[1] or not right[1] or left==right:continue
                reverse.setdefault(right,set()).add(left)
                if left==origin:adjacent.append((right,dest))
        distances={n:0 for n in target_nodes}
        pending=deque(target_nodes)
        while pending:
            node=pending.popleft()
            for adj in reverse.get(node,()):
                if adj not in distances:
                    distances[adj]=distances[node]+1
                    pending.append(adj)
        options={}
        for right,dest in adjacent:
            if distances.get(right,99999)<distances.get(origin,99999):
                options.setdefault(distances[right],set()).add(dest)
        for dist in sorted(options):
            plan=self.local_path(start,options[dist])
            if plan:return plan
        try:
            return super().path(start, goals)
        except ValueError:
            raise ValueError(f"No walk from {start} to {target} ({len(goals)} permitted arrival cells)") from None


class StoryLoss(Exception):
    pass


class UnovaPlayer(EmeraldPlayer):
    def go(self, goals, until_flag=None):
        try:
            return super().go(goals,until_flag)
        except RuntimeError as problem:
            if not str(problem).startswith("Cannot reach"):raise
            target=next(iter(goals))[0]
            raise RuntimeError(f"Cannot reach {target} ({len(goals)} arrival cells) from {self.pos}") from None

    def field_moves(self):
        era = "b2" if "u2_started" in self.state["flags"] and "u1_memory" not in self.state["flags"] else "bw"
        occupied=self.routes.occupied.get(self.pos[0],set())
        self.routes.set_era(era)
        self.routes.occupied[self.pos[0]]=occupied
        self.routes.flags = set(self.state["flags"])
        prefix = "u1_" if era=="bw" else "u2_"
        codes = [15,19,57,70,127,291]
        return frozenset(move for mon in self.state["party"] for move in mon[5]
                         if move in codes and prefix+"hm_"+str(codes.index(move)+1) in self.routes.flags)

    def nurse(self, mid):
        self.enter(mid)
        nurse=next(row for row in self.state["actors"] if row[6])
        self.use_at(mid,nurse[0])
        assert all(mon[3]==mon[4] for mon in self.state["party"]), (mid,self.state["dialog"])

    def train_at(self, mid, level, clinic):
        if self.state["party"][0][2]>=level:return
        field=self.routes.fields[mid]
        cells={(x,y) for y in range(field.h) for x in range(field.w)
               if field.get("grass",x,y) and not field.get("collision",x,y) and not field.get("water",x,y)}
        cells={xy for xy in cells if any((xy[0]+dx,xy[1]+dy) in cells for dx,dy,*_ in VECTORS.values())}
        assert cells,("no grass",mid)
        patch=Habitat(mid,mid,cells,{},level)
        previous_level=int(self.state["party"][0][2])
        for loop in range(700*max(1,level-previous_level)):
            lead=self.state["party"][0]
            if lead[2]>previous_level:
                previous_level=lead[2]
                print("TRAINED",mid,lead[0],previous_level,"of",level,flush=True)
                self.do("save")
                if self.result_save:self.result_save.write_bytes(self.save_slot.read_bytes())
            if lead[2]>=level:break
            self.do("mode",value="travel")
            if lead[3]<max(7,lead[4]*.65):league_heal(self)
            lead=self.state["party"][0]
            if lead[3]<max(7,lead[4]*.6) or sum(lead[6])<8:self.nurse(clinic)
            self.go({(mid,*xy) for xy in cells})
            purpose="collect" if len(self.state["party"])<4 and self.state["bag"].get("精灵球") and loop%4==0 else "train"
            try:
                pace(self,patch,purpose,20)
            except RuntimeError:
                if self.pos[0]==patch.mid or not any(row[6] for row in self.state["actors"]):raise
                # Whiteout is an ordinary return to the last Pokémon Center. Retry from its counter.
                print("TRAINING WHITEOUT",mid,"->",self.pos,flush=True)
        else:raise RuntimeError(("training",mid,level,self.state["party"]))
        self.do("mode",value="travel")
        self.nurse(clinic)

    def clinic(self, city):
        # Original BW/B2 zone names have stable native facility IDs even where towns share a map ID.
        place=self.routes.fields["unova_"+city].data["unova_zone"]
        options=[(mid,f) for mid,f in self.routes.fields.items() if f.data["unova_zone"].startswith(place+"_") and
                 any(int(c["model"])==75 for c in f.data["unova_cast"])]
        if not options:
            options=[(mid,f) for mid,f in self.routes.fields.items() if f.data["unova_zone"].startswith(place+"_") and "宝可梦中心" in f.data["name"]]
        return next(mid for mid,f in options if "中心" in f.data["name"]) if any("中心" in f.data["name"] for _,f in options) else options[0][0]

    def teach(self, number):
        moves = [15,19,57,70,127,291]
        labels = ["居合斩","飞翔","冲浪","怪力","攀瀑","潜水"]
        move=moves[number-1]
        if any(move in m[5] for m in self.state["party"]):return
        self.do("hm")
        assert self.select(labels[number-1]), (number,self.state["buttons"])
        if "教给队员" in self.state["buttons"]:self.select("教给队员")
        choices=self.state["buttons"]
        chosen=next((p for p in choices if "冷水猴" in p and number in (1,4)),choices[0] if choices else None)
        if not chosen:raise AssertionError(("no compatible party",number,self.state["party"]))
        self.select(chosen)
        if self.state["buttons"]:
            buttons=self.state["buttons"]
            weak=("摇尾巴","摇晃舞","瞪眼","撞击","聚气","玩水","水枪")
            choice=next((b for w in weak for b in buttons if w in b),next((b for b in buttons if "不学" not in b and not any(k in b for k in labels)),None))
            assert choice,buttons
            self.select(choice)
        assert any(move in m[5] for m in self.state["party"]), ("teaching",number,self.state["buttons"])

    def stock_medicine(self,center):
        merchant=next(r for r in self.state["actors"] if r[3])
        self.use_at(center,merchant[0])
        for item,number in [("活力碎片",12),("全满药",16)]:
            amount=max(0,number-int(self.state["bag"].get(item,0)))
            if amount:self.do("shop",item=item,amount=amount)
        self.do("back")

    def victory_road_strength(self):
        # Entering Black 2's ruins from the south first opens the outdoor approach.
        # The east boulder in the following cavern connects the southern and northern routes.
        for zone,x,y,pushes in [(587,53,22,3),(590,31,9,2)]:
            mid=f"unova_b2_zone_{zone}"
            hole=f"hole:{mid}:{x},{y-pushes}"
            if hole in self.state["flags"]:continue
            self.routes.avoid.add((mid,x,y))
            self.routes.edges.cache_clear()
            try:self.go({(mid,x,y+1)})
            finally:
                self.routes.avoid.clear()
                self.routes.edges.cache_clear()
            for k in range(pushes):
                self.go({(mid,x,y+1-k)})
                self.do("face",dir="u")
            assert hole in self.state["flags"],(self.pos,self.state["dialog"])
            self.go({(mid,x,y-pushes)})
            print("UNOVA STRENGTH PASS",self.pos,flush=True)

    def teach_blizzard(self):
        if any(59 in m[5] for m in self.state["party"]):return
        center=self.clinic("lacunosa")
        self.nurse(center)
        item="合众招式学习器14・暴风雪"
        if not self.state["bag"].get(item):
            self.use_at(center,(11,18))
            self.do("shop",item=item,amount=1)
            self.do("back")
        assert self.state["bag"].get(item),item
        self.do("key_item",item=item)
        choice=next((b for b in self.state["buttons"] if "大剑鬼" in b),None)
        if not choice:
            for _ in range(3):
                if self.state["panels"]>0:self.do("back")
            return
        self.select(choice)
        if self.state["buttons"]:
            replace=next((b for b in self.state["buttons"] if "水流尾" in b),None)
            if not replace:replace=next(b for b in self.state["buttons"] if "不学" not in b and not any(hm in b for hm in ["冲浪","攀瀑","怪力"]))
            self.select(replace)
        assert any(59 in m[5] for m in self.state["party"])
        for _ in range(3):
            if self.state["panels"]>0:self.do("back")
        print("UNOVA TM14 PASS",center,flush=True)

    def prepare(self,e):
        key=e["id"]
        thresholds={
            "u1_bianca_2":("2",10,"accumula"),"u1_school":("2",13,"striaton"),"u1_badge_1":("2",15,"striaton"),
            "u1_badge_2":("3",23,"nacrene"),"u1_badge_3":("3",28,"nacrene"),
            "u1_badge_4":("4",34,"nimbasa"),"u1_badge_5":("5",39,"driftveil"),
            "u1_badge_6":("7",45,"mistralton"),"u1_badge_7":("7",51,"mistralton"),
            "u1_badge_8":("9",54,"opelucid"),"u1_last_rival":("10",62,"opelucid"),"u1_again_shauntal":("13",80,"lacunosa"),
            "u2_ranch_rival":("19",9,"floccesy"),"u2_badge_1":("20",15,"aspertia"),
            "u2_badge_2":("b2_zone_457",21,"virbank"),"u2_badge_3":("castelia_sewers",27,"castelia"),
            "u2_badge_4":("4",34,"nimbasa"),"u2_badge_5":("5",40,"driftveil"),
            "u2_badge_6":("7",48,"mistralton"),"u2_badge_7":("13",54,"lacunosa"),
            "u2_badge_8":("13",59,"lacunosa"),"u2_rival_road":("23",68,"humilau")}
        if key=="u2_ship_ice" and any(m[3]<m[4]*.65 for m in self.state["party"]):
            cabin="unova_b2_zone_576"
            self.use_at(cabin,(23,3))
            assert self.select("休息") and all(m[3]==m[4] for m in self.state["party"]),(self.pos,self.state["dialog"])
        if key=="u2_lacunosa":self.teach_blizzard()
        if key=="u2_mchn":
            center=self.clinic("humilau")
            self.nurse(center)
            self.stock_medicine(center)
        if key in ("u2_lab","u2_purrloin"):
            league_heal(self)
            if any(m[3]<m[4]*.5 for m in self.state["party"]):
                center=self.clinic("humilau")
                self.nurse(center)
                self.stock_medicine(center)
        if key in ("u1_league","u2_league"):
            center="unova_"+("bw" if key.startswith("u1") else "b2")+"_zone_146"
            self.nurse(center)
            self.stock_medicine(center)
        elif key.split("_")[-1] in ("shauntal","grimsley","caitlin","marshal","iris","alder"):
            league_heal(self)
        if key in thresholds:
            mid,lv,town=thresholds[key]
            self.train_at("unova_"+mid,lv,self.clinic(town))
        unova_gym_route.prepare(self,key)
        machines={"u1_dream_mist":1,"u1_tower_alarm":3,"u2_flight":3,"u2_rival_road":5}
        if key=="u2_rival_road":self.teach(4)
        if key in machines:self.teach(machines[key])
        if key=="u2_rival_road":self.victory_road_strength()
        if key=="u1_dream_mist" and "u1_dreamyard_cut" not in self.state["flags"]:
            mid="unova_dreamyard"
            field=self.routes.fields[mid]
            tree=next(c for c in field.data["unova_cast"] if int(c.get("script",0))==10004)
            self.use_at(mid,tree["at"])
            if self.state["buttons"]:self.select("居合斩")
            assert "u1_dreamyard_cut" in self.state["flags"],(self.pos,self.state["dialog"],self.state["buttons"])
        if key=="u1_reshiram":
            self.do("throw_with",species=643,item="大师球")

    def scene(self,e,transfer):
        key,mid=e["id"],e["map"]
        self.enter(mid)
        if key in self.state["flags"]:return
        if key=="u2_ship_switches":
            ox,oy=self.routes.fields[mid].data["unova_origin"]
            for i,(x,y) in enumerate(((6,7),(6,12),(16,7),(16,12)),1):
                flag=f"u2_panel_{i}"
                if flag not in self.state["flags"]:self.go({(mid,x-ox,y-oy)},until_flag=flag)
                assert flag in self.state["flags"]
            assert key in self.state["flags"]
            return
        if e["trigger"]["kind"]=="enter":
            self.do("walk",legs=[])
            if key not in self.state["flags"]:
                for direction,target in self.routes.edges(self.pos):
                    if isinstance(target,tuple):
                        self.do("walk",legs=[[direction,list(target)]])
                        break
            assert key in self.state["flags"],(key,self.pos,self.state["dialog"])
            return
        if key=="u1_badge_4":
            for ride in self.routes.fields[mid].data.get("unova_mechanisms",[]):
                if ride["kind"]!="coaster":continue
                if "switch_at" in ride:
                    self.go({(mid,*ride["switch_at"])})
                self.go({(mid,*ride["to"])})
        npc=next((r for r in self.state["actors"] if e["trigger"]["actor"] in (r[1],r[8])),None)
        assert npc,("missing actor",key,mid,self.state["actors"])
        if key=="u2_charles":
            # Approach first so any trainer battle on Route 5 has finished before counting the party.
            self.go({(mid,npc[0][0],npc[0][1]+1)})
            for _ in range(3):
                ready=sum(mon[3]>0 for mon in self.state["party"])
                if ready>=3:break
                center=self.clinic("nimbasa")
                self.nurse(center)
                self.go({(mid,npc[0][0],npc[0][1]+1)})
            assert sum(mon[3]>0 for mon in self.state["party"])>=3,("rotation eligibility",self.state["party"])
            print("ROTATION READY",[(mon[0],mon[3]) for mon in self.state["party"]],flush=True)
        self.use_at(mid,npc[0])
        if key.endswith("_first_battle"):
            assert self.select("水水獭"),self.state
        elif key=="u1_monkey":
            assert self.select("一起旅行"),self.state["buttons"]
        elif key=="u2_studio":
            assert self.select("正合我意"),self.state["buttons"]
        elif key=="u2_password":
            for code in ("2202","7707","9909","捷克罗姆","雷希拉姆"):
                if not self.state["buttons"]:self.use_at(mid,npc[0])
                assert self.select(code),self.state["buttons"]
                if key in self.state["flags"]:break
        elif key=="u2_pwt":
            for _ in range(3):
                if not self.state["buttons"]:break
                self.do("click",label=self.state["buttons"][0])
        elif key=="u1_two_years":
            assert self.select("寄存队伍" if transfer=="boxed" else "带现有队伍"),self.state["buttons"]
            assert "u2_started" in self.state["flags"]
            return
        if key=="u1_reshiram":self.do("mode",value="travel")
        if key not in self.state["flags"] and any("赶到安全" in t for t in self.state["dialog"]):
            raise StoryLoss(key)
        assert key in self.state["flags"],(key,self.pos,self.state["dialog"],self.state["buttons"],self.state["party"])
        departures={"u1_n_museum","u1_bridge_ghetsis","u1_n_final","u2_freeze","u2_shadow","u2_zinzolin_last"}
        if key in departures and self.pos[0]==mid:
            remaining=[(r[1],r[2],r[0]) for r in self.state["actors"] if r[1]==key or r[1].startswith(key+"_guest")]
            assert not remaining,(key,"cast stayed on screen",remaining)
            print("CAST EXIT",key,mid,npc[0],flush=True)

    def memory_link(self):
        self.do("start")
        assert self.select("工具") and self.select("回忆链接"),self.state["buttons"]

    def verify_memory(self,folder):
        self.do("save")
        before=read(folder/"save.json")
        self.memory_link()
        assert self.select("留在这里") and self.pos[0]=="unova_b2_home"
        self.memory_link()
        assert self.select("重访两年前的鹿子镇")
        assert self.pos[0]=="unova_bw_home_2f" and "u1_memory" in self.state["flags"]
        assert all(not r[1].startswith("u1_first_battle") for r in self.state["actors"])
        self.enter("unova_bw_home_1f")
        assert all(not r[1].startswith("u1_two_years") for r in self.state["actors"])
        self.enter("unova_bw_home_2f")
        self.memory_link()
        assert self.select("回到两年后的桧扇市")
        assert self.pos[0]=="unova_b2_home" and "u1_memory" not in self.state["flags"]
        self.do("save")
        after=read(folder/"save.json")
        defaults={"party":[],"boxes":[],"regional_badges":{},"hall_of_fame":{},"unova_sequel_party":""}
        for field,empty in defaults.items():
            assert before.get(field,empty)==after.get(field,empty),field
        assert after["flags"]["u1_ghetsis"] and after["flags"]["u2_champion"]
        print("UNOVA MEMORY LINK PASS both bedrooms, menu cancellation, party, boxes, badges and Hall of Fame",flush=True)

    def run(self,folder,args):
        self.save_slot=folder/"save.json"
        self.result_save=args.result_save
        for attempt in range(5):
            try:
                self.play_events(folder,args)
                break
            except StoryLoss as loss:
                if attempt==4:raise
                key=str(loss)
                print("STORY WHITEOUT",key,"returning to battle from",self.pos,flush=True)
                if key in ["u2_iris","u2_caitlin","u2_shauntal","u2_marshal","u2_grimsley"]:
                    self.teach_blizzard()
                    self.train_at("unova_13",min(86,self.state["party"][0][2]+4),self.clinic("lacunosa"))

    def play_events(self,folder,args):
        for e in self.routes.book["events"]:
            key=e["id"]
            alder=(args.with_alder or args.stop_at=="u1_alder") and (key.startswith("u1_again_") or key=="u1_alder")
            if not e["route"] and key not in ("u1_monkey",args.stop_at) and not alder:continue
            if key in self.state["flags"] or (key=="u1_two_years" and "u2_started" in self.state["flags"]):continue
            if e["era"]==1 and "u2_started" in self.state["flags"]:continue
            print("NEXT",key,self.pos,flush=True)
            self.prepare(e)
            self.scene(e,args.transfer)
            self.milestone("u2_started" if key=="u1_two_years" else key)
            if args.result_save:args.result_save.write_bytes((folder/"save.json").read_bytes())
            if args.checkpoints:
                args.checkpoints.mkdir(parents=True,exist_ok=True)
                (args.checkpoints/(key+".json")).write_bytes((folder/"save.json").read_bytes())
            if key==args.stop_at:break
        assert args.stop_at in self.state["flags"]
        if args.stop_at=="u2_champion":
            assert all(f"u{i}_badge_{n}" in self.state["flags"] for i in (1,2) for n in range(1,9))
            assert self.state["hall"].get("unova_b2")
            if args.verify_memory:self.verify_memory(folder)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",default="godot")
    parser.add_argument("--pack",type=Path)
    parser.add_argument("--resume",type=Path)
    parser.add_argument("--result-save",type=Path)
    parser.add_argument("--checkpoints",type=Path)
    parser.add_argument("--with-alder",action="store_true")
    parser.add_argument("--verify-memory",action="store_true")
    parser.add_argument("--stop-at",default="u2_champion")
    parser.add_argument("--transfer",choices=("boxed","carried"),default="carried")
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-unova-") as folder_name:
        folder=Path(folder_name)
        if args.resume:(folder/"save.json").write_bytes(args.resume.read_bytes())
        godot=[args.godot,"--headless","--fixed-fps","60"]
        godot+=["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        p=UnovaPlayer(UnovaRoutes(),godot,dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=folder_name),folder,
                      [] if args.resume else ["--","new-unova","unova-boxed"])
        try:p.run(folder,args)
        finally:p.finish()
    print("UNOVA JOURNEY PASS",args.stop_at)

if __name__=="__main__":
    main()
