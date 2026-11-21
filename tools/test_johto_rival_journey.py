"""Walk a copied Johto champion save to Mt. Moon, then test the dated Indigo rematches."""
import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

from campaign_route import ROOT, Routes
from test_johto_journey import JohtoPlayer

LOBBY = "johto_indigo_plateau_pokecenter_1f"
MOON = "johto_mount_moon"


def visit_corridor(p):
    p.visit(LOBBY,(8,3))
    p.visit(LOBBY,(8,2))


def verify(args):
    with tempfile.TemporaryDirectory(prefix="pokesaga-rival-") as folder:
        save=Path(folder,"save.json")
        shutil.copyfile(args.save,save)
        flags=json.loads(save.read_text())["flags"]
        assert flags.get("johto_champion") and not flags.get("j2_rival_moon")
        cmd=[args.godot,"--headless","--fixed-fps","60"]
        cmd+=["--main-pack",str(args.pack.resolve())] if args.pack else ["--path",str(ROOT)]
        for day,stage,total in [
            ("2026-11-23","before_moon",0),("2026-11-22","moon",0),
            ("2026-11-23","monday",1),("2026-11-23","monday_reload",1),
            ("2026-11-24","tuesday",1),("2026-11-25","wednesday",2),
            ("2026-11-30","next_monday",3),
        ]:
            env=dict(os.environ,POKESAGA_CHAPTER_TEST_DIR=folder,POKESAGA_CHAPTER_TEST_DATE=day)
            p=JohtoPlayer(Routes(("johto",)),cmd,env,folder)
            try:
                if stage=="moon":
                    p.enter(MOON)
                    p.milestone("j2_rival_moon")
                    assert not p.actors(MOON,"j2_moon_rival")
                visit_corridor(p)
                visit_corridor(p)
                assert not p.actors(LOBBY,"j2_plateau_rival")
                p.do("save")
                result=json.loads(save.read_text())["flags"]
                assert int(result.get("j2_rival_wins",0))==total, (stage,result.get("j2_rival_wins"))
                if stage in ("monday","wednesday","next_monday"): assert result["j2_rival_day"]==day
                print("RIVAL",day,stage,"League wins",total,flush=True)
            finally:
                p.finish()
        print("JOHTO RIVAL MOON AND CALENDAR PASS",flush=True)


if __name__=="__main__":
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot",default="godot")
    ap.add_argument("--save",type=Path,required=True)
    ap.add_argument("--pack",type=Path)
    verify(ap.parse_args())
