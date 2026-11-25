"""Walk the Sword/Shield first badge, including a transfer with an existing shared party."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from campaign_collection import Habitat, pace
from campaign_route import Field, ROOT, Routes, VECTORS, read
from test_hoenn_journey import EmeraldPlayer
from test_unova_journey import UnovaPlayer


TRAINING_STOPS = {
    "g_endorsement": ("galar_2", 9, "galar_wedgehurst"),
    "g_yell_one": ("galar_wild_south", 14, "galar_motostoke"),
    "g_bede": ("galar_3", 17, "galar_motostoke"),
}


class GalarRoutes(Routes):
    def __init__(self):
        super().__init__(())
        self.regions = ("galar",)
        self.book = read(ROOT / "content/galar_campaign.json")
        self.flags = set()
        for path in (ROOT / "content/regions/galar/maps").glob("*.json"):
            data = read(path)
            grid = data["tiles"]
            meta = data.get("physics") or {
                "collision": [[cell in (1, 2, 6, 7) for cell in row] for row in grid],
                "water": [[cell == 2 for cell in row] for row in grid],
                "grass": [[cell == 11 for cell in row] for row in grid],
            }
            self.fields[path.stem] = Field(data, meta)

    def projection(self, dest):
        if dest.get("map") == "galar_rose" and dest.get("at") == [11, 17] and "g_champion" in self.flags:
            return ("galar_battle_tower", 14, 16)
        requirement = self.book["gates"].get(dest["map"], {}).get("require", [])
        keys = [requirement] if isinstance(requirement, str) else requirement
        if not set(keys) <= self.flags:
            return None
        return super().projection(dest)


def party(save):
    return [mon for mon in save["party"] if mon]


def boxes(save):
    return [mon for box in save.get("boxes", []) for mon in box["mons"] if mon]


def as_bag(members):
    # Distinct copies of the same species and gaps in a box must survive deposit.
    return Counter(json.dumps(mon, ensure_ascii=False, sort_keys=True) for mon in members)


class GalarPlayer(EmeraldPlayer):
    train_at = UnovaPlayer.train_at
    nurse = UnovaPlayer.nurse

    def field_moves(self):
        self.routes.flags = set(self.state["flags"])
        return frozenset()

    def saved(self):
        self.do("save")
        return read(self.save_slot)

    def click_exact(self, label):
        assert label in self.state["buttons"], (self.pos, label, self.state["buttons"])
        self.do("click", label=label)

    def transfer(self, name, inspect_town=False):
        self.do("key_item", item="地区转移器")
        self.click_exact(name)
        if inspect_town:
            self.click_exact("草路镇")
        self.click_exact("出发前往" + name)

    def launch_chapter(self, before, mode, version):
        self.transfer("伽勒尔", inspect_town=True)
        self.click_exact("寄存队伍，重新组队" if mode == "boxed" else "带现有队伍出发")
        self.click_exact("《剑》" if version == "sword" else "《盾》")
        after = self.saved()
        assert after["flags"]["g_version"] == version and after["chapters"]["galar"] == mode
        assert after["region"] == "galar" and after["map"] in ("galar_player_home", "galar_postwick"), self.pos
        assert not after["regional_badges"].get("galar") and "g_badge_1" not in self.state["flags"]
        assert all(after["regional_badges"].get(r) == v for r, v in before["regional_badges"].items())
        if mode == "boxed":
            assert not party(after)
            assert as_bag(boxes(after)) == as_bag(boxes(before) + party(before))
        else:
            assert party(after) == party(before) and boxes(after) == boxes(before)
        print("FIRST ARRIVAL", version, mode, len(party(before)), self.pos, flush=True)
        return after

    def probe_exit(self, source, target):
        self.enter(source)
        field = self.routes.fields[source]
        gates = [w for w in field.data["warps"] if w["to"]["map"] == target]
        assert gates, (source, target)
        gate = gates[len(gates) // 2]
        x, y = gate["at"]
        approaches = {}
        for k, (dx, dy, *_) in VECTORS.items():
            nx, ny = x - dx, y - dy
            if 0 <= nx < field.w and 0 <= ny < field.h and not field.get("collision", nx, ny):
                if (nx, ny) not in field.doors:
                    approaches[(source, nx, ny)] = k
        self.go(approaches)
        direction = approaches[self.pos]
        self.do("walk", legs=[[direction, [target, *gate["to"]["at"]]]])
        assert self.pos[0] == source and "g_badge_1" not in self.state["flags"], self.pos
        assert self.routes.book["gates"][target]["message"] in self.state["dialog"], self.state["dialog"]
        print("EARLY EXIT BLOCKED", source, target, self.state["dialog"], flush=True)

    def event(self, event, starter, version):
        key, mid = event["id"], event["map"]
        self.enter(mid)
        if key not in self.state["flags"]:
            actor = next((row for row in self.state["actors"] if row[1] == key), None)
            assert actor, (key, self.pos, self.state["actors"])
            assert actor[2] == event["who"] and actor[0] == event["at"], (key, actor)
            names = {row[2] for row in self.state["actors"]}
            for guest in event.get("guests", []):
                if guest.get("version", version) == version:
                    assert guest["name"] in names, (key, guest, names)
            self.use_at(mid, actor[0])
        picks = 0
        while self.state["buttons"]:
            picks += 1
            assert picks <= 4, (key, self.state["buttons"])
            if starter in self.state["buttons"]:
                self.click_exact(starter)
            elif key == "g_registration":
                self.click_exact(str(picks))
            elif key == "g_mist":
                self.click_exact(self.state["buttons"][0])
            else:
                raise AssertionError((key, self.pos, self.state["dialog"], self.state["buttons"]))
        if key not in self.state["flags"]:
            raise AssertionError((key, self.pos, self.state["dialog"], self.state["fights"]))
        if key in ("g_registration", "g_mist"):
            assert picks == 3, (key, picks)
        assert all(row[1] != key for row in self.state["actors"]), (key, "old cast still present")
        if key == "g_ceremony":
            report = "".join(self.state["dialog"])
            featured, other = ("彩豆", "欧尼奥") if version == "sword" else ("欧尼奥", "彩豆")
            assert featured in report and other not in report, report
        if key == "g_home":
            self.probe_exit("galar_postwick", "galar_weald")
        print("EVENT", key, self.pos, self.state["steps"], self.state["turns"], flush=True)

    def close_menus(self):
        for _ in range(5):
            if not self.state["panels"]:
                return
            self.do("back")
        assert not self.state["panels"], self.state["buttons"]

    def road_trainers(self):
        for mid, roster in self.routes.book["trainers"].items():
            self.nurse("galar_wedgehurst" if mid == "galar_2" else "galar_motostoke")
            self.enter(mid)
            for opponent in roster:
                name = opponent["name"]
                self.use_at(mid, opponent["at"])
                assert any(f[0] == name and f[3] == "a" for f in self.state["fights"]), (mid, name, self.state["dialog"])
                self.use_at(mid, opponent["at"])
                assert not self.state["fights"] and opponent["post"][0] in self.state["dialog"], (mid, name, self.state["dialog"])
            print("ROUTE TRAINERS", mid, len(roster), flush=True)

    def catch_gossifleur(self):
        mid = "galar_3"
        f = self.routes.fields[mid]
        cells = {(x, y) for y in range(f.h) for x in range(f.w) if f.get("grass", x, y)}
        cells = {xy for xy in cells if any((xy[0]+dx, xy[1]+dy) in cells for dx,dy,*_ in VECTORS.values())}
        habitat = Habitat("三号道路", mid, cells, {}, 0)
        for _ in range(300):
            if any(m[1] in (829, 830) for m in self.state["party"]):
                self.do("mode", value="travel")
                return
            self.go({(mid, *xy) for xy in cells})
            ball = next((kind for kind in ("精灵球", "超级球", "高级球") if self.state["bag"].get(kind)), None)
            assert ball, self.state["bag"]
            self.do("throw_with", item=ball, species=829)
            pace(self, habitat, "throw", 12)
        raise AssertionError("三号道路没有捕获幼棉棉")

    def teach_item(self, item, move, member, menu_open=False):
        assert move not in member[5]
        if not menu_open:
            self.do("key_item", item=item)
        self.click_exact(member[0])
        def knows():
            return any(m[0] == member[0] and move in m[5] for m in self.state["party"])
        if not knows():
            self.click_exact(next(b for b in self.state["buttons"] if "不学" not in b))
        assert knows(), (item, member, self.state["dialog"])
        self.close_menus()

    def try_gym_rewards(self, boxed):
        self.do("key_item", item="草之套装")
        assert "g_grass_uniform_worn" in self.state["flags"]
        self.close_menus()
        self.do("key_item", item="草之套装")
        assert "g_grass_uniform_worn" not in self.state["flags"]
        self.close_menus()
        if boxed:
            member = next(m for m in self.state["party"] if m[1] in (829, 830))
            self.teach_item("伽勒尔招式学习器10·魔法叶", 345, member)
            starter = next(m for m in self.state["party"] if m[1] in range(810,819))
            self.teach_item("伽勒尔招式学习器40·高速星星", 129, starter)
        print("GRASS UNIFORM", "TM10 & TM40 TAUGHT" if boxed else "", flush=True)

    def test_items(self, key):
        if key == "g_dex":
            self.do("key_item", item="伽勒尔宝可梦图鉴")
            assert self.state["panels"] > 0 and self.state["buttons"]
            self.do("back")
        if key == "g_wild_area":
            self.do("key_item", item="宝可梦盒")
            self.click_exact("从队伍存入")
            self.click_exact("从箱子取出")
            self.do("back")
        if key == "g_band":
            assert "许愿星" not in self.state["bag"] and "极巨腕带" in self.state["bag"]
        if key == "g_train":
            assert self.pos[0] == "galar_wild_south"
            self.do("key_item", item="露营组合")
            assert "看看伙伴" in self.state["buttons"]
            self.click_exact("收起帐篷")
        if key == "g_leon_card":
            self.do("key_item", item="丹帝的联盟卡")
            assert any("喷火龙" in text for text in self.state["dialog"])
        if key == "g_registration":
            self.do("key_item", item="推荐函")
            assert any("123" in text for text in self.state["dialog"])
        if key == "g_taxi":
            self.do("key_item", item="飞翔出租车")
            assert "草路镇" not in self.state["buttons"]
            self.click_exact("木杆镇")
            assert self.pos[0] == "galar_wedgehurst"
            self.do("key_item", item="飞翔出租车")
            self.click_exact("机擎市")
            assert self.pos[0] == "galar_motostoke"
        self.close_menus()
        if key == "g_rope":
            self.enter("galar_mine")
            self.do("key_item", item="伽勒尔离洞绳")
            assert self.pos[0] == "galar_3" and self.state["bag"]["伽勒尔离洞绳"] == 1
            if self.state["panels"]:
                self.do("back")

    def record(self, key, folder):
        data = self.saved()
        if folder:
            folder.mkdir(exist_ok=True, parents=True)
            shutil.copyfile(self.save_slot, folder / (key + ".json"))
        return data


def verify_return(player, prior, region_name):
    completed = player.saved()
    player.transfer(region_name)
    after = player.saved()
    assert after["region"] == prior["region"]
    assert after["regional_badges"] == completed["regional_badges"]
    assert after["chapters"] == completed["chapters"]
    for flag, value in prior["flags"].items():
        if flag.startswith("a_"):
            assert after["flags"].get(flag) == value, flag
    assert after.get("hall_of_fame") == prior.get("hall_of_fame")
    assert party(after) == party(completed) and boxes(after) == boxes(completed)
    return after


def run(args):
    godot = [args.godot, "--headless", "--fixed-fps", "60"]
    godot += ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(ROOT)]
    with tempfile.TemporaryDirectory(prefix="galar-walk-") as tmp:
        folder = Path(tmp)
        slot = folder / "save.json"
        env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=tmp)
        if args.resume:
            shutil.copyfile(args.resume, slot)
        else:
            subprocess.run([*godot, "--script", str(ROOT / "tools/test_first_chapter.gd"), "--", "play"],
                           cwd=folder, env=env, check=True)
        routes = GalarRoutes()
        if args.stop_at not in {e["id"] for e in routes.book["events"]} | {"g_badge_1"}:
            raise ValueError(f"Unknown Galar checkpoint {args.stop_at!r}")

        def start():
            p = GalarPlayer(routes, godot, env, folder)
            p.save_slot = slot
            p.result_save = None
            return p

        p = start()
        try:
            prior = p.saved()
            if prior["flags"].get(args.stop_at):
                raise ValueError(f"This save already completed {args.stop_at}; use an earlier checkpoint to replay it")
            if args.require_full_party:
                assert len(party(prior)) == 12 and any(len(v) >= 8 for v in prior["regional_badges"].values())
            if not prior.get("chapters", {}).get("galar"):
                entrance = p.launch_chapter(prior, args.transfer, args.version)
            else:
                entrance = prior
                assert prior["flags"]["g_version"] == args.version
            starter = {"敲音猴": 810, "炎兔儿": 813, "泪眼蜥": 816}[args.starter]
            for event in routes.book["events"]:
                key = event["id"]
                if key in p.state["flags"]:
                    continue
                if key in TRAINING_STOPS:
                    p.train_at(*TRAINING_STOPS[key])
                p.event(event, args.starter, args.version)
                for step in event["steps"]:
                    if "galar_key" in step:
                        assert p.state["bag"].get(step["galar_key"], 0) > 0, (key, step)
                if key == "g_hop_first":
                    assert p.state["galar_first_rival_party"] == [starter], p.state["galar_first_rival_party"]
                p.test_items(key)
                if key == "g_rope":
                    for side in routes.book.get("side_events", []):
                        if side["map"] == "galar_3" and side["id"] not in p.state["flags"]:
                            p.event(side, args.starter, args.version)
                    if "g_route3_cheri" in p.state["flags"]:
                        p.do("key_item", item="露营组合")
                        p.click_exact(next(b for b in p.state["buttons"] if "煮咖喱" in b))
                        assert all(m[3] == m[4] for m in p.state["party"])
                        p.close_menus()
                    if args.transfer == "boxed":
                        p.catch_gossifleur()
                save = p.record(key, args.checkpoints)
                if any("galar_starter" in a for a in event["steps"]):
                    assert save["flags"]["g_starter"] == starter
                    gift = boxes(save) if len(party(entrance)) == 12 else party(save)
                    assert any(int(m["species_id"]) == starter for m in gift)
                if key == args.stop_at:
                    break
            if args.stop_at == "g_badge_1":
                from galar_gym_walk import herd
                if args.route_trainers:
                    p.road_trainers()
                p.train_at("galar_4", 21, "galar_turffield")
                herd(p)
                assert args.stop_at in p.state["flags"] and p.state["galar_dynamax_inputs"] > 0
                p.try_gym_rewards(args.transfer == "boxed")
            assert args.stop_at in p.state["flags"], (args.stop_at, p.pos)
            result = p.record(args.stop_at, args.checkpoints)
            assert bool(result["regional_badges"].get("galar")) == (args.stop_at == "g_badge_1")
            print("GALAR TOTAL", p.state["steps"], "field inputs", p.state["turns"], "battle turns",
                  p.state["galar_dynamax_inputs"], "stadium transformations", flush=True)
            if args.result_save:
                args.result_save.parent.mkdir(exist_ok=True, parents=True)
                shutil.copyfile(slot, args.result_save)
            if args.stop_at == "g_badge_1" and prior["region"] in ("alola", "kanto"):
                home = {"alola": "阿罗拉", "kanto": "关都"}[prior["region"]]
                after = verify_return(p, prior, home)
                p.finish()
                p = start()
                reopened = p.saved()
                assert reopened["region"] == after["region"] and reopened["pos"] == after["pos"]
                p.transfer("伽勒尔")
                revisited = p.saved()
                assert revisited["regional_badges"] == result["regional_badges"] and revisited["chapters"] == result["chapters"]
                assert revisited["flags"]["g_badge_1"] and revisited["flags"]["g_version"] == args.version
                assert party(revisited) == party(result) and boxes(revisited) == boxes(result)
                print("ROUND TRIP AND RELOAD", home, revisited["regional_badges"]["galar"], flush=True)
            print("GALAR JOURNEY PASS", args.version, args.transfer, args.stop_at, flush=True)
        finally:
            if p.process.poll() is None:
                p.finish()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--pack", type=Path)
    ap.add_argument("--resume", type=Path, help="a shared save earned before the requested checkpoint")
    ap.add_argument("--version", choices=["sword", "shield"], default="sword")
    ap.add_argument("--transfer", choices=["boxed", "carried"], default="boxed")
    ap.add_argument("--starter", choices=["敲音猴", "炎兔儿", "泪眼蜥"], default="炎兔儿")
    ap.add_argument("--stop-at", default="g_badge_1")
    ap.add_argument("--require-full-party", action="store_true")
    ap.add_argument("--route-trainers", action="store_true", help="battle all 19 optional route and mine trainers")
    ap.add_argument("--checkpoints", type=Path)
    ap.add_argument("--result-save", type=Path)
    run(ap.parse_args())
