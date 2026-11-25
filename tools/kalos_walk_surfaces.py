"""Supply a surface under XY's raised, projected meshes wherever a player can stand."""

import base64
import json
from pathlib import Path
import zlib

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[1]
VOID=(39,45,54)
WEB=(34,64,59)


def tiles(pic, shape):
    h,w=shape
    step=pic.width//w
    assert (w*step,h*step)==pic.size
    return np.asarray(pic.convert("RGB")).reshape(h,step,w,step,3).transpose(0,2,1,3,4)


def support_web(pic, walk):
    """Mark the cardinal turns that the original diagonal silk stroke misses."""
    source=tiles(pic,walk.shape)
    missing=walk & (source==WEB).all((2,3,4))
    if not missing.any(): return pic
    result=pic.copy()
    d=ImageDraw.Draw(result)
    for y,x in np.argwhere(missing):
        cx,cy=int(x)*16+8,int(y)*16+8
        for dx,dy in [(0,-1),(0,1),(-1,0),(1,0)]:
            nx,ny=x+dx,y+dy
            if 0<=ny<walk.shape[0] and 0<=nx<walk.shape[1] and walk[ny,nx]:
                d.line((cx,cy,cx+dx*12,cy+dy*12),fill="#8c935f",width=4)
                d.line((cx,cy-1,cx+dx*12,cy-1+dy*12),fill="#c9c47c",width=2)
    return result


def extend_ground(pic,m):
    """Restore only void pixels on dry walking cells, with a local surface of the
    same underlying metatile. Collision, encounter masks and set-piece silhouettes
    remain available to distinguish forest ground, banks, and stone corridors."""
    solid=np.asarray(m["physics"]["collision"],bool)
    walk=~solid & ~np.asarray(m["physics"].get("water",np.zeros_like(solid)),bool)
    source=tiles(pic,walk.shape)
    px=source.shape[2]
    # All zero-material pixels in the raster share the same ink. Require a
    # majority void footprint: individual dark edges and line art stay intact.
    void=(source==VOID).all(-1)
    missing=walk & (void.sum((2,3))>px*px//2)
    if not missing.any(): return pic,0
    available=walk & ~void.any((2,3))
    if not available.any():raise ValueError((m["id"],"no visible floor"))
    kinds=np.frombuffer(zlib.decompress(base64.b64decode(m["hoenn_art"]["t"])),"<u2").reshape(walk.shape)
    # Prefer a grounded interior tile with its four neighbouring cells on the
    # same floor, keeping projected roofs and cliffs off the walking strip.
    inner=ndimage.binary_erosion(available)
    rgb=np.asarray(pic.convert("RGB")).copy()
    out=rgb.reshape(solid.shape[0],px,solid.shape[1],px,3).transpose(0,2,1,3,4)
    for kind in np.unique(kinds[missing]):
        same=available & (kinds==kind)
        candidates=same & inner
        if not candidates.any():candidates=same if same.any() else available
        iy,ix=ndimage.distance_transform_edt(~candidates,return_distances=False,return_indices=True)
        for y,x in np.argwhere(missing & (kinds==kind)):
            mask=void[y,x]
            out[y,x][mask]=source[iy[y,x],ix[y,x]][mask]
    return Image.fromarray(rgb),int(missing.sum())


def bake_existing():
    seen=set()
    for p in sorted((ROOT/'content/regions/kalos/maps').glob('*.json')):
        m=json.loads(p.read_bytes())
        path=m.get("hoenn_art",{}).get("scene",[""])[0]
        if path in seen:continue
        seen.add(path)
        path=ROOT/path.removeprefix('res://')
        if path.stem!="gba_gym_56" and not path.stem.startswith('field_'):continue
        if "physics" not in m:continue
        with Image.open(path) as source:
            # Fast test all single-palette scenes from the signed project.
            if path.stem=="gba_gym_56":
                pic=support_web(source.convert("RGB"),~np.asarray(m["physics"]["collision"],bool));n=1
            else:
                pal=source.getpalette() or []
                if not any(tuple(pal[i:i+3])==VOID for i in range(0,len(pal),3)):continue
                pic,n=extend_ground(source,m)
            if n:
                # Reuse the identical palette, retaining fitted furniture and markers pixel for pixel.
                pic.quantize(palette=source,dither=Image.Dither.NONE).save(path,optimize=True)
                print(m["id"],n,flush=True)

if __name__=="__main__":bake_existing()
