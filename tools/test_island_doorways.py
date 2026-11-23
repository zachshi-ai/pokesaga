"""Walk the new Alola interiors, buy an evolution stone and verify persistence after relaunch."""

import argparse
import os
from pathlib import Path
import shutil
import tempfile

from campaign_route import ROOT, read
from island_households import ROOMS
from test_alola_journey import AlolaRoutes, Player


def run(args):
    cmd = [args.godot, "--headless", "--fixed-fps", "60"]
    cmd += (
        ["--main-pack", str(args.pack.resolve())]
        if args.pack
        else ["--path", str(ROOT)]
    )
    with tempfile.TemporaryDirectory(prefix="alola-island-doors-") as temp:
        folder = Path(temp)
        shutil.copyfile(args.save, folder / "save.json")
        env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=temp)
        routes = AlolaRoutes(read(args.save)["flags"]["a_version"])

        def start():
            return Player(routes, cmd, env, folder)

        def close(p):
            if p.process.poll() is None:
                p.do("quit")
                p.process.wait(timeout=20)

        p = start()
        try:
            for parent, key, *_ in ROOMS:
                outside = "alola_" + parent
                inside = "alola_" + key
                p.enter(outside)
                door = next(
                    w
                    for w in routes.fields[outside].data["warps"]
                    if w["to"]["map"] == inside
                )
                p.enter(inside)
                assert p.pos == (inside, *door["to"]["at"]), (inside, p.pos)
                resident = routes.fields[inside].data["npcs"][0]
                p.use_at(inside, resident["at"])
                if key == "konikoni_gems":
                    cost = p.state["money"]
                    current = p.state["bag"].get("火之石", 0)
                    p.do("shop", item="火之石", amount=1)
                    assert (
                        p.state["money"] == cost - 3000
                        and p.state["bag"]["火之石"] == current + 1
                    )
                    p.do("back")
                p.enter(outside)
                x, y = door["at"]
                assert p.pos == (outside, x, y + 1), (outside, p.pos, (x, y))
            p.do("save")
            end = p.pos
            quantity = p.state["bag"]["火之石"]
            print("walked", p.state["steps"], "steps; exit", end, flush=True)
        finally:
            close(p)
        restored = start()
        try:
            assert restored.pos == end and restored.state["bag"]["火之石"] == quantity
            print(
                "ISLAND DOORWAYS PASS four resident interactions, stone purchased, four return doors and save reload"
            )
        finally:
            close(restored)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pack", type=Path)
    run(parser.parse_args())
