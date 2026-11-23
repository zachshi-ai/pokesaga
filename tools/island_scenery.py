"""Local terrain features, original circuit paths and landmarks visible from the player's route."""

from functools import lru_cache
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]


@lru_cache(None)
def edition_points():
    fields = {}

    def add(mid, rows):
        fields.setdefault(mid, set()).update(tuple(r["at"]) for r in rows if "at" in r)

    for mid, data in json.loads(
        (ROOT / "content/alola_ground.json").read_bytes()
    ).items():
        add(mid, data["add"])
    for group in json.loads(
        (ROOT / "content/alola_berries.json").read_bytes()
    ).values():
        for mid, rows in group.items():
            add(mid, rows)
    for group in json.loads(
        (ROOT / "content/alola_machines.json").read_bytes()
    ).values():
        for m in group.values():
            add(m["map"], [m])
    return fields


def signpost(f, scene):
    # The canyon's suspended bridge has ropes, hanging posts and real plank joints.
    # Its deck follows an existing valid route, including the USUM encounters.
    mid = f.mid
    if mid not in {
        "canyon_174",
        "mahalo_bridge",
        "blueberry_canyon",
        "poni_gauntlet",
        "distortion_cascade",
    }:
        return
    sx, sy = f.story
    connected = f.limits()
    h, w = connected.shape
    ground = ~(f.terrain_solid | f.water)
    best = None
    for yy in range(max(1, sy - 10), min(h - 1, sy + 11)):
        for xx in range(max(2, sx - 6), min(w - 2, sx + 7)):
            if not connected[yy, xx]:
                continue
            for axis in (0, 1):
                run = []
                for i in range(-6, 7):
                    a, b = (xx + i, yy) if axis == 0 else (xx, yy + i)
                    safe = all(
                        0 <= x < w
                        and 0 <= y < h
                        and ground[y, x]
                        and not f.occupied[y, x]
                        for x, y in [(a, b), (a, b + 1) if axis == 0 else (a + 1, b)]
                    )
                    if safe:
                        run.append((a, b))
                    elif len(run) >= 5:
                        break
                    else:
                        run = []
                if len(run) < 5:
                    continue
                center = run[len(run) // 2]
                score = len(run) - 0.38 * (abs(sx - center[0]) + abs(sy - center[1]))
                if best is None or score > best[0]:
                    best = (score, run, axis)
    if not best:
        return
    _, run, axis = best
    d = ImageDraw.Draw(scene)
    p = 16
    for i, (x, y) in enumerate(run):
        u = x * p
        v = y * p
        if axis:
            for off in (0, 5, 10):
                d.rectangle(
                    (u, v + off, u + 30, v + off + 4),
                    fill=["#b68e62", "#c29d6e", "#a98a66"][i % 3],
                    outline="#89725a",
                )
                d.point((u + 4, v + off + 2), fill="#61594d")
                d.point((u + 26, v + off + 2), fill="#61594d")
        else:
            for off in (0, 5, 10):
                d.rectangle(
                    (u + off, v, u + off + 4, v + 30),
                    fill=["#b68e62", "#c29d6e", "#aa8a69"][i % 3],
                    outline="#89725a",
                )
                d.point((u + off + 2, v + 4), fill="#625849")
                d.point((u + off + 2, v + 26), fill="#625849")
    for side in (0, 30):
        rope = []
        for i, (x, y) in enumerate(run):
            xx = x * p + (side if axis else 4)
            yy = y * p + (2 if axis else side)
            if i % 3 == 0 or i == len(run) - 1:
                d.rectangle(
                    (xx - 2, yy - 5, xx + 2, yy + 2), fill="#846645", outline="#5f5348"
                )
                rope.append((xx, yy - 5))
            else:
                rope.append((xx, yy - 2))
        d.line(rope, fill="#6c6255", width=2)
        d.line([(x, y - 1) for x, y in rope], fill="#dcc89b")


def town_edges(f):
    # Rebuild house blocks on the dry, closed plots of the retail street survey;
    # the shop fronts handled by front() retain the coordinates of all usable doors.
    styles = {
        "oldtown": ("home_green", "home"),
        "westerntown": ("home_green", "home_city"),
        "promenade": ("home_blue", "home_city"),
        "ruinsvillage": ("home", "home_green"),
        "derelictstreet": ("home_city", "home_blue"),
        "harbour": ("home_blue", "home_city"),
        "snowtown": ("home_green", "home"),
        "festival": ("stall", "pergola"),
        "prismcity": ("lab", "coil"),
    }
    if f.style not in styles:
        return
    allowed = f.terrain_solid & ~f.offmap & ~f.seascape & ~f.water
    edge = ndimage.binary_dilation(f.limits(), iterations=5)
    mask = allowed & edge
    if getattr(f, "survey_rgb", None) is not None:
        r, g, b = f.survey_rgb.transpose(2, 0, 1)
        mask &= ~((g > r * 1.23) & (g > b * 1.08))
    components, _ = ndimage.label(mask)
    groups = ndimage.find_objects(components)
    fx, fy = f.spawn
    sites = []
    for j, bbox in enumerate(groups, 1):
        if not bbox:
            continue
        ys, xs = bbox
        if (xs.stop - xs.start) < 4 or (ys.stop - ys.start) < 3:
            continue
        for y in range(ys.start + 2, ys.stop, 5):
            for x in range(xs.start + 2, xs.stop - 1, 7):
                if components[y, x] != j:
                    continue
                if not mask[y - 2 : y + 1, x - 2 : x + 2].all():
                    continue
                sites.append((abs(x - fx) + abs(y - fy), x, y))
    for i, (_, x, y) in enumerate(sorted(sites)[:16]):
        key = styles[f.style][i % 2]
        f.place(key, (x, y), max_shift=1, scenic=True)


def pattern(f, scene):
    mid = f.mid
    d = ImageDraw.Draw(scene)
    sx, sy = f.story
    p = 16
    cx = sx * p + 8
    cy = sy * p + 8
    if mid == "battle_tree":
        # The battle court is built into a living tree. A timber deck is flush with the
        # walkable floor; its stem, roots and native canopy occupy the backdrop.
        poly = [
            (cx - 65, cy - 26),
            (cx - 49, cy - 41),
            (cx + 50, cy - 41),
            (cx + 64, cy - 26),
            (cx + 64, cy + 35),
            (cx + 46, cy + 47),
            (cx - 45, cy + 47),
            (cx - 65, cy + 35),
        ]
        overlay = scene.copy()
        t = ImageDraw.Draw(overlay)
        t.polygon(poly, fill="#af9168", outline="#685e4c", width=3)
        clip = Image.new("1", scene.size)
        ImageDraw.Draw(clip).polygon(poly, fill=1)
        for y in range(cy - 40, cy + 47, 6):
            t.line((cx - 65, y, cx + 65, y), fill="#927757")
            t.line((cx - 65, y + 1, cx + 65, y + 1), fill="#c5a47a")
            for x in range(cx - 70 + (y % 4) * 6, cx + 65, 22):
                t.line((x, y + 2, x, y + 5), fill="#9a8160")
        t.ellipse((cx - 23, cy - 16, cx + 23, cy + 16), outline="#e3c397", width=2)
        scene.paste(overlay, mask=clip)
    elif mid in {
        "canyon_175",
        "altar",
        "moone",
        "conflict",
        "hope",
        "life",
        "abundance",
        "crown_ruins",
        "armor_towers",
    }:
        cool = mid in {"moone", "hope", "crown_ruins"}
        frame = "#8b98a1" if cool else "#ac9478"
        glint = "#cdd6cb" if cool else "#e6ce9f"
        overlay = scene.copy()
        t = ImageDraw.Draw(overlay)
        for i in range(4):
            yy = cy + 24 + i * 5
            wid = 33 + i * 5
            t.line((cx - wid, yy, cx + wid, yy), fill=frame, width=3)
            t.line((cx - wid, yy - 1, cx + wid, yy - 1), fill=glint)
        for dx in (-1, 1):
            for i in range(3):
                xx = cx + dx * (28 + i * 8)
                yy = cy - 2 + i * 5
                t.line(
                    (xx - 4, yy + 2, xx, yy - 3, xx + 4, yy + 2), fill=glint, width=2
                )
        mask = Image.fromarray(
            ((~f.terrain_solid & ~f.water) * 255).astype("uint8")
        ).resize(scene.size, Image.Resampling.NEAREST)
        scene.paste(overlay, mask=mask)
    elif f.style == "abyss":
        # Deep Sea air bubbles and phosphorescent vents mark its floor at GBA scale.
        selected = (
            (np.sin(f.x * 0.55 + f.y * 0.23) > 0.91)
            & (np.cos(f.x * 0.45 - f.y * 0.52) > 0.72)
            & ~f.s
            & ~f.water
        )
        for yy, xx in np.argwhere(selected):
            x = xx * p + 8
            y = yy * p + 9
            for dx, dy, r in ((0, 0, 2), (3, -6, 1), (-3, -13, 1)):
                d.ellipse(
                    (x + dx - r, y + dy - r, x + dx + r, y + dy + r), outline="#b5adcc"
                )
    elif mid in {
        "paniola_ranch",
        "paniola",
        "kitakami_orchard",
        "berry_fields",
        "armor_fields",
    }:
        # Hoof tracks follow patches of packed ground. The gate and its hinge posts remain solid.
        for y, x in np.argwhere(f.route & ~f.s & ~f.water & ~f.grass):
            if (x + 2 * y) % 11 or (y + x // 3) % 3:
                continue
            for dx, dy in ((4, 5), (8, 9)):
                d.arc(
                    (x * 16 + dx, y * 16 + dy, x * 16 + dx + 2, y * 16 + dy + 3),
                    0,
                    210,
                    fill="#a18b62",
                )
    signpost(f, scene)
    return scene


def flower_meadow(f, grid):
    # A meadow uses drifts of one island flower on soft grass, with isolated leaves.
    st = f.style
    if st not in {
        "wildflowers",
        "forestdell",
        "rainforest",
        "garden",
        "orchard",
        "forest",
        "bamboo",
        "grassland",
        "ranch",
    }:
        return
    from kalos_gym_rooms import tile

    grass = tile("grass").convert("RGB")
    arr = np.array(grass).astype(float)
    darker = Image.fromarray(
        np.uint8(np.clip(arr * [0.85, 0.92, 0.82] + [4, 4, 3], 0, 255))
    )
    mask = (f.drifts > 0.45) & ~(f.terrain_solid | f.water | f.grass | f.route)
    grid[mask] = np.asarray(darker)
    # A verge in the atlas is a flowering hedge with a wooden rail; reserve it for real
    # hedge beds rather than using that chip to paint shade on the floor.
    grid[(f.land == "verge") & ~f.terrain_solid] = np.asarray(darker)
    if st in {"wildflowers", "forestdell", "garden"}:
        bymid = {
            "melemele_meadow": "#dfbf69",
            "ulaula_meadow": "#c47874",
            "poni_meadow": "#b99bcb",
        }
        color = bymid.get(f.mid, "#dcba8d")
        fl = grass.copy()
        pen = ImageDraw.Draw(fl)
        for x, y in ((4, 5), (11, 10), (6, 13)):
            pen.line((x, y + 1, x - 1, y + 3), fill="#568267")
            pen.rectangle((x - 1, y - 1, x + 1, y + 1), fill=color)
            pen.point((x, y), fill="#eed598")
        grid[mask & (f.drifts > 1.07)] = np.asarray(fl)
