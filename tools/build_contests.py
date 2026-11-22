#!/usr/bin/env python3
"""Extract Emerald's contest moves, judges' effects, opponent pools and berry properties."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
src = parser.parse_args().source / "src"
root = Path(__file__).resolve().parents[1] / "content"
moves = {key:int(num) for key,num in re.findall(r"^#define MOVE_(\w+)\s+(\d+)", (src.parent/"include/constants/moves.h").read_text(), re.M)}
species = {v["key"]:v["id"] for v in json.loads((root/"species.json").read_text())}
species["CASTFORM"]=351
categories = ["Cool","Beauty","Cute","Smart","Tough"]

def field(block, key):
    return re.search(r"\."+key+r"\s*=\s*([^,\n]+)", block)[1].strip()

def records(text, pattern):
    return re.findall(r"\["+pattern+r"\]\s*=\s*\{(.*?)\n    \},?", text, re.S)

raw = (src/"data/contest_moves.h").read_text()
effects = {key:[int(field(value,"appeal")),int(field(value,"jam"))]
           for key,value in records(raw, r"CONTEST_EFFECT_(\w+)")}
rows = {}
for key, block in records(raw[raw.index("[MOVE_POUND]"):], r"MOVE_(\w+)"):
    effect = field(block,"effect").removeprefix("CONTEST_EFFECT_")
    cat = field(block,"contestCategory").removeprefix("CONTEST_CATEGORY_").title()
    combos = re.search(r"\.comboMoves\s*=\s*\{([^}]*)",block)
    combos = combos[1] if combos else ""
    rows[moves[key]] = dict(effect=effect,category=categories.index(cat),appeal=effects[effect][0],
                            jam=effects[effect][1],starter=field(block,"comboStarterId").removeprefix("COMBO_STARTER_"),
                            combo=re.findall(r"COMBO_STARTER_(\w+)",combos))
raw = (src/"data/contest_opponents.h").read_text()
filters = dict(re.findall(r"\[CONTEST_OPPONENT_(\w+)\] = CONTEST_FILTER_(\w+)",raw))
ranks = ["NORMAL","SUPER","HYPER","MASTER"]
opponents = []
for key, block in records(raw,r"CONTEST_OPPONENT_(\w+)"):
    if ".species" not in block:continue
    opponents.append(dict(species=species[field(block,"species")[8:]],trainer=key.title(),
                          rank=ranks.index(field(block,"whichRank")[13:]),filter=filters[key],
                          categories=[i for i,c in enumerate(categories) if field(block,"aiPool_"+c)=="TRUE"],
                          moves=[moves[m] for m in re.findall(r"\bMOVE_(\w+)",block) if m!="NONE"],
                          condition=[int(field(block,c.lower())) for c in categories],sheen=int(field(block,"sheen"))))
berry_text=(src/"berry.c").read_text()
berries={}
for key,block in records(berry_text.split("const struct BerryCrushBerryData")[0],r"ITEM_(\w+)_BERRY - FIRST_BERRY_INDEX"):
    berries[key.lower()]=dict(flavor=[int(field(block,k)) for k in ("spicy","dry","sweet","bitter","sour")],
                              smooth=int(field(block,"smoothness")))
for key,presses,powder in re.findall(r"\[ITEM_(\w+)_BERRY - FIRST_BERRY_INDEX\]\s*=\s*\{\.difficulty =\s*(\d+), .powder =\s*(\d+)",berry_text):
    berries[key.lower()].update(presses=int(presses),powder=int(powder))
print(len(rows),len(effects),len(opponents),len(berries))
assert len(rows)==354 and len(effects)==48 and len(opponents)>=90 and len(berries)==43
(root/"emerald_contests.json").write_text(json.dumps(dict(moves=rows,opponents=opponents,berries=berries),ensure_ascii=False,separators=(",",":"))+"\n")

# Background 3 is a 32×32 GBA tilemap. The audience tiles start at VRAM
# screen block 4, directly after the 256 interface tiles in character block 0.
from PIL import Image
import struct
stage_root = src.parent / "graphics/contest"
interface = Image.open(stage_root / "interface.png")
audience = Image.open(stage_root / "audience.png")
palette = interface.getpalette()
words = struct.iter_unpack("<H", (stage_root / "audience.bin").read_bytes())
backdrop = Image.new("RGB", (256, 256))
for cell, (word,) in enumerate(words):
    tile_id = word & 1023
    sheet = audience if tile_id >= 256 else interface
    tile_id %= 256
    left, top = tile_id % 16 * 8, tile_id // 16 * 8
    tile = sheet.crop((left, top, left + 8, top + 8))
    tile = tile.point([((word >> 12) * 16 + (i % 16)) for i in range(256)])
    tile.putpalette(palette)
    if word & 0x400:
        tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if word & 0x800:
        tile = tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    backdrop.paste(tile.convert("RGB"), (cell % 32 * 8, cell // 32 * 8))
# Extend the original spectator rail for the four simultaneous mobile portraits.
panorama = Image.new("RGB", (448, 88))
for left in (0, 168, 336):
    panorama.paste(backdrop.crop((0, 0, 168, 88)), (left, 0))
for left in range(0, 448, 112):
    panorama.paste(backdrop.crop((56, 40, 168, 88)), (left, 40))
panorama.save(root.parent / "assets/contest_audience.png")

# The blender's rotating center is an affine 8-bit tilemap.
import io
import subprocess
def blender_file(name):
    path = Path("graphics/berry_blender") / name
    entry = src.parent / path
    if entry.exists():
        return entry.read_bytes()
    return subprocess.check_output(["git","-C",str(src.parent),"show","HEAD:"+path.as_posix()])
center = Image.open(io.BytesIO(blender_file("center.png"))).convert("RGBA")
center.putdata([(r,g,b,0 if (r,g,b)==center.getpixel((0,0))[:3] else 255) for r,g,b,_ in center.getdata()])
wheel = Image.new("RGBA", (256,256))
for i, tile in enumerate(blender_file("center_map.bin")):
    x, y = tile % 8 * 8, tile // 8 * 8
    wheel.paste(center.crop((x,y,x+8,y+8)),(i%32*8,i//32*8))
wheel.crop(wheel.getbbox()).save(root.parent / "assets/contest_blender.png")
