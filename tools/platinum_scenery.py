"""Paint Platinum's matrix ground and separately depth-sort its original placed models.

The mesh cache is produced by hgss_render's platinum_scenery example. All generated
graphics are flat nearest-neighbour pixel art with a shared Emerald field palette.
Story, warp, encounter, save and movement coordinates remain on their native DS grid.
"""

import argparse
from collections import Counter
from functools import lru_cache
import json
import math
from pathlib import Path
import re
import struct

import numpy as np
from PIL import Image

from ds_pixel_art import save_scene, fit_spawn
from platinum_layout import catalog, OUT, ROOT, SEABREAK, write
from unova_art import glb
from unova_interiors import palette, raster, texture, values
from unova_streets import grass_tile

# These floors switch with scripts or already have their own field painting.
START = {"sinnoh_twinleaf", "sinnoh_sandgem", "sinnoh_201"}
LEAGUE = {
    "sinnoh_pokemon_league_" + name + "_room" for name in ("aaron", "bertha", "flint", "lucian", "champion")
}
OUT_ART = ROOT / "assets/platinum_native/scenery"


@lru_cache(160)
def mesh(path):
    doc, binary = glb(path)
    parts = []
    for shape in doc.get("meshes", []):
        for pr in shape["primitives"]:
            attr = pr["attributes"]
            mat = doc["materials"][pr["material"]]
            name = mat["name"].lower()
            if re.search(r"kage|shadow|tshadow|_light_lm|flare|fog", name):
                continue
            tex = texture(path.parent, doc, binary, mat)
            if tex is None:
                continue
            xyz = values(doc, binary, attr["POSITION"])
            uv = values(doc, binary, attr["TEXCOORD_0"]) if "TEXCOORD_0" in attr else np.zeros((len(xyz), 2))
            ix = np.ascontiguousarray(values(doc, binary, pr["indices"]).ravel(), dtype=np.uint32)
            if not ix.size:
                continue
            # Nitro uses both mirrored and clamped UVs. Extend mirrored textures
            # by one tile; for clamped ones a replicated border prevents wrapping.
            tex_id = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index")
            if tex_id is not None:
                td = doc["textures"][tex_id]
                samp = doc["samplers"][td["sampler"]]
                uv = uv.copy()
                for col, axis, mode in ((0, 1, "wrapS"), (1, 0, "wrapT")):
                    n = tex.shape[axis]
                    if samp[mode] == 33648:
                        tex = np.concatenate((tex, np.flip(tex, axis)), axis=axis)
                        uv[:, col] /= 2
                    elif samp[mode] == 33071:
                        pad = [(0, 0), (0, 0), (0, 0)]
                        pad[axis] = (1, 1)
                        tex = np.pad(tex, pad, mode="edge")
                        uv[:, col] = (np.clip(uv[:, col], 0, 1) * n + 1) / (n + 2)
            parts.append((name, xyz, uv, ix, np.ascontiguousarray(tex)))
    return parts


def paint(parts, pixels, depth, offset, scale=(1, 1, 1), ground=False, outdoor=False, base=0):
    h, w = depth.shape
    for name, xyz, uv, indices, tex in parts:
        if ground and outdoor and re.search(r"(^|_)tree\d|hayashi|conttree", name):
            # Emerald trees remain independent occluders on the original foliage footprints.
            continue
        x = xyz[:, 0] * scale[0] + offset[0]
        z = xyz[:, 2] * scale[2] + offset[1]
        y = xyz[:, 1] * scale[1]
        if ground:
            shift = np.clip((y - base) * 0.42, -10, 12)
        else:
            shift = y * 0.70
        if ground and outdoor and re.match(r"^(ngrass|lgreen)_", name):
            tex = grass_tile("grass")
            uv = np.column_stack((x, z)) / 16
        verts = np.ascontiguousarray(np.column_stack((x, z - shift, z * 0.70 + y, uv)), dtype=np.float32)
        raster()(
            pixels.ctypes.data,
            depth.ctypes.data,
            w,
            h,
            verts.ctypes.data,
            indices.ctypes.data,
            len(indices) // 3,
            tex.ctypes.data,
            tex.shape[1],
            tex.shape[0],
        )


def store(im):
    indexed = im.convert("RGB").quantize(palette=palette(), dither=Image.Dither.NONE)
    file = save_scene(indexed, im.getchannel("A"), OUT_ART)
    return "res://" + str(file.relative_to(ROOT))


@lru_cache(768)
def prop(meshfile, scale):
    parts = mesh(meshfile)
    if not parts:
        return None
    xyz = np.concatenate([q[1] for q in parts]) * scale
    x = xyz[:, 0]
    y = xyz[:, 2] - xyz[:, 1] * 0.70
    left, top = int(np.floor(x.min())) - 1, int(np.floor(y.min())) - 1
    w = int(np.ceil(x.max())) - left + 2
    h = int(np.ceil(y.max())) - top + 2
    if w < 2 or h < 2:
        return None
    pixels = np.zeros((h, w, 4), dtype="uint8")
    depth = np.full((h, w), -1e20, dtype="float32")
    paint(parts, pixels, depth, (-left, -top), scale)
    im = Image.fromarray(pixels)
    bbox = im.getbbox()
    if not bbox:
        return None
    cropped = im.crop(bbox)
    return left + bbox[0], top + bbox[1], float(xyz[:, 2].max()), cropped


@lru_cache(None)
def prop_uri(path, scale):
    return store(prop(path, scale)[3])


@lru_cache(None)
def prop_rows(root, land):
    raw = (root / "res/field/mapmodels/data" / f"map_data_{land:03}.bin").read_bytes()
    physics, count = struct.unpack_from("<2I", raw)
    start = 16 + physics
    return list(struct.iter_unpack("<12i", raw[start : start + count // 48 * 48]))


def base_height(parts):
    flat = Counter()
    for _, xyz, _, ids, _ in parts:
        tri = xyz[ids].reshape(-1, 3, 3)
        floors = tri[np.ptp(tri[:, :, 1], axis=1) < 0.3]
        if not len(floors):
            continue
        # Dominant floor by projected area, not vertex count.
        a = floors[:, 1] - floors[:, 0]
        b = floors[:, 2] - floors[:, 0]
        area = np.abs(a[:, 0] * b[:, 2] - a[:, 2] * b[:, 0])
        for height, total in zip(np.round(floors[:, 0, 1]).astype(int), area):
            flat[int(height)] += float(total)
    return flat.most_common(1)[0][0] if flat else 0


@lru_cache(None)
def furnished(name, size):
    # Fit the room model's measured footprint. A bed, a shelf or a plant keeps the
    # GBA artwork's upright perspective at every original furnishing anchor.
    source = next(
        (
            kind
            for prefix, kind in [
                ("shelf", "bookshelf"),
                ("plant", "plant_indoor"),
                ("bed", "ceilingbed"),
                ("sofa", "carebench"),
                ("table", "desk"),
                ("tv", "tv"),
            ]
            if name.startswith(prefix)
        ),
        None,
    )
    if not source or min(size) < 8:
        return None
    with Image.open(ROOT / "assets/emerald/field" / (source + ".png")) as file:
        im = file.convert("RGBA")
    w, h = size
    height = max(12, round(im.height * w / im.width))
    im = im.resize((w, min(max(h, 20), height)), Image.Resampling.NEAREST)
    return store(im), im


def indoor_floor(bg, doc):
    # DS rooms with flat diffuse floors have little visual relief in a fixed camera.
    # Tint the subdued grain of an Emerald metatile underfoot; preserve the original
    # motifs, carpet borders, counter areas and all the untouched source silhouettes.
    from scipy import ndimage

    pixels = np.asarray(bg).copy()
    rgb = pixels[:, :, :3].astype("int16")
    high = np.max(rgb, axis=2)
    area = (ndimage.maximum_filter(high, 5) - ndimage.minimum_filter(high, 5) < 5) & (pixels[:, :, 3] > 0)
    walk = np.repeat(np.repeat(np.asarray(doc["physics"]["collision"]) == 0, 16, axis=0), 16, axis=1)
    area &= walk
    yy, xx = np.where(area)
    if not len(yy):
        return bg
    wood = grass_tile("floor")[:, :, :3].astype(int).mean(2)
    fluct = (wood - wood.mean()) * 0.40
    seam = (yy % 16 == 0) | ((xx + 16 * ((yy // 16) % 2)) % 32 == 0)
    delta = np.clip(fluct[yy % 16, xx % 16], -7, 7) - 7 * seam
    pixels[yy, xx, :3] = np.clip(rgb[yy, xx] + delta[:, None], 0, 255)
    return Image.fromarray(pixels)


def draw_hearthome_lift(bg, doc):
    # The retired D/P leader room has an animated elevator. Its stationary model
    # shows a red platform at the other end of the room, away from the actual warp.
    pixels = np.array(bg)
    original = pixels.copy()
    floor = original[9 * 16 : 10 * 16, 9 * 16 : 10 * 16]
    walk = np.repeat(np.repeat(np.asarray(doc["physics"]["collision"]) == 0, 16, axis=0), 16, axis=1)
    dark = (pixels[:, :, 3] < 128) | (pixels[:, :, :3].max(2) < 32)
    y, x = np.where(walk & dark)
    pixels[y, x] = floor[y % 16, x % 16]

    y1, x1 = 210, 56
    patch = original[y1:230, x1:88].copy()
    red = (patch[:, :, 0].astype(int) > patch[:, :, 1].astype(int) * 1.25) & (patch[:, :, 0] > 70)
    y, x = np.where(red)
    pixels[y1 + y, x1 + x] = floor[(y1 + y) % 16, (x1 + x) % 16]
    patch[:, :, 3] = red.astype("uint8") * 255
    lift = Image.fromarray(patch)
    lift = lift.crop(lift.getbbox()).resize((16, 12), Image.Resampling.NEAREST)
    bg = Image.fromarray(pixels)
    x, y = doc["warps"][0]["at"]
    bg.alpha_composite(lift, (x * 16, y * 16 + 2))
    return bg


def layer_picture(doc, rows, geo, root, cache, bank):
    w, h = doc["size"]
    ox, oy = doc["platinum_origin"]
    outdoor = doc["map_type"] in ("MAP_TYPE_OUTDOORS", "MAP_TYPE_TOWN_CITY", "MAP_TYPE_ROUTE")
    art = doc["hoenn_art"]
    # Preserve game-driven items and source trees. Ordinary furnishing is redrawn from the
    # placed furniture models; duplicating it with placeholder desks conceals staircases.
    props = [
        p
        for p in art["p"]
        if p[0] in ("tree", "berry_tree")
        or (
            p[0] == "sign"
            and any(
                e.get("atlas") == "world" and abs(e["at"][0] - p[1]) + abs(e["at"][1] - p[2]) < 2
                for e in doc["warps"]
            )
        )
    ]
    pixels = np.zeros((h * 16, w * 16, 4), dtype="uint8")
    depth = np.full((h * 16, w * 16), -1e20, dtype="float32")
    under = []
    for (bx, by), land in rows.items():
        cx = (bx * 32 - ox) * 16 + 256
        cy = (by * 32 - oy) * 16 + 256
        parts = mesh(cache / f"ground_{land}_{geo['area']}.glb")
        paint(parts, pixels, depth, (cx, cy), ground=True, outdoor=outdoor, base=base_height(parts))
        for r in prop_rows(root, land):
            pid = r[0]
            if pid in (0, 26):
                continue  # Script-controlled berry growth, debug bounding box.
            path = cache / f"{bank}_{pid}.glb"
            scale = tuple(v / 4096 for v in r[7:10])
            obj = prop(path, scale)
            if not obj:
                continue
            left, top, front, im = obj
            uri = None
            x = cx + r[1] / 4096
            y = cy + r[3] / 4096
            left = round(x) + left
            top = round(y) + top
            if left + im.width <= 0 or top + im.height <= 0 or left >= 16 * w or top >= 16 * h:
                continue
            model = glb_name(path)
            if doc["id"] == "sinnoh_canalave":
                if model == "c2_s02":
                    from platinum_canalave_library import facade

                    library = facade()
                    top += im.height - library.height
                    uri, im = store(library), library
                elif model == "c5_door_s" and (math.floor(x / 16), math.floor(y / 16)) == (5, 14):
                    # The redrawn portico contains the door at this original Platinum warp.
                    continue
            if doc["map_type"] == "MAP_TYPE_INDOORS":
                gba = furnished(model, im.size)
                if gba:
                    top += im.height - gba[1].height
                    uri, im = gba
            # Flat treadways and boards under the character share the ground plane.
            # Tall architecture and furniture must cover a character walking behind them.
            if re.search(
                r"^d_mat|rug|carpet|sheet|bridge|bascul|floor|step|stage|hashi|hasige|^[ab]_road", model
            ):
                under.append((top + im.height, left, top, im))
                continue
            cellx = min(w - 1, max(0, math.floor(x / 16)))
            foottop = math.floor((y + front - 1) / 16)
            if "door" in model:
                foottop += 1  # Door panels are drawn over their own facade.
            celly = min(h - 1, max(0, foottop))
            props.append(
                [uri or prop_uri(path, scale), cellx, celly, [cellx * 16 + 8 - left, (celly + 1) * 16 - top]]
            )
    bg = Image.fromarray(pixels)
    if doc["map_type"] == "MAP_TYPE_INDOORS":
        bg = indoor_floor(bg, doc)
    for _, left, top, im in sorted(under, key=lambda a: a[0]):
        bg.alpha_composite(im, (left, top))
    if "grass" in doc["physics"] and outdoor:
        from unova_first_routes import native_grass

        bg = native_grass(bg, np.asarray(doc["physics"]["grass"], bool))
    if doc["id"] == "sinnoh_hearthome_city_dp_gym_leader_room":
        bg = draw_hearthome_lift(bg, doc)
    return bg, props


@lru_cache(None)
def glb_name(path):
    doc, _ = glb(path)
    return doc["nodes"][0].get("name", "").lower()


def fit_authored_spawn(doc):
    import base64, zlib

    # The Villa and Eterna Gym use their own dynamic floor graphics. Check their
    # original tile layer directly so the saved entrance remains on its floor.
    if doc["id"] not in ("sinnoh_villa", "sinnoh_eterna_city_gym"):
        return
    art = doc["hoenn_art"]
    w, h = doc["size"]
    grid = np.frombuffer(zlib.decompress(base64.b64decode(art["t"])), dtype="<u2").reshape(h, w)
    with Image.open(ROOT / "assets/platinum_native/tiles.png") as sheet:
        centers = np.asarray(sheet.convert("RGBA"))[8::16, 8::16].reshape(-1, 4)
    alpha = np.where((grid != 0) & (centers[grid, 3] > 128) & (centers[grid, :3].max(2) > 16), 255, 0).astype(
        "uint8"
    )
    panel = Image.new("RGBA", (16 * w, 16 * h))
    panel.putalpha(Image.fromarray(alpha).resize(panel.size, Image.Resampling.NEAREST))
    fit_spawn(doc, panel, "platinum_previous_spawn")


def dress(root, cache, selected):
    records = {r["id"]: r for r in catalog(root).values()}
    count = Counter()
    missing = []
    for folder in ("maps", "flower"):
        for file in sorted((OUT / folder).glob("*.json")):
            doc = json.loads(file.read_bytes())
            mid = doc["id"]
            if selected and mid not in selected:
                continue
            if (
                mid in START | LEAGUE
                or doc.get("platinum_gym")
                or doc.get("platinum_ride_tile")
                or doc.get("platinum_cycling")
                or mid == "sinnoh_villa"
            ):
                fit_authored_spawn(doc)
                if doc.get("platinum_previous_spawn"):
                    write(file, doc)
                count["prior authored layouts"] += 1
                continue
            geo = records[mid]
            rows = dict(geo["rows"])
            if folder == "flower" and mid == "sinnoh_224":
                rows.update(SEABREAK)
            header = json.loads(
                (root / "res/field/area_data" / f"area_data_{geo['area']:03}.json").read_bytes()
            )
            bank = header["mapPropSet"].replace("model", "texture")
            if mid == "sinnoh_underground":
                from platinum_underground_art import paint_maze

                paint_maze(doc, rows, geo, cache)
                write(file, doc)
                count["underground"] += 1
                continue
            bg, props = layer_picture(doc, rows, geo, root, cache, bank)
            if doc["map_type"] in ("MAP_TYPE_INDOORS", "MAP_TYPE_CAVE"):
                fit_spawn(doc, bg, "platinum_previous_spawn")
            bbox = bg.getbbox()
            if not bbox and not props:
                missing.append(mid)
                continue
            if bbox:
                doc["hoenn_art"]["scene"] = [store(bg.crop(bbox)), bbox[0], bbox[1]]
            doc["hoenn_art"]["p"] = sorted(props, key=lambda p: (p[2], p[1], p[0]))
            write(file, doc)
            count["new fields"] += 1
            if count["new fields"] % 100 == 0:
                print(dict(count), flush=True)
    print(dict(count), "no native geometry", missing, flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("root", type=Path)
    p.add_argument("mesh_cache", type=Path)
    p.add_argument("maps", nargs="*")
    args = p.parse_args()
    dress(args.root, args.mesh_cache, set(args.maps))
