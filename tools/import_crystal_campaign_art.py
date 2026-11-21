"""Export the original 16 px field frames used by the Johto story actors."""
import json
import re
from pathlib import Path
from PIL import Image

from asset_paths import project_path, source_path


def main():
    src = Path(source_path("crystal"))
    art = Path(project_path("assets/npc"))
    defs = json.loads(Path(project_path("content/regions/johto/campaign.json")).read_text())
    rows = [row for room in defs["actors"].values() for row in room.values()]
    rows += [row for room in defs["add"].values() for row in room]
    names = {row["field_art"][3:] for row in rows if row.get("field_art", "").startswith("cr_")}
    palettes = {}
    day = (src / "gfx/overworld/npc_sprites.pal").read_text().split("; day\n")[1].split("; nite")[0]
    for line in day.strip().splitlines():
        if ";" not in line: continue
        raw, name = line.split(";")
        values = [round(int(k)*255/31) for k in re.findall(r"\d+",raw)]
        palettes[name.strip()] = [tuple(values[i:i+3]) for i in range(0,12,3)]
    colors = {}
    for name,palette in re.findall(r"overworld_sprite (\w+)SpriteGFX,.*?PAL_OW_(\w+)",(src/"data/sprites/sprites.asm").read_text()):
        colors[name.lower()] = palette.lower()
    frames = {"amphy":"monster", "eusine":"super_nerd", "red_gyarados":"gyarados", "electrode":"voltorb", "murkrow":"bird"}
    overrides = {"amphy":"brown", "eusine":"blue", "red_gyarados":"red", "electrode":"red", "murkrow":"blue",
                 "bird":"brown","raikou":"brown","entei":"red","suicune":"blue","sudowoodo":"tree","apprentice":"green"}
    for name in sorted(names):
        frame = frames.get(name,name)
        path = src/"gfx/sprites"/(frame+".png")
        if name in {"murkrow","electrode","red_gyarados"} or not path.exists(): path = src/"gfx/icons"/(frame+".png")
        image = Image.open(path).convert("L").crop((0,0,16,16))
        palette = palettes[overrides.get(name,colors.get(frame.replace("_",""),"blue"))]
        rgb = Image.new("RGBA",image.size)
        rgb.putdata([(*palette[(255-v)//85],255 if v<255 else 0) for v in image.getdata()])
        rgb.save(art/("cr_"+name+".png"))


if __name__ == "__main__":
    main()
