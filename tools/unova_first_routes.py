"""Bake Emerald-paletted field landmarks along the two Unova starting itineraries."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

from unova_art import encode
from unova_locations import assign
from unova_source import UnovaSource

ROOT=Path(__file__).resolve().parents[1]
OPENING={'bw':{'unova_nuvema','unova_1','unova_accumula','unova_2','unova_striaton','unova_nacrene'},
         'b2':{'unova_aspertia','unova_19','unova_floccesy','unova_20','unova_ranch','unova_virbank',
               'unova_nuvema','unova_1','unova_accumula','unova_2','unova_striaton','unova_nacrene'}}


def native_grass(im, encounter):
    """Place Emerald encounter grass only on visible grass, keeping plants off bridges and roofs."""
    from unova_art import K
    atlas=Image.open(ROOT/'assets/unova/tiles.png').convert('RGBA')
    col,row=K['tall']%16,K['tall']//16
    blade=np.array(atlas.crop((16*col,16*row,16*col+16,16*row+16)))
    # Leave the source patch boundary visible. Only recolour pixels in its green ground plane.
    pixels=np.array(im)
    for y,x in np.argwhere(encounter):
        tile=pixels[16*y:16*y+16,16*x:16*x+16]
        r,g,b=tile[:,:,0].astype(int),tile[:,:,1].astype(int),tile[:,:,2].astype(int)
        green=(g-r>8)&(g-b>5)&(tile[:,:,3]==255)
        if np.count_nonzero(green)<210:continue
        ground=green&(blade[:,:,3]!=0)
        tile[ground]=blade[ground]
    return Image.fromarray(pixels)


def build_existing(bw,b2,black_models):
    from unova_interiors import bake
    sequel=UnovaSource(bw,b2,'b2')
    for era,mids in OPENING.items():
        src=sequel if era=='b2' else UnovaSource(bw,b2,'bw')
        src.companion=sequel
        if era=='bw':src.black_glbs=black_models
        assign(src)
        for mid in sorted(mids):
            path=ROOT/'content/unova_native'/era/(mid+'.json')
            if not path.exists():continue
            doc=json.loads(path.read_text())
            z=src.zones[doc['unova_zone_id']]
            geometry={'z':z,'blocks':src.blocks(z['i']),'size':doc['size'],'origin':doc['unova_origin'],
                      'warps':doc['warps'],'collision':np.array(doc['physics']['collision']),
                      'grass':np.array(doc['physics'].get('grass',[]),dtype=bool)}
            scene=bake(src,geometry)
            if not scene:raise ValueError(f'No native outdoor scene: {era}/{mid}')
            doc['hoenn_art'].update(scene=scene,t=encode(np.zeros(doc['size'][::-1],dtype='uint16')),p=geometry['street_facades'])
            path.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':'))+'\n')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('bw',type=Path);ap.add_argument('b2',type=Path)
    ap.add_argument('black_models',type=Path,help='Original Black GLBs produced by unova_black_models.convert')
    args=ap.parse_args()
    build_existing(args.bw,args.b2,args.black_models)
