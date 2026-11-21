"""Extract the field sprites and daytime NPC colors used by Crystal's Kanto encounters."""
import argparse
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
# Map script overrides take precedence over the sprite's default palette.
ACTORS = {"red":"red", "blue":"red", "janine":"blue", "surge":"brown", "erika":"green",
          "brock":"brown", "blaine":"brown", "misty":"red", "sabrina":"red", "teacher":"green"}


def import_sprites(source):
    text = (source / "gfx/overworld/npc_sprites.pal").read_text()
    day = text.split("; day\n",1)[1].split("; nite",1)[0].split("\n\n",1)[0]
    palette = {}
    for values, name in re.findall(r"RGB ([\d, ]+) ; (\w+)", day):
        channels = [round(int(v)*255/31) for v in values.split(",")]
        palette[name] = [(0,0,0,0)] + [tuple(channels[i:i+3])+(255,) for i in (3,6,9)]
    for sprite, name in ACTORS.items():
        with Image.open(source / "gfx/sprites" / (sprite+".png")) as sheet:
            frame = sheet.crop((0,0,16,16)).convert("L")
        out = Image.new("RGBA",frame.size)
        out.putdata([palette[name][3-round(value/85)] for value in frame.getdata()])
        out.save(ROOT / "assets/npc" / ("crystal_"+sprite+".png"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    import_sprites(parser.parse_args().source)
