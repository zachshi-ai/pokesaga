"""Fetch the pinned upstream inputs for the asset pipeline into a sibling directory."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from asset_paths import REPO, source_path

# Restrict large upstream repositories to files used by the production stages.
PATHS = {
    "crystal": ["constants","data","gfx/tilesets","maps"],
    "firered": ["data/layouts","data/maps","data/tilesets","include/constants","graphics/object_events/pics/people"],
    "emerald": ["graphics/items","graphics/pokemon","src/data/graphics","src/data/pokemon","sound/songs/midi"],
    "emerald_original": ["data/maps","data/layouts","data/tilesets","graphics/pokemon",
                         "graphics/battle_environment","graphics/battle_interface","graphics/object_events/pics",
                         "graphics/title_screen","graphics/pokenav/region_map","graphics/bag",
                         "graphics/party_menu","graphics/items"],
    "pokeapi": ["data/v2/csv"],
    "sprites": ["sprites/pokemon/back/female","sprites/pokemon/back/shiny/female",
                "sprites/pokemon/versions/generation-ix/scarlet-violet"],
    "noto": ["Sans/OTF/SimplifiedChinese"],
}


def fetch(name, pin):
    destination = Path(source_path(name))
    if destination.exists():
        head = subprocess.check_output(["git","-C",str(destination),"rev-parse","HEAD"],text=True).strip()
        if head != pin["revision"]:
            raise SystemExit(f"{destination} is at {head}; expected {pin['revision']}. Select another input directory.")
        if not all((destination/p).is_dir() for p in PATHS[name]):
            subprocess.run(["git","-C",str(destination),"sparse-checkout","add",*PATHS[name]],check=True)
        print(f"{name} {head} ({destination})", flush=True)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".source-") as staging:
        checkout = Path(staging)/name
        subprocess.run(["git","init","-q",str(checkout)],check=True)
        def git(*args):
            subprocess.run(["git","-C",str(checkout),*args],check=True)
        git("remote","add","origin",pin["repository"])
        git("sparse-checkout","set","--cone",*PATHS[name])
        git("fetch","--quiet","--depth=1","--filter=blob:none","origin",pin["revision"])
        git("checkout","--quiet","--detach","FETCH_HEAD")
        checkout.rename(destination)
    print(f"{name} {pin['revision']} ({destination})", flush=True)


if __name__ == "__main__":
    sources = json.loads((REPO/"tools/asset_sources.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", metavar="SOURCE", help=", ".join(sources))
    for name in parser.parse_args().names or sources:
        if name not in sources:
            parser.error(f"unknown source: {name}")
        fetch(name,sources[name])
