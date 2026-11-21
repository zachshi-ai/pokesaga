"""Render bathymetry and shaded relief around the game's registered map coordinates."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SIZE = (750, 570)
W, H = SIZE
Y, X = np.mgrid[0:H, 0:W]
X = X / W
Y = Y / H


def noise(rng, nx, ny):
    raw = rng.uniform(0, 255, (ny, nx)).astype('uint8')
    return np.asarray(Image.fromarray(raw).resize(SIZE, Image.Resampling.BICUBIC)) / 255 - .5


def chart(key, hills):
    rng = np.random.default_rng(int(hashlib.sha256(key.encode()).hexdigest()[:8], 16))
    coast = noise(rng, 17, 13) * .24 + noise(rng, 55, 40) * .075
    fine = noise(rng, 127, 89)
    elevation = np.full((H, W), -2.)
    for x, y, rx, ry in hills:
        angle = rng.uniform(-1.1, 1.1)
        dx, dy = X-x, Y-y
        u = (dx*np.cos(angle)+dy*np.sin(angle))/rx
        v = (dy*np.cos(angle)-dx*np.sin(angle))/ry
        elevation = np.maximum(elevation, 1 - np.sqrt(u*u + v*v))
    elevation += coast + fine*.035
    peaks = np.maximum(0, elevation + noise(rng, 25, 19)*.62)
    colors = np.array([[18,76,113],[30,110,147],[66,162,179],[131,204,202],
                       [226,223,173],[171,198,135],[109,165,116],[79,135,108],
                       [145,157,127],[209,201,168],[237,234,210]])
    levels = [-1.1,-.55,-.23,-.05,0,.06,.22,.42,.61,.80,.99]
    height = np.where(elevation > .045, np.maximum(.046, .68*elevation+.32*peaks),elevation)
    image = np.stack([np.interp(height, levels, colors[:, i]) for i in range(3)], axis=-1)
    dy, dx = np.gradient(height)
    shade = np.where(elevation>0, np.clip(-(dx*1700+dy*2100),-24,24), 0)
    image += (shade + fine * 4)[:,:,None]
    for depth in (-.12,-.34,-.59):
        image[np.abs(elevation-depth)<.006] += 9
    grid = ((np.mod(np.arange(W), W/12)<1)[None,:] | (np.mod(np.arange(H), H/9)<1)[:,None])
    image[grid & (elevation<-.07)] += 7
    output = ROOT/'assets/atlas'/f'{key}.webp'
    Image.fromarray(np.uint8(np.clip(image,0,255))).save(output, quality=87, method=6)


def main():
    graph = json.loads((ROOT/'content/world_graph.json').read_text())
    sw, sh = graph['plate']['size']
    radius = {'sinnoh':(.103,.085),'kanto':(.101,.062),'johto':(.099,.073),
              'hoenn':(.098,.084),'alola':(.064,.038),'paldea':(.083,.079)}
    # Coastal spurs, volcanic islands and mountain chains give each silhouette its own form.
    spurs = {
        'galar':[(-.5,-1.1,.6,.9),(.2,-1.65,.43,.49),(.25,1.0,.55,.72),(-.95,-.3,.3,.4)],
        'kalos':[(-.7,-.53,.71,.53),(.73,-.8,.6,.6),(.3,.68,.75,.52)],
        'paldea':[(-.7,.32,.7,.64),(.63,.3,.76,.72),(-.2,1.0,.67,.55)],
        'unova':[(-.69,-.82,.74,.67),(.36,-.76,.73,.71),(.86,-.87,.53,.68),(.5,1,.45,.73)],
        'alola':[(-.97,-1.06,.48,.64),(.98,.91,.66,.86),(1.70,1.8,.56,.85),(-1.77,-1.51,.38,.51)],
        'sinnoh':[(-.6,-.65,.65,.73),(.21,-1.03,.61,.98),(1.01,-.35,.74,.44),(.41,.78,.62,.65)],
        'johto':[(-.64,.14,.76,.63),(.7,-.5,.84,.73),(-.92,.92,.3,.39)],
        'kanto':[(-.58,-.55,.77,.69),(.58,-.48,.68,.59),(.67,.52,.43,.41)],
        'hoenn':[(-.45,-.65,.75,.66),(.31,-.74,.85,.47),(.95,-.22,.38,.35),(1.38,.38,.28,.29),(-.73,.8,.3,.38)]}
    masses = []
    for key,region in graph['regions'].items():
        cx,cy = region['at'][0]/sw,region['at'][1]/sh
        rx,ry = radius.get(key,(.089,.071))
        # Smaller interlocking hills form coves and headlands.
        rx,ry = rx*.78,ry*.80
        masses.append((cx,cy,rx,ry))
        masses.extend((cx+ox*rx,cy+oy*ry,hx*rx,hy*ry) for ox,oy,hx,hy in spurs[key])
    # The world chart is project geography. The real routes are overlaid in Godot.
    insets = json.loads((ROOT/'content/atlas_insets.json').read_text())
    for region in graph['specials']:
        if region['kind'] == 'island':
            x,y = insets[region['id']]
            masses.append((x/100,y/100,.034,.023))
    chart('world', masses)
    catalog = ROOT/'content/world_destinations.json'
    if catalog.exists():
        for key, region in json.loads(catalog.read_text())['regions'].items():
            towns = [n for n in region['locations'] if n['kind'] in ('city','town','landmark')]
            terrain = towns if len(towns)>3 else region['locations']
            hills = [(p['pos'][0]/100,p['pos'][1]/100,.18,.16) for p in terrain]
            chart(key, hills)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,default=ROOT)
    ROOT = parser.parse_args().project.resolve()
    (ROOT/'assets/atlas').mkdir(parents=True,exist_ok=True)
    main()
