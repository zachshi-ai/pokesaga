"""Replay the original Viridian Gym approach and Victory Road's four floor switches."""
from campaign_mansion import TRAVERSALS, replay


def viridian_gym(p):
    p.visit("viridiancity_gym",(17,22))
    replay(p, TRAVERSALS["viridian_gym"]["inputs"])
    p.do("face", dir="u")
    p.milestone("绿色徽章")


def victory_road(p):
    final_switch="btn:victoryroad_2f:14,19"
    if final_switch in p.state["flags"] and p.pos[0]=="kanto_main" and p.pos[2]<62:
        return
    if not any(70 in mon[5] for mon in p.state["party"]):
        raise RuntimeError("Teach Strength to a team member before entering Victory Road")
    p.visit("victoryroad_1f",(11,20))
    for row in TRAVERSALS["victory_road"]:
        replay(p,row["inputs"])
        assert p.pos==tuple(row["finish"]), (row["stage"],p.pos,row["finish"])
    for flag in ["btn:victoryroad_1f:20,16","btn:victoryroad_2f:2,19","btn:victoryroad_3f:7,7","victory_rock_dropped",final_switch]:
        p.milestone(flag)
