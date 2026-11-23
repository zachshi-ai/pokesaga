"""Replay Sword/Shield from the Turffield badge through the Champion Cup and the postgame."""
import argparse
from functools import lru_cache
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from campaign_collection import Habitat, pace
from campaign_route import ROOT, VECTORS, read
from test_galar_journey import GalarPlayer, GalarRoutes, as_bag, boxes, party
from test_kanto_journey import league_heal


GYM_PREPARATION = {
    2: (24, "galar_5", "galar_hulbury"),
    3: (28, "galar_mine2", "galar_motostoke"),
    4: (36, "galar_6", "galar_stow"),
    5: (38, "galar_tangle", "galar_ballonlea"),
    6: (42, "galar_8", "galar_circhester"),
    7: (46, "galar_9", "galar_spikemuth"),
    8: (49, "galar_9", "galar_circhester"),
}


class ContinuationRoutes(GalarRoutes):
    def __init__(self):
        super().__init__()
        self.later = read(ROOT / "content/galar_later_campaign.json")
        self.book["gates"].update(self.later["gates"])
        self.field_book = read(ROOT / "content/galar_later_field.json")
        self.encounters = {**self.book["encounters"], **self.field_book["encounters"]}
        self.gyms = read(ROOT / "content/galar_gyms.json")["gyms"]
        self.bike = False
        self.shore = self.fields.get("galar_circhester_bay")
        self.bank = self.shore.grid["collision"][:] if self.shore else []
        for mid in ("galar_mine", "galar_mine2", "galar_tunnel"):
            cave = self.fields[mid]
            cave.grid["grass"] = [int(not solid and not cave.grid["water"][i])
                                   for i, solid in enumerate(cave.grid["collision"])]

    def water_bike(self, riding):
        if self.shore and self.bike != riding:
            self.bike = riding
            water = self.shore.grid["water"]
            self.shore.grid["collision"] = [0 if riding and water[i] else cell for i, cell in enumerate(self.bank)]
            super().edges.cache_clear()

    @lru_cache(maxsize=300000)
    def edges(self, loc):
        result = []
        for direction, dest in super().edges(loc):
            if isinstance(dest, dict):
                mid = dest.get("map", "")
                if mid.startswith("galar_gym_") and mid.endswith("_mission"):
                    n = int(mid.split("_")[2])
                    pitch = f"galar_gym_{n}_pitch"
                    if f"g_gym_{n}_mission" in self.flags:
                        if loc[0] == pitch:
                            dest = self.fields[mid].data["warps"][0]["to"]
                        elif loc[0] != mid:
                            dest = {"region": "galar", "map": pitch, "at": [14, 24]}
                elif mid == "galar_turffield_mission" and "g_gym_mission" in self.flags:
                    if loc[0] == "galar_turffield_pitch":
                        dest = {"region": "galar", "map": "galar_turffield_pitch_room", "at": [6, 1]}
                    elif loc[0] == "galar_turffield_pitch_room":
                        dest = {"region": "galar", "map": "galar_turffield_pitch", "at": [14, 24]}
            result.append((direction, dest))
        return result


    def path(self, start, goals):
        try:
            return super().path(start, goals)
        except ValueError:
            destinations = sorted({p[0] for p in goals})
            raise ValueError(f"No route from {start} to {destinations} ({len(goals)} approach tiles)") from None


class Player(GalarPlayer):
    def field_moves(self):
        super().field_moves()
        riding = self.state.get("bike", False) and "g_water_bike" in self.state["flags"]
        self.routes.water_bike(riding)
        return frozenset({57}) if riding else frozenset()

    def probe_hub(self):
        before = self.saved()
        self.do("key_item", item="地区转移器")
        self.click_exact("伽勒尔")
        self.click_exact("宫门市")
        self.click_exact("出发前往伽勒尔")
        assert self.pos[0] != "galar_wyndon", self.pos
        after = self.saved()
        assert before["regional_badges"] == after["regional_badges"]
        assert before["chapters"] == after["chapters"] and not after["flags"].get("g_champion")
        print("EARLY ATLAS BLOCKED", self.pos, flush=True)

    def probe_road(self, source, target):
        self.enter(source)
        field = self.routes.fields[source]
        warp = next(w for w in field.data["warps"] if w["to"]["map"] == target)
        x, y = warp["at"]
        approaches = {}
        around = [(x, y)] + [(x - dx, y - dy) for dx, dy, *_ in VECTORS.values()]
        for sx, sy in around:
            if not (0 <= sx < field.w and 0 <= sy < field.h) or field.get("collision", sx, sy):
                continue
            stand = (source, sx, sy)
            for direction, dest in self.routes.edges(stand):
                if isinstance(dest, dict) and dest.get("map") == target:
                    approaches[stand] = direction
        assert approaches, (source, target, warp)
        self.go(approaches)
        self.do("walk", legs=[[approaches[self.pos], [target, *warp["to"]["at"]]]])
        assert self.pos[0] == source and self.state["dialog"], (self.pos, self.state["dialog"])
        print("EARLY ROAD BLOCKED", source, target, self.state["dialog"], flush=True)

    def lead(self, species):
        slot = next((i for i, mon in enumerate(self.state["party"]) if mon[1] in species and mon[3] > 0), 0)
        if slot:
            self.do("lead", slot=slot)

    def league_lead(self, level):
        members = self.state["party"]
        if members[0][2] >= level:
            return
        evolved = {815, 818, 812, 823, 826, 834, 888, 889, 890}
        choices = [i for i, mon in enumerate(members) if mon[3] > 0 and (i == 0 or mon[1] in evolved)]
        strongest = max(choices, key=lambda i: members[i][2])
        if strongest:
            self.do("lead", slot=strongest)

    def recover_for_battle(self):
        def needs_healing():
            return any(mon[3] < mon[4] / 2 for mon in self.state["party"])
        if not needs_healing():
            return
        league_heal(self)
        if not needs_healing():
            return
        goals = set()
        for mid, field in self.routes.fields.items():
            for nurse in field.data.get("npcs", []):
                if not nurse.get("heal"):
                    continue
                x, y = nurse["at"]
                goals.update((mid, x + dx, y + dy) for dx, dy, *_ in VECTORS.values()
                             if 0 <= x + dx < field.w and 0 <= y + dy < field.h
                             and not field.get("collision", x + dx, y + dy))
        self.go(goals)
        self.nurse(self.pos[0])

    def train_for(self, level, preferred, clinic):
        if self.state["party"][0][2] >= level:
            return
        fields = self.routes.fields
        choices = [preferred, "galar_10", "galar_9", "galar_8", "galar_7", "galar_tangle",
                   "galar_6", "galar_wild_north", "galar_mine2", "galar_5", "galar_4"]
        for candidate in choices:
            if candidate not in self.routes.encounters or candidate not in fields:
                continue
            f = fields[candidate]
            legal = self.routes.projection({"map": candidate, "region": "galar", "at": f.data["spawn"]})
            grass = f.grid.get("grass", [])
            if legal and any(grass):
                self.train_at(candidate, level, clinic)
                return
        raise AssertionError(("no reachable training grass", preferred, level, self.pos))

    def road_opponents(self):
        for mid, trainers in self.routes.field_book["trainers"].items():
            clinic = {"galar_5":"galar_hulbury", "galar_mine2":"galar_motostoke", "galar_6":"galar_stow",
                      "galar_tangle":"galar_ballonlea", "galar_7":"galar_hammerlocke", "galar_8":"galar_circhester",
                      "galar_9":"galar_circhester", "galar_10":"galar_wyndon"}[mid]
            self.nurse(clinic)
            self.enter(mid)
            for npc in trainers:
                name = npc["name"]
                if name not in self.state["defeated"].get("galar/" + mid, []):
                    self.use_at(mid, npc["at"])
                    assert any(f[0] == name and f[3] == "a" for f in self.state["fights"]), (mid, name, self.state["dialog"])
                self.use_at(mid, npc["at"])
                assert not self.state["fights"] and npc["post"][0] in self.state["dialog"], (name, self.state["dialog"])
            print("ROUTE TRAINERS", mid, len(trainers), flush=True)

    def catch_chewtle(self):
        if any(mon[1] in (833, 834) for mon in self.state["party"]):
            return
        mid = "galar_2"
        field = self.routes.fields[mid]
        cells = {(x, y) for x in range(field.w) for y in range(field.h) if field.get("grass", x, y)}
        cells = {p for p in cells if any((p[0]+dx, p[1]+dy) in cells for dx, dy, *_ in VECTORS.values())}
        patch = Habitat("二号道路", mid, cells, {}, 7)
        self.go({(mid, *at) for at in cells})
        for _ in range(400):
            ball = next((b for b in ("精灵球", "超级球", "高级球") if self.state["bag"].get(b)), None)
            assert ball, "No Poké Balls left for the Water-type teammate"
            self.do("throw_with", item=ball, species=833)
            pace(self, patch, "throw", 16)
            if any(mon[1] == 833 for mon in self.state["party"]):
                self.do("mode", value="travel")
                return
        raise AssertionError("Failed to catch Chewtle on Route 2")

    def prepare_gym(self, number, version):
        level, road, clinic = GYM_PREPARATION[number]
        self.nurse(clinic)
        if number == 2:
            self.lead({830, 44, 25})
        elif number == 3:
            if max(m[2] for m in self.state["party"]) < 40:
                self.catch_chewtle()
                self.train_for(31, road, clinic)
                self.lead({833, 834})
                self.train_for(30, road, clinic)
                swimmer = self.state["party"][0]
                if 250 not in swimmer[5]:
                    machine = next(item for item in self.state["bag"] if item.startswith("伽勒尔招式学习器36"))
                    self.teach_item(machine, 250, swimmer)
            else:
                self.lead({834, 51})
        elif number == 4:
            self.lead({822, 823, 18} if version == "sword" else {274, 275, 53})
        elif number in (5, 6):
            self.lead({814, 815, 58})
        elif number == 7:
            self.lead({815, 814, 57})
        self.train_for(level, road, clinic)

    def gym(self, number, version):
        from galar_league_gym_walk import challenge
        self.prepare_gym(number, version)
        transformations = self.state["galar_dynamax_inputs"]
        for attempt in range(4):
            try:
                if f"g_gym_{number}_mission" in self.state["flags"]:
                    pitch = f"galar_gym_{number}_pitch"
                    self.enter(pitch)
                    trainer = next(row for row in self.state["actors"] if row[1] == "g_fac_leader")
                    self.use_at(pitch, trainer[0])
                    assert f"g_badge_{number}" in self.state["flags"], self.state["fights"]
                else:
                    challenge(self, number)
                changes = self.state["galar_dynamax_inputs"] - transformations
                assert changes == 0 if number == 7 else changes > 0, (number, changes)
                if number == 5:
                    print("BALLONLEA ANSWERS", self.state["galar_quiz_answers"], flush=True)
                print("STADIUM TRANSFORMATIONS", number, changes, flush=True)
                return
            except AssertionError:
                if not any(f[3] == "b" for f in self.state["fights"]) or attempt == 3:
                    raise
                _, road, clinic = GYM_PREPARATION[number]
                self.nurse(clinic)
                target = min(100, int(self.state["party"][0][2]) + 3)
                print("GYM REMATCH", number, "training to", target, flush=True)
                self.train_for(target, road, clinic)

    def ride_bay(self):
        mid = "galar_circhester_bay"
        self.enter(mid)
        self.go({(mid, 12, 7)})
        if self.state["bike"]:
            self.do("key_item", item="洛托姆自行车")
            self.close_menus()
        assert not self.state["bike"]
        self.do("walk", legs=[["d", [mid, 12, 8]]])
        assert self.pos == (mid, 12, 7), ("walked onto the water", self.pos)
        self.do("key_item", item="洛托姆自行车")
        self.close_menus()
        assert self.state["bike"]
        self.do("walk", legs=[["d", [mid, 12, 8]]])
        assert self.pos == (mid, 12, 8) and self.routes.fields[mid].get("water", 12, 8)
        self.do("walk", legs=[["d", [mid, 12, y]] for y in range(9, 15)])
        assert self.pos == (mid, 12, 14) and not self.routes.fields[mid].get("water", 12, 14)
        print("BIKE CROSSED CIRCHESTER BAY", self.pos, flush=True)

    def cast(self, name, version):
        local = {"@贵族": ("索德", "西尔迪"), "@兄弟": ("西尔迪", "索德"),
                 "@己方狼": ("苍响", "藏玛然特"), "@另一只狼": ("藏玛然特", "苍响")}
        if name in local:
            return local[name][version == "shield"]
        if name in ("@溯传馆主", "@战竞馆主"):
            return self.routes.gyms["4" if name == "@溯传馆主" else "6"][version]["leader"]
        return name

    def gear(self, event, version):
        key = event["id"]
        for step in event["steps"]:
            if "galar_card" in step:
                person = self.cast(step["galar_card"], version)
                title = person + ("的稀有联盟卡" if step.get("rare") else "的联盟卡")
                self.do("key_item", item=title)
                assert any(person in line for line in self.state["dialog"]), (key, title, self.state["dialog"])
                self.close_menus()
            if "galar_key" in step:
                assert self.state["bag"].get(step["galar_key"]) == 1
            if step.get("galar_machine") == 79:
                machine = "伽勒尔招式学习器79·报仇"
                assert self.state["bag"].get(machine) == 1
                self.do("key_item", item=machine)
                candidates = [mon for mon in reversed(self.state["party"]) if mon[0] in self.state["buttons"] and 514 not in mon[5]]
                if candidates:
                    self.teach_item(machine, 514, candidates[0], menu_open=True)
                    assert self.state["bag"].get(machine) == 1
                    print("TAUGHT", machine, candidates[0][0], flush=True)
                else:
                    self.close_menus()
        if key in ("g_bridge_yell", "g_water_bike"):
            bike = "洛托姆自行车"
            if not self.state["bike"]:
                self.do("key_item", item=bike)
                self.close_menus()
            assert self.state["bike"]
            if key == "g_bridge_yell":
                self.do("key_item", item=bike)
                self.close_menus()
                assert not self.state["bike"]
        if key == "g_staff_3":
            self.do("key_item", item="单轨列车钥匙")
            assert any("单轨列车" in line for line in self.state["dialog"])
            self.close_menus()
        if key in ("g_rusted_relic", "g_royal_thieves", "g_hop_altar"):
            relic = "腐朽的剑" if version == "sword" else "腐朽的盾"
            assert self.state["bag"].get(relic, 0) == (0 if key == "g_hop_altar" else 1)
            self.do("key_item", item="索妮亚的书" if key == "g_hop_altar" else relic)
            assert self.state["dialog"]
            self.close_menus()
        if key == "g_train_wyndon":
            assert self.pos[0] == "galar_10", self.pos

    def talk(self, event, version):
        key, mid = event["id"], event["map"]
        self.enter(mid)
        visible = {row[1]: row for row in self.state["actors"]}
        assert key in visible, (key, self.pos, list(visible))
        actor = visible[key]
        assert actor[2] == self.cast(event["who"], version) and actor[0] == event["at"], (key, actor)
        for guest in event.get("guests", []):
            if guest.get("version", version) == version:
                name = self.cast(guest["name"], version)
                assert any(row[2] == name and row[0] == guest["at"] for row in visible.values()), (key, guest)
        raid_count = len(self.state["galar_raids"])
        ball_count = self.state["bag"].get("大师球", 0)
        if key == "g_wolf_caught":
            species = 888 if version == "sword" else 889
            assert self.state["bag"].get("大师球"), "Collect the Master Ball gift before confronting the wolf"
            self.do("throw_with", item="大师球", species=species)
        self.use_at(mid, actor[0])
        battles = [step["battle"] for step in event["steps"] if "battle" in step]
        if battles:
            outcomes = self.state["fights"]
            assert len(outcomes) == len(battles) and all(f[3] == "a" for f in outcomes), (key, outcomes, self.state["dialog"])
        declared_raids = [b for b in battles if "galar_raid" in b]
        if declared_raids:
            assert len(self.state["galar_raids"]) == raid_count + len(declared_raids)
            for attempt, configuration in zip(self.state["galar_raids"][raid_count:], declared_raids):
                assert len(attempt[2]) == (0 if configuration.get("galar_solo_raid") else 3), (key, attempt)
                if configuration["galar_raid"] == "eternamax":
                    assert attempt[1] == 890 and attempt[2] == [832, 888, 889], attempt
                leaders = {"g_raid_grass": 841 if version == "sword" else 842, "g_raid_water": 834, "g_raid_fire": 851}
                if key in leaders:
                    starter = int(read(self.save_slot)["flags"]["g_starter"])
                    hop_partner = {810: 818, 813: 812, 816: 815}[starter]
                    assert attempt[2] == [hop_partner, 862, leaders[key]], (key, attempt)
            print("RAID", key, self.state["galar_raids"][raid_count:], flush=True)
        if key == "g_master_ball":
            assert self.state["bag"].get("大师球", 0) == ball_count + 1
        if key == "g_eternatus_caught" and self.state["buttons"]:
            ball = next(b for b in ("精灵球", "超级球", "高级球") if b in self.state["buttons"])
            previous = self.state["bag"][ball]
            self.click_exact(ball)
            assert self.state["bag"].get(ball, 0) == previous - 1
        if key == "g_wolf_caught":
            assert any(f[3] == "caught" for f in self.state["fights"]), self.state["fights"]
            assert self.state["bag"].get("大师球", 0) == ball_count - 1
            self.do("mode", value="travel")
        if self.state["buttons"]:
            raise AssertionError((key, self.state["buttons"], self.state["dialog"]))
        assert key in self.state["flags"], (key, self.pos, self.state["fights"], self.state["dialog"])
        assert all(row[1] != key for row in self.state["actors"]), (key, "actor remained after the event")
        self.gear(event, version)
        print("STORY", key, self.pos, self.state["steps"], self.state["turns"], flush=True)

    def snapshot(self, key, folder):
        save = self.saved()
        if folder:
            folder.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.save_slot, folder / (key + ".json"))
        return save


def protected_progress(before, after):
    for name, badges in before["regional_badges"].items():
        if name != "galar":
            assert after["regional_badges"].get(name) == badges, name
    for name, record in before.get("hall_of_fame", {}).items():
        if name != "galar":
            assert after["hall_of_fame"].get(name) == record, name
    assert after["chapters"] == before["chapters"]
    for key, value in before["flags"].items():
        if key.startswith("a_"):
            assert after["flags"].get(key) == value, key


def persisted(before, after):
    for key in ("region", "map", "pos", "party", "boxes", "bag", "regional_badges", "chapters", "hall_of_fame"):
        assert before.get(key) == after.get(key), (key, before["map"], after["map"])
    for key, value in before["flags"].items():
        if key.startswith("g_"):
            assert after["flags"].get(key) == value, key


def checkpoint_first_badge(args, destination):
    if args.resume:
        shutil.copyfile(args.resume, destination)
        return
    cmd = [sys.executable, str(ROOT / "tools/test_galar_journey.py"),
           "--godot", args.godot, "--version", args.version, "--transfer", "boxed",
           "--result-save", str(destination)]
    if args.pack:
        cmd.extend(["--pack", str(args.pack.resolve())])
    subprocess.run(cmd, cwd=ROOT, check=True)


def verify_finish(p, start):
    data = p.saved()
    badges = data["regional_badges"]["galar"]
    assert len(badges) == len(set(badges)) == 8, badges
    assert data["flags"].get("g_champion") and data["flags"].get("g_hop_final")
    assert data.get("hall_of_fame", {}).get("galar"), "Galar Hall of Fame entry missing"
    species = [int(mon["species_id"]) for mon in party(data) + boxes(data)]
    legend = 888 if data["flags"]["g_version"] == "sword" else 889
    assert legend in species and 890 in species, (legend, species)
    if len(party(start)) == 12:
        assert len(party(data)) == 12
        assert not (as_bag(boxes(start)) - as_bag(boxes(data))), "An existing boxed Pokémon changed"
        for sid, flag in ((legend, "g_wolf_caught"), (890, "g_eternatus_caught")):
            if not start["flags"].get(flag):
                assert sum(m["species_id"] == sid for m in boxes(data)) == 1 + sum(m["species_id"] == sid for m in boxes(start))
    protected_progress(start, data)
    return data


def run(args):
    routes = ContinuationRoutes()
    godot = [args.godot, "--headless", "--fixed-fps", "60"]
    godot += ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(ROOT)]
    with tempfile.TemporaryDirectory(prefix="pokesaga-galar-cup-") as tmp:
        folder = Path(tmp)
        slot = folder / "save.json"
        env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=str(folder))
        checkpoint_first_badge(args, slot)

        def launch():
            p = Player(routes, godot, env, folder)
            p.save_slot = slot
            if args.checkpoints:
                args.checkpoints.mkdir(parents=True, exist_ok=True)
            p.result_save = args.checkpoints / "training.json" if args.checkpoints else None
            return p

        p = launch()
        try:
            initial = p.saved()
            version = initial["flags"]["g_version"]
            assert version == args.version and initial["flags"].get("g_badge_1")
            if args.require_full_party:
                assert len(party(initial)) == 12 and initial["chapters"]["galar"] == "carried"
            events = [e for e in routes.later["events"] if e.get("version", version) == version]
            checkpoints = {e["id"] for e in events} | {f"g_badge_{n}" for n in range(2, 9)}
            if args.stop_at not in checkpoints:
                raise ValueError(f"Unknown {version} checkpoint {args.stop_at!r}")
            if initial["flags"].get(args.stop_at):
                raise ValueError(f"{args.stop_at} already completed; replay from an earlier save")
            if not any(initial["flags"].get(e["id"]) for e in events):
                p.probe_hub()
                p.probe_road("galar_wild_lake", "galar_wild_north")
            for event in events:
                key = event["id"]
                if key not in p.state["flags"]:
                    for requirement in event.get("require", []):
                        if requirement.startswith("g_badge_") and requirement not in p.state["flags"]:
                            n = int(requirement.rsplit("_", 1)[1])
                            assert f"g_gym_{n}_ready" in p.state["flags"], (key, requirement, p.pos)
                            p.gym(n, version)
                            save = p.snapshot(requirement, args.checkpoints)
                            award = routes.gyms[str(n)][version]
                            badges = save["regional_badges"]["galar"]
                            assert save["flags"].get(requirement) and len(badges) == n and badges[-1] == award["badge"], badges
                            assert p.state["bag"].get(award["uniform"]) == 1, award
                            assert any(name.startswith(f"伽勒尔招式学习器{int(award['tm']):02d}")
                                       for name in p.state["bag"]), (n, award, p.state["bag"])
                            protected_progress(initial, save)
                            print("BADGE", n, save["regional_badges"]["galar"], flush=True)
                            if args.stop_at == requirement:
                                break
                    if args.stop_at in p.state["flags"]:
                        break
                    if key == "g_gym_7_ready":
                        p.ride_bay()
                    if key == "g_semi_marnie":
                        if args.route_trainers:
                            p.road_opponents()
                        p.nurse("galar_wyndon")
                        p.train_for(54, "galar_10", "galar_wyndon")
                    if key in ("g_final_bede", "g_champion"):
                        p.nurse("galar_wyndon")
                        if key == "g_final_bede":
                            p.train_for(58, "galar_10", "galar_wyndon")
                        else:
                            p.league_lead(66)
                            p.train_for(66, "galar_lake_out", "galar_hammerlocke")
                    if key == "g_hop_final":
                        p.nurse("galar_hammerlocke")
                        p.league_lead(71)
                        p.train_for(71, "galar_lake_out", "galar_hammerlocke")
                    if any("battle" in step or "galar_wolf_catch" in step for step in event["steps"]):
                        p.recover_for_battle()
                    p.talk(event, version)
                    blocked_doors = {
                        "g_vault": ("galar_hammerlocke_castle_room", "galar_energy_plant"),
                        "g_wyndon_arrival": ("galar_wyndon", "galar_rose"),
                        "g_plant_open": ("galar_energy_plant", "galar_tower_summit"),
                    }
                    if key in blocked_doors:
                        p.probe_road(*blocked_doors[key])
                    if key in ("g_bridge_hop", "g_master_ball"):
                        side_key = "g_toxel" if key == "g_bridge_hop" else "g_rose_card"
                        side = next(e for e in routes.later["side_events"] if e["id"] == side_key)
                        if side_key not in p.state["flags"]:
                            before = p.saved()
                            p.talk(side, version)
                            after = p.snapshot(side_key, args.checkpoints)
                            if side_key == "g_toxel":
                                collection = boxes if len(party(before)) == 12 else party
                                count = lambda save: sum(int(m["species_id"]) == 848 for m in collection(save))
                                assert count(after) == count(before) + 1
                    state = p.snapshot(key, args.checkpoints)
                    if key == "g_wolf_caught":
                        relic = "RUSTED_SWORD" if version == "sword" else "RUSTED_SHIELD"
                        species = 888 if version == "sword" else 889
                        assert any(mon["species_id"] == species and mon.get("galar_hero") and mon.get("capture_ball") == "大师球"
                                   and mon.get("held") == relic for mon in party(state) + boxes(state))
                    if key == "g_champion":
                        inductees = state["hall_of_fame"]["galar"]
                        assert [int(mon["species_id"]) for mon in inductees] == [int(mon["species_id"]) for mon in party(state)]
                if key == args.stop_at:
                    break
            assert args.stop_at in p.state["flags"], (args.stop_at, p.pos, p.state["flags"])
            result = verify_finish(p, initial) if args.stop_at == "g_hop_final" else p.saved()
            protected_progress(initial, result)
            if args.result_save:
                args.result_save.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(slot, args.result_save)
            print("PLAYED", version, p.state["steps"], "field inputs", p.state["turns"], "battle turns",
                  p.state["galar_dynamax_inputs"], "stadium transformations", flush=True)
            p.finish()
            p = launch()
            persisted(result, p.saved())
            if args.stop_at == "g_hop_final":
                home = "阿罗拉" if initial["chapters"]["galar"] == "carried" and "alola" in initial["chapters"] else "关都"
                p.transfer(home)
                home_save = p.saved()
                assert home_save["region"] == ("alola" if home == "阿罗拉" else "kanto")
                p.finish()
                p = launch()
                persisted(home_save, p.saved())
                p.transfer("伽勒尔")
                returned = p.saved()
                assert returned["region"] == "galar"
                for key in ("party", "boxes", "bag", "regional_badges", "chapters", "hall_of_fame"):
                    assert returned.get(key) == result.get(key), key
                assert returned["flags"].get("g_hop_final")
                print("ROUND TRIP", home, returned["regional_badges"]["galar"], flush=True)
            print("GALAR CONTINUATION PASS", version, args.stop_at, flush=True)
        except Exception:
            if args.checkpoints and slot.is_file():
                shutil.copyfile(slot, args.checkpoints / "last_saved.json")
            raise
        finally:
            if p.process.poll() is None:
                p.finish()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pack", type=Path)
    parser.add_argument("--resume", type=Path, help="a first-badge save or later earned checkpoint")
    parser.add_argument("--version", choices=("sword", "shield"), default="sword")
    parser.add_argument("--require-full-party", action="store_true")
    parser.add_argument("--route-trainers", action="store_true", help="fight every optional later route and mine trainer")
    parser.add_argument("--checkpoints", type=Path)
    parser.add_argument("--result-save", type=Path)
    parser.add_argument("--stop-at", default="g_hop_final")
    run(parser.parse_args())
