#!/usr/bin/env python3
"""Build the Pokédex portrait sheets from rh-hideout/pokeemerald-expansion.

Pin: 759b2a1b8ec279ec923f3c493e6ebed9da2cee3c.
PokeAPI/sprites pin: c0542f7c51215d9672439012838c99f520596cbd.
Use POKESAGA_EMERALD and POKESAGA_SPRITES to select these checkouts. The preprocessor resolves the
original species macros, including named sweets, type palettes and gender art.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image
from asset_paths import project_path, source_path

TILE = 64
COLS = 16
PAGE = COLS * COLS
SOURCE_REV = "759b2a1b8ec279ec923f3c493e6ebed9da2cee3c"
FIELDS = ["frontPic", "palette", "shinyPalette"]


def read_graphics(root):
    headers = sorted((root / "src/data/pokemon/species_info").glob("gen_*_families.h"))
    source = "\n".join(p.read_text() for p in headers)
    # Enable optional families and forms, using the modern (non-GBA) front art.
    switches = sorted(set(re.findall(r"\bP_\w+", source)))
    config = "".join(f"#define {name} {int('GBA_STYLE' not in name)}\n" for name in switches)
    expanded = subprocess.run(["cc", "-E", "-P", "-x", "c", "-"],
                              input=config + source, text=True, check=True,
                              capture_output=True).stdout
    gfx = (root / "src/data/graphics/pokemon.h").read_text()
    gfx = re.sub(r"//[^\n]*|/\*.*?\*/", "", gfx, flags=re.S)
    declarations = re.findall(r'\b(gMon(?:FrontPic|Palette|ShinyPalette)_\w+)\[\]\s*=\s*INCGFX_\w+\("([^"]+)"', gfx)
    files = {}
    for symbol, path in declarations:
        if symbol not in files or "_gba." in files[symbol]:
            files[symbol] = path
    parts = re.split(r"\[SPECIES_([A-Z\d_]+)\]\s*=", expanded)
    species = {}
    for key, block in zip(parts[1::2], parts[2::2]):
        fields = re.findall(r"\.(frontPic(?:Female)?|palette(?:Female)?|shinyPalette(?:Female)?)\s*=\s*(gMon\w+)", block)
        species[key] = {field: files[sym] for field, sym in fields}
        species[key]["dex"] = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", block)[1]
    return species


def portrait(root, paths, spinda_pid=None):
    frame, regular, shiny = (root / p for p in paths)
    with Image.open(frame) as image:
        if image.mode != "P" or image.width != TILE or image.height < TILE:
            raise ValueError(f"Expected an indexed 64px front frame in {frame}")
        indices = image.crop((0, 0, TILE, TILE))
    if spinda_pid is not None:
        # Same first-frame spot masks, anchors and color indices as pokemon_spots.c.
        for i, (x, y) in enumerate([(16, 7), (40, 8), (22, 27), (34, 26)]):
            with Image.open(frame.parent / "spots" / f"spot_{i}.png") as mask:
                pos = (spinda_pid >> (8*i)) & 255
                left, top = x + (pos & 15) - 8, y + (pos >> 4) - 8
                for dy in range(16):
                    for dx in range(16):
                        point = left+dx, top+dy
                        if (mask.getpixel((dx,dy)) and 0 <= point[0] < TILE and 0 <= point[1] < TILE):
                            color = indices.getpixel(point)
                            if 1 <= color <= 3:
                                indices.putpixel(point, color + 4)
    tile_images = []
    for palette in (regular, shiny):
        lines = palette.read_text().strip().splitlines()
        if lines[0] != "JASC-PAL" or not 1 <= int(lines[2]) <= 16:
            raise ValueError(f"Unexpected palette in {palette}")
        colors = [bytes([*map(int, rgb.split()), 255]) for rgb in lines[3:3 + int(lines[2])]]
        colors[0] = bytes(4)
        rgba = b"".join(colors[index & 15] for index in indices.tobytes())
        tile_images.append(Image.frombytes("RGBA", (TILE, TILE), rgba))
    return tile_images


def legacy_key(key):
    aliases = {
        "EEVEE_PARTNER": "EEVEE_STARTER", "UNOWN_A": "UNOWN",
        "BASCULIN_HISUI": "BASCULIN_WHITE_STRIPED",
        "MAGEARNA_ORIGINAL_COLOR": "MAGEARNA_ORIGINAL",
        "ZYGARDE_10": "ZYGARDE_10_AURA_BREAK", "MIMIKYU_TOTEM_BUSTED": "MIMIKYU_BUSTED_TOTEM",
        "ALCREMIE_CARAMEL_SWIRL": "ALCREMIE_STRAWBERRY_CARAMEL_SWIRL",
        "ALCREMIE_RAINBOW_SWIRL": "ALCREMIE_STRAWBERRY_RAINBOW_SWIRL",
    }
    if key in aliases:
        return aliases[key]
    if key.startswith("ALCREMIE_") and key.removeprefix("ALCREMIE_") in SWEETS:
        return key + "_VANILLA_CREAM"
    return key.replace("POKE_BALL", "POKEBALL")


SWEETS = "STRAWBERRY BERRY LOVE STAR CLOVER FLOWER RIBBON".split()
CREAMS = "VANILLA_CREAM RUBY_CREAM MATCHA_CREAM MINT_CREAM LEMON_CREAM SALTED_CREAM RUBY_SWIRL CARAMEL_SWIRL RAINBOW_SWIRL".split()


def fit_frame(path):
    with Image.open(path) as file:
        frame = file.convert("RGBA")
    frame = frame.crop(frame.getbbox())
    frame.thumbnail((TILE - 2, TILE - 2), Image.Resampling.LANCZOS)
    tile = Image.new("RGBA", (TILE, TILE))
    tile.paste(frame, ((TILE - frame.width)//2, (TILE - frame.height)//2))
    return tile


def build(root, sprites, output):
    if subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip() != SOURCE_REV:
        raise ValueError(f"Expected upstream commit {SOURCE_REV}")
    second_rev = subprocess.check_output(["git", "-C", str(sprites), "rev-parse", "HEAD"], text=True).strip()
    if second_rev != "c0542f7c51215d9672439012838c99f520596cbd":
        raise ValueError("Expected the pinned PokeAPI/sprites commit")
    records = read_graphics(root)
    local = json.loads(Path(project_path("content/species.json")).read_text())
    grouped = defaultdict(list)
    for key, record in records.items():
        grouped[record["dex"]].append(key)
    by_id = {}
    for species in local:
        sid, key = species["id"], species["key"]
        dex = {665: "SPEWPA", 666: "VIVILLON"}.get(sid, records.get(key, {}).get("dex", key))
        by_id[dex] = sid
    if len(by_id) != 1025:
        raise ValueError("National Pokédex mapping is incomplete")
    output.mkdir(parents=True, exist_ok=True)
    sheets = []
    hashes = {}
    reusable = {}
    index = defaultdict(dict)

    def register(sid, key, imgs):
        digest = hashlib.sha256(imgs[0].tobytes() + imgs[1].tobytes()).digest()
        if digest not in hashes:
            pos = len(hashes)
            hashes[digest] = pos
            if pos % PAGE == 0:
                sheets.append([Image.new("RGBA", (COLS*TILE, COLS*TILE)) for _ in range(2)])
            corner = ((pos % COLS)*TILE, (pos % PAGE // COLS)*TILE)
            for sheet, img in zip(sheets[-1], imgs):
                sheet.paste(img, corner)
        index[sid][key] = hashes[digest]

    for key, record in records.items():
        sid = by_id[record["dex"]]
        for female in [False, True]:
            if female and not any(f + "Female" in record for f in FIELDS):
                continue
            paths = tuple(record.get(f + "Female", record[f]) if female else record[f] for f in FIELDS)
            name = key + "_FEMALE" if female else key
            if paths in reusable:
                index[sid][name] = reusable[paths]
            else:
                register(sid, name, portrait(root, paths))
                reusable[paths] = index[sid][name]

    for species in local:
        sid, key = species["id"], species["key"]
        canonical = {664: "SCATTERBUG_ICY_SNOW", 665: "SPEWPA_ICY_SNOW", 666: "VIVILLON_MEADOW"}.get(sid, key)
        dex = next(k for k, v in by_id.items() if v == sid)
        if canonical not in index[sid]:
            canonical = grouped[dex][0]
        index[sid][""] = index[sid][canonical]
        if canonical + "_FEMALE" in index[sid]:
            index[sid][dex + "_FEMALE"] = index[sid][canonical + "_FEMALE"]
        for form in species.get("forms", []):
            form_key = form["key"]
            name = legacy_key(form_key)
            if sid == 666:
                name = name.replace("SPEWPA_", "VIVILLON_")
            if name in index[sid]:
                index[sid][form_key] = index[sid][name]
    for sweet in SWEETS:
        for cream in CREAMS:
            index[869]["ALCREMIE_" + cream + "_" + sweet] = index[869]["ALCREMIE_" + sweet + "_" + cream]

    catalog = json.loads(Path(project_path("content/dex_catalog.json")).read_text())["species"]
    spinda = tuple(records["SPINDA"][f] for f in FIELDS)
    register(327, "", portrait(root, spinda, 0x88888888))
    register(327, "SPINDA_SPOTS", portrait(root, spinda, 0x13579BDF))
    sprite_dir = sprites / "sprites/pokemon"
    for text_id, species in catalog.items():
        sid = int(text_id)
        for item in species["variants"]:
            key = item["art_key"]
            if key in index[sid]:
                continue
            alias = legacy_key(key).replace("MEOWSTIC_FEMALE_MEGA", "MEOWSTIC_F_MEGA")
            if alias in index[sid]:
                index[sid][key] = index[sid][alias]
            elif sid in (255, 418, 419) and key.endswith("_FEMALE"):
                # The dimorphism is on the back; show that view for direct inspection.
                register(sid, key, [fit_frame(sprite_dir / "back" / mode / "female" / f"{sid}.png")
                                    for mode in ("", "shiny")])
            elif sid in (1007, 1008):
                sv = sprite_dir / "versions/generation-ix/scarlet-violet"
                register(sid, key, [fit_frame(sv / mode / f"{item['pokeapi_id']}.webp") for mode in ("", "shiny")])
            else:
                raise ValueError(f"Missing art for {sid}: {key}")

    for page, images in enumerate(sheets):
        for prefix, im in zip(("normal", "shiny"), images):
            im.save(output / f"{prefix}_{page}.png", optimize=True)
    manifest = Path(project_path("content/dex_art.json"))
    manifest.write_text(json.dumps(index, sort_keys=True, separators=(",", ":")) + "\n")
    print(f"{len(index)} species, {len(records)} upstream forms, {len(hashes)} distinct portrait pairs, {len(sheets)} sheets per palette")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(source_path("emerald")))
    parser.add_argument("--sprites", type=Path, default=Path(source_path("sprites")))
    args = parser.parse_args()
    build(args.source, args.sprites, Path(project_path("assets/dex")))
