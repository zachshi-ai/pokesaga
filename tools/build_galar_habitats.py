"""Mark playable encounter pockets with Emerald long-grass blades in local terrain colors."""
import json
from collections import deque
from pathlib import Path
from PIL import Image

from unova_art import K

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "content/regions/galar/maps"
ART = ROOT / "assets/galar/habitats"
PATCHES = {
    "galar_6": ("dry", [(9, 16, 3, 2), (21, 25, 4, 2), (43, 20, 3, 2)]),
    "galar_8": ("green", [(23, 9, 3, 2), (24, 21, 3, 2), (25, 33, 3, 2)]),
    "galar_9": ("coast", [(8, 7, 3, 2), (30, 14, 3, 2), (34, 30, 3, 2)]),
    "galar_10": ("snow", [(11, 13, 3, 2), (30, 19, 4, 2), (15, 28, 4, 2)]),
    "galar_slope": ("snow", [(24, 12, 4, 2), (34, 27, 4, 2)]),
    "galar_tangle": ("shade", [(9, 14, 3, 2), (34, 9, 3, 2), (34, 15, 2, 2)]),
    "galar_lake_out": ("coast", [(9, 11, 4, 2), (44, 25, 3, 2), (39, 37, 4, 2)]),
}
COLORS = {
    "green": ("#395731","#208658","#9bc88a"), "dry": ("#725a32","#9d813e","#d1b65b"),
    "snow": ("#496772","#7c9c9b","#deefe9"), "shade": ("#264d4b","#408c69","#87bfa2"),
    "coast": ("#536555","#78996b","#b8c993"),
}


def foliage():
    ART.mkdir(parents=True,exist_ok=True)
    atlas=Image.open(ROOT/"assets/unova/tiles.png").convert("RGB")
    index=K["tall"]
    x,y=index%16*16,index//16*16
    tile=atlas.crop((x,y,x+16,y+16))
    for name,tones in COLORS.items():
        colors = {(57,82,0):tones[0],(24,164,106):tones[1],(164,213,197):tones[2]}
        sprite=Image.new("RGBA",(16,16))
        for y in range(16):
            for x in range(16):
                c=colors.get(tile.getpixel((x,y)))
                if c:
                    sprite.putpixel((x,y),(*bytes.fromhex(c[1:]),255))
        sprite.save(ART/(name+".png"))


def habitat(mid,style,patches):
    path=MAPS/(mid+".json")
    m=json.loads(path.read_text())
    tiles=m["tiles"]
    obstacles={tuple(n["at"]) for k in ("npcs","objects","warps") for n in m.get(k,[])}
    spawn=tuple(m["spawn"])
    for e in json.loads((ROOT/"content/galar_later_campaign.json").read_text())["events"]:
        if e["map"]==mid:obstacles.update([tuple(e["at"])]+[tuple(g["at"]) for g in e["guests"]])
    for n in json.loads((ROOT/"content/galar_later_field.json").read_text())["trainers"].get(mid,[]):
        obstacles.add(tuple(n["at"]))
    can={(x,y) for y,row in enumerate(tiles) for x,t in enumerate(row) if t in (0,11)}-obstacles
    reached={spawn}
    queue=deque([spawn])
    while queue:
        x,y=queue.popleft()
        for cell in ((x+1,y),(x-1,y),(x,y-1),(x,y+1)):
            if cell in can and cell not in reached:
                reached.add(cell)
                queue.append(cell)
    props=m["hoenn_art"]["p"]
    props[:]=[p for p in props if "/galar/habitats/" not in p[0]]
    avoid={(p[1],p[2]) for p in props}|obstacles|{spawn}
    cells=set()
    for x,y,rx,ry in patches:
        for dx in range(-rx,rx+1):
            for dy in range(-ry,ry+1):
                c=x+dx,y+dy
                if (dx/rx)**2+(dy/ry)**2<=1 and c in reached and c not in avoid:
                    cells.add(c)
    assert len(cells)>=12,(mid,len(cells))
    for x,y in sorted(cells):
        tiles[y][x]=11
        props.append(["res://assets/galar/habitats/"+style+".png",x,y,[8,16]])
    path.write_text(json.dumps(m,ensure_ascii=False,separators=(",",":"))+"\n")
    print(mid,len(cells))


def build():
    town=MAPS/"galar_turffield.json"
    data=json.loads(town.read_text())
    if not any(o.get("held")=="EVERSTONE" for o in data["objects"]):
        data["objects"].append({"kind":"hidden","at":[30,22],"name":"不变之石","category":"held","held":"EVERSTONE"})
    for obj in data["objects"]:
        if obj.get("kind")=="sign" and "5号道路" in obj.get("text",""):
            obj["text"]="前往5号道路。东南牧场旁的岔路尽头，有石头在草根里发光。"
    town.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n")
    foliage()
    for mid,(style,patches) in PATCHES.items():
        habitat(mid,style,patches)


if __name__=="__main__":
    build()
