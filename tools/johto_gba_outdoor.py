#!/usr/bin/env python3
"""Rebuild GBA art on the native Johto tile, collision and door coordinates.

First run tools/hgss_render on the map catalog to export the annotated
HGSS surfaces. Provide the local Emerald, FireRed and HnS sources to this CLI.
The optional positional list regenerates individual maps.
"""

import argparse
import base64
from functools import lru_cache
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image

from bake_emerald_field import Emerald, TOWN, CAVE, ICE, normalized
from johto_gba_landmarks import FireRed, generate

ROOT = Path(__file__).resolve().parents[1]
HGSS = ROOT / "content/hgss"
OUT = ROOT / "assets/johto_gba"
PROPS = ROOT / "assets/emerald/field"
EXTRA = {"MAP_ILEX_FOREST", "MAP_VIRIDIAN_FOREST", "MAP_MOUNT_SILVER_CAVE_SUMMIT", "MAP_BELL_TOWER_ROOF"}


def outdoor(hid, h):
    return h["matrix_id"] == 0 or h["map_type"] in {"MAP_TYPE_CITY_TOWN", "MAP_TYPE_ROUTE"} or hid in EXTRA


class Hns(Emerald):
    """HnS config reserves 640 character/metatile addresses and 7 primary palettes."""

    @lru_cache(None)
    def tileset(self, name):
        path = self.dirs[normalized(name.removeprefix("gTileset_"))]
        image = np.array(Image.open(path / "tiles.png"))
        tiles = (
            image.reshape(image.shape[0] // 8, 8, image.shape[1] // 8, 8)
            .transpose(0, 2, 1, 3)
            .reshape(-1, 8, 8)
        )
        entries = np.fromfile(path / "metatiles.bin", "<u2").reshape(-1, 8)
        pals = {}
        for f in (path / "palettes").glob("*.pal"):
            if not f.stem.isdigit():
                continue
            colors = np.array(
                [[*map(int, line.split()), 255] for line in f.read_text().splitlines()[3:19]], np.uint8
            )
            colors[0, 3] = 0
            pals[int(f.stem)] = colors
        return tiles, entries, pals

    @lru_cache(None)
    def tile(self, primary, secondary, mid, upper_only=False):
        banks = [self.tileset(primary), self.tileset(secondary)]
        entries = banks[int(mid >= 640)][1][mid % 640]
        out = Image.new("RGBA", (16, 16))
        for i, entry in enumerate(entries):
            if upper_only and i < 4:
                continue
            n = int(entry)
            addr = n & 1023
            bank = 1 if addr >= 640 else 0
            chips = banks[bank][0]
            k = addr - bank * 640
            if k >= len(chips):
                continue
            chip = chips[k]
            pal = n >> 12
            colors = banks[int(pal >= 7)][2].get(pal)
            if colors is None:
                continue
            if n & 1024:
                chip = chip[:, ::-1]
            if n & 2048:
                chip = chip[::-1]
            out.alpha_composite(Image.fromarray(colors[chip & 15]), ((i % 2) * 8, (i % 4 // 2) * 8))
        return out


@lru_cache(None)
def climb_wall(emerald, behavior):
    # Rough ledges use the Emerald stone palette, with staggered handholds
    # drawn along the permitted axis in the original 16px tile.
    block = emerald.metatile("FallarborTown", 0x265).copy()
    from PIL import ImageDraw
    draw = ImageDraw.Draw(block)
    for x, y in ((3, 2), (8, 6), (4, 11)):
        draw.line((x, y+1, x+3, y+1), fill=(82, 66, 58, 255))
        draw.line((x+1, y, x+4, y), fill=(231, 206, 165, 255))
    return block if behavior==75 else block.transpose(Image.Transpose.ROTATE_90)


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")


@lru_cache(None)
def semantic(path):
    return json.loads(path.read_text())


def floor_kind(mat, rgb, word, city, snow):
    behavior = word & 255
    solid = word & 32768
    r, g, b = rgb
    if behavior == 19:
        return "waterfall"
    if behavior in (56, 57, 58, 59):
        return "ledge_" + str(behavior)
    if behavior in (16, 17, 18, 20, 21, 25, 42, 80, 81, 82, 83, 115, 120, 124):
        return "water"
    if behavior in (2, 3):
        return "tall"
    if behavior == 32:
        return "ice"
    if behavior == 33:
        return "sand"
    if behavior == 168 or snow or any(n in mat for n in ["yuki", "snow"]):
        return "snow"
    if "flower" in mat and not solid:
        return "flowers"
    if any(n in mat for n in ["bridge", "deck", "pier", "sanjyo"]):
        return "bridge"
    if "cavehole" in mat:
        return "cave"
    if any(n in mat for n in ["cliff", "wall", "peak", "slope", "kabe", "stone", "iwa", "rock"]) and (
        "water" not in mat
    ):
        return "cliff" if solid else "rockfloor"
    if any(n in mat for n in ["fence", "hei0"]):
        return "fence" if solid else "grass"
    if any(n in mat for n in ["road", "miti", "_rd0", "_r0", "track", "fieldkk"]) and not ("grass" in mat):
        if r + 9 < g and b < g:
            return "grass"
        return "pave" if city and max(rgb) - min(rgb) < 44 else "trail"
    if any(n in mat for n in ["beach", "sand"]):
        return "sand"
    if any(n in mat for n in ["sea_", "pond_", "sea0", "wave", "water", "river"]):
        return (
            "water"
            if solid and behavior not in range(94, 113)
            else ("bridge" if not solid and b > r * 1.35 and b > g * 1.10 else "grass")
        )
    if any(n in mat for n in ["grass", "tree", "wood", "momi", "ueki", "siba"]):
        return "grass"
    if city and r > 0 and max(rgb) - min(rgb) < 35:
        return "pave"
    if r > g * 1.04 and r > b * 1.25:
        return "trail" if not solid else "rockfloor"
    return "grass"


@lru_cache(None)
def asset(name):
    return Image.open(PROPS / (name + ".png")).convert("RGBA")


def prop_kind(dest):
    name = dest.lower()
    if "house" in name and "players_house" not in name:
        return "home"
    if "pokemon_center" in name or "pokecenter" in name:
        return "center"
    if "mart" in name or "shop" in name:
        return "mart"
    if "gym" in name or "dojo" in name:
        return "gym"
    if "lab" in name or "research" in name:
        return "lab"
    if any(n in name for n in ["mart", "department_store"]):
        return "mart"
    if any(
        n in name
        for n in [
            "tower",
            "museum",
            "station",
            "radio",
            "department",
            "building",
            "mansion",
            "office",
            "academy",
            "league",
            "power_plant",
        ]
    ):
        return "academy"
    if any(
        n in name for n in ["cave", "tunnel", "path", "ruins", "well", "island", "passage", "mt_", "mount_"]
    ):
        return "cave"
    return "home"


AUTOTILES = {
    "trail": [[0x118, 0x119, 0x11A], [0x120, 0x121, 0x122], [0x128, 0x129, 0x12A]],
    "water": [[0xB0, 0xB1, 0xB2], [0xB8, 0xA1, 0xBA], [0xC8, 0xC9, 0xCA]],
    "cliff": [[104, 105, 106], [112, 113, 114], [120, 121, 122]],
}
TILES = {
    "waterfall": (TOWN, 0xB9),
    "ledge_56": (TOWN, 0x86),
    "ledge_57": (TOWN, 0x85),
    "ledge_58": (TOWN, 0x8F),
    "ledge_59": (TOWN, 0x8F),
    "grass": (TOWN, 1),
    "tall": (TOWN, 0xD),
    "flowers": (TOWN, 4),
    "pave": ("RustboroCity", 0x2BB),
    "sand": (TOWN, 0x121),
    "fence": (TOWN, 0x1B),
    "cliff": (CAVE, 0x211),
    "rockfloor": (CAVE, 0x201),
    "bridge": ("FortreeCity", 0x297),
    "cave": (CAVE, 0x201),
    "snow": (ICE, 0x381),
    "ice": (ICE, 0x38D),
}


def render(mid, field, header, materials, e, anchors, fr, custom, hns):
    out = OUT / "maps" / mid
    out.mkdir(exist_ok=True, parents=True)
    w, h = field["size"]
    words = np.frombuffer(base64.b64decode(field["terrain"]), "<u2").reshape(h, w)
    kind = np.full((h, w), "empty", dtype=object)
    trees = {}
    props = []
    occupied = set()
    parts = []
    city = header["map_type"] == "MAP_TYPE_CITY_TOWN"
    snow = "SILVER_CAVE_SUMMIT" in field["header"]
    for col, row, key in field["parts"]:
        section = semantic(materials / (key.replace(":", "_") + ".json"))
        names = section["materials"]
        parts.append((col, row))
        for i, (mat, r, g, b) in enumerate(section["surface"]):
            x = col + i % 32
            y = row + i // 32
            kind[y, x] = floor_kind(names[mat], (r, g, b), int(words[y, x]), city, snow)
        for tx, tz, name in section["foliage"]:
            # DS renders a second backs-facing crown material on the very same trees.
            if "_un" in name or "shadow" in name:
                continue
            tx += col * 16
            tz += row * 16
            trees[(round(tx / 16), round(tz / 16))] = (tx, tz)
        for id, name, at, lo, hi in section["props"]:
            props.append((name, at[0] + col * 16, at[2] + row * 16, lo, hi))
    art = []
    buildings = []
    houses = []

    def place(name, x, y, baseline=None, tag=None):
        if name in custom:
            source = custom[name]
            anchor = source["anchor"]
            width, height = source["size"]
            path = source["path"]
        else:
            anchor = anchors[name]
            width, height = asset(name).size
            path = "res://assets/emerald/field/" + name + ".png"
        left = round(x - anchor[0])
        top = round(y - anchor[1])
        art.append({"png": path, "at": [left, top], "sort_y": int(baseline if baseline is not None else y) - 1})
        return (left, top, left + width, top + height)

    for warp in field["warps"]:
        if mid == "johto_new_bark_town" and warp["to"]["map"] == "johto_elms_house":
            x, y = warp["at"]
            place("elm_stairs", (x + 0.5) * 16, (y + 1) * 16, (y + 2) * 16)
            continue
        if warp.get("edge"):
            continue
        direction = warp.get("trigger", "step")
        if direction not in ("door", "up", "down", "left", "right"):
            continue
        x, y = warp["at"]
        dest = warp["to"]["map"]
        name = prop_kind(dest)
        specials = [
            ("burned_tower", "burned_tower"),
            ("sprout_tower", "sprout_tower"),
            ("bell_tower", "bell_tower"),
            ("tin_tower", "bell_tower"),
            ("radio_tower", "radio_tower"),
            ("lighthouse", "lighthouse"),
            ("train_station", "goldenrod_station"),
            ("magnet_train", "goldenrod_station"),
            ("department_store", "department_store"),
            ("dance_theater", "dance_theater"),
            ("slowpoke_well", "slowpoke_well"),
            ("farm_barn", "barn"),
            ("moo_moo_farm", "barn"),
        ]
        specials.append(("dept_store", "department_store"))
        special = next((v for k, v in specials if k in dest), None)
        if "embedded_tower" in dest:
            special = "cave"
        if direction in ("up", "down", "left", "right") and "gate" in dest:
            if any(b["to"] == dest and abs(b["door"][0] - x) + abs(b["door"][1] - y) <= 2 for b in buildings):
                continue
            special = (
                "gate_side"
                if direction in ("left", "right")
                else ("cliff_gate" if "cliff_edge" in dest else "gate_front")
            )
        elif direction in ("left", "right", "down") and not special:
            continue
        if special:
            name = special
        if name == "cave":
            # Cave entrances are actual overworld rock arch metatiles, drawn below.
            kind[y, x] = "cave"
            place("cave_mouth", (x + 0.5) * 16, (y + 1) * 16, y * 16 + 8)
            continue
        if (x, y) in occupied:
            continue
        if "johto_elms_lab" == dest:
            name = "elm_lab"
        elif "players_house" in dest:
            name = "fr_home_red"
        elif name == "home":
            name = ("fr_home_green", "home_blue", "fr_home_slate", "fr_school")[(x + 3 * y) % 4]
        else:
            name = {"lab": "fr_lab", "center": "fr_center", "mart": "fr_mart", "gym": "fr_gym"}.get(name, name)
        px = (x + 0.5) * 16
        py = (y + 1) * 16
        if kind[y, x] == "water" and int(words[y, x]) & 255 in (16, 17, 18, 19, 20, 21):
            continue
        area = place(name, px, py, y * 16 + 9)
        buildings.append({"door": [x, y], "kind": name, "to": dest, "bounds": list(area)})
        houses.append(area)
        occupied.add((x, y))
        kind[y, x] = "trail" if not city else "grass"

    def under_house(x, y):
        return any(l - 3 < x < r + 3 and t < y < b + 3 for l, t, r, b in houses)

    for x, y in trees.values():
        cx = int(x // 16)
        cy = int((y - 4) // 16)
        if not (0 <= cx < w and 0 <= cy < h) or under_house(x, y):
            continue
        if not words[cy, cx] & 32768 or kind[cy, cx] == "water":
            continue
        place("fr_tree", x, y)
    for name, x, y, lo, hi in props:
        if under_house(x, y):
            continue
        if re.fullmatch(r"(?:[a-z0-9]+_h\d+[a-z0-9]*|(?:wk_hhouse|honda_h|hndo_h))", name):
            front = y + hi[2]
            cx = int(x // 16)
            cy = int((front - 5) // 16)
            native_door = any(
                abs(b["door"][0] * 16 + 8 - x) < max(50.0, hi[0] - lo[0])
                and abs(b["door"][1] * 16 + 8 - front) < 46
                for b in buildings
            )
            if (
                not native_door
                and 0 <= cx < w
                and 0 <= cy < h
                and words[cy, cx] & 32768
                and kind[cy, cx] != "water"
            ):
                sealed = ("fr_home_red_sealed", "fr_home_green_sealed", "fr_home_slate_sealed")[
                    sum(name.encode()) % 3
                ]
                houses.append(place(sealed, x, front))
                continue
        if name.startswith("board_"):
            place("fr_sign", x, y + 8)
        elif "light" in name or name.endswith(("_sl", "_tourou")):
            place("streetlamp", x, y + 8)
        elif "funsui" in name:
            place("fountain", x, y + 8)
        elif name.endswith("hata"):
            place("banner", x, y + 8)
    pieces = []
    for col, row in parts:
        pic = Image.new("RGBA", (512, 512))
        for iy in range(32):
            for ix in range(32):
                x = col + ix
                y = row + iy
                k = kind[y, x]
                if snow or field["header"] == "MAP_BELL_TOWER_ROOF":
                    # Both originals have a three-tile summit walkway. Keep each GBA pixel
                    # and align Red / the cave threshold with their native HGSS coordinates.
                    if snow:
                        donor = "MtSilver_SummitDay"
                        sx = x - 20
                        sy = y - 5 if y <= 11 else 6 + round((y - 11) * 15 / 25) if y <= 36 else 21 + y - 36
                        grid = hns.grid(donor)
                        tile = int(grid[sy, sx]) if 0 <= sy < grid.shape[0] and 0 <= sx < grid.shape[1] else 908
                    else:
                        donor = "TinTower_RoofDay"
                        sx = x - 5
                        sy = y - 7 if y <= 18 else 11 + round((y - 18) / 2) if y <= 24 else 14 + y - 24
                        grid = hns.grid(donor)
                        tile = int(grid[sy, sx]) if 0 <= sy < grid.shape[0] and 0 <= sx < grid.shape[1] else 788
                    block = hns.metatile(donor, tile)
                elif k in AUTOTILES:

                    def outside(nx, ny):
                        return 0 <= nx < w and 0 <= ny < h and kind[ny, nx] != k

                    dx = -1 if outside(x - 1, y) else (1 if outside(x + 1, y) else 0)
                    dy = -1 if outside(x, y - 1) else (1 if outside(x, y + 1) else 0)
                    if mid == "johto_new_bark_town" and k == "trail":
                        block = fr.tile(
                            "PalletTown", [[678, 654, 655], [686, 662, 663], [694, 670, 671]][dy + 1][dx + 1]
                        )
                    elif k == "cliff":
                        block = fr.tile("PalletTown", AUTOTILES[k][dy + 1][dx + 1])
                    elif k == "water":
                        block = fr.tile(
                            "PalletTown", [[290, 291, 292], [298, 299, 300], [306, 307, 308]][dy + 1][dx + 1]
                        )
                    else:
                        block = e.metatile(TOWN, AUTOTILES[k][dy + 1][dx + 1])
                elif k == "grass":
                    block = fr.tile("PalletTown", (17, 8, 17, 9)[(x + 2 * y) % 4])
                elif k == "flowers":
                    block = fr.tile("PalletTown", 4)
                elif k == "fence":
                    block = fr.tile("PalletTown", 215)
                else:
                    block = e.metatile(*TILES[k])
                behavior = int(words[y, x]) & 255
                if behavior in (75, 76):
                    block = climb_wall(e, behavior)
                pic.alpha_composite(block, (ix * 16, iy * 16))
        file = f"ground_{col}_{row}.png"
        pic.save(out / file, optimize=True)
        pieces.append({"png": file, "at": [col * 16, row * 16]})
    art.sort(key=lambda a: a["sort_y"])
    pieces.extend(art)
    info = {
        "native_header": field["header"],
        "size": field["size"],
        "tile_px": 16,
        "pieces": pieces,
        "doors": buildings,
    }
    write_json(out / "index.json", info)
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("emerald", type=Path)
    ap.add_argument("semantic_dir", type=Path)
    ap.add_argument("--firered", required=True, type=Path)
    ap.add_argument("--hns", required=True, type=Path)
    ap.add_argument("maps", nargs="*")
    args = ap.parse_intermixed_args()
    fr = FireRed(args.firered, ROOT)
    hns = Hns(args.hns)
    custom = generate(OUT / "fields", fr, hns)
    e = Emerald(args.emerald)
    anchors = json.loads((ROOT / "content/emerald_fields.json").read_text())["anchors"]
    heads = json.loads((HGSS / "events.json").read_text())["headers"]
    n = 0
    for p in sorted((HGSS / "maps").glob("*.json")):
        if args.maps and p.stem not in args.maps:
            continue
        f = json.loads(p.read_text())
        head = heads[f["header"]]
        if not outdoor(f["header"], head):
            continue
        render(p.stem, f, head, args.semantic_dir, e, anchors, fr, custom, hns)
        n += 1
    print(f"{n} GBA outdoor maps rendered")


if __name__ == "__main__":
    main()
