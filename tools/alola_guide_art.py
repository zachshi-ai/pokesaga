"""Dress Brendan in the Trial Guide cap and shirt while retaining the Emerald walk and Surf frames."""
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def dress(name,shift):
    art=np.array(Image.open(ROOT/'assets'/(name+'.png')).convert('RGBA'))
    original=art[:,:,:3].copy()
    yy=np.indices(art.shape[:2])[0]-shift
    for lo,hi,colors in [(8,18,{'dee6ee':'c34a43','ffffff':'f18570','73cd73':'f2c872','4a9452':'993c36','394a7b':'763b43'}),
                         (23,27,{'c54141':'33b5a1','ff625a':'83ddbb','7b4141':'367b77','102039':'264c58'}),
                         (27,29,{'7b4141':'d4dcce','c54141':'b8c9c0','73cd73':'557773'})]:
        for src,dst in colors.items():
            m=(yy>=lo)&(yy<=hi)&(art[:,:,3]>0)&(original==list(bytes.fromhex(src))).all(2)
            art[m,:3]=list(bytes.fromhex(dst))
    Image.fromarray(art).save(ROOT/'assets/alola'/('guide_'+name+'.png'))
if __name__=='__main__':
    dress('player_emerald',0);dress('player_surf',1)
