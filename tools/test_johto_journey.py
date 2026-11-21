#!/usr/bin/env python3
"""Start in New Bark, play through both leagues' regions and defeat Red using game inputs."""
import argparse
import json
import os
import tempfile
from pathlib import Path

from campaign_collection import Habitat, pace
from campaign_route import ROOT, VECTORS
from test_kanto_journey import Player
from hgss_route import JohtoRoutes, NativeField


class JohtoPlayer(Player):
    def receive(self):
        state=super().receive()
        self.routes.powered="j2_power" in self.state["flags"]
        return state

    def native_target(self, mid, old, trigger=False):
        f = self.routes.fields[mid]
        if not isinstance(f, NativeField): return mid, tuple(old)
        key = f"{old[0]},{old[1]}"
        anchor = (f.bindings.get("triggers",{}).get(key) if trigger else None) or f.bindings.get("sites",{}).get(key)
        if anchor:
            return self.routes.index[anchor["header"]],tuple(anchor["at"])
        return mid, f.position(old)

    def visit(self, mid, xy, face=None):
        room, point = self.native_target(mid,xy,trigger=True)
        if face and isinstance(self.routes.fields[mid], NativeField):
            dx,dy,*_ = VECTORS[face]
            ahead=(xy[0]+dx,xy[1]+dy)
            if f"{ahead[0]},{ahead[1]}" in self.routes.fields[mid].bindings.get("sites",{}):
                room, target=self.native_target(mid,ahead)
                point=(target[0]-dx,target[1]-dy)
        super().visit(room,point,face)

    def interact(self, mid, xy, role=None):
        room, point = self.native_target(mid,xy)
        f=self.routes.fields[mid]
        if isinstance(f,NativeField) and role in f.bindings.get("roles",{}):
            entry = f.bindings["roles"][role]
            room,point = self.routes.index[entry["header"]],tuple(entry["at"])
        if isinstance(self.routes.fields[mid], NativeField):
            self.enter(room)
            visible=[r for r in self.state["actors"] if len(r)>5 and r[4]==list(xy) and r[5]==mid]
            if role: visible=[r for r in visible if r[1]==role]
            if len(visible)==1: point=tuple(visible[0][0])
            field = self.routes.fields[room]
            goals = {}
            for direction, (dx,dy,*_) in VECTORS.items():
                near = point[0]-dx,point[1]-dy
                if not (0<=near[0]<field.w and 0<=near[1]<field.h): continue
                if field.get("counter",*near):
                    near = near[0]-dx,near[1]-dy
                if not (0<=near[0]<field.w and 0<=near[1]<field.h): continue
                if not field.get("collision",*near) and near not in self.routes.occupied.get(room,{}):
                    goals[(room,*near)]=direction
            if mid == "johto_elms_lab" and point==(8,4):
                goals = {(room,8,5):"u"}
            self.go(goals)
            self.do("face",dir=goals[self.pos])
            print("TALK",room,point,self.state["dialog"][-3:],self.state["buttons"],flush=True)
        else:
            super().interact(room,point)

    def milestone(self, name):
        super().milestone(name)
        if os.environ.get("POKESAGA_JOURNEY_CHECKPOINT"):
            Path(os.environ["POKESAGA_JOURNEY_CHECKPOINT"]).write_bytes((self.save_dir/"save.json").read_bytes())

    def checkpoint(self, label):
        self.do("save")
        if label == "red" and getattr(self, "red_entry_save", None):
            self.red_entry_save.write_bytes((self.save_dir / "save.json").read_bytes())

    def service(self, key, name=None):
        self.do("mode", value="travel")
        approaches = {}
        for mid, field in self.routes.fields.items():
            if name and mid != name: continue
            for npc in field.data.get("npcs", []):
                if not npc.get(key): continue
                x, y = field.position(npc["at"]) if isinstance(field,NativeField) else npc["at"]
                for direction, (dx,dy,*_) in VECTORS.items():
                    nx, ny = x-dx,y-dy
                    if isinstance(field,NativeField) and 0<=nx<field.w and 0<=ny<field.h and field.get("counter",nx,ny):
                        nx,ny = nx-dx,ny-dy
                    if 0 <= nx < field.w and 0 <= ny < field.h and not field.get("collision",nx,ny) and (nx,ny) not in field.doors:
                        approaches[mid,nx,ny] = direction
        self.go(set(approaches))
        self.do("face",dir=approaches[self.pos])

    def heal(self, city=None):
        if city and not city.startswith("johto_"): city = "johto_" + city
        if city and not city.endswith("_1f"): city += "_pokecenter_1f"
        self.service("heal",city)
        assert all(m[3] == m[4] for m in self.state["party"]), ("Center failed to heal", self.pos)

    def buy(self, name, amount):
        if amount <= 0: return
        self.service("shop")
        before = self.state["bag"].get(name,0)
        self.do("shop", item=name, amount=amount)
        self.do("back")
        acquired = self.state["bag"].get(name,0) - before
        if acquired != amount: raise RuntimeError(f"Bought {acquired}/{amount} {name} at {self.pos}")

    def key_item(self, name):
        self.do("key_item",item=name)

    def actors(self, mid, name):
        if self.pos[0] != mid:
            self.enter(mid)
        return [tuple(xy) for xy,role,label,*_ in self.state["actors"] if name in (role,label)]

    def enter(self, mid):
        if self.pos[0] != mid:
            f = self.routes.fields[mid]
            self.go({(mid,x,y) for y in range(f.h) for x in range(f.w) if not f.get("collision",x,y)})

    def teach(self, name, move_id):
        if any(move_id in m[5] for m in self.state["party"]): return
        self.do("hm")
        self.do("click",label=name)
        candidates = [m for m in self.state["party"] if m[0] in self.state["buttons"]]
        if not candidates: raise RuntimeError((name,"no compatible party member",self.state["buttons"]))
        mon = min(candidates,key=lambda m: (len(m[5])>=4,sum(v in (15,19,57,70,148,250,127,431) for v in m[5])))
        self.do("click",label=mon[0])
        if not any(move_id in m[5] for m in self.state["party"]):
            moves = {m["id"]:m for m in json.loads((ROOT/"content/moves.json").read_text())}
            eligible = [moves[n] for n in mon[5] if n not in (15,19,57,70,148,250,127,431)]
            old = min(eligible,key=lambda m:m.get("power",0))
            self.do("click",label=old["name"])
        assert any(move_id in m[5] for m in self.state["party"]), (name,self.state["dialog"])

    def patch(self, mid):
        f = self.routes.fields[mid]
        meta = json.loads((ROOT/"content/emerald_maps"/(mid+".json")).read_text()) if mid.startswith("johto_") else {}
        cells = {(x,y) for y in range(f.h) for x in range(f.w) if (f.get("grass",x,y) or meta.get("wild_any")) and
                 not f.get("collision",x,y) and not f.get("water",x,y) and not f.get("ledge",x,y) and
                 (x,y) not in f.doors and (x,y) not in f.blockers}
        actors = {tuple(n["at"]) for n in f.data.get("npcs",[])}
        cells -= actors
        cells = {c for c in cells if any((c[0]+d[0],c[1]+d[1]) in cells for d in VECTORS.values())}
        if not cells or not f.data.get("encounters"): raise RuntimeError("No encounter patch in "+mid)
        return Habitat(mid,mid,cells,{},0)

    def train(self, mid, level):
        if any(m[2]>=level for m in self.state["party"]): return
        if not mid.startswith(("johto_","hgss_")): mid="johto_"+mid
        patch = self.patch(mid)
        self.do("mode",value="travel")
        if self.state["money"] >= 200 and self.state["bag"].get("精灵球",0)<3 and len(self.state["party"])<6:
            self.buy("精灵球", min(8,int(self.state["money"])//200))
        center = {"johto_route_31":"violet","johto_route_33":"azalea","johto_route_34":"goldenrod",
                  "johto_victory_road":"indigo_plateau","hgss_victory_road_3f":"indigo_plateau"}.get(mid)
        damaging = {m["id"] for m in json.loads((ROOT/"content/moves.json").read_text()) if m.get("power",0)>0}
        while max((m[2] for m in self.state["party"]),default=0) < level:
            lead=self.state["party"][0]
            if lead[3] < lead[4]*0.70 or sum(pp for move,pp in zip(lead[5],lead[6]) if move in damaging) < 5:
                self.heal(center)
            self.do("mode",value="travel")
            self.go({(mid,*xy) for xy in patch.grass})
            mode = "collect" if len(self.state["party"])<6 and self.state["bag"].get("精灵球",0) and self.state["steps"]%3==0 else "train"
            try:
                pace(self,patch,mode,8)
            except RuntimeError:
                if self.pos[0] == mid:
                    raise
                # A loss returns the party to the last Center, from which they walk back.
        self.heal(center)



def play(p):
    from johto_story_route import main_story
    from johto_postgame_route import postgame
    bedroom = "johto_players_house_2f"
    if p.pos != (bedroom,*p.routes.fields[bedroom].data["spawn"]) or p.state["party"] or p.state["badges"]:
        raise RuntimeError("Expected a fresh Johto bedroom")
    p.interact("johto_players_house_1f",(3,2))
    p.milestone("j_gear")
    main_story(p)
    league(p)
    postgame(p)
    p.milestone("j2_red_defeated")


def league(p):
    from test_kanto_journey import league_heal

    rules = json.loads((ROOT / "content/regions/johto/league.json").read_text())
    assert set(rules["badges"]) <= set(p.state["badges"])
    if "johto_champion" in p.state["flags"]: return
    if not any(row["flag"] in p.state["flags"] for row in rules["rounds"]):
        if "j2_rival_victory" not in p.state["flags"]:
            p.enter("johto_victory_road")
            p.visit("johto_victory_road",(6,4))
            p.milestone("j2_rival_victory")
        p.train("hgss_victory_road_3f" if "hgss_victory_road_3f" in p.routes.fields else "johto_victory_road",59)
        p.heal("indigo_plateau")
    for opponent in rules["rounds"]:
        if opponent["flag"] in p.state["flags"]: continue
        mid = opponent["room"]
        actor = next(n for n in p.routes.fields[mid].data["npcs"] if n.get("league_flag") == opponent["flag"])
        p.interact(mid,actor["at"])
        p.milestone(opponent["flag"])
        if mid != rules["rounds"][-1]["room"]: league_heal(p)
    p.enter(rules["hall"])
    if "johto_champion" not in p.state["flags"]:
        p.visit(rules["hall"],(2,5))
    p.milestone("johto_champion")
    assert p.state["hall"].get("johto"), "First champion's team missing from Hall of Fame"


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",default="godot")
    parser.add_argument("--pack",type=Path)
    parser.add_argument("--resume",type=Path,help="Continue a previous input-driven playthrough from a copied save")
    parser.add_argument("--result-save",type=Path)
    parser.add_argument("--red-entry-save",type=Path)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-johto-") as folder:
        env = dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=folder)
        cmd = [args.godot,"--headless","--fixed-fps","60"]
        cmd += ["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        routes=JohtoRoutes()
        if args.resume:
            (Path(folder)/"save.json").write_bytes(args.resume.read_bytes())
        player = JohtoPlayer(routes,cmd,env,folder,startup=() if args.resume else ("--","new-johto"))
        try:
            player.save_dir = Path(folder)
            player.red_entry_save = args.red_entry_save
            if args.resume:
                from johto_story_route import main_story
                from johto_postgame_route import postgame
                if "johto_champion" not in player.state["flags"]:
                    main_story(player)
                    league(player)
                postgame(player)
                player.do("save")
            else:
                play(player)
        finally:
            player.finish()
        restored = JohtoPlayer(routes,cmd,env,folder)
        try:
            assert set(restored.state["flags"]) == set(player.state["flags"])
            for key in ("badges","party","bag","dex","hall","pos"):
                assert restored.state[key] == player.state[key], key
            if args.result_save:
                args.result_save.write_bytes(Path(folder,"save.json").read_bytes())
            print("JOHTO NEW GAME TO RED AND RELOAD PASS",restored.pos,restored.state["badges"],flush=True)
        finally:
            restored.finish()


if __name__ == "__main__":
    main()
