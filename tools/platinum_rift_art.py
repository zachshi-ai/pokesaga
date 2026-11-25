"""Render the ten Platinum Distortion World floors from the Nitro meshes and tw_arc.

Use after build_platinum_maps. Arguments: pret/pokeplatinum checkout, Platinum mesh
cache, apicula executable, temporary effects directory. The source floor offsets and
all source model origins are expressed in the same tiles as the runtime passages.
"""

import argparse
import json
import random
import re
import struct
import subprocess
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

from platinum_distortion import narc
from platinum_layout import ROOT, catalog, write
from platinum_scenery import base_height, mesh, paint, projected_prop
from dream_distortion_fields import (
    mask_image,
    offset,
    patch,
    sky_background,
    subtile,
    texture,
    tinted,
)

ART = ROOT / "assets/platinum_native/rift"


def parse_source(src):
    overlay = (src / "src/overlay009/ov9_02249960.c").read_text()
    enum = overlay.split("enum PropKind {", 1)[1].split("PROP_KIND_COUNT", 1)[0]
    names = [s.lower() for s in re.findall(r"PROP_KIND_([A-Z0-9_]+)", enum)]
    headers = (src / "generated/map_headers.txt").read_text().splitlines()
    data = narc(src / "res/prebuilt/fielddata/tornworld/tw_arc.narc")
    tables = {}
    for hid, index, ox, _alt, oz in struct.iter_unpack("<IHhhh", data[0][4:]):
        raw = data[index + 1]
        _, platforms, jumps, cameras, ghosts = struct.unpack_from("<5I", raw)
        room = {
            "offset": (ox, oz),
            "props": [],
            "triggers": [],
            "default": 0,
            "lifts": [],
        }
        tables[headers[hid]] = room
        wall = None
        if platforms and headers[hid].endswith("_B4F"):
            count = struct.unpack_from("<I", raw, 20)[0]
            for n in range(count):
                kind, _, px, py, pz, sx, sy, sz, _, _ = struct.unpack_from(
                    "<hH6h2H", raw, 24 + 20 * n
                )
                if kind == 2:
                    wall = (px, py, pz, sy, sz)
        if not ghosts:
            continue
        loc = 20 + platforms + jumps + cameras
        n, t, room["default"] = struct.unpack_from("<III", raw, loc)
        loc += 12
        for group, kind, x, height, z in struct.iter_unpack(
            "<IHhhh", raw[loc : loc + n * 12]
        ):
            room["props"].append((group, names[kind], x, height, z))
        loc += n * 12
        for group, direction, on, x, height, z, dx, dy, dz in struct.iter_unpack(
            "<I8h", raw[loc : loc + t * 20]
        ):
            room["triggers"].append([group, direction, on, x, z, dx + 1, dz + 1])
            # Project the original height range into the same four-way strip as
            # platinum_distortion.install uses for the B4F walk on the wall.
            if wall:
                px, py, pz, sy, sz = wall
                a = max(height, py)
                b = min(height + dy, py + sy)
                c = max(z, pz)
                d = min(z + dz, pz + sz)
                if x <= px <= x + dx and a <= b and c <= d:
                    room["triggers"].append(
                        [group, direction, on, px + 1 + a - py, c, b - a + 1, d - c + 1]
                    )
    for level, body in re.findall(
        r"static const DistWorldMovingPlatformTemplate sMovingPlatformMapTemplate(\w+?)_\d+ = \{(.*?)\};",
        overlay,
        re.S,
    ):
        fields = dict(re.findall(r"\.(\w+) = ([-\w]+)", body))
        tables["MAP_HEADER_DISTORTION_WORLD_" + level]["lifts"].append(
            (
                fields["propKind"].removeprefix("PROP_KIND_").lower(),
                int(fields["tileX"], 0),
                int(fields["tileZ"], 0),
            )
        )
    return tables


def gba_colors(im):
    # Keep the warm rock tops and blue crystal undersides of the source models,
    # using the contrast, stepped highlights and palette depth of Hoenn's caves.
    a = np.asarray(im.convert("RGBA")).copy()
    rgb = a[:, :, :3].astype("float32")
    l = rgb[:, :, 0] * 0.33 + rgb[:, :, 1] * 0.49 + rgb[:, :, 2] * 0.18
    blue = rgb[:, :, 2] > rgb[:, :, 0] * 1.30 + 10
    green = (rgb[:, :, 1] > rgb[:, :, 0] * 1.16) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.04)
    out = a[:, :, :3]
    for mask, colors in [
        (
            ~(blue | green),
            [
                "#393847",
                "#594859",
                "#775963",
                "#946a72",
                "#b68689",
                "#d6b1a5",
                "#ebd6bb",
            ],
        ),
        (
            blue,
            [
                "#272e50",
                "#384268",
                "#4a537d",
                "#626b91",
                "#8393ad",
                "#9fbdc7",
                "#d1e3db",
            ],
        ),
        (
            green,
            [
                "#333b4d",
                "#435966",
                "#587176",
                "#708c88",
                "#92a99c",
                "#b5c4a7",
                "#dde0bd",
            ],
        ),
    ]:
        lut = np.array([tuple(bytes.fromhex(x[1:])) for x in colors])
        values = (
            l[mask] if mask is not blue else rgb[:, :, 2][mask] * 0.7 + l[mask] * 0.3
        )
        out[mask] = lut[np.clip((values / 37).astype(int), 0, len(lut) - 1)]
    return Image.fromarray(a)


def effects(src, converter, cache):
    output = {}
    for file in sorted(
        (src / "res/graphics/field_effects").glob("distortion_world*.nsbmd")
    ):
        kind = file.stem.removeprefix("distortion_world_")
        dest = cache / kind
        if not dest.exists():
            subprocess.run(
                [str(converter), "convert", str(file), "-f", "glb", "-o", str(dest)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        model = next(dest.glob("*.glb"))
        obj = projected_prop(mesh(model), (1, 1, 1))
        if obj:
            left, top, _, im = obj
            output[kind] = (left, top, gba_colors(im))
    return output


def native_floor(doc, geo, placements, models, cache, backdrop):
    w, h = doc["size"]
    floor = ~np.asarray(doc["physics"]["collision"], bool)
    water = np.asarray(doc["physics"].get("water", np.zeros_like(floor)), bool)
    plates = floor | water
    # Give the four-way projection of a vertical surface a painted floor as well.
    # These strips are defined by original collision and launch/landing cells.
    base = sky_background((w * 16, h * 16), random.Random(doc["id"]), False)
    if backdrop is not None:
        inactive = Image.fromarray(subtile(backdrop).astype("uint8") * 255)
        inactive = inactive.transform(
            base.size,
            Image.Transform.AFFINE,
            (1.16, 0, -80, 0, 1.16, -130),
            resample=Image.Resampling.NEAREST,
        )
        base.paste("#423d59", (0, 0, base.width, base.height), inactive)
    surface = subtile(plates)
    real = texture(tinted(patch("meteor_floor"), ("#514556", "#a17c83")), w, h)
    base.paste(
        "#453950", (0, 0, base.width, base.height), mask_image(offset(surface, 0, 6))
    )
    base.paste(real, (0, 0), mask_image(surface))
    pixels = np.zeros((h * 16, w * 16, 4), dtype="uint8")
    depth = np.full((h * 16, w * 16), -1e20, dtype="float32")
    ox, oz = placements["offset"]
    for (bx, bz), land in geo["rows"].items():
        parts = mesh(cache / f'ground_{land}_{geo["area"]}.glb')
        paint(
            parts,
            pixels,
            depth,
            ((ox + 32 * bx) * 16 + 256, (oz + 32 * bz) * 16 + 256),
            ground=True,
            base=base_height(parts),
        )
    model = gba_colors(Image.fromarray(pixels))
    base.paste(model, (0, 0), model)
    # Original sloping walls cast into the floor on DS. Keep the projected water operable and visible.
    if water.any():
        from alola_melemele import cell

        wet = subtile(water)
        base.paste(
            texture(tinted(cell("water"), ("#526282", "#90b9c8")), w, h),
            (0, 0),
            mask_image(wet),
        )
        base.paste(
            "#aacbd0",
            (0, 0, base.width, base.height),
            mask_image(wet & ~offset(wet, 0, 1)),
        )
    for kind, x, z in sorted(placements["lifts"], key=lambda q: q[2]):
        left, top, im = models[kind]
        base.paste(im, (x * 16 + 8 + left, z * 16 + 8 + top), im)
    for warp in doc["warps"]:
        if warp.get("mechanism") == "distortion_lift":
            x, z = warp["at"]
            u, v = x * 16 + 8, z * 16 + 8
            ImageDraw.Draw(base).polygon(
                [(u, v - 4), (u + 4, v), (u, v + 3), (u - 4, v)],
                fill="#b6cbc4",
                outline="#62657d",
            )
    if any(w.get("mechanism") == "reversed_waterfall" for w in doc["warps"]):
        d = ImageDraw.Draw(base)
        for z in range(76, 80):
            for s in (4, 9, 14):
                y = z * 16 + s
                d.line((104 * 16 + 2, y, 105 * 16 + 2, y - 4), fill="#ceecdb")
    occupied = plates.copy()
    for wrow in doc["warps"]:
        x, z = wrow["at"]
        occupied[z, x] = True
    # The map matrix includes intentionally empty 32x32 tiles surrounding each floor.
    yy, xx = np.where(occupied)
    left = max(0, int(xx.min() - 5) * 16)
    top = max(0, int(yy.min() - 5) * 16)
    right = min(w * 16, int(xx.max() + 6) * 16)
    bottom = min(h * 16, int(yy.max() + 6) * 16)
    target = ART / (doc["id"].removeprefix("sinnoh_distortion_world_") + ".png")
    base.crop((left, top, right, bottom)).quantize(96, dither=Image.Dither.NONE).save(
        target, optimize=True
    )
    plan = doc["hoenn_art"]
    plan["scene"] = ["res://" + str(target.relative_to(ROOT)), left, top]
    plan["camera_bounds"] = [left, top, right, bottom]
    sprites = []
    for group, kind, x, alt, z in placements["props"]:
        if kind not in models:
            continue
        dx, dy, img = models[kind]
        file = ART / (kind + ".png")
        img.save(file, optimize=True)
        sprites.append([group, x, z, dx, dy, "res://" + str(file.relative_to(ROOT))])
    plan["rift"] = {
        "sprites": sprites,
        "visible": placements["default"],
        "triggers": placements["triggers"],
    }


def render(src, cache, converter, effect_cache):
    ART.mkdir(exist_ok=True)
    effect_cache.mkdir(parents=True, exist_ok=True)
    tables = parse_source(src)
    geo = catalog(src)
    models = effects(src, converter, effect_cache)
    files = ROOT / "content/platinum_native/maps"
    docs = {
        k: json.loads((files / (geo[k]["id"] + ".json")).read_bytes()) for k in tables
    }
    for i, (k, doc) in enumerate(docs.items()):
        key = list(docs)[i + 1] if i < 7 else None
        backdrop = ~np.asarray(docs[key]["physics"]["collision"], bool) if key else None
        native_floor(doc, geo[k], tables[k], models, cache, backdrop)
        write(files / (doc["id"] + ".json"), doc)
        print(
            doc["id"], len(tables[k]["props"]), len(tables[k]["triggers"]), flush=True
        )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for k in ["platinum", "meshes", "apicula", "cache"]:
        p.add_argument(k, type=Path)
    a = p.parse_args()
    render(a.platinum, a.meshes, a.apicula, a.cache)
