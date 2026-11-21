"""Fetch the pinned ORAS field player and illustrated Hoenn panorama, then bake game assets."""
import argparse
import hashlib
import json
import subprocess
import sys
import urllib.parse
from pathlib import Path

from PIL import Image


def verified(url, file, sha):
    if file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest()==sha:
        return file
    data = subprocess.check_output(['curl','--fail','--silent','--show-error','--location','--max-time','45',url])
    if hashlib.sha256(data).hexdigest()!=sha:
        raise ValueError('Source image or model changed: '+url)
    file.parent.mkdir(parents=True,exist_ok=True)
    file.write_bytes(data)
    return file


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache',type=Path,default=Path.home()/'.cache/pokesaga/oras-chart')
    args = parser.parse_args()
    tools = Path(__file__).resolve().parent
    sources = json.loads((tools/'chart_actor_sources.json').read_text())
    model = args.cache/'BrendanOW'
    raw = 'https://raw.githubusercontent.com/{repository}/{revision}/{directory}/'.format(**sources)
    for name,sha in sources['sha256'].items():
        verified(urllib.parse.quote(raw+name,safe=':/'),model/name,sha)
    subprocess.run([sys.executable,str(tools/'render_brendan.py'),str(model)],check=True)
    art = sources['hoenn_art']
    with Image.open(verified(art['source'],args.cache/'hoenn.png',art['sha256'])) as picture:
        dest = tools.parents[1]/'assets/atlas/hoenn_art.webp'
        dest.parent.mkdir(parents=True,exist_ok=True)
        picture.convert('RGB').save(dest,quality=92,method=6)


if __name__=='__main__':
    main()
