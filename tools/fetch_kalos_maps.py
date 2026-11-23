#!/usr/bin/env python3
"""Cache the X/Y atlas catalog, town chart and meshopt scenes used by the map baker."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import json
from pathlib import Path
import subprocess
BASE='https://3ds.pzfans.com/static/zones/pokemon-x-and-y/data/'

def fetch(folder,remote):
    local=folder/Path(remote).name
    if not local.is_file():
        temp=local.with_suffix(local.suffix+'.partial')
        subprocess.run(['curl','--fail','--silent','--show-error','--location','--retry','4',
                        '--retry-all-errors','--max-time','90',BASE+remote,'-o',str(temp)],check=True)
        temp.replace(local)
    if remote.endswith('.gzip'):
        with gzip.open(local,'rb') as f:
            if f.read(4)!=b'glTF':raise ValueError('Invalid scene '+str(local))
    return local

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('cache',type=Path);p.add_argument('--jobs',type=int,default=4)
    args=p.parse_args();args.cache.mkdir(exist_ok=True,parents=True)
    catalog=json.loads(fetch(args.cache,'map.json').read_text())
    fetch(args.cache,'townmap.webp')
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        downloaded=list(pool.map(lambda n:fetch(args.cache,f'maps/view-{n}.glb.gzip'),catalog['views']))
    print('Kalos atlas:',len(downloaded),'views,',len(catalog['zones']),'zone records')
if __name__=='__main__':main()
