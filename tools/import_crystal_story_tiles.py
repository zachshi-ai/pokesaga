"""Restore Crystal story corridors from all four 16-pixel quadrants of each room block."""
import json
import re
from pathlib import Path

from asset_paths import project_path, source_path
from render_crystal_maps import load_blockdata, map_profiles, tileset

MAPS = (
    "mahogany_town vermilion_city route_35 route_36 national_park goldenrod_city ilex_forest burned_tower_1f burned_tower_b1_f ecruteak_gym dance_theater "
    "cianwood_gym olivine_lighthouse_2f olivine_lighthouse_3f olivine_lighthouse_4f "
    "olivine_lighthouse_5f olivine_lighthouse_6f team_rocket_base_b1_f team_rocket_base_b2_f "
    "team_rocket_base_b3_f goldenrod_underground goldenrod_underground_switch_room_entrances "
    "goldenrod_underground_warehouse radio_tower_3f radio_tower_4f radio_tower_5f "
    "blackthorn_gym_1f blackthorn_gym_2f dragons_den_b1_f dragon_shrine"
).split()


def write_grid(path, field):
    original = path.read_text()
    style = {"indent":1} if "\n " in original else {"separators":(",",":")}
    path.write_text(json.dumps(field,ensure_ascii=False,**style)+("\n" if original.endswith("\n") else ""))


def main():
    src = Path(source_path("crystal"))
    table = (src/"data/collision/collision_permissions.asm").read_text().splitlines()
    land = {ln.split(";")[-1].strip().removeprefix("COLL_") for ln in table if "db LAND_TILE" in ln}
    for room in MAPS:
        p = Path(project_path(f"content/emerald_maps/johto_{room}.json"))
        field = json.loads(p.read_text())
        w,h = field["size"]
        tile_classes = (src/"data/tilesets"/(field["tileset"]+"_collision.asm")).read_text()
        classes = [ln.partition(";")[0].strip().removeprefix("tilecoll ").split(", ") for ln in tile_classes.splitlines() if ln.strip().startswith("tilecoll ")]
        blocks = load_blockdata(field["map"])
        for y in range(h):
            for x in range(w):
                kinds = classes[blocks[y*w+x]]
                if land.intersection(kinds) and not field['water'][y][x]:
                    field['collision'][y][x]=0
        if room == "dance_theater":
            # The stage side aisles share projected blocks with its front lip.
            for x in (1,4):
                field["ledge"][1][x] = 0
        write_grid(p,field)
    # The radio tower's tile callback replaces the locked shutters. Keep the collision
    # and displayed metatile from the same original block whenever a switch changes.
    name = "GoldenrodUndergroundSwitchRoomEntrances"
    ts = tileset("elite_four_room",*map_profiles()[name])
    script = (src/"maps"/(name+".asm")).read_text()
    doors = []
    for ln in script.splitlines():
        if not ln.strip().startswith("ugdoor_def "): continue
        values = [int(v.replace("$","0x"),0) for v in ln.partition(";")[0].strip()[11:].split(",")]
        cells=[]
        for i in range(0,len(values),4):
            x,y,closed,opened=values[i:i+4]
            cells.append([x//2,y//2,closed,opened])
        doors.append(cells)
    asset_path=Path(project_path("assets/field"))
    asset_path.mkdir(exist_ok=True)
    forest=tileset("forest",*map_profiles()["IlexForest"])
    forest.render(0x17).save(asset_path/"crystal_ilex_cut.png")
    from PIL import Image
    ids=sorted({tile for cells in doors for *_,closed,opened in cells for tile in (closed,opened)})
    atlas=Image.new("RGB",(32*len(ids),32))
    for i,value in enumerate(ids): atlas.paste(ts.render(value),(i*32,0))
    atlas.save(asset_path/"crystal_shutters.png")
    rules={}
    for pos in range(7):
        block=script.split(f".Position{pos}:")[1].split("refreshmap")[0]
        rules[str(pos)]={str(door):kind=="Open" for kind,door in re.findall(r"scall \.(Open|Close)Door(\d+)",block)}
    nav=Path(project_path("content/emerald_maps/johto_goldenrod_underground_switch_room_entrances.json"))
    field=json.loads(nav.read_text())
    for cells in doors:
        for x,y,closed,opened in cells:
            if opened in [0x2d,0x3d] or closed==0x3d:
                field["collision"][y][x]=0
    write_grid(nav,field)
    p=Path(project_path("content/regions/johto/shutters.json"))
    p.write_text(json.dumps({"tiles":ids,"doors":doors,"updates":rules},indent=1)+"\n")


if __name__ == "__main__":
    main()
