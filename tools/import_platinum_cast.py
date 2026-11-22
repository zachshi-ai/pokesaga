"""Build a GBA-sized field atlas from the Platinum cast and Emerald Rogue's Sinnoh redraws."""
import argparse
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GBA = "graphics/object_events/pics"
# The DS textures contain four animation phases per direction (north, south, west, east).
DS_FRAMES = (5, 1, 9, 4, 6, 0, 2, 8, 10, 13, 12, 14)
GBA_FRAMES = (0, 1, 2, 3, 4, 5, 6, 7, 8, 2, 7, 8)


def rgba(path):
    image = Image.open(path)
    if "transparency" not in image.info and image.mode == "P":
        image.info["transparency"] = 0
    return image.convert("RGBA")


def read_gba(path):
    image = rgba(path)
    assert image.size == (144, 32), (path, image.size)
    result = []
    for i, frame in enumerate(GBA_FRAMES):
        cell = image.crop((16*frame, 0, 16*(frame+1), 32))
        result.append(cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if i >= 9 else cell)
    return result


def adapt(path, person, palette):
    image = rgba(path)
    w, h = image.size
    animated = h >= 16*w
    source = [image.crop((0, w*i, w, w*(i+1))) for i in DS_FRAMES] if animated else [image.crop((0, 0, min(w,h), min(w,h)))]*12
    bounds = [frame.getbbox() for frame in source if frame.getbbox()]
    if not bounds:
        return None
    left, top = (min(b[i] for b in bounds) for i in (0,1))
    right, bottom = (max(b[i] for b in bounds) for i in (2,3))
    scale = min((16 if person else 32)/(right-left), (25 if person else 32)/(bottom-top), 1)
    size = (max(1,round((right-left)*scale)),max(1,round((bottom-top)*scale)))
    result = []
    for frame in source:
        frame = frame.crop((left, top, right, bottom)).resize(size,Image.Resampling.NEAREST)
        colors = frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
        colors.putalpha(frame.getchannel("A"))
        cell = Image.new("RGBA",(16 if person else 32,32))
        cell.paste(colors,((cell.width-size[0])//2,32-size[1]))
        result.append(cell)
    return result


def build(platinum, rogue):
    src = platinum/"res/graphics/field_sprites"
    rogue = rogue/GBA
    redraws = {p.stem:p for p in (rogue/"rogue/npc/sinnoh").glob("*.png")}
    redraws.update({n:rogue/p for n,p in {
        "dawn":"people/dawn/walking.png","barry":"rogue/npc/rival/barry.png","looker":"rogue/npc/misc/looker.png",
        "cyrus":"rogue/npc/team/galactic_cyrus.png","grunt_m":"rogue/npc/team/galactic_grunt_m.png",
        "grunt_f":"rogue/npc/team/galactic_grunt_f.png"}.items()})
    sheets = {key:read_gba(path) for key,path in redraws.items()}
    sample = Image.new("RGB",(16,len(sheets)*32))
    for i,frames in enumerate(sheets.values()):
        sample.paste(frames[0],(0,i*32),frames[0])
    palette = sample.quantize(192,method=Image.Quantize.MEDIANCUT)
    for group in ("npc","pokemon","objects"):
        for path in sorted((src/group).glob("*.png")):
            if path.stem in sheets: continue
            frames = adapt(path,group=="npc",palette)
            if frames: sheets[path.stem]=frames
    atlas = Image.new("RGBA",(1536,32*((len(sheets)+3)//4)))
    records = {}
    for index,(key,frames) in enumerate(sorted(sheets.items())):
        x,y = (index%4)*384,(index//4)*32
        records[key]=[x,y,frames[0].width]
        for i,frame in enumerate(frames):
            atlas.paste(frame,(x+i*frame.width,y))
    out=ROOT/"assets/platinum/actors"
    out.mkdir(exist_ok=True,parents=True)
    atlas.save(out/"cast.png",optimize=True)
    (out/"cast.json").write_text(json.dumps(records,sort_keys=True,separators=(",",":"))+"\n")
    print(len(sheets), "field sheets;", len(redraws), "GBA redraws")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platinum",type=Path)
    parser.add_argument("rogue",type=Path)
    args=parser.parse_args()
    build(args.platinum,args.rogue)
