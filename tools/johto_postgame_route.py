"""Continue the Johto champion's save aboard the S.S. Aqua and through Mt. Silver."""
import json

from campaign_route import ROOT


BOOK = json.loads((ROOT / "content/regions/johto/postgame.json").read_text())
ROLES = {npc["role"]: (room, tuple(npc["at"]))
         for room, npcs in BOOK["actors"].items() for npc in npcs}
SHIP = "johto_fast_ship_1f"


def done(p, key):
    return key in p.state["flags"]


def talk(p, role, event=None):
    flag = "j2_" + (event or role)
    if done(p, flag):
        return
    room, pos = ROLES["j2_" + role]
    p.interact(room, pos, role="j2_"+role)
    p.milestone(flag)


def voyage(p):
    if not done(p, "j2_ship_ticket"):
        if p.pos[0] == "johto_hall_of_fame":
            p.go({("johto_hall_of_fame",6,22)})
            p.do("walk",legs=[["d",["johto_players_house_2f",6,6]]])
            assert p.pos==("johto_players_house_2f",6,6)
        p.interact("johto_elms_lab", (2,1))
        p.milestone("j2_ship_ticket")
    if done(p, "j2_ship_landed"): return
    if not done(p, "j2_ship_boarded"):
        p.enter("johto_olivine_port")
        p.enter(SHIP)
        p.milestone("j2_ship_boarded")
    talk(p, "sailor_watch", "sailor_missing")
    talk(p, "sailor_sleep", "sailor_back")
    talk(p, "girl", "girl_found")
    assert p.state["bag"].get("金属膜",0) > 0
    p.go({(SHIP,24,19)})
    p.do("walk", legs=[["d",["johto_vermilion_port",23,18]]])
    p.milestone("j2_ship_landed")


def kanto_power(p):
    talk(p,"manager","power_missing")
    if not done(p,"j2_thief_ran"):
        p.enter("johto_cerulean_gym")
        p.milestone("j2_thief_ran")
    talk(p,"robber_bridge","thief_beaten")
    if not done(p,"j2_machine_part"):
        p.interact("johto_cerulean_gym",(1,4))
        p.milestone("j2_machine_part")
        assert p.state["bag"]["发电机零件"] == 1
    if not done(p,"j2_power"):
        talk(p,"manager","power")
        assert p.pos[0]=="hgss_route_10_power_plant_repaired",(p.pos,"generators after repair")
    assert not p.state["bag"].get("发电机零件",0)
    if not done(p,"j2_misty_back"):
        p.enter("johto_route_25")
        if not done(p,"j2_misty_back"):
            p.interact("johto_route_25", (22,3))
        p.milestone("j2_misty_back")
    talk(p,"radio","expn")
    talk(p,"copy","lost_doll")
    talk(p,"doll_owner","doll")
    talk(p,"copy","train_pass")
    assert p.state["bag"].get("磁浮列车通行证",0) and not p.state["bag"].get("遗失玩偶",0)
    for station, destination in (("saffron","goldenrod"),("goldenrod","saffron")):
        mid = "johto_" + station + "_magnet_train_station"
        other = "johto_" + destination + "_magnet_train_station"
        gate = (14,7) if station=="saffron" else (6,6)
        p.go({(mid,*gate)})
        p.do("walk",legs=[["u",[other,3,3]]])
        assert p.pos == (other,3,3), (p.pos,p.state["dialog"])
    if not done(p,"j2_snorlax"):
        p.enter("johto_vermilion_city")
        p.key_item("收音机扩充卡")
        if p.state["buttons"]: p.do("back")
        p.milestone("j2_flute")
        p.do("mode",value="train")
        try:
            talk(p,"snorlax")
        finally:
            p.do("mode",value="travel")


def postgame(p):
    voyage(p)
    if not done(p,"j2_snorlax"):
        kanto_power(p)
    for group in ("ltsurge","sabrina","erika","janine","misty","brock","blaine","blue"):
        if group == "blue": talk(p,"blue","blue_returns")
        flag = "badge_" + group
        if not done(p,"j2_" + flag):
            p.heal()
            talk(p,flag)
        if group == "brock":
            from johto_item_route import kanto
            kanto(p)
    assert set(BOOK["badges"]) <= set(p.state["flags"])
    talk(p,"oak","silver_pass")
    if not done(p,"j2_red_defeated"):
        if not p.state["bag"].get("城都秘传学习器 08"):
            p.interact("johto_oaks_lab",(2,1),role="j2_oak")
        p.train("johto_silver_cave_room_1",88)
        p.heal()
        p.teach("攀岩",431)
        assert 431 in p.routes.field_moves,(p.state["badges"],p.state["party"])
        p.enter("johto_silver_cave_room_3")
        p.checkpoint("red")
        talk(p,"red","red_defeated")
    assert not p.actors("johto_silver_cave_room_3", "j2_red")


def resume():
    """Exercise the second half independently without modifying the supplied save."""
    import argparse
    import os
    import tempfile
    from pathlib import Path

    from hgss_route import JohtoRoutes
    from test_johto_journey import JohtoPlayer

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("champion_save", type=Path, help="Existing Johto Hall of Fame save.json")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--pack", type=Path)
    parser.add_argument("--result-save", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="pokesaga-postgame-") as folder:
        save_dir = Path(folder)
        save = save_dir / "save.json"
        save.write_bytes(args.champion_save.read_bytes())
        cmd = [args.godot, "--headless", "--fixed-fps", "60"]
        cmd += ["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        env = dict(os.environ, POKESAGA_CHAPTER_TEST_DIR=folder)
        routes = JohtoRoutes()
        player = JohtoPlayer(routes,cmd,env,folder)
        try:
            assert done(player,"johto_champion"), "The supplied save has not entered the Johto Hall of Fame"
            player.save_dir = save_dir
            postgame(player)
            player.do("save")
        finally:
            player.finish()
        restored = JohtoPlayer(routes,cmd,env,folder)
        try:
            assert set(player.state["flags"]) == set(restored.state["flags"]), {
                "lost":set(player.state["flags"])-set(restored.state["flags"]),
                "gained":set(restored.state["flags"])-set(player.state["flags"])}
            for key in ("badges","party","bag","pos"):
                assert player.state[key] == restored.state[key], key
            assert done(restored,"j2_red_away") and done(restored,"j2_red_defeated")
            if args.result_save: args.result_save.write_bytes(save.read_bytes())
            print("JOHTO POSTGAME AND RELOAD PASS", restored.pos, len(restored.state["badges"]))
        finally:
            restored.finish()


if __name__ == "__main__":
    resume()
