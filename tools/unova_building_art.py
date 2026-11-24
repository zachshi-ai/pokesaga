"""Depth-sort BW and B2 exterior buildings at their authored ground-level footprint."""

import re
from functools import lru_cache
from math import floor

import numpy as np
from ds_pixel_art import save_scene
from PIL import Image
from unova_art import ROOT, glb

# The names here are building *models*, not e.g. "gym_sign" or "door_mat".
BUILDING = re.compile(
    r"house|buill|build|^pc_\d|^gate_\d|gym_|station|ballpark|football|stadium|theater|museum|school|labo|(?:^|_)mall|ctower|untower|^door"
)
RISE = 0.72


def exterior_model(name):
    return bool(BUILDING.search(name)) and not any(
        word in name
        for word in ("sign", "kanban", "light", "mat_", "houseki", "door_bar")
    )


@lru_cache(256)
def elevation(path, rotation):
    from unova_interiors import palette, render_mesh, values

    doc, binary = glb(path)
    xyz = np.concatenate(
        [
            values(doc, binary, pr["attributes"]["POSITION"])
            for mesh in doc["meshes"]
            for pr in mesh["primitives"]
        ]
    )
    c, s = np.cos(rotation), np.sin(rotation)
    x = xyz[:, 0] * c + xyz[:, 2] * s
    z = xyz[:, 2] * c - xyz[:, 0] * s
    projected = z - xyz[:, 1] * RISE
    left, top = floor(x.min()) - 1, floor(projected.min()) - 1
    w, h = int(np.ceil(x.max())) - left + 2, int(np.ceil(projected.max())) - top + 2
    if min(w, h) < 2:
        return None
    pixels = np.zeros((h, w, 4), dtype=np.uint8)
    depth = np.full((h, w), -1e20, dtype=np.float32)
    render_mesh(path, (-left, 0, -top), rotation, pixels, depth, rise=RISE)
    sprite = Image.fromarray(pixels)
    bounds = sprite.getbbox()
    if not bounds:
        return None
    sprite = sprite.crop(bounds)
    if path.parent.name == "bc_build_s1":
        # Black City reuses this tower in rows only eight walking cells apart.
        # The DS camera can tilt past it. Keep a roof, a full window band and the
        # foot cornice so the GBA view still exposes the entire street behind.
        original_height = sprite.height
        attic = sprite.crop((0, 0, sprite.width, 105)).resize(
            (sprite.width, 43), Image.Resampling.NEAREST
        )
        facade = sprite.crop((0, original_height - 53, sprite.width, original_height))
        sprite = Image.new("RGBA", (sprite.width, attic.height + facade.height))
        sprite.alpha_composite(attic)
        sprite.alpha_composite(facade, (0, attic.height))
        top += original_height - sprite.height
    indexed = sprite.convert("RGB").quantize(
        palette=palette(), dither=Image.Dither.NONE
    )
    file = save_scene(indexed, sprite.getchannel("A"), ROOT / "assets/unova/elevations")
    return (
        "res://" + str(file.relative_to(ROOT)),
        left + bounds[0],
        top + bounds[1],
        float(z.max()),
    )


def placement(path, rotation, x, y, z, size):
    art = elevation(path, float(rotation))
    if not art:
        return None
    uri, left, top, front = art
    cellx = min(size[0] - 1, max(0, floor(x / 16)))
    celly = min(size[1] - 1, max(0, floor((z + front - 1) / 16)))
    # Door panels are separate models. Sort in front of the coincident wall
    # (as in Platinum), but anchor the drawn pixels at the same doorway.
    if path.parent.name.startswith("door"):
        celly = min(size[1] - 1, celly + 1)
    return [
        uri,
        cellx,
        celly,
        [
            cellx * 16 + 8 - round(x + left),
            (celly + 1) * 16 - round(z + top - y * 0.36),
        ],
    ]


# These two gates face sideways and north along the original walking grid.
# The DS camera turns at their thresholds. Use a cutaway on the fixed GBA camera.
ROUTE_GATES = {
    "unova_12": ((7, 14), "east"),
    "unova_14": ((19, 56), "north"),
}


@lru_cache(2)
def gate_sprite(view):
    from PIL import ImageDraw

    donor = Image.open(ROOT / "assets/johto_gba/fields/gate_side.png").convert("RGBA")
    # Only borrow the station's eaves, windows and masonry. The right side of
    # the source crop contains a strip of neighbouring lawn and a tree.
    facade = donor.crop((2, 44, 94, 80))
    roof = donor.crop((2, 2, 94, 42)).resize((92, 21), Image.Resampling.NEAREST)
    pixels = np.array(roof)
    light = pixels[:, :, 0].astype(int)
    colors = [(63, 99, 88), (77, 125, 108), (109, 151, 118), (147, 179, 137)]
    pixels[:, :, :3] = np.array(colors, dtype=np.uint8)[
        np.digitize(light, [110, 150, 172])
    ]
    roof = Image.fromarray(pixels)
    if view == "east":
        img = Image.new("RGBA", (88, 70))
        d = ImageDraw.Draw(img)
        img.alpha_composite(roof.crop((0, 0, 64, 21)), (1, 4))
        img.alpha_composite(facade.crop((0, 0, 64, 36)), (1, 25))
        # The slope and facade recede towards the *real* east-facing opening.
        d.polygon(
            [(65, 4), (78, 0), (85, 16), (65, 25)], fill="#6c9473", outline="#496358"
        )
        for x in (67, 71, 75):
            d.line((x + 7, 4, x, 20), fill="#8dae8c")
        d.polygon(
            [(65, 25), (85, 16), (85, 54), (65, 62)], fill="#ab956e", outline="#645c5c"
        )
        for y in [27, 34, 41, 48, 55]:
            d.line((66, y + 2, 84, y - 5), fill="#c4ae81")
        d.polygon(
            [(75, 29), (84, 25), (84, 54), (75, 58)], fill="#414857", outline="#686573"
        )
        d.line((76, 30, 82, 27), fill="#b4c7bd")
        d.polygon(
            [(72, 29), (84, 23), (87, 25), (74, 33)], fill="#d6c7a7", outline="#677475"
        )
        d.polygon(
            [(75, 58), (85, 54), (87, 56), (75, 62)], fill="#95a4a1", outline="#6b7478"
        )
        anchor = [80, 55]
    else:
        img = Image.new("RGBA", (88, 82))
        d = ImageDraw.Draw(img)
        # From the north expose the passage through the middle. The two visible
        # roof wings give the player a view inside without painting over the road.
        for x in (0, 57):
            img.alpha_composite(roof.crop((0, 0, 31, 19)), (x, 10))
            img.alpha_composite(facade.crop((12, 0, 43, 36)), (x, 29))
            d.line((x, 10, x + 29, 10), fill="#c4cda5", width=2)
            d.line((x, 64, x + 30, 64), fill="#675e60")
        d.rectangle((27, 25, 60, 65), fill="#535e64", outline="#5d5860")
        d.rectangle((33, 30, 54, 64), fill="#404853")
        for y in (45, 51, 58, 64):
            d.line((34, y, 53, y), fill="#697780")
        for x in (27, 55):
            d.rectangle((x, 21, x + 5, 65), fill="#b59d76", outline="#67635f")
            d.line((x + 1, 24, x + 1, 62), fill="#e1cf9d", width=2)
        d.polygon(
            [(26, 25), (28, 19), (59, 19), (62, 25), (60, 28), (27, 28)],
            fill="#537c70",
            outline="#43565c",
        )
        d.line((29, 20, 58, 20), fill="#b4c49a", width=2)
        d.rectangle((37, 23, 51, 26), fill="#d3ccae")
        # Open apron at the northern rim and front edge seen from the top road.
        d.rectangle((34, 66, 53, 70), fill="#969e96")
        d.line((34, 67, 53, 67), fill="#c6c5af")
        anchor = [44, 21]
    directory = ROOT / "assets/unova/transit"
    file = directory / ("route_gate_" + view + ".png")
    if not file.exists() or Image.open(file).convert("RGBA").tobytes() != img.tobytes():
        img.save(file, optimize=True)
    return "res://" + str(file.relative_to(ROOT)), anchor


def route_gate(mid):
    (x, y), view = ROUTE_GATES[mid]
    uri, anchor = gate_sprite(view)
    return [uri, x, y, anchor]
