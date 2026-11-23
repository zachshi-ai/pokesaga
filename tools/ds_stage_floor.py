"""Light passable surfaces below rail-driven stages and mechanical lifts."""

from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

from ds_pixel_art import save_scene
from unova_art import ROOT
from unova_interiors import palette
from unova_streets import grass_tile

# These models depend on a black camera mask, animated lift or spotlight in the DS
# engine. The player's 2-D feet must still be legible on that same collision surface.
SETUPS = {
    "unova_e4_shauntal": ("stone", (77, 61, 92), (108, 91, 121)),
    "unova_e4_caitlin": ("tiles", (106, 76, 111), (142, 103, 134)),
    "unova_e4_grimsley": ("tiles", (80, 60, 71), (111, 80, 93)),
    "unova_e4_marshal": ("stone", (77, 97, 103), (113, 129, 123)),
    "unova_b2_gym_nimbasa": ("tiles", (65, 70, 92), (105, 110, 139)),
    "unova_b2_gym_opelucid": ("stone", (78, 86, 88), (109, 119, 113)),
    "unova_bw_zone_137": ("stone", (102, 95, 75), (150, 142, 113)),
    "unova_b2_zone_137": ("stone", (102, 95, 75), (150, 142, 113)),
    "unova_b2_zone_503": ("rockfloor", (78, 69, 63), (113, 98, 78)),
    "unova_b2_zone_504": ("rockfloor", (78, 69, 63), (113, 98, 78)),
    "unova_b2_zone_596": ("rockfloor", (48, 48, 58), (86, 82, 88)),
    "unova_b2_zone_98": ("floor", (118, 105, 90), (148, 133, 113)),
    **{"unova_b2_zone_" + str(n): ("floor", (133, 116, 93), (163, 143, 111)) for n in range(543, 551)},
    "unova_bw_zone_239": ("stone", (91, 96, 97), (129, 134, 124)),
    "unova_b2_zone_239": ("stone", (91, 96, 97), (129, 134, 124)),
}


@lru_cache(None)
def chip(name):
    source, shade, light = SETUPS[name]
    texture = grass_tile(source)
    levels = texture[:, :, :3].astype(float).mean(2)
    levels = (levels - levels.min()) / max(1, float(np.ptp(levels)))
    rgb = np.asarray(shade) + (np.asarray(light) - shade) * (0.25 + 0.65 * levels[:, :, None])
    im = Image.fromarray(rgb.astype("uint8"), "RGB")
    p = ImageDraw.Draw(im)
    if name == "unova_b2_zone_596":
        return np.array(im)
    p.line((0, 15, 15, 15), fill=shade)
    if name.endswith("_137"):
        for x in (2, 13):
            p.rectangle((x, 2, x + 1, 3), fill=light)
    elif "nimbasa" in name:
        p.line((4, 14, 8, 10, 12, 14), fill=light)
    else:
        p.line((15, 0, 15, 15), fill=shade)
    return np.array(im)


def light_floor(doc):
    key = doc["id"]
    if key not in SETUPS or "scene" not in doc["hoenn_art"]:
        return
    w, h = doc["size"]
    sc = doc["hoenn_art"]["scene"]
    image = Image.new("RGBA", (w * 16, h * 16))
    with Image.open(ROOT / sc[0][6:]) as old:
        image.alpha_composite(old.convert("RGBA"), tuple(sc[1:]))
    pixels = np.array(image)
    walk = np.asarray(doc["physics"]["collision"]) == 0
    allowed = np.repeat(np.repeat(walk, 16, axis=0), 16, axis=1)
    hi = pixels[:, :, :3].max(2)
    lo = pixels[:, :, :3].min(2)
    # An animated spotlight leaves neutral white placeholder polygons on Route 17.
    # Cut only flat extremes. Keep columns, highlights and rail markings.
    extreme = (pixels[:, :, 3] < 128) | (hi < 32) | (lo > 241)
    y, x = np.where(allowed & extreme)
    if not y.size:
        return
    tile = chip(key)
    pixels[y, x, :3] = tile[y % 16, x % 16]
    pixels[y, x, 3] = 255
    if key == "unova_b2_zone_596":
        # Feather the path into the cave's shadow. Columns and the visible cliffs
        # come from the original field; only their unlit surroundings take this grain.
        from scipy import ndimage

        dark = extreme & ~allowed
        distance = ndimage.distance_transform_edt(~allowed)
        yy, xx = np.indices(distance.shape)
        edge = 20 + 4 * np.sin(xx / 9) + 3 * np.cos(yy / 13)
        y, x = np.where(dark & (distance < edge))
        fade = np.clip(0.66 * (1 - distance[y, x] / edge[y, x]), 0, 1)
        pixels[y, x, :3] = np.rint(tile[y % 16, x % 16] * fade[:, None]).astype("uint8")
        pixels[y, x, 3] = 255
    out = Image.fromarray(pixels)
    box = out.getbbox()
    out = out.crop(box)
    indexed = out.convert("RGB").quantize(palette=palette(), dither=Image.Dither.NONE)
    file = save_scene(indexed, out.getchannel("A"), ROOT / "assets/unova/scenery")
    doc["hoenn_art"]["scene"] = ["res://" + str(file.relative_to(ROOT)), box[0], box[1]]
