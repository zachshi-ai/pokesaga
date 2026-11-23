"""Walk the Melemele house and shop doors in Godot, buy a malasada, and reload the save."""

import argparse
import os
from pathlib import Path
import shutil
import tempfile

from alola_melemele import HOMES, SHOP_DOORS
from campaign_route import ROOT, read
from test_alola_journey import AlolaRoutes, Player


def check_block(player, exterior, places):
    exterior = "alola_" + exterior
    player.enter(exterior)
    for key in places:
        target = "alola_" + key
        outdoor = next(w for w in player.routes.fields[exterior].data["warps"] if w["to"]["map"] == target)
        player.enter(target)
        assert player.pos == (target, *outdoor["to"]["at"]), (key, "entry", player.pos)
        if key == "malasada_shop":
            previous = player.state["bag"].get("大马拉萨达", 0)
            clerk = player.routes.fields[target].data["npcs"][0]
            player.use_at(target, clerk["at"])
            assert player.select("350元"), player.state["buttons"]
            assert player.state["bag"].get("大马拉萨达", 0) == previous + 1
        x, y = outdoor["at"]
        player.enter(exterior)
        assert player.pos == (exterior, x, y + 1), (key, "exit", player.pos)
        print("DOOR", key, player.pos, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path, help="Existing Ultra Sun/Moon save with Hauoli unlocked")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pack", type=Path)
    args = parser.parse_args()
    version = read(args.save)["flags"]["a_version"]
    assert version.startswith("ultra"), "The Alola Photo Club requires Ultra Sun/Moon."
    with tempfile.TemporaryDirectory(prefix="alola-shop-walk-") as temp:
        folder = Path(temp)
        shutil.copyfile(args.save, folder / "save.json")
        cmd = [args.godot, "--headless", "--fixed-fps", "60"]
        cmd += ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(ROOT)]
        env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=temp)
        player = Player(AlolaRoutes(version), cmd, env, folder)
        try:
            check_block(player, "iki", [row[0] for row in HOMES])
            check_block(player, "hauoli", SHOP_DOORS)
            player.do("save")
            saved = read(folder / "save.json")
            assert tuple(saved["pos"]) == player.pos[1:] and saved["map"] == player.pos[0]
            print(
                "ALOLA STREETS PASS",
                version,
                len(HOMES) + len(SHOP_DOORS),
                "paired doors",
                player.state["steps"],
                "steps",
                flush=True,
            )
        finally:
            if player.process.poll() is None:
                player.do("quit")
                player.process.wait(timeout=15)
        reopened = Player(AlolaRoutes(version), cmd, env, folder)
        try:
            assert reopened.pos == player.pos
            assert reopened.state["bag"]["大马拉萨达"] == player.state["bag"]["大马拉萨达"]
            print("ALOLA STREET SAVE RELOAD PASS", reopened.pos, flush=True)
        finally:
            if reopened.process.poll() is None:
                reopened.do("quit")
                reopened.process.wait(timeout=15)


if __name__ == "__main__":
    main()
