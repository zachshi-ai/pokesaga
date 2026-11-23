"""Revisit all four editions through Start using a copy of an earned Sun champion save."""
import argparse
import os
import shutil
import tempfile
from pathlib import Path

from campaign_route import ROOT, VECTORS, read
from test_alola_journey import AlolaRoutes, Player


TITLES = {"sun": "《太阳》", "moon": "《月亮》", "ultra_sun": "《究极之日》", "ultra_moon": "《究极之月》"}


def individuals(rows):
    return [{k: v for k, v in m.items() if k != "alola_origin"} for m in rows if m]


def pc(data):
    return individuals(m for box in data["boxes"] for m in box["mons"])


def shared(data):
    return {key: data.get(key) for key in ["origin", "money", "dex", "dex_variants", "dex_seen", "dex_caught"]}


def trophies(data):
    return [data["flags"].get("a_champion", False), data["regional_badges"]["alola"], data.get("hall_of_fame", {}).get("alola", [])]


def switch(p, folder, version, started=False, boxed=False):
    assert p.pos[0] == "alola_home"
    p.do("save")
    before = read(folder / "save.json")
    p.do("start")
    for label in ["工具", "阿罗拉版本", TITLES[version] + ("　继续巡礼" if started else "　开始巡礼")]:
        assert p.select(label), (label, p.state["buttons"])
    if not started:
        label = "寄存队伍，重新组队" if boxed else "带现有队伍出发"
        assert p.select(label), (label, p.state["buttons"])
    p.do("save")
    data = read(folder / "save.json")
    assert data["flags"]["a_version"] == version and data["map"] == "alola_home"
    assert shared(data) == shared(before), ("global collection changed", version)
    team = individuals(before["party"])
    assert individuals(data["party"]) == ([] if boxed else team), ("party", version)
    assert pc(data) == pc(before) + (team if boxed else []), ("box", version)
    if version != "sun":
        assert trophies(data) == [False, [], []] and not data["flags"].get("a_starter")
        assert not data["flags"].get("a_z_ring") and not any("手环" in b["name"] for b in data["bag"])
    p.routes = AlolaRoutes(version)
    p.do("status")
    return data


def lab_gate(p):
    # Step into the actual lab threshold, starting on its original exterior map.
    mid = "alola_hauoli_outskirts"
    p.enter(mid)
    field = p.routes.fields[mid]
    door = next(w for w in field.data["warps"] if w["to"]["map"] == "alola_lab")
    x, y = door["at"]
    adj = {(mid, x-dx, y-dy) for dx, dy, *_ in VECTORS.values()}
    p.go(adj)
    dx, dy = x-p.pos[1], y-p.pos[2]
    direction = next(k for k, v in VECTORS.items() if tuple(v[:2]) == (dx, dy))
    p.do("walk", legs=[[direction, ["alola_lab", *door["to"]["at"]]]])
    assert p.pos[0] == mid and any("祭典" in msg for msg in p.state["dialog"]), (p.pos, p.state["dialog"])
    p.enter("alola_home")


def close(p):
    if p.process.poll() is None:
        p.do("quit")
        p.process.wait(timeout=30)


def play(args, folder, boxed=False):
    shutil.copy2(args.source, folder / "save.json")
    initial = read(args.source)
    cmd = [args.godot, "--headless", "--fixed-fps", "60"]
    cmd += ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(ROOT)]
    env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=str(folder))
    def boot(version):
        return Player(AlolaRoutes(version), cmd, env, folder)
    p = boot("sun")
    try:
        assert trophies(initial)[0] and len(trophies(initial)[1]) == 4 and trophies(initial)[2]
        p.enter("alola_lab")  # This same threshold is open for the returning champion.
        p.do("start")
        assert p.select("工具")
        assert "阿罗拉版本" not in p.state["buttons"] and "宝可度假地" in p.state["buttons"]
        assert p.select("返回") and p.select("退出菜单")
        p.enter("alola_home")
        print("SUN HOME WALK", p.state["steps"], flush=True)
        if boxed:
            data = switch(p, folder, "ultra_moon", boxed=True)
            assert data["chapters"]["alola"] == "boxed"
            close(p)
            p = boot("ultra_moon")
            restored = switch(p, folder, "sun", started=True)
            assert trophies(initial) == trophies(restored) and not individuals(restored["party"])
            print("EARNED BOX TRANSFER PASS", len(pc(data)), "individuals retained after restart", flush=True)
            return
        for version in ["moon", "ultra_sun", "ultra_moon"]:
            switch(p, folder, version)
            lab_gate(p)
            print("LOCKED LAB", version, p.state["steps"], flush=True)
        restored = switch(p, folder, "sun", started=True)
        assert trophies(restored) == trophies(initial) and restored["flags"].get("a_z_ring")
        assert any(b["name"] == "Ｚ手环" for b in restored["bag"])
        assert any(m.get("alola_origin") == "sun" and m.get("alola_partner") for m in restored["party"] if m)
        close(p)
        p = boot("sun")
        p.do("save")
        cold = read(folder / "save.json")
        assert trophies(cold) == trophies(initial) and shared(restored) == shared(cold)
        assert individuals(restored["party"]) == individuals(cold["party"]) and pc(restored) == pc(cold)
        assert set(cold["alola_editions"]) == {"moon", "ultra_sun", "ultra_moon"}
        p.enter("alola_lab")
        p.enter("alola_home")
        # Reopen every archived itinerary after a true process restart, then restore Sun a second time.
        for version in ["moon", "ultra_sun", "ultra_moon", "sun"]:
            returned = switch(p, folder, version, started=True)
        assert trophies(returned) == trophies(initial)
        print("ALOLA EARNED EDITIONS PASS",
              len(returned["dex"]["seen"]), "seen", len(returned["dex"]["caught"]), "caught",
              len(returned["dex_variants"]), "variant records",
              len(individuals(returned["party"])), "carried", len(pc(returned)), "boxed",
              "champion and 4 stamps restored", flush=True)
    finally:
        close(p)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pack", type=Path)
    parser.add_argument("--boxed", action="store_true", help="exercise the first-visit option to deposit the earned team")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="alola-edition-journey-") as d:
        play(args, Path(d), args.boxed)


if __name__ == "__main__":
    main()
