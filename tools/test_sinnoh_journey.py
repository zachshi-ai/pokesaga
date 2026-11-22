#!/usr/bin/env python3
"""Play Platinum in the shared save through ordinary field, party, bag and battle inputs."""
import argparse
import json
import os
import tempfile
from pathlib import Path
from functools import lru_cache

import platinum_gym_route as gyms
import platinum_rift_route as rift
import platinum_boulder_route as rocks
from campaign_collection import Habitat, mode, pace
from campaign_route import ROOT, Routes, VECTORS, read
from test_hoenn_journey import EmeraldPlayer


class PlatinumRoutes(Routes):
    def __init__(self, book):
        super().__init__(("sinnoh",))
        self.flags=set()
        self.gates=book["gates"]
        for field in self.fields.values():
            for n in field.data.get("npcs",[]):
                kind={"FieldMoves_CutTree":"cut","FieldMoves_Rock":"rock","FieldMoves_Boulder":"boulder"}.get(n.get("source_script"))
                if kind: field.blockers[tuple(n["at"])]=kind

    @lru_cache(maxsize=300000)
    def edges(self,loc):
        variants={
            "sinnoh_acuity_lakefront":(("sinnoh_acuity","sinnoh_lake_acuity_low_water"),"sinnoh_acuity" if "s_verity_mars" in self.flags else "sinnoh_lake_acuity_low_water"),
            "sinnoh_verity_lakefront":(("sinnoh_verity","sinnoh_lake_verity_low_water"),"sinnoh_verity" if "s_valor_saturn" in self.flags else "sinnoh_lake_verity_low_water"),
            "sinnoh_valor_lakefront":(("sinnoh_valor","sinnoh_lake_valor_drained"),"sinnoh_lake_valor_drained" if "s_library" in self.flags and "s_giratina" not in self.flags else "sinnoh_valor"),
            "sinnoh_mt_coronet_6f":(("sinnoh_spear","sinnoh_spear_pillar_distorted"),"sinnoh_spear_pillar_distorted" if "s_spear_tag" in self.flags and "s_giratina" not in self.flags else "sinnoh_spear"),
        }
        edges=super().edges(loc)
        pair=variants.get(loc[0])
        if not pair: return edges
        return [(k,dest.get("platinum_alternates",{}).get(pair[1],dict(dest,map=pair[1])) if isinstance(dest,dict) and dest.get("map") in pair[0] else dest) for k,dest in edges]

    def projection(self, dest):
        if dest.get("map")=="sinnoh_vista_lighthouse_elevator":
            back=dest.get("remember_passage",{}).get("destination",{}).get("map")
            if back=="sinnoh_sunyshore": return ("sinnoh_lighthouse",6,10)
            if back=="sinnoh_lighthouse": return ("sinnoh_sunyshore",54,55)
        if not self.flags.issuperset(self.gates.get(dest.get("map"),{}).get("require",[])):
            return None
        return super().projection(dest)


class PlatinumPlayer(EmeraldPlayer):
    def __init__(self,*args,**kwargs):
        self.book=read(ROOT/"content/sinnoh_campaign.json")
        self.registry=read(ROOT/"content/platinum_native/index.json")
        super().__init__(*args,**kwargs)
        self.events=self.book["events"]

    def receive(self):
        state=super().receive()
        mid=self.pos[0]
        if mid in self.routes.fields:
            field=self.routes.fields[mid]
            obstacles={tuple(at):kind for at,kind in state["pl_obstacles"]}
            if field.blockers!=obstacles:
                self.routes.cleared.update((mid,*at) for at in field.blockers if at not in obstacles)
                field.blockers=obstacles
                self.routes.edges.cache_clear()
                Routes.edges.cache_clear()
        return state

    def go(self,goals,until_flag=None):
        if self.pos[0].startswith(rift.PREFIX) and goals and all(pos[0].startswith(rift.PREFIX) for pos in goals):
            return rift.travel(self,goals,until_flag)
        return super().go(goals,until_flag)

    def field_moves(self):
        flags=set(self.state["flags"])
        self.routes.flags=flags
        machines={15:(1,2),19:(2,4),57:(3,5),70:(4,6),432:(5,3),249:(6,1),127:(7,8),431:(8,7)}
        moves=frozenset(move for mon in self.state["party"] for move in mon[5] if move in machines
            and {"s_hm_%s"%machines[move][0],"s_badge_%s"%machines[move][1]}<=flags)
        if self.routes.field_moves!=moves: Routes.edges.cache_clear()
        return moves

    def enter(self,mid):
        current=self.pos[0]
        if mid!=current and current=="sinnoh_canalave_city_gym":
            door=self.routes.fields[current].data["warps"][0]
            gyms.lift_plan(self,current,{tuple(door["at"])},target_floor=0)
            self.do("walk",legs=[["d",[door["to"]["map"],*door["to"]["at"]]]])
        super().enter(mid)

    def local(self,mid,x,y):
        ox,oy=self.routes.fields[mid].data["platinum_origin"]
        return x-ox,y-oy

    def nurse(self,mid):
        row=next(r for r in self.routes.fields[mid].data["npcs"] if r.get("platinum_gfx")=="OBJ_EVENT_GFX_POKECENTER_NURSE")
        self.use_at(mid,row["at"])
        assert all(m[3]==m[4] for m in self.state["party"]),("heal",mid,self.pos,self.state["dialog"])

    def train(self,route,level,center):
        field=self.routes.fields[route]
        cells={(x,y) for x in range(field.w) for y in range(field.h) if field.get("grass",x,y) and not field.get("collision",x,y)}
        cells={at for at in cells if any((at[0]+dx,at[1]+dy) in cells for dx,dy,*_ in VECTORS.values())}
        patch=Habitat(route,route,cells,{},level)
        loops=0
        while self.state["party"][0][2]<level:
            lead=self.state["party"][0]
            if lead[3]<=max(8,lead[4]*.6) or sum(lead[6])<7: self.nurse(center)
            self.go({(route,*xy) for xy in cells})
            purpose="collect" if len(self.state["party"])<4 and self.state["bag"].get("精灵球",0)>0 and loops%3==0 else "train"
            try: pace(self,patch,purpose,16)
            except RuntimeError:
                if self.pos[0]==route: cells.discard(self.pos[1:])
                if not cells: raise
            loops+=1
            if loops>1000: raise RuntimeError(("training",route,level,self.state["party"]))
        mode(self,"travel")
        self.nurse(center)

    def teach(self,n,*preferred):
        keys=[15,19,57,70,432,249,127,431]
        labels=["居合斩","飞翔","冲浪","怪力","清除浓雾","碎岩","攀瀑","攀岩"]
        move=keys[n-1]
        if any(move in mon[5] for mon in self.state["party"]): return
        self.do("hm")
        assert self.select(labels[n-1]),("missing machine",n,self.state["buttons"])
        if "教给队员" in self.state["buttons"]: self.select("教给队员")
        choices=[b for b in self.state["buttons"] if "Lv." in b]
        choice=next((b for name in preferred for b in choices if name in b),choices[0] if choices else None)
        assert choice,("no eligible mon",n,self.state["buttons"],self.state["party"])
        self.select(choice)
        choices=self.state["buttons"]
        if choices:
            keep={"居合斩","碎岩","怪力","冲浪","攀瀑","攀岩","飞翔"}
            replace=next((b for b in choices if not any(word in b for word in keep) and "不学" not in b),None)
            assert replace,(n,choices)
            self.select(replace)
        assert any(move in mon[5] for mon in self.state["party"]),(n,self.state["dialog"],self.state["buttons"])

    def acquisition(self,mid,script):
        row=next(n for n in self.routes.fields[mid].data["npcs"] if n.get("source_script")==script)
        self.use_at(mid,row["at"])

    def prepare(self,key):
        if key=="s_wind_guard":
            if "s_hm_6" not in self.state["flags"]: self.acquisition("sinnoh_gate","OreburghGate1F_Hiker")
            self.teach(6,"大尾狸","大牙狸","波皇子")
        if key=="s_jupiter" and "s_hm_1" in self.state["flags"]: self.teach(1,"大尾狸","大牙狸","波皇子")
        if key=="s_canalave_rival":
            self.nurse("sinnoh_celestic_town_pokecenter_1f")
            self.teach(3,"波皇子","帝王拿波","大尾狸")
        if key=="s_library_entry" and "s_hm_4" not in self.state["flags"]:
            self.acquisition("sinnoh_canalave","CanalaveCity_SailorEldritch")
            assert self.select("钢铁岛"),self.state["buttons"]
            self.acquisition("sinnoh_iron_island","IronIsland_Riley")
            self.teach(4,"大尾狸","大牙狸","勒克猫","帝王拿波")
            self.acquisition("sinnoh_iron_island","IronIsland_Sailor")
            assert self.select("水脉市"),self.state["buttons"]
        if key=="s_acuity_ledge":
            if "s_hm_8" not in self.state["flags"]: self.acquisition("sinnoh_217","VisibleItems_Route217_HM08")
            self.teach(8,"大尾狸","帝王拿波","勒克猫")
        if key=="s_league_rival": self.teach(7,"帝王拿波","大尾狸")
        if key=="s_aaron":
            center="sinnoh_pokemon_league_north_pokecenter_1f"
            self.nurse(center)
            for item in ("活力碎片","全满药"):
                if self.state["bag"].get(item,0)>=10: continue
                self.acquisition(center,"PokemonLeagueNorthPokecenter1F_VendorCommon")
                assert self.select(item),self.state["buttons"]
                assert self.select("10 件"),self.state["buttons"]
        if key in ("s_bertha","s_flint","s_lucian","s_cynthia"):
            for slot in range(len(self.state["party"])):
                if self.state["party"][slot][3]==0 and self.state["bag"].get("活力碎片",0)>0:
                    self.do("use",item="活力碎片",slot=slot)
                mon=self.state["party"][slot]
                if mon[3]<mon[4]*.7 and self.state["bag"].get("全满药",0)>0:
                    self.do("use",item="全满药",slot=slot)
        workouts={
            "s_rival_203":("sinnoh_202",14,"sinnoh_sandgem_town_pokecenter_1f"),
            "s_badge_1":("sinnoh_203",17,"sinnoh_oreburgh_city_pokecenter_1f"),
            "s_badge_2":("sinnoh_205",26,"sinnoh_eterna_city_pokecenter_1f"),
            "s_badge_3":("sinnoh_208",33,"sinnoh_hearthome_city_pokecenter_1f"),
            "s_badge_4":("sinnoh_215",37,"sinnoh_veilstone_city_pokecenter_1f"),
            "s_badge_5":("sinnoh_213",42,"sinnoh_pastoria_city_pokecenter_1f"),
            "s_badge_6":("sinnoh_218",47,"sinnoh_canalave_city_pokecenter_1f"),
            "s_badge_7":("sinnoh_217",53,"sinnoh_snowpoint_city_pokecenter_1f"),
            "s_spear_grunts":("sinnoh_217",56,"sinnoh_snowpoint_city_pokecenter_1f"),
            "s_badge_8":("sinnoh_222",60,"sinnoh_sunyshore_city_pokecenter_1f"),
            "s_league_rival":("sinnoh_222",66,"sinnoh_sunyshore_city_pokecenter_1f"),
        }
        if key in workouts: self.train(*workouts[key])

    def scene(self,event):
        mid=self.registry[event["map"]]
        key=event["id"]
        trig=event["trigger"]
        gyms.prepare(self,event)
        if trig["kind"]=="enter" and self.pos[0]!=mid:
            field=self.routes.fields[mid]
            arrivals={(mid,x,y) for y in range(field.h) for x in range(field.w) if not field.get("collision",x,y)}
            self.go(arrivals,until_flag=key)
        else:
            self.enter(mid)
        if key in self.state["flags"]: return
        if key in rocks.PUSHES: return rocks.push(self,event)
        if trig["kind"]=="talk":
            npc=next((r for r in self.state["actors"] if r[8]==trig["actor"]),None)
            if not npc: raise AssertionError(("missing speaker",key,mid,trig))
            self.use_at(mid,npc[0])
        elif trig["kind"] in ("field","step"):
            cells={(mid,*self.local(mid,x,y)) for left,top,w,h in trig["areas"]
                   for x in range(left,left+w) for y in range(top,top+h)}
            if trig["kind"]=="step":
                self.go(cells,until_flag=key)
            else:
                self.use_at(mid,sorted(cells)[0][1:])
        if self.state["buttons"]:
            if key=="s_first_battle": assert self.select("波加曼")
            elif key.startswith("s_coupon_"): assert self.select("是")
        if key not in self.state["flags"]: raise RuntimeError((key,self.pos,self.state["dialog"],self.state["buttons"],self.state["party"]))

    def run(self,folder,args):
        self.do("save")
        for event in self.events:
            key=event["id"]
            if key in self.state["flags"]: continue
            print("NEXT",key,self.pos,flush=True)
            self.prepare(key)
            self.scene(event)
            self.milestone(key)
            if args.result_save: args.result_save.write_bytes((folder/"save.json").read_bytes())
            checkpoint_dir=os.environ.get("POKESAGA_CHECKPOINT_DIR")
            if checkpoint_dir:
                path=Path(checkpoint_dir)
                path.mkdir(exist_ok=True,parents=True)
                (path/(key+".json")).write_bytes((folder/"save.json").read_bytes())
            if key==args.stop_at or args.stop_at in self.state["flags"]: break


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--godot",default="godot")
    p.add_argument("--pack",type=Path)
    p.add_argument("--resume",type=Path)
    p.add_argument("--transfer",choices=["carried","boxed"])
    p.add_argument("--stop-at",default="s_champion")
    p.add_argument("--result-save",type=Path)
    args=p.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-platinum-") as tmp:
        folder=Path(tmp)
        if args.resume: (folder/"save.json").write_bytes(args.resume.read_bytes())
        args1=[args.godot,"--headless","--fixed-fps","60"]
        args1+=["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        startup=["--","new-sinnoh"] if not args.resume else []
        if args.transfer: startup=["--","sinnoh-"+args.transfer] if args.resume else ["--","new-sinnoh","sinnoh-"+args.transfer]
        player=PlatinumPlayer(PlatinumRoutes(read(ROOT/"content/sinnoh_campaign.json")),args1,
                              dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=tmp),tmp,startup)
        try:
            player.run(folder,args)
            assert args.stop_at in player.state["flags"]
            if args.stop_at=="s_champion":
                assert all("s_badge_"+str(i) in player.state["flags"] for i in range(1,9))
                assert player.state["hall"].get("sinnoh")
        finally:
            player.finish()
        print("PLATINUM JOURNEY PASS",args.stop_at)


if __name__=="__main__":
    main()
