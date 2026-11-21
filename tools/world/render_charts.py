"""Draw PokéNav-style pixel charts around the game's registered map coordinates."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SIZE = (240, 168)
W, H = SIZE
Y, X = np.mgrid[0:H, 0:W]
X = X / W
Y = Y / H


def noise(rng, nx, ny):
    raw = rng.uniform(0, 255, (ny, nx)).astype('uint8')
    return np.asarray(Image.fromarray(raw).resize(SIZE, Image.Resampling.BICUBIC)) / 255 - .5


def chart(key, hills):
    rng = np.random.default_rng(int(hashlib.sha256(key.encode()).hexdigest()[:8], 16))
    coast = noise(rng, 21, 16) * .30 + noise(rng, 52, 37) * .10
    heights = np.full((H, W), -2.)
    for x, y, rx, ry in hills:
        angle = rng.uniform(-1.1, 1.1)
        u = ((X-x)*np.cos(angle) + (Y-y)*np.sin(angle)) / rx
        v = ((Y-y)*np.cos(angle) - (X-x)*np.sin(angle)) / ry
        heights = np.maximum(heights, 1 - np.sqrt(u*u + v*v))
    heights += coast
    # Keep the GBA chart's alternating sea scanlines, stepped coast and flat
    # elevation bands. The overlays in atlas_chart.gd share these coordinates.
    levels = np.zeros((H, W), dtype=np.uint8)
    levels[1::2] = 1
    relief = heights + noise(rng, 13, 10)*.70
    levels[heights > -.18] = 2
    levels[heights > -.08] = 3
    land = heights > 0
    levels[land] = 4
    for threshold, index in [(0.07,5),(.26,6),(.44,7),(.62,8),(.78,9),(.91,10)]:
        levels[land & (relief > threshold)] = index
    colors = [(95,157,218),(115,181,225),(137,203,228),(183,224,226),
              (41,122,79),(75,163,77),(113,183,78),(155,201,80),
              (187,208,101),(213,180,90),(232,202,125)]
    image = Image.fromarray(np.array(colors, dtype=np.uint8)[levels])
    image.save(ROOT/'assets/atlas'/f'{key}.webp', lossless=True, method=6)


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
