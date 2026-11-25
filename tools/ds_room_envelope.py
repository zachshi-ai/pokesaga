"""Keep DS room underlays and camera limits inside the native scenery and walking floor."""
import base64
from functools import lru_cache
from pathlib import Path
import zlib

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


@lru_cache(512)
def picture_size(uri):
    with Image.open(ROOT / uri.removeprefix("res://")) as image:
        return image.size


def fit_room(doc):
    art = doc["hoenn_art"]
    scene = art.get("scene")
    if not scene or doc.get("unova_technical") or doc.get("platinum_gym") or doc.get("unova_mechanisms"):
        return
    platinum = "platinum_native" in doc
    if platinum:
        if doc["map_type"] != "MAP_TYPE_INDOORS" or doc["id"] in (
            "sinnoh_library", "sinnoh_canalave_library_2f", "sinnoh_canalave_library_3f"
        ):
            return
    elif doc["allow_fly"] or doc["allow_cycling"]:
        return
    width, height = doc["size"]
    path, left, top = scene
    sw, sh = picture_size(path)
    if sw > width*16 or sh > height*16:
        return
    # Projected geometry, native walk permissions and independently sorted props all
    # contribute to the frame. Hallways behind an opaque wall remain reachable.
    mask = np.asarray(doc["physics"]["collision"]) == 0
    ys, xs = np.nonzero(mask)
    if not xs.size:
        return
    bounds = [min(left, int(xs.min())*16), min(top,int(ys.min())*16),
              max(left+sw,(int(xs.max())+1)*16), max(top+sh,(int(ys.max())+1)*16)]
    for prop in art.get("p", []):
        if len(prop)<4 or not isinstance(prop[3], list):
            continue
        # emerald_field positions each prop from the bottom-centred tile plus its anchor.
        sprite, x, y, anchor = prop[:4]
        if not sprite.startswith("res://"):
            sprite = "res://assets/emerald/field/"+sprite+".png"
        pw, ph = picture_size(sprite)
        px, py = x*16+8-anchor[0], (y+1)*16-anchor[1]
        bounds = [min(bounds[0],px),min(bounds[1],py),max(bounds[2],px+pw),max(bounds[3],py+ph)]
    bounds = [max(0,bounds[0]),max(0,bounds[1]),min(width*16,bounds[2]),min(height*16,bounds[3])]
    if bounds != [0,0,width*16,height*16]:
        art["camera_bounds"] = bounds
    if not platinum:
        # The map compiler had stamped a whole DS cell with generic tiles. On small
        # models this exposed wood/rock even outside the walls. Keep native models
        # untouched, and keep underlying floors wherever players can stand or warp.
        grid = np.frombuffer(zlib.decompress(base64.b64decode(art["t"])), dtype="<u2").reshape(height,width).copy()
        keep = mask.copy()
        for warp in doc["warps"]:
            x,y=warp["at"]
            keep[y,x] = True
        if np.any(grid[~keep]):
            grid[~keep]=0
            art["t"] = base64.b64encode(zlib.compress(grid.tobytes(),9)).decode()


if __name__ == "__main__":
    import json
    from collections import Counter
    result=Counter()
    for name in ("platinum_native/maps", "platinum_native/flower", "unova_native/bw", "unova_native/b2"):
        for file in sorted((ROOT/"content"/name).glob("*.json")):
            doc=json.loads(file.read_bytes())
            before=dict(doc["hoenn_art"])
            fit_room(doc)
            if before!=doc["hoenn_art"]:
                for field in ("t","camera_bounds"):
                    if before.get(field)!=doc["hoenn_art"].get(field):result[name,field]+=1
                file.write_text(json.dumps(doc,ensure_ascii=False,separators=(",",":"))+"\n")
    print(result)
