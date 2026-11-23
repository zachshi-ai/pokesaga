"""Furnish interiors from native Emerald floor, wall and object art."""

import json
import zlib
from collections import deque
from functools import lru_cache
import numpy as np
from PIL import Image, ImageDraw
from .art import ROOT, FIELD, BUILDINGS, asset
from .terrain import masonry

ANCHORS = json.loads((ROOT / "content/emerald_fields.json").read_bytes())["anchors"]
# Crop an actual native room with its own movement layer. Use only single-room spaces;
# upstairs/lift art in multi-floor donors is capped with a bookcase.
DONORS = {
    "gable": "VerdanturfTown_WandasHouse",
    "rowhouse": "DewfordTown_Hall",
    "shop": "Route104_PrettyPetalFlowerShop",
    "factory": "SlateportCity_SternsShipyard_1F",
    "manor": "RustboroCity_CuttersHouse",
    "beacon": "Route104_MrBrineysHouse",
    "castle": "LilycoveCity_LilycoveMuseum_1F",
    "market": "SlateportCity_Harbor",
    "aqueduct": "SlateportCity_OceanicMuseum_1F",
    "lab": "LittlerootTown_ProfessorBirchsLab",
    "theatre": "FallarborTown_BattleTentLobby",
    "hotel": "SlateportCity_PokemonFanClub",
    "station": "BattleFrontier_ReceptionGate",
    "mill": "Route116_TunnelersRestHouse",
    "hall": "RustboroCity_DevonCorp_1F",
    "stadium": "VerdanturfTown_BattleTentLobby",
    "tower": "MossdeepCity_SpaceCenter_1F",
}
ROOM_DONOR = {
    "family": "LittlerootTown_BrendansHouse_1F",
    "bakery": "LavaridgeTown_HerbShop",
    "nursery": "Route117_PokemonDayCare",
    "stationzero": "Route119_WeatherInstitute_1F",
    "eatery": "Route109_SeashoreHouse",
    "lodgings": "MossdeepCity_StevensHouse",
    "concert": "DewfordTown_Hall",
    "lab": "LittlerootTown_ProfessorBirchsLab",
    "books": "RustboroCity_PokemonSchool",
    "fishmarket": "Route109_SeashoreHouse",
    "studio": "LilycoveCity_LilycoveMuseum_1F",
    "market": "SlateportCity_Harbor",
    "cafe": "SlateportCity_PokemonFanClub",
    "leaguehall": "EverGrandeCity_HallOfFame",
    "lakehouse": "LilycoveCity_House1",
}


@lru_cache(None)
def donor(em, native):
    rec = json.loads((em.source / "data/maps" / native / "map.json").read_bytes())
    layout = next(l for l, data in em.layouts.items() if data["id"] == rec["layout"])
    w, h = em.grid(layout).shape[::-1]
    image = em.patch(layout, 0, 0, w, h).convert("RGB")
    raw = np.fromfile(
        em.source / em.layouts[layout]["blockdata_filepath"], dtype="<u2"
    ).reshape(h, w)
    solid = ((raw >> 10) & 3 != 0).astype("uint8")
    entries = [
        (v["x"], v["y"])
        for v in rec["warp_events"]
        if 0 <= v["x"] < w and 0 < v["y"] < h
    ]
    return image, solid, entries


def generated_room(em, mid, key, home, door, region):
    name, form, _ = BUILDINGS[key]
    seed = zlib.crc32((mid + key + str(door)).encode())
    variants = {
        "gable": [
            "VerdanturfTown_WandasHouse",
            "MossdeepCity_StevensHouse",
            "Route104_MrBrineysHouse",
            "LilycoveCity_House1",
            "SlateportCity_NameRatersHouse",
            "RustboroCity_CuttersHouse",
        ],
        "rowhouse": [
            "DewfordTown_Hall",
            "LilycoveCity_House1",
            "VerdanturfTown_WandasHouse",
        ],
        "shop": [
            "Route104_PrettyPetalFlowerShop",
            "LavaridgeTown_HerbShop",
            "MauvilleCity_BikeShop",
        ],
        "market": ["SlateportCity_Harbor", "Route109_SeashoreHouse"],
    }
    available = variants.get(form, [DONORS.get(form, "RustboroCity_CuttersHouse")])
    native = ROOM_DONOR.get(key, available[seed % len(available)])
    base, grid, entries = donor(em, native)
    im = base.copy()
    g = grid.copy()
    h, w = g.shape
    # In a few original lobbies the first portal is a corridor, not the front door.
    front = max(entries, key=lambda p: (p[1], -p[0]))
    exits = [p for p in entries if p[1] == front[1] and abs(p[0] - front[0]) <= 1]
    # The Hoenn hall of fame is an enclosed chamber with an exit well before the south edge.
    if not exits:
        exits = [front]
    x, y = front
    homecell = [door[0], door[1] + 1]
    m = {
        "name": home["name"] + "・" + name,
        "style": "interior",
        "biome": "interior",
        "npcs": [],
        "objects": [],
        "warps": [],
    }

    g[y, x] = 0
    spawn = (x, y - 1)
    g[spawn[1], spawn[0]] = 0
    for xx, yy in exits:
        g[yy, xx] = 0
        g[yy - 1, xx] = 0
        m["warps"].append(
            {
                "at": [xx, yy],
                "trigger": "down",
                "to": {"region": region, "map": mid, "at": homecell},
                "switch_door": True,
            }
        )
    for xx, yy in set(entries) - set(exits):
        # Remove donor-only stairways visually and physically.
        if yy + 1 < h and abs(xx - x) + abs(yy - y) > 3:
            core = im.crop((x * 16, (y - 1) * 16, (x + 1) * 16, y * 16))
            im.paste(core, (xx * 16, yy * 16))
            s = Image.open(FIELD / "bookshelf_home.png").convert("RGBA")
            im.paste(s, (xx * 16, yy * 16 + 16 - s.height), s)
            g[yy, xx] = 1
    services = {
        "market",
        "shop",
        "cafe",
        "bakery",
        "eatery",
        "bazaar",
        "piercafe",
        "fishmarket",
        "books",
        "craft",
        "shutter",
    }
    role = (
        "shop"
        if key in services
        else "heal"
        if key in ("hotel", "lodge", "lodgings", "nursery")
        else ""
    )
    if role:
        cells = [
            (abs(xx - w // 2) + abs(yy - (h // 2)), xx, yy)
            for yy in range(2, h - 2)
            for xx in range(1, w - 1)
            if not g[yy, xx]
            and not g[yy + 1, xx]
            and (xx, yy + 1) != spawn
            and (xx, yy) != spawn
        ]
        if cells:
            _, xx, yy = min(cells)
            m["npcs"].append(
                {
                    "name": "补给商" if role == "shop" else "护士",
                    "gfx": "clerk" if role == "shop" else "nurse",
                    "at": [xx, yy],
                    role: True,
                }
            )
    # Redraw the return rug in the region palette; the warp and the rug occupy identical cells.
    d = ImageDraw.Draw(im)
    for xx, yy in exits:
        d.rectangle((xx * 16, yy * 16 + 8, xx * 16 + 15, yy * 16 + 14), fill="#a77c68")
        d.line((xx * 16, yy * 16 + 9, xx * 16 + 15, yy * 16 + 9), fill="#d4b18c")
    # Place tools, furniture and exhibits appropriate to the work done inside. Native
    # floor obstacles and all approaches to the exit or attendant must stay navigable.
    furniture = {
        "beacon": "map clock carebench",
        "castle": "statue banner bookshelf",
        "factory": "ore crate desk",
        "manor": "ceilingbed clock plant_indoor",
        "lab": "pc bookshelf officecounter_compact",
        "mill": "hay crate desk",
        "theatre": "carebench banner tv",
        "stadium": "carebench banner console",
        "hotel": "ceilingbed plant_indoor map",
        "market": "crate stall urn",
        "shop": "crate plant_indoor desk",
        "gable": "ceilingbed tv bookshelf_home",
        "rowhouse": "ceilingbed bookshelf_home plant_indoor",
        "station": "carebench clock map",
        "aqueduct": "pump pc desk",
        "hall": "statue bookshelf map",
        "tower": "pc carebench clock",
    }
    custom = {
        "family": "ceilingbed tv console",
        "studio": "mosaic urn bookshelf_home",
        "bakery": "crate urn desk",
        "books": "bookshelf bookshelf_home carebench",
        "eatery": "desk urn plant_indoor",
        "fishmarket": "crate reed desk",
        "piercafe": "desk carebench plant_indoor",
        "nursery": "berry plant_indoor bookshelf_home",
        "concert": "console tv carebench",
        "market": "crate urn stall",
        "lodgings": "ceilingbed bookshelf_home plant_indoor",
        "craft": "crate urn desk",
        "kiln": "urn ore desk",
        "stationzero": "pc console crystal",
        "workshop": "ore crate desk",
        "leaguehall": "statue banner bookshelf_home",
    }
    extras = custom.get(key, furniture.get(form, "desk carebench")).split()
    actors = {tuple(n["at"]) for n in m["npcs"]}
    approaches = {(x, y - 1) for x, y in exits}
    reserved = set(exits) | approaches | actors
    blocked = set(exits) | actors
    for i, prop in enumerate(extras):
        path = FIELD / (prop + ".png")
        if path.exists():
            sprite = Image.open(path).convert("RGBA")
            ax, ay = ANCHORS[prop]
        else:
            sprite, _, (ax, ay) = asset(prop)
        candidates = []
        for yy in range(2, h - 1):
            for xx in range(1, w - 1):
                left, top = xx * 16 + 8 - ax, (yy + 1) * 16 - ay
                bounds = sprite.getbbox()
                pixels = (
                    left + bounds[0],
                    top + bounds[1],
                    left + bounds[2] - 1,
                    top + bounds[3] - 1,
                )
                if (
                    pixels[0] < 0
                    or pixels[1] < 16
                    or pixels[2] >= w * 16
                    or pixels[3] >= h * 16
                ):
                    continue
                footprint = {
                    (cx, cy)
                    for cx in range(pixels[0] // 16, pixels[2] // 16 + 1)
                    for cy in range(pixels[1] // 16, pixels[3] // 16 + 1)
                }
                if footprint & reserved or any(g[cy, cx] for cx, cy in footprint):
                    continue
                # Keep the central aisle clear. Different doors favour different walls and bays.
                tx = 1 if (seed >> (i * 3)) & 1 else w - 2
                ty = 2 + ((seed >> (i * 5)) % (h - 4))
                rank = (abs(xx - tx) + abs(yy - ty), xx, yy)
                candidates.append((rank, left, top, footprint))
        for _, left, top, footprint in sorted(candidates, key=lambda c: c[0]):
            seen = {spawn}
            pending = deque([spawn])
            while pending:
                xx, yy = pending.popleft()
                for a, b in ((xx + 1, yy), (xx - 1, yy), (xx, yy + 1), (xx, yy - 1)):
                    if (
                        (a, b) not in seen | footprint
                        and 0 <= a < w
                        and 0 <= b < h
                        and not g[b, a]
                        and (a, b) not in blocked
                    ):
                        seen.add((a, b))
                        pending.append((a, b))
            if not approaches <= seen or any(
                not any(
                    (xx + dx, yy + dy) in seen
                    for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))
                )
                for xx, yy in actors
            ):
                continue
            im.paste(sprite, (left, top), sprite)
            for xx, yy in footprint:
                g[yy, xx] = 1
            break
    m.update(spawn=list(spawn), size=[w, h], switch_room=key, switch_field_revision=1)
    return m, im, g, []


# Rebuild the five already-registered signature interiors around their original public doors.
# The seats and touchline in Wyndon, administrative desks in Galaxy Hall, book stacks and
# lectern in Uva, lift doors at Rose Tower and the sealed crystal chamber in Zero Lab are independent layouts.
def signature(em, mid, m):
    w, h = m["size"]
    kind = mid.split("_", 1)[1]
    g = np.zeros((h, w), dtype="uint8")
    g[[0, -1], :] = 1
    g[:, [0, -1]] = 1
    props = []
    {
        "stadium": ("RustboroCity_PokemonSchool", 0x201),
        "academy": ("House1", 0x23E),
        "village": ("House1", 0x23E),
        "lab": ("MossdeepCity_SpaceCenter_1F", 0x300),
        "rose": ("RustboroCity_DevonCorp_1F", 0x380),
    }[kind]
    tile = masonry(
        {
            "stadium": "gray",
            "academy": "warm",
            "village": "wood",
            "lab": "lab",
            "rose": "dark",
        }[kind]
    )
    im = Image.new("RGB", (w * 16, h * 16))
    d = ImageDraw.Draw(im)
    for j in range(h):
        for i in range(w):
            im.paste(tile, (i * 16, j * 16))
    fixed = {tuple(n["at"]) for k in ("warps", "npcs", "objects") for n in m[k]} | {
        tuple(m["spawn"])
    }
    protect = {
        (x + dx, y + dy)
        for x, y in fixed
        for dx, dy in [(0, 0), (0, 1), (0, -1), (1, 0), (-1, 0)]
    }

    def add(name, x, y, width=1):
        pos = {(xx, y) for xx in range(x - width // 2, x + (width - 1) // 2 + 1)}
        if pos & protect or any(
            not (0 < xx < w - 1 and 0 < yy < h - 1) or g[yy, xx] for xx, yy in pos
        ):
            return
        if (FIELD / (name + ".png")).exists():
            props.append([name, x, y])
        else:
            _, path, an = asset(name)
            props.append([path, x, y, an])
        for xx, yy in pos:
            g[yy, xx] = 1

    wall = {
        "stadium": "#738197",
        "academy": "#a18b86",
        "village": "#90745b",
        "rose": "#77829a",
        "lab": "#626e86",
    }[kind]
    d.rectangle((0, 0, w * 16 - 1, 25), fill=wall)
    d.line((1, 26, w * 16 - 1, 26), fill="#c2b7a1", width=3)
    for x in range(16, w * 16 - 22, 32):
        d.rectangle((x, 4, x + 22, 20), fill=wall, outline="#666873")
        d.line((x + 1, 5, x + 20, 5), fill="#b4aba1")
        if kind in ("lab", "academy", "rose"):
            d.rectangle((x + 4, 7, x + 18, 17), fill="#90aeb8", outline="#65747d")
            d.line((x + 11, 8, x + 11, 17), fill="#c9d3c7")
    d.rectangle((0, 0, 6, h * 16 - 1), fill=wall)
    d.rectangle((w * 16 - 7, 0, w * 16 - 1, h * 16 - 1), fill=wall)

    if kind == "stadium":
        d.rounded_rectangle(
            (3 * 16, 3 * 16, (w - 3) * 16, (h - 3) * 16),
            17,
            fill="#6c9c6d",
            outline="#cacfaa",
            width=3,
        )
        d.line((w * 8, 49, w * 8, (h - 3) * 16 - 2), fill="#d5d7b1", width=2)
        d.ellipse(
            (w * 8 - 25, h * 8 - 25, w * 8 + 25, h * 8 + 25), outline="#d5d7b1", width=2
        )
        for xx in [3 * 16, (w - 3) * 16 - 25]:
            d.rectangle(
                (xx, h * 8 - 27, xx + 25, h * 8 + 27), outline="#d1d7b0", width=2
            )
        for x in range(3, w - 2, 3):
            add("carebench", x, 2, 2)
            add("carebench", x, h - 2, 2)
    elif kind == "academy":
        d.rectangle(
            (w * 8 - 22, 45, w * 8 + 22, (h - 2) * 16),
            fill="#9e85a6",
            outline="#d9bba7",
            width=3,
        )
        for y in (5, 9, 13):
            for x in [3, 6, w - 7, w - 4]:
                add("bookcase", x, y, 2)
        add("desk", w // 2, 3, 3)
        add("clock", w // 2, 1)
        add("desk", w // 2 + 1, h // 2, 3)
        add("plant_indoor", w // 2 - 3, h // 2 + 3)
        d.rectangle(
            (w * 8 - 19, 48, w * 8 + 19, (h - 2) * 16 - 4), outline="#c3a5b0", width=2
        )
        add("plant_indoor", w - 3, 3)
    elif kind == "village":
        d.rectangle((31, 45, (w - 4) * 16, 59), outline="#a48a6c", width=3)
        add("map", w // 2, 2)
        add("desk", w // 2, 4, 3)
        for x in [3, 7, w - 7, w - 3]:
            add("bookshelf", x, 2, 2)
        for x, y in [(5, 7), (5, 12), (w - 6, 6), (w - 6, 12)]:
            add("desk", x, y, 3)
            add("carebench", x, y + 1, 2)
    elif kind == "rose":
        for x in [5, w // 2, w - 5]:
            xx = x * 16
            d.rectangle(
                (xx - 13, 3, xx + 13, 30), fill="#6e8496", outline="#becbd0", width=2
            )
            d.line((xx, 5, xx, 30), fill="#455869")
        add("officecounter", w // 2, 5, 5)
        for x in (3, w - 3):
            add("plant_indoor", x, 3)
            add("carebench", x, h // 2, 2)
    else:
        for x in [3, 6, w - 5, w - 8]:
            add("pc", x, 4)
            add("officecounter_compact", x, 5, 2)
        for x, y in [(3, 9), (5, h - 4), (w - 3, 10), (w - 7, h - 3)]:
            add("crystal", x, y, 2)
        add("console", w // 2, 3)
        add("reactor", w // 2 + 3, h // 2, 2)
        add("crystal", w // 2 - 3, h // 2 + 2, 2)
        add("pc", w // 2 + 3, h // 2 + 2)
        add("console", w // 2 - 3, h // 2 - 1)
        for xx in range(w // 2 - 4, w // 2 + 4):
            d.line(
                (xx * 16, (h // 2 + 1) * 16, xx * 16 + 10, (h // 2 + 1) * 16),
                fill="#a4bbc0",
                width=2,
            )
    for n in m["warps"]:
        x, y = n["at"]
        g[y, x] = 0
        d.rectangle(
            (x * 16, y * 16 + 5, x * 16 + 15, y * 16 + 13),
            fill="#bd936f",
            outline="#e6c595",
        )
        for xx, yy in ((x, y + 1), (x, y - 1), (x + 1, y), (x - 1, y)):
            if 0 < xx < w - 1 and 0 < yy < h - 1:
                g[yy, xx] = 0
    return im, g, props
