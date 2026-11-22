"""Convert the first game's *own* Nitro scene meshes and matching texture banks to cached GLBs."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import struct
import subprocess
from unova_source import archive

def convert(src, apicula, out):
    models=src.raw_models
    textures=archive(src.bw,'0/1/4')
    areas=list(struct.iter_unpack('<HHBBBBBB',(src.bw/'files/a/0/1/3').read_bytes()))
    def one(pair):
        model,area=pair
        d=out/('%d_%d'%pair)
        if next(d.glob('*.glb'),None):return
        d.mkdir(exist_ok=True,parents=True)
        raw=models[model];off=struct.unpack_from('<I',raw,4)[0]
        (d/'scene.nsbmd').write_bytes(raw[off:off+struct.unpack_from('<I',raw,off+8)[0]])
        (d/'textures.nsbtx').write_bytes(textures[areas[area][1]])
        subprocess.run([str(apicula),'convert',str(d/'scene.nsbmd'),str(d/'textures.nsbtx'),'-f','glb','-o',str(d),'--overwrite'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
    pairs={(int(m),z['area']) for z in src.zones for m in src.blocks(z['i']).values()}
    with ThreadPoolExecutor(8) as pool:list(pool.map(one,pairs))
    src.black_glbs=out
