"""Import named GBA field actors from PokemonHnS-Development/pokemonHnS.

Usage: python3 tools/import_johto_cast.py /path/to/pokemonHnS
The source revision and artist credits are in doc/城都角色素材.md. Requires Pillow.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
LEADERS = "falkner bugsy whitney morty chuck jasmine pryce clair brock misty surge erika janine sabrina blaine blue"
ELITE = "will koga bruno karen lance"
SPECIAL = "silver elm eusine kimono kurt prof_oak red_normal bill"
ROCKETS = "proton petrel ariana archer rocket_f rocket_m"
PEOPLE = "mom policeman sage old_man old_man_2 gentleman scientist_m youngster black_belt girl_1 beauty lass nurse woman_2 little_girl"
POKEMON = "ampharos farfetchd sudowoodo electrode shiny_gyarados murkrow slowpoke dragonite raikou entei suicune lugia ho_oh celebi snorlax"
TREE_FRUITS = {"red":"cheri","blue":"chesto","yellow":"aspear","green":"rawst","white":"lum","black":"wiki","pink":"pecha"}


def transparent(path):
    indexed = Image.open(path)
    if indexed.mode != "P":
        raise ValueError(f"Expected a GBA indexed tile sheet: {path}")
    indexed.info["transparency"] = 0
    return indexed.convert("RGBA")


def sheets(root):
    for directory, names in [("people/gym_leaders",LEADERS),("people/elite_four",ELITE),
                            ("people/special",SPECIAL),("people/rockets",ROCKETS),("people",PEOPLE)]:
        for name in names.split():
            sheet = transparent(root/directory/(name+".png"))
            w, h = 16, sheet.height
            if h not in (16,32) or sheet.width < w*3:
                raise ValueError((name,sheet.size))
            yield name, sheet.crop((0,0,min(w*9,sheet.width),h)), w
    for name in POKEMON.split():
        source = transparent(root/"pokemon"/(name+".png"))
        w = source.height
        if source.width not in (w*6,w*8):
            raise ValueError((name,source.size))
        # HnS's sAnimTable_Following has two frames per direction. Normalize to
        # Emerald's nine-slot standard object table, keeping the native silhouettes.
        sheet = Image.new("RGBA",((12 if source.width==w*8 else 9)*w,w))
        for dest,frame in enumerate((0,2,4,1,1,3,3,5,5)):
            sheet.paste(source.crop((w*frame,0,w*(frame+1),w)),(w*dest,0))
        if source.width==w*8:
            for dest,frame in enumerate((6,7,7),9):
                sheet.paste(source.crop((w*frame,0,w*(frame+1),w)),(w*dest,0))
        yield name, sheet, w
    for name, berry in TREE_FRUITS.items():
        tree = transparent(root/"berry_trees"/(berry+".png"))
        # BERRY_STAGE_BERRIES is the fifth stage (the final pair in the sheet).
        yield "fruit_"+name, tree.crop((64,0,80,32)), 16
    tree = transparent(root/"berry_trees/oran.png")
    yield "fruit_empty", tree.crop((0,0,16,32)), 16


def draw_cart():
    """32-pixel GBA rail car with a Spinarak shell, six striped legs and metal wheels."""
    im = Image.new("RGBA",(38,32))
    d = ImageDraw.Draw(im)
    ink,steel,metal = "#33354A","#6A7492","#B6C6D0"
    dark,green,light,lime = "#39704B","#73AB39","#A5CE4A","#DEE76A"
    yellow,gold,red,redlight = "#F7D65A","#B58C42","#B5414A","#F77362"
    def poly(points,fill,outline=ink): d.polygon(points,fill,outline)
    for x in (8,24):
        for y in (8,25):
            poly([(x,y),(x+5,y),(x+5,y+4),(x+4,y+5),(x+1,y+5),(x,y+4)],steel)
            d.line([(x+1,y+2),(x+4,y+2)],metal)
    for x,y in [(7,7),(5,15),(6,22)]:
        for sign in (1,-1):
            def at(offset,dy): return ((x+offset) if sign==1 else 37-x-offset, y+dy)
            poly([at(4,0),at(0,-2),at(-4,-1),at(-5,2),at(-3,5),at(-2,2),at(0,1),at(4,4)],gold)
            d.line([at(-2,0),at(0,0)],yellow);d.point(at(2,1),ink)
    poly([(8,21),(29,21),(29,25),(25,28),(12,28),(8,25)],steel)
    d.line([(12,26),(25,26)],metal)
    poly([(7,11),(9,6),(14,3),(23,3),(28,6),(30,10),(30,20),(27,24),(24,26),(13,26),(9,23),(7,20)],dark)
    poly([(9,11),(11,7),(15,5),(23,5),(27,8),(28,11),(28,18),(25,22),(21,24),(15,23),(10,20)],green,dark)
    poly([(13,6),(22,5),(26,8),(26,10),(23,12),(14,12),(11,10)],light,dark)
    d.line([(14,6),(22,6)],lime)
    poly([(12,9),(15,7),(22,7),(25,9),(23,12),(14,12)],steel)
    d.line([(15,8),(22,8)],metal)
    d.line([(11,16),(13,14),(15,14),(16,15)],dark,width=2)
    d.line([(22,15),(23,14),(25,14),(27,16)],dark,width=2)
    poly([(15,18),(17,20),(20,20),(23,18),(21,22),(16,22)],lime,dark)
    for x in (12,23):
        poly([(x,22),(x+2,22),(x+2,25),(x+1,27),(x,26)],red)
        d.point((x+1,23),redlight)
    poly([(16,4),(19,0),(20,0),(20,4),(18,6)],yellow)
    return im


def build(source, dest):
    sheet_rows = list(sheets(source/"graphics/object_events/pics"))
    atlas = Image.new("RGBA",(max(s.width for _,s,_ in sheet_rows),sum(s.height for _,s,_ in sheet_rows)))
    y, frames = 0, {}
    for name,sheet,width in sheet_rows:
        atlas.paste(sheet,(0,y))
        frames[name] = [y,width,sheet.height,sheet.width//width]
        y += sheet.height
    dest.mkdir(parents=True,exist_ok=True)
    atlas.save(dest/"cast.png",optimize=True)
    (dest/"cast.json").write_text(json.dumps(frames,sort_keys=True,separators=(",",":"))+"\n")
    (dest.parent/"props").mkdir(exist_ok=True)
    draw_cart().save(dest.parent/"props/spinarak_cart.png",optimize=True)
    print(f"{len(frames)} field sheets, {sum(r[3] for r in frames.values())} GBA frame slots")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("--out",type=Path,default=ROOT/"assets/johto_gba/actors")
    args=parser.parse_args()
    build(args.source,args.out)
