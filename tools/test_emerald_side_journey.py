"""Play the Winstrates, champion caves, eight Trick House rooms and coastal town rewards."""
import argparse
import json
import os
import re
import tempfile
from pathlib import Path

from hoenn_field_route import click, gift, machine
from hoenn_trick_route import goal
from test_hoenn_journey import EmeraldPlayer, Routes, ROOT, VECTORS

HIDING_PLACES = [(6, 3), (11, 5), (9, 1), (3, 1), (0, 5), (11, 1), (8, 1), (4, 4)]
TRICK_HOUSE = "em_route110_trick_house_"


def enable_quiz_answers(player):
    """Answer each Mechadoll on the choice sheet as the walking player encounters it."""
    script = (ROOT / "core/hoenn_side.gd").read_text()
    banks = json.loads(re.search(r"const QUIZZES := (\[.*?\])\n\n", script, re.S)[1])
    press = player.do

    def answer(action, **arguments):
        state = press(action, **arguments)
        if action != "quit" and state and state["buttons"]:
            for bank in banks:
                for _, answers, correct in bank:
                    if all(option in state["buttons"] for option in answers):
                        return press("click", label=answers[correct])
        return state

    player.do = answer


def family_and_steven(p):
    if "h_winstrates" not in p.state["flags"]:
        p.use_at("hoenn_111", (13, 114))
        assert "h_winstrates" in p.state["flags"], (p.pos, p.state["dialog"])
    p.use_at("em_route111_winstrate_familys_house", (7, 4))
    assert p.state["bag"].get("强制锻炼器") == 1
    for mid in ("hoenn_103", "hoenn_meteor"):
        field = p.routes.fields[mid]
        for x, y, *cell in field.data["mechanisms"]["champion_cave"]:
            field.grid["collision"][y * field.w + x] = cell[-1]
    p.routes.edges.cache_clear()
    p.enter("em_altering_cave")
    print("ALTERING", p.pos, flush=True)
    p.use_at("em_meteor_falls_stevens_cave", (19, 3))
    assert "h_steven_duel" in p.state["flags"]
    print("WINSTRATE, ALTERING CAVE, STEVEN PASS", p.pos, flush=True)


def trick_house(p, slot):
    if "h_item_hm_cut" not in p.state["flags"]:
        gift(p, "em_rustboro_city_cutters_house", "RustboroCity_CuttersHouse_EventScript_Cutter", "h_item_hm_cut")
    machine(p, 15, (57, 70, 249))
    entrance, reward_room = TRICK_HOUSE + "entrance", TRICK_HOUSE + "end"
    for number, hiding_place in enumerate(HIDING_PLACES, 1):
        if json.loads(slot.read_text())["flags"].get("h_trick_cleared", 0) >= number:
            continue
        mid = TRICK_HOUSE + "puzzle" + str(number)
        if p.pos[0] != mid:
            p.enter(entrance)
            p.use_at(entrance, hiding_place)
            assert "h_trick_found" in p.state["flags"], (p.pos, p.state["dialog"])
            p.use_at(entrance, (5, 1))
        assert p.pos[0] == mid, (p.pos, p.state["dialog"])
        field = p.routes.fields[mid]
        scroll = next(o for o in field.data["objects"] if o.get("source_script", "").endswith("_Scroll"))
        x, y = scroll["at"]
        adjacent = {(x - dx, y - dy): direction for direction, (dx, dy, *_) in VECTORS.items()}
        goal(p, set(adjacent))
        p.do("face", dir=adjacent[p.pos[1:]])
        p.do("save")
        assert int(json.loads(slot.read_text())["flags"].get("h_trick_scroll", 0)) == number
        goal(p, {(13, 2)})
        p.do("walk", legs=[["u", [reward_room, 10, 1]]])
        assert p.pos[0] == reward_room, (p.pos, p.state["dialog"])
        p.use_at(reward_room, (4, 5))
        if number == 8:
            click(p, "蓝色帐篷")
        p.do("save")
        assert int(json.loads(slot.read_text())["flags"].get("h_trick_cleared", 0)) == number
        print("TRICK", number, p.pos, flush=True)


def coast(p, slot):
    house = "em_route109_seashore_house"
    if "h_seashore_soda" not in p.state["flags"]:
        for at in ((2, 3), (14, 9), (10, 5)):
            p.use_at(house, at)
        before = p.state["bag"].get("劲爽汽水", 0)
        p.use_at(house, (6, 2))
        assert p.state["bag"]["劲爽汽水"] == before + 6
    before = p.state["bag"]["劲爽汽水"]
    money = p.state["money"]
    p.use_at(house, (6, 2))
    click(p, "购买")
    assert p.state["bag"]["劲爽汽水"] == before + 1 and p.state["money"] == money - 300
    p.use_at("hoenn_slateport", (4, 47))
    p.do("save")
    first = json.loads(slot.read_text())["party"][0]
    assert first.get("effort_ribbon") or sum(first.get("effort", {}).values()) < 510
    gift_map = "em_pacifidlog_town_house2"
    p.use_at(gift_map, (3, 5))
    if first.get("friendship", 200) >= 150 or first.get("friendship", 200) < 50:
        assert "h_fan_tm_day" in p.state["flags"]
    p.do("save")
    print("SEASHORE, SLATEPORT, PACIFIDLOG PASS", p.pos, flush=True)


def lilycove_ladies(p, slot):
    center = "em_lilycove_city_pokemon_center_1f"
    lobby = "em_lilycove_city_contest_lobby"
    p.use_at("em_route123_berry_masters_house", (4, 4))
    p.do("save")
    berries = [r["name"] for r in json.loads(slot.read_text())["bag"] if r.get("category") == "berry" and r["count"]]
    assert berries, "the Berry Master should provide fruit for blending"
    if "宝可方块盒" not in p.state["bag"]:
        p.use_at(lobby, (14, 2))
    assert p.state["bag"].get("宝可方块盒", 0)
    p.use_at(lobby, (27, 5))
    click(p, berries[0])
    p.do("save")
    blocks = json.loads(slot.read_text())["flags"].get("h_blocks", [])
    assert blocks, "timed berry blending should create a real Pokéblock"
    before_blocks = len(blocks)
    p.enter(center)
    data = json.loads((ROOT / "content/hoenn_native/lilycove_lady.json").read_text())
    seen = set()
    for _ in range(3):
        p.do("save")
        state = json.loads(slot.read_text())["flags"]["h_lily_ladies"]
        visitor = state["current"]
        seen.add(visitor)
        p.use_at(center, (1, 3))
        if visitor == 0:
            click(p, "挑战问答")
            question = data["quiz"][int(state["quiz"]["index"])]
            click(p, question["options"][int(question["correct"])])
            assert p.state["bag"].get(data["items"][question["prize"]], 0)
        elif visitor == 1:
            click(p, "看看她想要什么")
            spec = data["favor"][int(state["favor"]["index"])]
            names = [data["items"][k] for k in [state["favor"]["favorite"], *spec["items"]]]
            item = next((name for name in names if any(b.startswith(name + " ×") for b in p.state["buttons"])), None)
            if not item:
                item = next(b.split(" ×")[0] for b in p.state["buttons"] if " ×" in b)
            old = p.state["bag"][item]
            click(p, item + " ×")
            assert p.state["bag"].get(item, 0) == old - 1
        else:
            click(p, "看看她想要什么")
            click(p, blocks[0]["name"])
            p.do("save")
            assert len(json.loads(slot.read_text())["flags"]["h_blocks"]) == before_blocks - 1
        p.use_at(center, (1, 3))
        click(p, "交换本地活动记录")
    assert seen == {0, 1, 2}
    p.do("save")
    print("LILYCOVE LADIES, BERRY BLENDER PASS", p.pos, flush=True)


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--entry-save", type=Path, required=True)
    parser.add_argument("--pack", type=Path)
    parser.add_argument("--result-save", type=Path)
    parser.add_argument("--lilycove-only", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        slot = Path(folder) / "save.json"
        slot.write_bytes(args.entry_save.read_bytes())
        launch = [args.godot, "--headless", "--fixed-fps", "60", "--path", str(ROOT)]
        if args.pack:
            launch += ["--main-pack", str(args.pack)]
        player = EmeraldPlayer(Routes(("hoenn",)), launch, dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=folder), folder)
        try:
            enable_quiz_answers(player)
            if not args.lilycove_only:
                family_and_steven(player)
                trick_house(player, slot)
                coast(player, slot)
            lilycove_ladies(player, slot)
            if args.result_save:
                args.result_save.write_bytes(slot.read_bytes())
        finally:
            player.finish()


if __name__ == "__main__":
    run()
