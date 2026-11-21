#!/usr/bin/env python3
"""Import the map-facing rendered models recorded in sources.json, using Pillow."""

import colorsys
import hashlib
import io
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import requests

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "assets/oras_npc"
SOURCES = HERE / "sources.json"


ROCKET_R = ("1110", "1001", "1110", "1010", "1001")


def render_adaptation(role, record):
    recipe = record["adaptation"]
    path = OUT / (recipe["base_role"] + ".png")
    img = Image.open(path).convert("RGBA")
    # Pixel hashes remain stable when another zlib release encodes the PNG
    # differently. The manifest retains both the source and PNG file hashes.
    if (
        img.size != (80, 90)
        or hashlib.sha256(img.tobytes()).hexdigest() != recipe["base_rgba_sha256"]
    ):
        raise ValueError(f"{role}: original ORAS base sprite changed")
    left, top, right, bottom = img.getchannel("A").getbbox()
    width, height = right - left, bottom - top
    pixels = img.load()
    for y in range(top, bottom):
        for x in range(left, right):
            red, green, blue, alpha = pixels[x, y]
            if not alpha:
                continue
            h, s, v = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
            h *= 360
            a, b = (x - left + 0.5) / width, (y - top + 0.5) / height
            for rule in recipe["palette"]:
                x0, y0, x1, y1 = rule["box"]
                lo, hi = rule["hue"]
                hue_ok = lo <= h <= hi if lo <= hi else h >= lo or h <= hi
                if not (
                    x0 <= a < x1
                    and y0 <= b < y1
                    and hue_ok
                    and rule["saturation"][0] <= s <= rule["saturation"][1]
                    and rule["value"][0] <= v <= rule["value"][1]
                ):
                    continue
                hue, sat, v0, v1 = rule["target_hsv"]
                color = colorsys.hsv_to_rgb(hue / 360, sat, v0 + (v1 - v0) * v)
                pixels[x, y] = (*[round(c * 255) for c in color], alpha)
                break
    if "emblem" in recipe:
        ax, ay = recipe["emblem"]["at"]
        ox, oy = left + round(ax * width), top + round(ay * height)
        for dy, row in enumerate(ROCKET_R):
            for dx, bit in enumerate(row):
                if bit == "1" and pixels[ox + dx, oy + dy][3] > 220:
                    pixels[ox + dx, oy + dy] = (213, 39, 52, 255)
    img.save(OUT / (role + ".png"), optimize=True)
    return role, record["sha256"]


def import_role(entry):
    role, record = entry
    if "adaptation" in record:
        return render_adaptation(role, record)
    response = requests.get(record["url"], timeout=30)
    response.raise_for_status()
    raw = response.content
    digest = hashlib.sha256(raw).hexdigest()
    if record.get("sha256", digest) != digest:
        raise ValueError(f"{role}: source image changed")
    source = Image.open(io.BytesIO(raw)).convert("RGBA")
    bounds = source.getchannel("A").getbbox()
    if not bounds or bounds == (0, 0, *source.size):
        raise ValueError(f"{role}: expected a transparent model silhouette")
    model = source.crop(bounds)
    model.thumbnail((78, 87), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (80, 90))
    canvas.alpha_composite(model, ((80 - model.width) // 2, 89 - model.height))
    canvas.save(OUT / (role + ".png"), optimize=True)
    return role, digest


if __name__ == "__main__":
    catalog = json.loads(SOURCES.read_text())
    OUT.mkdir(exist_ok=True, parents=True)
    selected = [
        (role, definition)
        for role, definition in catalog.items()
        if not sys.argv[1:] or role in sys.argv[1:]
    ]
    # Rebuild canonical imports before reading them as authored costume bases.
    for batch in (
        [row for row in selected if "adaptation" not in row[1]],
        [row for row in selected if "adaptation" in row[1]],
    ):
        with ThreadPoolExecutor(max_workers=5) as pool:
            for role, digest in pool.map(import_role, batch):
                print(role, digest[:12])
                catalog[role]["sha256"] = digest
    SOURCES.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
