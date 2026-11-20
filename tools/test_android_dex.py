"""Drive the installed study APK on a disposable 3:2 Android emulator using adb.
The fixture temporarily adds seen IDs to an existing debug save. The original is
backed up in --output and restored when the run exits. Screenshots stay in --output.
"""
import argparse
import io
import json
import subprocess
import time
from pathlib import Path

from PIL import Image

PACKAGE = "com.stepx.pokesaga.study"
ACTIVITY = PACKAGE + "/com.godot.game.GodotAppLauncher"
ROOT = Path(__file__).resolve().parents[1]


def run(adb_path, serial, out):
    if not serial.startswith("emulator-"):
        raise ValueError("Select a disposable Android Emulator by serial")
    out.mkdir(parents=True, exist_ok=True)
    def adb(*args, input=None):
        return subprocess.run([adb_path, "-s", serial, *args], input=input, capture_output=True, check=True).stdout

    def capture():
        return Image.open(io.BytesIO(adb("exec-out","screencap","-p"))).convert("RGB")

    w,h = capture().size
    if abs(w / h - 1.5) > 0.02:
        raise ValueError("Test uses the game's landscape 3:2 viewport")
    def tap(x,y):
        adb("shell","input","tap",str(round(x*w/480)),str(round(y*h/320)))
        time.sleep(.36)

    def arrival():
        adb("shell","am","start","-W","-n",ACTIVITY)
        time.sleep(2)

    def write_save(raw):
        adb("shell","am","force-stop",PACKAGE)
        adb("shell",f"run-as {PACKAGE} sh -c 'cat > files/save.json'",input=raw)

    atlas = json.loads((ROOT / "content/dex_art.json").read_text())
    def portrait(sid, key, shiny, filename):
        im = capture()
        im.save(out / (filename + ".png"))
        slot = atlas[str(sid)][key]
        page = Image.open(ROOT / ("assets/dex/%s_%d.png" % ("shiny" if shiny else "normal",slot//256))).convert("RGBA")
        x, y = slot%16*64, slot%256//16*64
        chip = page.crop((x,y,x+64,y+64))
        colors = {px[:3] for px in chip.getdata() if px[3] > 200}
        box = (round(16*w/480),round(72*h/320),round(180*w/480),round(225*h/320))
        shown = set(im.crop(box).getdata())
        matched = len(colors & shown) / len(colors)
        if matched < .76:
            raise AssertionError(f"{filename}: expected atlas colours {matched:.0%}")

    def lookup(query, first=False):
        if not first:
            tap(37,23)  # return to results
            tap(456,72)  # clear the previous query
        tap(280,72)
        adb("shell","input","text",query)
        adb("shell","input","keyevent","66")
        tap(70,133)

    raw = adb("exec-out","run-as",PACKAGE,"cat","files/save.json")
    (out / "save-before-test.json").write_bytes(raw)
    save = json.loads(raw)
    seen = save.setdefault("dex",{}).setdefault("seen",[])
    seen.extend([990,666,869,201,493,1017])
    try:
        write_save(json.dumps(save,ensure_ascii=False).encode())
        arrival()
        tap(60,19)
        lookup("990",True)
        portrait(990,"",False,"01-paradox-990-under-0232")
        lookup("vivillon-icy-snow")
        portrait(666,"VIVILLON_ICY_SNOW",False,"02-vivillon-icy-snow")
        lookup("vivillon-polar")
        portrait(666,"SPEWPA_POLAR",False,"03-vivillon-polar")
        lookup("arceus-fire")
        portrait(493,"ARCEUS_FIRE",False,"04-arceus-fire")
        lookup("unown-f")
        portrait(201,"UNOWN_F",False,"05-unown-F")
        lookup("869")
        portrait(869,"ALCREMIE_VANILLA_CREAM_STRAWBERRY",False,"06-alcremie-vanilla")
        tap(320,104)
        tap(350,75)
        tap(130,70)
        adb("shell","input","text","MATCHA_CREAM_RIBBON")
        adb("shell","input","keyevent","66")
        tap(110,115)
        portrait(869,"ALCREMIE_MATCHA_CREAM_RIBBON",False,"07-alcremie-matcha-ribbon")
        tap(320,150)
        tap(350,75)
        portrait(869,"ALCREMIE_MATCHA_CREAM_RIBBON",True,"08-alcremie-star")
        tap(320,150)
        tap(110,120)
        portrait(869,"ALCREMIE_MATCHA_CREAM_RIBBON",True,"09-alcremie-square")
    finally:
        write_save(raw)
        arrival()
    print("ANDROID DEX PASS: 9 screenshots; original QA save restored")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--adb",default="adb")
    cli.add_argument("--serial",required=True)
    cli.add_argument("--output",type=Path,required=True)
    opt = cli.parse_args()
    run(opt.adb,opt.serial,opt.output)
