"""Bake exact ORAS views first, then matching later Pokémon HOME front views."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image
from asset_paths import project_path, source_path

CELL, COLS = 96, 16
REV = 'c0542f7c51215d9672439012838c99f520596cbd'
MODES = ('','shiny','back','back/shiny')


def candidates(row, number, species, first):
    """Each candidate must identify the exact form, even when multiple forms share one API ID."""
    slug = row['slug']
    stem = species['slug']+'-'
    suffix = slug[len(stem):] if slug.startswith(stem) else ''
    api_id = int(row['pokeapi_id'])
    names = []
    if suffix:
        names.append((False, f'{number}-{suffix}'))
        if suffix=='female':
            names.append((True, str(number)))
    if api_id != number:
        names.append((False,str(api_id)))
    elif first or not suffix:
        names.append((False,str(number)))
    return names


def build(sprites, project):
    rev = subprocess.check_output(['git','-C',str(sprites),'rev-parse','HEAD'],text=True).strip()
    if rev != REV:
        raise ValueError('Use PokeAPI/sprites at '+REV)
    base = sprites/'sprites/pokemon'
    source = base/'versions/generation-vi/omega-ruby-alpha-sapphire'
    home = base/'other/home'
    if not (source/'25.png').is_file() or not (home/'1025.png').is_file():
        raise ValueError('Checkout the ORAS and Pokémon HOME sprite directories first.')
    target = project/'assets/oras/pokemon'
    target.mkdir(parents=True,exist_ok=True)
    listings = json.loads((project/'content/dex_catalog.json').read_text())['species']
    pages, cache, digests, index = [], {}, {}, {}
    feet = []
    source_counts = {'ORAS':0,'HOME':0}

    def slot(path):
        if path in cache:
            return cache[path]
        with Image.open(path) as im:
            frame = im.convert('RGBA')
        bbox = frame.getchannel('A').getbbox()
        if not bbox: return -1
        frame = frame.crop(bbox)
        frame.thumbnail((CELL-6,CELL-6),Image.Resampling.LANCZOS)
        cell = Image.new('RGBA',(CELL,CELL))
        cell.paste(frame,((CELL-frame.width)//2,(CELL-frame.height)//2))
        key = hashlib.sha256(cell.tobytes()).digest()
        if key not in digests:
            pos = len(digests)
            digests[key] = pos
            feet.append((CELL-frame.height)//2+frame.height)
            if pos%(COLS*COLS)==0:
                pages.append(Image.new('RGBA',(CELL*COLS,CELL*COLS)))
            pages[-1].paste(cell,((pos%COLS)*CELL,(pos//COLS%COLS)*CELL))
        cache[path] = digests[key]
        return digests[key]

    for number, species in listings.items():
        sid = int(number)
        forms = {}
        for i, row in enumerate(species['variants']):
            names = candidates(row,sid,species,i==0)
            match = None
            for label, base_dir in (('ORAS',source),('HOME',home)):
                for female, name in names:
                    tail = Path('female' if female else '')/(name+'.png')
                    if (base_dir/tail).is_file():
                        match = (label,base_dir,tail)
                        break
                if match: break
            if not match: continue
            label,base_dir,_ = match
            source_counts[label] += 1
            slots = []
            for mode in MODES:
                candidates_for_view = (base_dir/mode/('female' if f else '')/(name+'.png') for f,name in names)
                view = next((p for p in candidates_for_view if p.is_file()),None)
                slots.append(slot(view) if view else -1)
            if slots[0]<0: continue
            keys = {row['art_key'], *row.get('record_forms',[])}
            if row.get('form'): keys.add(row['form'])
            if i==0: keys.add('')
            for key in keys:
                if key or i==0:
                    forms.setdefault(key,slots)
        if forms: index[number] = forms
    for page, picture in enumerate(pages):
        # Replace the completed page in one rename. A live Godot editor watches this directory.
        with tempfile.NamedTemporaryFile(dir=target,suffix='.tmp',delete=False) as temp:
            temp_path = Path(temp.name)
        try:
            picture.save(temp_path,format='WEBP',lossless=True,method=4)
            temp_path.replace(target/f'{page}.webp')
        finally:
            temp_path.unlink(missing_ok=True)
    (project/'content/oras_pokemon.json').write_text(json.dumps({"forms": index,"feet": feet},sort_keys=True,separators=(',',':'))+'\n')
    print(source_counts, len(index),'species;',len(digests),'unique views')


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sprites',type=Path,default=Path(source_path('sprites')))
    parser.add_argument('--project',type=Path,default=Path(project_path()))
    args = parser.parse_args()
    build(args.sprites,args.project)
