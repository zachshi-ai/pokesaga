#!/usr/bin/env python3
"""Bake the Galar, Hisui and Paldea GBA field plans using the pinned pret/pokeemerald art."""

import argparse
from collections import defaultdict
import heapq
import json
from pathlib import Path
import zlib
import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import Emerald, pack
from switch_fields.art import ROOT, BUILDINGS, asset
from switch_fields.terrain import relief, finish_ground, FOREST
from switch_fields.rooms import signature, generated_room


def arrival_views():
    views = {}
    for line in (
        (ROOT / "tools/switch_fields/arrival_views.txt").read_text().splitlines()
    ):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        mid, *features = line.split()
        views[mid] = {
            key: tuple(map(int, at.split(",")))
            for key, at in (f.split(":") for f in features)
        }
    return views


VIEWS = arrival_views()

REGIONS = ("galar", "hisui", "paldea")
DIRS = [(0, 1), (1, 0), (0, -1), (-1, 0)]
BASE = ROOT / "content/regions"
ART = ROOT / "assets/switch_fields/maps"
FIXED = {
    "hisui_village": "galaxy",
    "galar_stadium": "stadiumgate",
    "galar_rose": "rosehead",
    "paldea_academy": "uva",
    "paldea_league": "leaguegate",
    "paldea_lab": "zerolab",
}
DECALS = {
    "court",
    "mosaic",
    "plaza",
    "geoglyph",
    "stairs",
    "steep",
    "floe",
    "rail",
    "viaduct",
    "timberbridge",
    "jetty",
}


def read(p):
    return json.loads(p.read_bytes())


def write(p, v):
    p.write_text(json.dumps(v, ensure_ascii=False, separators=(",", ":")) + "\n")


def mapfile(key):
    return BASE / key.split("_")[0] / "maps" / (key + ".json")


def specifications():
    out = {}
    region = ""
    for raw in (ROOT / "tools/switch_fields/landscapes.txt").read_text().splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("["):
            region = s[1:-1]
            continue
        key, rows, road, landmarks = map(str.strip, s.split("|"))
        out[region + "_" + key] = (
            rows.split("/"),
            road.split(),
            [f.strip() for f in landmarks.split(",")],
        )
    return out


def dimensions(mid, m):
    w, h = m["size"]
    region, short = mid.split("_", 1)
    if m.get("switch_field_revision"):
        return (w, h)
    if short in {
        "pass_armor_fields",
        "pass_crown_freezington",
        "pass_kalos_cyllage",
        "pass_kitakami_road",
        "pass_unova_undella",
        "n3",
        "weald",
        "wedgehurst",
        "postwick",
    }:
        return (w, h)
    if m["style"] in ("town", "city", "interior") or mid in FIXED:
        return w, h
    factor = (
        2.15
        if region == "hisui"
        and short in ["obsidian", "coastlands", "highlands", "mirelands", "icelands"]
        else 1.65
        if region == "paldea"
        and short
        in ["asado", "lake", "zero", "glaseado", "socarrat", "tagtree", "bamboo"]
        else 1.36
    )
    return int(w * factor) | 1, int(h * factor) | 1


def edgepoint(p, old, new):
    # The registry's coordinates still represent the arrival party and service NPCs. Extend
    # the far map edges; change only an outward transition or the cell immediately inside it.
    return [
        n - oldv + newv if n >= oldv - 2 else n for n, oldv, newv in zip(p, old, new)
    ]


def galar_facades(props):
    """Swap just the art at the existing building lot. Each sprite's centreline is its doorway."""
    for prop in props:
        if not prop[0].startswith("res://assets/switch_fields/props/"):
            continue
        sprite = ROOT / "assets/galar/architecture" / Path(prop[0]).name
        if sprite.is_file():
            with Image.open(sprite) as art:
                prop[0] = "res://" + sprite.relative_to(ROOT).as_posix()
                prop[3] = [art.width // 2, art.height]


def scene(mid, m, im, grid, props):
    if mid.startswith("galar_"):
        galar_facades(props)
    ART.mkdir(parents=True, exist_ok=True)
    f = ART / (mid + ".png")
    im.quantize(200, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
        f, optimize=True
    )
    w, h = im.width // 16, im.height // 16
    m.update(
        size=[w, h],
        tiles=grid.tolist(),
        art_props=[],
        switch_field_revision=1,
        hoenn_art={
            "s": [w, h],
            "t": pack(np.zeros((h, w), dtype="<u2")),
            "p": props,
            "scene": ["res://" + str(f.relative_to(ROOT)), 0, 0],
        },
    )
    write(mapfile(mid), m)


class Field:
    def __init__(self, em, mid, m, spec, arrivals):
        self.em, self.mid, self.m = em, mid, m
        self.region = mid.split("_")[0]
        self.w, self.h = m["size"]
        self.seed = zlib.crc32(mid.encode())
        self.rows, self.road, self.landmarks = spec
        self.base = relief(self.rows, self.w, self.h, self.seed % 1993)
        # Arrival positions predate these terrains. Shape a real shoreline for standing
        # actors where a painted lake would otherwise leave a disconnected plank.
        sx, sy = m["spawn"]
        yy, xx = np.indices((self.h, self.w))
        nearby = (xx - sx) ** 2 / 36 + (yy - sy) ** 2 / 16 < 1
        bad = np.isin(self.base, list("WCK"))
        dry = {
            "galar_mine": "V",
            "galar_mine2": "V",
            "paldea_inlet": "V",
            "paldea_cave": "V",
            "galar_tunnel": "V",
            "hisui_mirelands": "X",
            "hisui_coastlands": "S",
            "paldea_asado": "D",
            "hisui_icelands": "N",
            "galar_9": "N",
            "galar_10": "N",
            "galar_slope": "N",
            "paldea_glaseado": "N",
        }.get(mid, "G")
        if bad[sy, sx]:
            # Extend the point of land back to the nearest bank rather than isolating it
            # in the middle of the lake. The taper follows the surveyed shoreline.
            candidates = np.argwhere(~bad)
            if len(candidates):
                by, bx = min(
                    candidates,
                    key=lambda v: (int(v[0]) - sy) ** 2 + (int(v[1]) - sx) ** 2,
                )
                pts = Image.new("1", (self.w, self.h))
                pen = ImageDraw.Draw(pts)
                pen.line(
                    [
                        (sx, sy),
                        ((sx + int(bx)) // 2, (sy + int(by)) // 2 + 1),
                        (int(bx), int(by)),
                    ],
                    fill=1,
                    width=5,
                )
                nearby |= np.asarray(pts, dtype=bool)
        self.base[nearby & bad] = dry
        self.surface = self.base.copy()
        self.city = m["style"] in ("town", "city")
        self.grid = np.zeros((self.h, self.w), dtype="uint8")
        self.reserved = set()
        self.goals = []
        self.props = []
        self.decals = []
        self.doors = []
        self.rooms = {}
        self.placed = []
        self.decks = []
        self.falls = []
        self.water_reservations = set()
        self.npcs = {tuple(v["at"]) for v in m["npcs"]}
        self.signs = {tuple(v["at"]) for v in m["objects"]}
        self.ports = {tuple(v["at"]) for v in m["warps"]}
        self.arrivals = set(arrivals) | {tuple(m["spawn"])}
        self.required = self.arrivals | self.npcs | self.signs | self.ports
        self.reserved.update(self.required)
        self.footprint = set()

    def coord(self, s):
        return tuple(
            round(int(n) * (dim - 1) / 9) for n, dim in zip(s, (self.w, self.h))
        )

    def valid(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def near(self, x, y, r):
        return [
            (xx, yy)
            for yy in range(max(1, y - r), min(self.h - 1, y + r + 1))
            for xx in range(max(1, x - r), min(self.w - 1, x + r + 1))
        ]

    def bounds(self, x, y, img, solid):
        left = (x * 16 + 8 - img.width // 2 + 3) // 16
        right = (x * 16 + 8 - img.width // 2 + img.width - 4) // 16
        depth = (
            max(2, (img.height + 1) // 16)
            if solid
            else max(1, min(2, (img.height + 4) // 16))
        )
        return {
            (xx, yy)
            for xx in range(left, right + 1)
            for yy in range(y - depth + 1, y + 1)
        }

    def deck(self, key, target):
        # Find a real shore or ravine at this landmark. A boardwalk terminates in water;
        # a bridge has dry ground at both ends. Keep its full walking surface and railings together.
        tx, ty = target
        jetty = key == "jetty"
        choices = []
        wet = "W" if jetty else "WC"
        for x, y in self.near(tx, ty, 12):
            if self.base[y, x] in "WCK" or (x, y) in self.reserved:
                continue
            for dx, dy in DIRS:
                cells = []
                for n in range(1, 15):
                    xx, yy = x + n * dx, y + n * dy
                    if (
                        not (1 <= xx < self.w - 1 and 1 <= yy < self.h - 1)
                        or (xx, yy) in self.reserved
                    ):
                        break
                    if self.base[yy, xx] in wet:
                        cells.append((xx, yy))
                        if jetty and len(cells) == 4:
                            break
                    else:
                        break
                if len(cells) < 2:
                    continue
                last = cells[-1]
                end = (last[0] + dx, last[1] + dy)
                if not jetty and (
                    not self.valid(*end)
                    or self.base[end[1], end[0]] in "WCK"
                    or end in self.reserved
                ):
                    continue
                mid = cells[len(cells) // 2]
                score = (
                    abs(mid[0] - tx)
                    + abs(mid[1] - ty)
                    + (0 if jetty else abs(len(cells) - 5) * 0.3)
                )
                choices.append((score, x, y, dx, dy, cells, end))
        if not choices:
            # An inland viaduct carries the route above a dry valley.
            for x, y in self.near(tx, ty, 9):
                cells = [(x + i, y) for i in range(1, 5)]
                end = (x + 5, y)
                if any(
                    not self.valid(xx, yy)
                    or (xx, yy) in self.reserved
                    or xx >= self.w - 1
                    for xx, yy in cells + [end]
                ):
                    continue
                choices.append((abs(x + 2 - tx) + abs(y - ty), x, y, 1, 0, cells, end))
        if not choices:
            raise ValueError((self.mid, "no crossing", key))
        _, x, y, dx, dy, cells, end = min(choices)
        self.goals.append((x, y))
        if not jetty:
            self.goals.append(end)
        for xx, yy in cells:
            self.surface[yy, xx] = "!" if dx else "="
        self.decks.append((cells, dx, dy, jetty))
        self.reserved.update(cells + [(x, y)] + ([] if jetty else [end]))

    def waterfall(self, target):
        # A cascade needs a lip and a plunge pool on the same watercourse. Put its
        # base inside the actual river and keep the approach to the bank unobstructed.
        tx, ty = target
        choices = []
        for y in range(5, self.h - 3):
            for x in range(3, self.w - 3):
                cells = {
                    (xx, yy) for xx in (x - 1, x, x + 1) for yy in range(y - 3, y + 3)
                }
                if cells & self.reserved or self.base[y + 1, x] != "W":
                    continue
                score = abs(x - tx) + abs(y - ty) + 4 * (self.base[y - 3, x] == "W")
                choices.append((score, y, x, cells))
        if not choices:
            raise ValueError((self.mid, "no waterfall shore"))
        _, y, x, cells = min(choices)
        self.falls.append((x, y))
        self.reserved |= cells
        self.water_reservations |= cells
        for xx, yy in cells:
            self.base[yy, xx] = "W"
            self.surface[yy, xx] = "W"
        for xx in [x - 2, x + 2]:
            for yy in range(y - 2, y + 1):
                if (xx, yy) not in self.reserved:
                    self.base[yy, xx] = "C"
                    self.surface[yy, xx] = "C"
        self.placed.append(("waterfall", x, y))

    def add(self, key, target, fixed=False):
        if key == "waterfall":
            self.waterfall(target)
            return
        if key in ("jetty", "viaduct", "timberbridge"):
            self.deck(key, target)
            return
        img, path, anchor = asset(key)
        is_house = key in BUILDINGS
        decal = key in DECALS
        x, y = target
        candidates = [target] if fixed else self.near(x, y, 8 if self.city else 11)
        choices = []
        for xx, yy in candidates:
            feet = self.bounds(xx, yy, img, is_house)
            front = (xx, yy + 1)
            points = feet | {front}
            if any(
                not self.valid(a, b)
                or a == 0
                or b == 0
                or a == self.w - 1
                or b == self.h - 1
                for a, b in points
            ):
                continue
            if not fixed and (points & self.reserved or points & self.footprint):
                continue
            if fixed and (feet & self.footprint):
                continue
            wet = sum(self.base[b, a] in "WCK" for a, b in feet)
            special = key in (
                "jetty",
                "waterfall",
                "floe",
                "wreck",
                "buoy",
                "viaduct",
                "timberbridge",
            )
            penalty = 0 if special else wet * (4 if is_house else 1)
            choices.append((abs(xx - x) + abs(yy - y) + penalty, yy, xx))
        if not choices:
            raise ValueError((self.mid, "no site", key, target))
        _, y, x = min(choices)
        feet = self.bounds(x, y, img, is_house)
        front = (x, y + 1)
        if decal:
            self.decals.append((img, x, y))
            self.reserved.update(feet)
            if key in (
                "court",
                "plaza",
                "mosaic",
                "maze",
                "stairs",
                "steep",
                "geoglyph",
            ):
                for xx, yy in feet:
                    self.surface[yy, xx] = "p" if self.city else "d"
                self.goals.append(front)
            return
        self.props.append([path, x, y, anchor])
        self.footprint |= feet
        self.reserved |= feet | {front}
        self.placed.append((key, x, y))
        for xx, yy in feet:
            if is_house or self.base[yy, xx] not in "W":
                self.surface[yy, xx] = "p" if self.city else "d"
        if is_house:
            self.goals.append(front)
            self.surface[front[1], front[0]] = "p" if self.city else "d"
            if fixed:
                self.doors.append((x, y))
                return
            roomid = self.mid + "_" + key + "_room"
            if roomid in self.rooms:
                roomid = self.mid + "_" + key + str(len(self.rooms)) + "_room"
            room, im, grid, props = generated_room(
                self.em, self.mid, key, self.m, (x, y), self.region
            )
            self.rooms[roomid] = (room, im, grid, props)
            self.m["warps"].append(
                {
                    "at": [x, y],
                    "trigger": "door",
                    "to": {"region": self.region, "map": roomid, "at": room["spawn"]},
                    "switch_door": True,
                }
            )
            self.doors.append((x, y))
        elif (
            key
            not in (
                "ore",
                "cairn",
                "log",
                "driftwood",
                "floe",
                "buoy",
                "waterfall",
                "bamboo",
                "crystal",
                "fir",
            )
            and self.base[y, x] != "W"
        ):
            self.goals.append(front)

    def route(self, start, goal):
        heap = [(0, start)]
        dist = {start: 0}
        prev = {}
        goal = tuple(goal)
        while heap:
            cost, p = heapq.heappop(heap)
            if p == goal:
                break
            if cost != dist[p]:
                continue
            for dx, dy in DIRS:
                xx, yy = p[0] + dx, p[1] + dy
                q = (xx, yy)
                if (xx, yy) in self.water_reservations:
                    continue
                if not self.valid(xx, yy) or (
                    q != goal
                    and (
                        q in self.footprint
                        or q in self.npcs
                        or q in self.ports
                        or q in self.signs
                    )
                ):
                    continue
                if (xx in (0, self.w - 1) or yy in (0, self.h - 1)) and q != goal:
                    continue
                k = self.surface[yy, xx]
                step = (
                    0.7
                    if k in "=!dp^"
                    else 4
                    if k in FOREST
                    else 12
                    if k in "CK"
                    else 18
                    if k == "W"
                    else 1.8
                )
                n = cost + step
                if n < dist.get(q, 1e20):
                    dist[q] = n
                    prev[q] = p
                    heapq.heappush(heap, (n, q))
        if goal != start and goal not in prev:
            raise ValueError((self.mid, "unreachable", start, goal))
        path = [goal]
        while path[-1] != start:
            path.append(prev[path[-1]])
        return path[::-1]

    def drawpath(self, points, width):
        cells = set()
        for i, (x, y) in enumerate(points):
            around = [(x, y)] if width == 1 else [(x, y), (x + 1, y), (x, y + 1)]
            for xx, yy in around:
                if (xx, yy) in self.water_reservations:
                    continue
                if not self.valid(xx, yy) or (xx, yy) in self.footprint:
                    continue
                if xx in (0, self.w - 1) or yy in (0, self.h - 1):
                    if (xx, yy) not in self.ports:
                        continue
                cells.add((xx, yy))
                k = self.base[yy, xx]
                dx = points[min(i + 1, len(points) - 1)][0] - points[max(i - 1, 0)][0]
                self.surface[yy, xx] = (
                    "!"
                    if k == "W" and dx
                    else "="
                    if k == "W"
                    else "^"
                    if k in "CK"
                    else "p"
                    if self.city
                    else "d"
                )
        return (cells & set(points)) - self.npcs - self.signs - self.ports

    def safe(self, at):
        x, y = at
        points = self.near(x, y, 5)
        return min(
            (
                p
                for p in points
                if p
                not in self.footprint
                | self.npcs
                | self.ports
                | self.signs
                | self.water_reservations
            ),
            key=lambda p: abs(p[0] - x) + abs(p[1] - y),
        )

    def streets(self):
        fixedgoals = []
        for w in self.m["warps"]:
            x, y = w["at"]
            target = w["to"]["map"]
            inside = 1 < x < self.w - 2 and 1 < y < self.h - 2
            if target in FIXED and inside:
                self.add(FIXED[target], (x, y), True)
                w["trigger"] = "door"
                fixedgoals.append((x, y + 1))
        focus = VIEWS.get(self.mid, {}).copy()
        sx, sy = self.m["spawn"]
        for feat in self.landmarks:
            key, pos = feat.split("@")
            target = self.coord(pos)
            if key in focus:
                dx, dy = focus.pop(key)
                target = (sx + dx, sy + dy)
            self.add(key, target)
        # Small fixtures belong to the street they serve: clay jars by the kiln,
        # baskets at a landing, thick reeds on the camp bank and gas lamps in shop streets.
        dressing = {
            "hisui_mirelands": [
                ("reed", -4, -2),
                ("reed", 4, 2),
                ("log", -5, 2),
                ("reed", 2, 3),
            ],
            "galar_mine": [("ore", -4, -2), ("crate", 3, 2)],
            "galar_mine2": [("crystal", -4, -2), ("timbers", 4, 2)],
            "hisui_jubilife": [("crate", -4, 1), ("berry", 5, 2)],
            "galar_motostoke": [("lamp", -4, 1), ("crate", 4, 1)],
            "paldea_artazon": [("sunflower", 3, 2), ("flowers", -4, 2)],
            "paldea_cabo": [("flowers", -4, 2), ("berry", 4, 2)],
            "paldea_lake": [("reed", -3, -2), ("driftwood", 4, 2)],
            "paldea_alfornada": [("urn", 4, 2), ("urn", -4, -2)],
            "paldea_levincia": [("lamp", 3, 2), ("bench", -4, 2)],
            "paldea_marinada": [("urn", 4, 2), ("crate", -4, -2)],
            "paldea_mesagoza": [("lamp", -4, 2), ("flowers", 4, 2)],
            "galar_wyndon": [("lamp", -4, -2), ("bench", 3, 2)],
            "paldea_medali": [("bench", 4, 2), ("urn", -4, -2)],
        }
        for key, dx, dy in dressing.get(self.mid, []):
            self.add(key, (sx + dx, sy + dy))
        spine = [self.safe(self.coord(s)) for s in self.road]
        network = {spine[0]}
        for a, b in zip(spine, spine[1:]):
            network |= self.drawpath(self.route(a, b), 2)
        self.reserved |= network
        # Each street meets the approach to an actual door. Keep existing board, actor and
        # transfer positions clear. Doorfronts and return coordinates are distinct cells.
        touch = {self.safe(p) for p in self.npcs | self.signs}
        self.goals += (
            list(self.arrivals)
            + fixedgoals
            + list(self.ports - set(self.doors))
            + list(touch)
        )
        for p in sorted(set(self.goals), key=lambda p: (p[1], p[0])):
            if p in self.footprint or p in self.npcs:
                continue
            near = min(network, key=lambda q: (abs(q[0] - p[0]) + abs(q[1] - p[1]), q))
            path = self.route(near, p)
            network |= self.drawpath(path, 1 if p in touch else 2)
        for p in self.npcs | self.signs:
            x, y = p
            if p not in self.footprint:
                self.surface[y, x] = "p" if self.city else "d"
        self.reserved |= network | self.arrivals

    def plant(self):
        h, w = self.grid.shape
        self.grid[np.isin(self.surface, list("CK"))] = 1
        self.grid[self.surface == "W"] = 2
        self.grid[self.surface == "Y"] = 11
        self.grid[[0, -1], :] = 1
        self.grid[:, [0, -1]] = 1
        for x, y in self.ports:
            if (x, y) not in self.doors:
                self.grid[y, x] = 0
        for x, y in self.footprint:
            self.grid[y, x] = 1
        for x, y in self.arrivals | self.npcs | self.signs:
            if (x, y) not in self.footprint:
                self.grid[y, x] = 0
        for y in range(2, h - 1):
            for x in range(1, w - 1):
                k = self.surface[y, x]
                noise = (x * 73856093 ^ y * 19349663 ^ self.seed) % 101
                if k in FOREST and y % 2 == 0 and x % 2 == (y // 2) % 2:
                    key = {
                        "F": "tree",
                        "M": "mushwood",
                        "T": "autumn",
                        "L": "snowtree",
                        "H": "bamboo",
                        "O": "olive",
                    }[k]
                elif k in "GB" and noise < 4:
                    key = "flowers"
                elif k == "Z" and noise < 17:
                    key = "crystal"
                elif k == "E" and noise < 19:
                    key = "reed"
                elif k == "D" and noise == 1:
                    key = "cactus"
                else:
                    continue
                pts = {(x, y), (x - 1, y)} if k in "FLMTO" else {(x, y)}
                if pts & self.reserved or pts & self.footprint:
                    continue
                if key in ("tree", "flowers"):
                    self.props.append([key, x, y])
                else:
                    _, path, anchor = asset(key)
                    self.props.append([path, x, y, anchor])
                if key != "flowers":
                    for xx, yy in pts:
                        self.grid[yy, xx] = 1
        for x, y in sorted(self.signs):
            self.props.append(["sign", x, y])
            self.grid[y, x] = 1

    def finish(self):
        self.streets()
        for cells, dx, dy, _ in self.decks:
            for x, y in cells:
                self.surface[y, x] = "!" if dx else "="
        for x, y in self.falls:
            for xx in (x - 1, x, x + 1):
                for yy in range(y - 3, y + 3):
                    self.surface[yy, xx] = "W"
        self.plant()
        im = finish_ground(self.em, self.mid, self.base, self.surface)
        for art, x, y in self.decals:
            # Decals sit behind the player; narrow decorative bridges only cross visible water.
            xx, yy = x * 16 + 8 - art.width // 2, (y + 1) * 16 - art.height
            if (
                self.base[y, x] == "W"
                and self.grid[y, x] == 2
                and (x, y) not in self.reserved
            ):
                continue
            im.paste(art, (xx, yy), art)
        for x, y in self.falls:
            cascade, _, _ = asset("waterfall")
            im.paste(
                cascade,
                (x * 16 + 8 - cascade.width // 2, (y + 1) * 16 - cascade.height),
                cascade,
            )
        pen = ImageDraw.Draw(im)
        for cells, dx, dy, jetty in self.decks:
            for i, (x, y) in enumerate(cells):
                left, top = x * 16, y * 16
                for offset in (1, 14):
                    if dx:
                        pen.line(
                            (left, top + offset, left + 15, top + offset),
                            fill="#745e48",
                            width=2,
                        )
                    else:
                        pen.line(
                            (left + offset, top, left + offset, top + 15),
                            fill="#745e48",
                            width=2,
                        )
                if i % 2 == 0:
                    for offset in (1, 14):
                        a, b = (
                            (left + 5, top + offset) if dx else (left + offset, top + 5)
                        )
                        pen.rectangle(
                            (a - 1, b - 2, a + 1, b + 1),
                            fill="#8c704e",
                            outline="#65594b",
                        )
        if self.mid in ("galar_mine", "galar_mine2"):
            cart = next((q for q in self.placed if q[0] in ("minecart", "pump")), None)
            if cart:
                p = (cart[1], cart[2] + 1)
                gate = tuple(self.m["warps"][0]["at"])
                route = self.route(p, gate)
                for (ax, ay), (bx, by) in zip(route[2:-2], route[3:-1]):
                    if self.grid[ay, ax] or self.grid[by, bx]:
                        continue
                    x, y = ax * 16 + 8, ay * 16 + 8
                    endx, endy = bx * 16 + 8, by * 16 + 8
                    vx, vy = bx - ax, by - ay
                    for z in (0, 8):
                        qx, qy = x + vx * z, y + vy * z
                        pen.line(
                            (qx - vy * 5, qy + vx * 5, qx + vy * 5, qy - vx * 5),
                            fill="#72614f",
                            width=3,
                        )
                    for side in (-3, 3):
                        pen.line(
                            (
                                x + vy * side,
                                y - vx * side,
                                endx + vy * side,
                                endy - vx * side,
                            ),
                            fill="#a8a9a3",
                            width=2,
                        )
        self.m["switch_sites"] = [{"kind": k, "at": [x, y]} for k, x, y in self.placed]
        if self.mid == "galar_hulbury":
            from switch_fields.hulbury import waterfront
            waterfront(self.em, im, self.grid)
        return im, self.grid, self.props


def build(source):
    em = Emerald(source)
    spec = specifications()
    maps = {k: read(mapfile(k)) for k in spec}
    sizes = {k: (m["size"], dimensions(k, m)) for k, m in maps.items()}
    arrivals = defaultdict(set)
    regs = {r: read(BASE / r / "region.json") for r in REGIONS}
    travel = read(ROOT / "content/world_destinations.json")["regions"]
    for mid, m in maps.items():
        old, new = sizes[mid]
        m["size"] = list(new)
        m["warps"] = [v for v in m["warps"] if not v.get("switch_door")]
        m["objects"] = [v for v in m["objects"] if not v.get("switch_sign")]
        for w in m["warps"]:
            w["at"] = edgepoint(w["at"], old, new)
            to = w["to"]
            n = to["map"]
            if n in sizes:
                to["at"] = edgepoint(to["at"], *sizes[n])
                arrivals[n].add(tuple(to["at"]))
    for r in REGIONS:
        for loc in travel[r]["locations"]:
            if "at" in loc:
                arrivals[loc["map"]].add(tuple(loc["at"]))
        hub = travel[r]["hub"]
        arrivals[hub["map"]].add(tuple(hub["at"]))
    for r in (ROOT / "content/regions").iterdir():
        for p in (r / "maps").glob("*.json"):
            if p.stem in maps:
                continue
            rec = read(p)
            if rec.get("switch_room"):
                continue
            for w in rec.get("warps", []):
                t = w.get("to", {})
                if t.get("map") in maps:
                    arrivals[t["map"]].add(tuple(t["at"]))
    output = {}
    newrooms = 0
    for mid, m in maps.items():
        if spec[mid][2] == ["interior"]:
            im, g, p = signature(em, mid, m)
        else:
            field = Field(em, mid, m, spec[mid], arrivals[mid])
            im, g, p = field.finish()
            output.update(field.rooms)
            newrooms += len(field.rooms)
        output[mid] = (m, im, g, p)
    for mid, args in output.items():
        scene(mid, *args)
    room_ids = {mid for mid, (m, _, _, _) in output.items() if m.get("switch_room")}
    for r, rec in regs.items():
        local_rooms = sorted(mid for mid in room_ids if mid.startswith(r + "_"))
        rec["maps"] = [mid for mid in rec["maps"] if mid not in room_ids] + local_rooms
        (BASE / r / "region.json").write_text(
            json.dumps(rec, ensure_ascii=False, indent=1)
        )
    # Reattach the playable chapter venues after rebuilding their original city and lobby.
    from build_motostoke_venues import build as build_motostoke
    from build_galar_grass_gym import main as build_turffield
    from build_galar_league_gyms import main as build_league_gyms
    from build_galar_story_sites import main as build_story_sites
    from build_galar_towers import main as build_towers
    from build_galar_habitats import build as build_habitats
    build_motostoke()
    build_turffield()
    build_league_gyms()
    build_story_sites()
    build_towers()
    build_habitats()
    from switch_fields.galar_streets import apply as pave_galar_cities
    pave_galar_cities(em, spec, ROOT)
    from build_galar_atlas import build as build_districts
    build_districts(em)
    print(
        f"{len(maps)} source locations, {newrooms} entered buildings, {sum(len(v[0]['warps']) for v in output.values())} exits; {sum(v[1].width * v[1].height // 256 for v in output.values())} movement cells"
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("emerald", type=Path)
    build(p.parse_args().emerald)
