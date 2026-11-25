"""Exercise the Crown rental run or Galar guest-room and battle services through normal game inputs."""

import argparse
import os
from pathlib import Path
import shutil
import tempfile

from campaign_route import ROOT, read
from test_galar_expansion_journey import ExpansionPlayer, ExpansionRoutes


def talk(player, location, role):
    player.enter(location)
    actor = next(row for row in player.state["actors"] if row[1] == role)
    player.use_at(location, actor[0])


def hotel(player):
    detective = "galar_ionia_east_guest_2"
    for role in [
        "venue_detective",
        "venue_suspect_0",
        "venue_suspect_1",
        "venue_suspect_2",
        "venue_skwovet",
    ]:
        talk(player, detective, role)
    assert player.state["bag"]["广角镜"] > 0
    for wing, number, role, item in [
        ("east", 3, "venue_screech", "伽勒尔招式学习器16·刺耳声"),
        ("east", 4, "venue_tears", "伽勒尔招式学习器47·假哭"),
        ("west", 1, "venue_director", "不晃捕捉护符"),
        ("west", 2, "venue_morimoto", "圆形护符"),
    ]:
        talk(player, f"galar_ionia_{wing}_guest_{number}", role)
        if role == "venue_morimoto":
            player.click_exact("对战")
        assert player.state["bag"][item] > 0, (role, player.state["fights"])
    for city in ["motostoke", "hammerlocke", "wyndon"]:
        player.nurse("galar_" + city)
        role = "venue_cafe_" + city
        talk(player, f"galar_{city}_cafe_room", role)
        player.click_exact("接受挑战")
        assert player.saved()["flags"].get("g_cafe_" + city)
        talk(player, f"galar_{city}_cafe_room", role)
        assert "接受挑战" not in player.state["buttons"]
    print(
        "HOTEL AND CAFES PASS",
        player.pos,
        player.state["steps"],
        player.state["turns"],
        flush=True,
    )


def tower(player):
    for mode, count in [("单打 · 3只", 3), ("双打 · 4只", 4)]:
        lobby = "galar_battle_tower"
        talk(player, lobby, "venue_tower_rental")
        player.click_exact("强攻队")
        talk(player, lobby, "venue_tower_sign")
        player.click_exact(mode)
        player.click_exact("租借的强攻队")
        for _ in range(count):
            player.click_exact(player.state["buttons"][0])
        assert player.pos[0] == "galar_battle_tower_field"
        own = [(m["species_id"], m["hp"]) for m in player.saved()["party"] if m]
        talk(player, player.pos[0], "venue_tower_fight")
        assert player.pos[0] == lobby and not player.saved()["flags"].get("g_tower_run")
        assert own == [(m["species_id"], m["hp"]) for m in player.saved()["party"] if m]
    print(
        "TOWER PASS",
        player.pos,
        player.state["steps"],
        player.state["turns"],
        flush=True,
    )


def fashion(player):
    for city in ["wedgehurst", "motostoke", "hammerlocke", "circhester", "wyndon"]:
        room = "galar_" + city + "_boutique_room"
        talk(player, room, "venue_boutique_" + city)
        label = player.state["buttons"][0]
        price = int(label.split("　")[1].removesuffix("元"))
        money = player.state["money"]
        player.click_exact(label)
        player.click_exact("买下　%d元" % price)
        bought = player.saved()
        code = bought["flags"].get("g_fashion_worn")
        assert (
            code in bought["galar_wardrobe"] and player.state["money"] == money - price
        )
        talk(player, room, "venue_fitting")
        player.click_exact("小悠的绿宝石原装")
        assert not player.saved()["flags"].get("g_fashion_worn")
        talk(player, room, "venue_fitting")
        player.click_exact(bought["galar_wardrobe"][code])
        player.enter("galar_" + city)
        if city == "wedgehurst":
            continue
        room = "galar_" + city + "_salon_room"
        talk(player, room, "venue_salon_" + city)
        player.click_exact("侧分")
        money = player.state["money"]
        player.click_exact("酒红")
        flags = player.saved()["flags"]
        assert (
            flags["g_fashion_cut"] == 1
            and flags["g_fashion_hair"] == "974f5a"
            and player.state["money"] == money - 3000
        )
        player.enter("galar_" + city)
    print(
        "FASHION PASS 5 purchases, 10 fitting-room changes, 4 haircuts",
        player.state["steps"],
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--resume", type=Path, required=True)
    parser.add_argument(
        "--part", choices=["tower", "hotel", "lair", "fashion"], required=True
    )
    parser.add_argument("--pack", type=Path)
    options = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="galar-venues-") as temp:
        folder = Path(temp)
        slot = folder / "save.json"
        shutil.copyfile(options.resume, slot)
        args = [options.godot, "--headless", "--fixed-fps", "60"]
        args += (
            ["--main-pack", str(options.pack.resolve())]
            if options.pack
            else ["--path", str(ROOT)]
        )
        p = ExpansionPlayer(
            ExpansionRoutes(),
            args,
            dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=temp),
            folder,
        )
        p.save_slot = slot
        try:
            if options.part == "lair":
                event = next(
                    e
                    for e in read(ROOT / "content/galar_expansion.json")
                    if e["id"] == "dlc_lair"
                )
                p.event(event, "water")
                stats = p.saved()
                assert (
                    not stats["flags"].get("dlc_field_adventure")
                    and p.pos[0] == "crown_max_lair"
                )
                assert len(p.state["galar_raids"]) == 4, p.state["galar_raids"]
                print(
                    "LAIR PASS",
                    p.pos,
                    p.state["steps"],
                    p.state["turns"],
                    p.state["galar_raids"],
                    flush=True,
                )
            elif options.part == "fashion":
                fashion(p)
            elif options.part == "tower":
                tower(p)
            else:
                hotel(p)
        finally:
            p.finish()


if __name__ == "__main__":
    main()
