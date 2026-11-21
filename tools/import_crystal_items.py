"""Import Crystal's three rod tables, route links and GBC overworld Pokémon."""
import argparse
import json
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def slug(name):
    name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    name = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", name)
    name = re.sub(r"(?<=[a-z])(?=\d)", "_", name)
    return re.sub(r"_(\d)_([A-Z])(?![a-z])", r"_\1\2", name).lower()


def channel_edges(terrain, blocks, layouts, source):
    """Keep the directions that cross a metatile edge in the original 16px collision map."""
    w,h=terrain["size"]
    permissions={}
    for line in (source/"data/collision/collision_permissions.asm").read_text().splitlines():
        match=re.match(r"\s*db (\w+).*?; (?:COLL_)?(\w+)",line)
        if match: permissions[match[2]]=match[1]
    def tile(x,y):
        return layouts[blocks[(y//2)*w+x//2]][(y%2)*2+x%2]
    def can_cross(x,y,dx,dy):
        if not (0<=x+dx<w*2 and 0<=y+dy<h*2): return False
        a,b=tile(x,y),tile(x+dx,y+dy)
        if "WALL_TILE" in (permissions.get(a),permissions.get(b)): return False
        d = {(0,-1):"UP",(0,1):"DOWN",(-1,0):"LEFT",(1,0):"RIGHT"}[(dx,dy)]
        opposite = {"UP":"DOWN","DOWN":"UP","LEFT":"RIGHT","RIGHT":"LEFT"}[d]
        return not (a.endswith("_WALL") and d in a.split("_") or b.endswith("_WALL") and opposite in b.split("_"))
    masks = [[0]*w for y in range(h)]
    for y in range(h):
        for x in range(w):
            for dx,dy,incoming in ((0,1,1),(0,-1,2),(-1,0,4),(1,0,8)):
                edge = [(2*x+i,2*y+int(dy>0)) for i in range(2)] if dy else [(2*x+int(dx>0),2*y+i) for i in range(2)]
                if not any(can_cross(a,b,dx,dy) for a,b in edge):
                    masks[y][x] |= incoming
    terrain["dirblock"]=masks


def tohjo_passages(root,source):
    directory=root/"content/regions/johto/maps"
    cave_path=directory/"johto_tohjo_falls.json"
    coast_path=directory/"johto_route_27.json"
    cave=json.loads(cave_path.read_text())
    coast=json.loads(coast_path.read_text())
    origin=re.findall(r"warp_event\s+(\d+),\s*(\d+), ROUTE_27,", (source/"maps/TohjoFalls.asm").read_text())
    coords=[[int(x)//2,int(y)//2] for x,y in origin]
    entrances=[row for row in coast["warps"] if row["to"]["map"]=="johto_tohjo_falls"]
    assert len(entrances)==len(cave["warps"])==len(coords)==2
    for inside,outside,pos in zip(cave["warps"],entrances,coords):
        inside["at"]=pos
        inside["trigger"]="down"
        outside["to"]["at"]=pos
        outside["to"]["facing"]="up"
    cave["spawn"]=coords[0]
    for path,room in [(cave_path,cave),(coast_path,coast)]:
        text=path.read_text()
        fmt={"indent":1} if text.startswith("{\n") else {"separators":(",",":")}
        path.write_text(json.dumps(room,ensure_ascii=False,**fmt)+("\n" if text.endswith("\n") else ""))


def sea_connections(root):
    # Route 41 and Cianwood share a full-height edge. Route 40 is offset by 15
    # metatiles to the east. Landing on the nearest land broke the islands' buoy rings.
    directory=root/"content/regions/johto/maps"
    for room in ("cianwood_city","route_40","route_41"):
        path=directory/("johto_"+room+".json")
        text=path.read_text()
        data=json.loads(text)
        for warp in data["warps"]:
            if not warp.get("edge"): continue
            target=warp["to"]
            x,y=warp["at"]
            if room=="cianwood_city" and target["map"]=="johto_route_41": landing=[0,y]
            elif room=="route_40" and target["map"]=="johto_route_41": landing=[x+15,0]
            elif room=="route_41" and target["map"]=="johto_cianwood_city": landing=[13,y]
            elif room=="route_41" and target["map"]=="johto_route_40": landing=[x-15,16]
            else: continue
            target["at"]=landing
            target["sea_connection"]=True
        fmt={"indent":1} if text.startswith("{\n") else {"separators":(",",":")}
        path.write_text(json.dumps(data,ensure_ascii=False,**fmt)+("\n" if text.endswith("\n") else ""))


def import_water_obstacles(source, root):
    # The game's grid uses one 32px Crystal metatile per step. The source whirlwind
    # occupies one quadrant of a buoy channel; a waterfall fills the entire block.
    definitions = {}
    for ts in ("johto","cave","dark_cave"):
        raw = (source/"data/tilesets"/(ts+"_collision.asm")).read_text()
        definitions[ts] = [line.split(";",1)[0].strip().split(" ",1)[1].strip().split(", ")
                           for line in raw.splitlines() if line.lstrip().startswith("tilecoll ")]
    updates = {}
    for path in sorted((root/"content/emerald_maps").glob("johto_*.json")):
        terrain = json.loads(path.read_text())
        layouts = definitions.get(terrain.get("tileset"))
        if layouts is None: continue
        file = source/"maps"/(terrain["map"]+".blk")
        if not file.exists(): continue
        w, h = terrain["size"]
        blocks = file.read_bytes()
        if len(blocks)!=w*h: continue
        for kind, name in (("WHIRLPOOL","whirl"),("WATERFALL","waterfall")):
            cells = [(i%w,i//w) for i,b in enumerate(blocks) if kind in layouts[b]]
            if not cells: continue
            grid = [[0]*w for y in range(h)]
            for x,y in cells:
                grid[y][x]=1
                terrain["water"][y][x]=1
            terrain[name]=grid
            updates.setdefault(path.stem,{})[name]=cells
        if path.stem in ("johto_tohjo_falls","johto_dragons_den_b1_f","johto_route_41"):
            channel_edges(terrain,blocks,layouts,source)
        if path.stem in updates:
            path.write_text(json.dumps(terrain, ensure_ascii=False, separators=(",",":")))
    tohjo_passages(root,source)
    sea_connections(root)
    return updates


def build(source, root):
    print("Crystal field obstacles:", import_water_obstacles(source,root))
    species = {s["key"]: s["id"] for s in json.loads((root / "content/species.json").read_text())}
    move_ids = {m["key"].replace("_", ""): m["id"] for m in json.loads((root / "content/moves.json").read_text())}
    tm_file = root / "content/tm_map.json"
    tm_map = json.loads(tm_file.read_text())
    machines = re.findall(r"^\s*add_tm (\w+)", (source / "constants/item_constants.asm").read_text(), re.M)
    assert len(machines) == 50
    for number, name in enumerate(machines, 1):
        key = ("PSYCHIC" if name == "PSYCHIC_M" else name).replace("_", "")
        tm_map[f"城都招式学习器 {number:02}"] = move_ids[key]
    tm_map["城都秘传学习器 06"] = move_ids["WHIRLPOOL"]
    tm_file.write_text(json.dumps(tm_map, ensure_ascii=False, indent=1)+"\n")
    data = (source / "data/wild/fish.asm").read_text()
    names = re.findall(r"^\s*const FISHGROUP_(\w+)", (source / "constants/map_data_constants.asm").read_text(), re.M)[1:]
    times = [(species[m[0]], int(m[1]), species[m[2]], int(m[3])) for m in re.findall(
        r"db (\w+),\s*(\d+),\s*(\w+),\s*(\d+)", data.split("TimeFishGroups:")[1])]
    pools = {}
    pending = []
    for line in data.split("TimeFishGroups:")[0].splitlines():
        label = re.fullmatch(r"\.(\w+):", line.strip())
        if label:
            pending.append(label[1])
            last = 0
        row = re.search(r"db\s+(\d+) percent(?: \+ 1)?,\s*(?:(\w+),\s*(\d+)|time_group (\d+))", line)
        if row:
            current = int(row[1])
            if row[4]:
                day, dl, night, nl = times[int(row[4])]
            else:
                day, dl = species[row[2]], int(row[3])
                night, nl = day, dl
            for pool in pending:
                pools.setdefault(pool, []).append([current - last, day, dl, night, nl])
            last = current
            if current == 100:
                pending.clear()
    groups = [[a, b, c] for a, b, c in re.findall(r"fishgroup [^,]+,\s*\.(\w+),\s*\.(\w+),\s*\.(\w+)", data)]
    assert len(groups) == len(names) and all(sum(row[0] for row in pools[t]) == 100 for row in groups for t in row)
    maps = {slug(m[0]): m[1] for m in re.findall(r"^\s*map (\w+),[^\n]+FISHGROUP_(\w+)",
                                              (source / "data/maps/maps.asm").read_text(), re.M) if m[1] != 'NONE'}
    roams = {}
    for line in (source/"data/wild/roammon_maps.asm").read_text().splitlines():
        if line.strip().startswith("roam_map ROUTE"):
            ids = re.findall(r"ROUTE_(\d+)",line)
            roams[ids[0]] = [int(i) for i in ids[1:]]
    out = root / "content/regions/johto/items_water.json"
    out.write_text(json.dumps(dict(maps=maps, groups=dict(zip(names,groups)), pools=pools, roaming=roams),
                              separators=(",",":"),ensure_ascii=False)+"\n")
    by_slug = {s["key"].lower().replace("_", ""): s["id"] for s in json.loads((root / "content/species.json").read_text())}
    weights = {}
    for entry in sorted((source / "data/pokemon/dex_entries").glob("*.asm")):
        raw = re.search(r"dw \d+,\s*(\d+) ; height, weight", entry.read_text())
        name = entry.stem.replace("_","")
        if raw and name in by_slug:
            weights[str(by_slug[name])] = round(int(raw[1]) * 0.045359237, 1)
    (out.parent/"weights.json").write_text(json.dumps(weights, separators=(",",":"))+"\n")
    # Crystal's front-facing 16px sprites use four grey indices. The first is transparent.
    colors = {"suicune": ([255,189,140],[82,123,214]), "raikou": ([255,222,114],[140,94,49]),
              "entei": ([255,189,140],[197,89,80]), "ho_oh": ([255,204,119],[206,89,66]),
              "lugia": ([239,231,229],[123,142,222]), "fruit_tree": ([161,205,109],[85,139,82])}
    for name, (light, mid) in colors.items():
        folder = "gfx/icons" if name in ("ho_oh","lugia") else "gfx/sprites"
        img = Image.open(source / folder / (name+".png")).convert("L").crop((0,0,16,16))
        art=Image.new("RGBA",img.size)
        art.putdata([(0,0,0,0) if v>220 else (*light,255) if v>125 else (*mid,255) if v>50 else (30,31,45,255)
                     for v in img.getdata()])
        art.save(root / "assets/npc" / ("cr_apricorn_tree.png" if name=="fruit_tree" else "crystal_"+name+".png"))


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    parser.add_argument("--project",type=Path,default=ROOT)
    args=parser.parse_args()
    build(args.source,args.project)
