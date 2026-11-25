"""Hotel Ionia, Battle Cafés, Wyndon's postgame tower and Crown's raid chambers."""

import json

import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import pack
from galar_atlas.art import ROOT, prop, surface
from kalos_gym_rooms import tile
from switch_fields.galar_streets import repeat
from switch_fields.terrain import relief
from switch_fields.rooms import donor

MAPS = ROOT / "content/regions"
OUT = ROOT / "assets/galar/districts"


def read(mid):
    return json.loads(
        (MAPS / mid.split("_")[0] / "maps" / (mid + ".json")).read_bytes()
    )


def write(mid, m):
    (MAPS / mid.split("_")[0] / "maps" / (mid + ".json")).write_text(
        json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n"
    )


def gate(x, y, dest, at, direction):
    return {
        "at": [x, y],
        "trigger": direction,
        "to": {"region": dest.split("_")[0], "map": dest, "at": list(at)},
        "galar_venue": True,
    }


def actor(at, name, role, gfx="expert_m"):
    return {
        "at": list(at),
        "name": name,
        "role": role,
        "gfx": gfx,
        "lines": [name + "向你点头致意。"],
    }


def field_mon(at, name, role, species):
    raw = Image.open(ROOT / "assets/party" / f"{species}.png").convert("RGBA")
    raw = raw.crop(raw.getbbox())
    raw.thumbnail((20, 22) if species == 819 else (29, 31), Image.Resampling.NEAREST)
    key = "galar_venue_" + str(species)
    raw.save(ROOT / "assets/npc" / (key + ".png"), optimize=True)
    return {**actor(at, name, role), "field_art": key}


def save(mid, title, im, g, spawn, warps, npcs=(), props=()):
    w, h = im.width // 16, im.height // 16
    OUT.mkdir(exist_ok=True)
    im.save(OUT / (mid + ".png"), optimize=True)
    m = {
        "name": title,
        "size": [w, h],
        "spawn": list(spawn),
        "tiles": g.tolist(),
        "warps": warps,
        "npcs": list(npcs),
        "objects": [],
        "style": "interior",
        "biome": "interior",
        "hoenn_art": {
            "s": [w, h],
            "t": pack(np.zeros((h, w), dtype="<u2")),
            "p": list(props),
            "scene": ["res://assets/galar/districts/" + mid + ".png", 0, 0],
        },
    }
    write(mid, m)
    return mid


def room(w, h, key="wood", wall="#b0a494"):
    im = repeat(tile(key), (w * 16, h * 16))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, w * 16 - 1, 42), fill=wall)
    d.rectangle((0, 0, w * 16 - 1, 8), fill="#655b65")
    d.line((0, 11, w * 16 - 1, 11), fill="#ddd0ae", width=3)
    d.rectangle((0, 37, w * 16 - 1, 47), fill="#94816d")
    d.line((0, 39, w * 16 - 1, 39), fill="#e0cba8", width=2)
    for x in range(7, w * 16, 26):
        d.line((x, 14, x, 34), fill="#a19885")
    g = np.zeros((h, w), dtype="uint8")
    g[:3, :] = 1
    g[:, [0, -1]] = 1
    g[-1, :] = 1
    return im, g, d


def rug(d, x, y, width, height, color, trim):
    x *= 16
    y *= 16
    box = (x, y, x + width * 16 - 1, y + height * 16 - 1)
    d.rectangle(box, fill=color, outline=trim, width=2)
    d.rectangle((x + 4, y + 4, box[2] - 4, box[3] - 4), outline=trim, width=1)


def threshold(im, x, y, up=True):
    d = ImageDraw.Draw(im)
    l, t = x * 16, y * 16
    if up:
        d.rectangle(
            (l - 3, t - 18, l + 18, t + 12), fill="#514b54", outline="#8a7968", width=3
        )
        d.rectangle((l, t - 15, l + 15, t + 11), fill="#756960", outline="#d8ba87")
        d.line((l + 8, t - 12, l + 8, t + 10), fill="#584d4f")
        d.point((l + 11, t + 2), fill="#e9d394")
    else:
        d.rectangle((l, t + 6, l + 15, t + 14), fill="#b87969")
        d.line((l, t + 7, l + 15, t + 7), fill="#e0bc8b", width=2)


def fixprops(g, props, things):
    for key, x, y in things:
        prop(props, key, x, y)
        g[y, x] = 1


def add_to(mid, d):
    m = read(mid)
    m["warps"] = [w for w in m["warps"] if w["to"]["map"] != d["to"]["map"]] + [d]
    x, y = d["at"]
    m["tiles"][y][x] = 0
    if d["trigger"] == "door":
        m["tiles"][y + 1][x] = 0
    write(mid, m)


def mark_door(mid, x, y, up=True):
    m = read(mid)
    img = ROOT / m["hoenn_art"]["scene"][0][6:]
    im = Image.open(img).convert("RGB")
    threshold(im, x, y, up)
    im.save(img, optimize=True)


def hotels(em):
    mids = []
    for wing, lobby in [
        ("west", "galar_circhester_hotel_room"),
        ("east", "galar_circhester_hotel1_room"),
    ]:
        wing_name = "西馆" if wing == "west" else "东馆"
        landing = "galar_ionia_" + wing
        add_to(lobby, gate(5, 3, landing, (12, 7), "door"))
        mark_door(lobby, 5, 3)
        im, g, d = room(25, 10, "wood", "#cabda7" if wing == "west" else "#bbc0b6")
        props = []
        rug(d, 2, 5, 21, 2, "#a1646b" if wing == "west" else "#758bb1", "#dfc299")
        hallway = [gate(12, 8, lobby, (5, 4), "down")]
        g[8, 12] = 0
        threshold(im, 12, 8, False)
        for i, x in enumerate([3, 8, 16, 21]):
            mid = landing + "_guest_" + str(i + 1)
            threshold(im, x, 3)
            hallway.append(gate(x, 3, mid, (5, 8), "door"))
            image, grid, draw = room(
                12, 10, "wood", "#cbc2b0" if wing == "west" else "#bbb6be"
            )
            fx = []
            rug(
                draw,
                3,
                5,
                6,
                3,
                ("#a36b71" if wing == "west" else "#8192a3"),
                "#dbc69f",
            )
            fixprops(
                grid,
                fx,
                [
                    ("ceilingbed", 2, 4),
                    ("ceilingbed", 3, 4),
                    ("plant_indoor", 9, 4),
                    ("desk", 8, 5),
                    ("tv", 2, 7),
                    ("bookshelf_home", 10, 3),
                ],
            )
            npcs = []
            if wing == "west" and i == 0:
                npcs = [actor((6, 4), "游戏总监", "venue_director", "scientist")]
            if wing == "west" and i == 1:
                npcs = [actor((7, 6), "森本", "venue_morimoto", "guard")]
            if wing == "east" and i == 1:
                npcs = [
                    actor((7, 6), "侦探", "venue_detective"),
                    field_mon((4, 6), "贪心栗鼠", "venue_skwovet", 819),
                    actor((3, 5), "旅客", "venue_suspect_0", "woman"),
                    actor((9, 7), "服务生", "venue_suspect_1", "clerk"),
                    actor((6, 4), "旅客的朋友", "venue_suspect_2", "lad"),
                ]
            if wing == "east" and i == 2:
                npcs = [actor((7, 6), "登山男", "venue_screech", "hiker")]
            if wing == "east" and i == 3:
                npcs = [actor((7, 6), "音乐家", "venue_tears", "guitarist")]
            if not npcs:
                npcs = [
                    {
                        "name": "旅客",
                        "gfx": "woman",
                        "at": [7, 6],
                        "lines": ["拉开窗帘，就能望见广场的温泉。"],
                    }
                ]
            grid[9, 5] = 0
            threshold(image, 5, 9, False)
            mids.append(
                save(
                    mid,
                    "爱奥尼亚酒店・" + wing_name + str(i + 1) + "号客房",
                    image,
                    grid,
                    (5, 8),
                    [gate(5, 9, landing, (x, 4), "down")],
                    npcs,
                    fx,
                )
            )
        fixprops(
            g,
            props,
            [
                ("plant_indoor", 1, 4),
                ("plant_indoor", 23, 4),
                ("carebench_compact", 5, 8),
                ("carebench_compact", 19, 8),
            ],
        )
        mids.append(
            save(
                landing,
                "爱奥尼亚酒店・" + wing_name + "二楼",
                im,
                g,
                (12, 7),
                hallway,
                props=props,
            )
        )
    m = read("galar_wyndon_hotel_room")
    m["name"] = "宫门市・伦度罗瑟酒店"
    write("galar_wyndon_hotel_room", m)
    return mids


def cafes():
    from galar_atlas.centers import avoid_events

    occupied_events = avoid_events()
    mids = []
    for city, target in [
        ("motostoke", (17, 18)),
        ("hammerlocke", (14, 17)),
        ("wyndon", None),
    ]:
        town = "galar_" + city
        m = read(town)
        mid = town + "_cafe_room"
        w, h = m["size"]
        existing = next((v for v in m["warps"] if v["to"]["map"] == mid), None)
        if existing:
            x, y = existing["at"]
        else:
            cells = np.array(m["tiles"])
            forbid = set(occupied_events.get(town, set()))
            for typ in ["warps", "npcs", "objects"]:
                forbid.update(tuple(v["at"]) for v in m[typ])
            for a in m["hoenn_art"]["p"]:
                uri, px, py, *rest = a
                if not isinstance(uri, str):
                    continue
                p = ROOT / (
                    uri[6:]
                    if uri.startswith("res://")
                    else "assets/emerald/field/" + uri + ".png"
                )
                if not p.exists():
                    continue
                aw, ah = Image.open(p).size
                ax, ay = rest[0] if rest else (aw // 2, ah)
                for yy in range(((py + 1) * 16 - ay) // 16, py + 1):
                    for xx in range(
                        (px * 16 + 8 - ax) // 16, (px * 16 + 8 - ax + aw - 1) // 16 + 1
                    ):
                        forbid.add((xx, yy))
            options = []
            for y in range(5, h - 3):
                for x in range(3, w - 3):
                    if any(
                        (xx, yy) in forbid or cells[yy, xx] not in (0, 11)
                        for yy in range(y - 3, y + 2)
                        for xx in range(x - 2, x + 3)
                    ):
                        continue
                    options.append((abs(x - target[0]) + abs(y - target[1]), x, y))
            _, x, y = min(options)
            m["warps"].append(gate(x, y, mid, (7, 9), "door"))
        if city != "wyndon":
            if not any(
                str(p[0]).endswith("architecture/cafe.png") and p[1:3] == [x, y]
                for p in m["hoenn_art"]["p"]
            ):
                prop(m["hoenn_art"]["p"], "cafe", x, y)
            for yy in (y - 1, y):
                m["tiles"][yy][x - 1 : x + 2] = [1, 1, 1]
            write(town, m)
        im, g, d = room(16, 11, "wood", "#c7ad95")
        fx = []
        rug(d, 5, 5, 6, 3, "#976558", "#d8bc92")
        fixprops(
            g,
            fx,
            [
                ("desk", 3, 5),
                ("desk", 12, 5),
                ("plant_indoor", 1, 5),
                ("plant_indoor", 14, 5),
                ("carebench_compact", 3, 7),
                ("carebench_compact", 12, 7),
                ("officecounter", 9, 3),
            ],
        )
        warps = []
        if city == "wyndon":
            old = read(mid)
            warps = old["warps"]
            # Existing callers and original saved coords use [6,9] / [7,9].
            for door in warps:
                dx, dy = door["at"]
                g[dy, dx] = 0
                threshold(im, dx, dy, False)
        else:
            g[10, 7] = 0
            threshold(im, 7, 10, False)
            warps = [gate(7, 10, town, (x, y + 1), "down")]
        mids.append(
            save(
                mid,
                m["name"] + "・对战咖啡馆",
                im,
                g,
                (7, 9),
                warps,
                [actor((8, 4), "咖啡店长", "venue_cafe_" + city, "clerk")],
                fx,
            )
        )
    return mids


def tower(em):
    # After the Champion Cup, the same Rose Tower facade leads to Leon's battle facility.
    lobby = "galar_battle_tower"
    arena = "galar_battle_tower_field"
    im, g, d = room(29, 18, "clinic", "#a5adb8")
    fx = []
    rug(d, 11, 5, 6, 12, "#6c8299", "#c4b490")
    rug(d, 4, 7, 6, 2, "#889ba4", "#d3c9af")
    rug(d, 19, 7, 6, 2, "#889ba4", "#d3c9af")
    fixprops(
        g,
        fx,
        [
            ("officecounter", 6, 5),
            ("officecounter", 22, 5),
            ("pc", 2, 5),
            ("plant_indoor", 3, 7),
            ("plant_indoor", 25, 7),
            ("carebench", 5, 12),
            ("carebench", 21, 12),
            ("banner", 9, 3),
            ("banner", 18, 3),
        ],
    )
    g[17, 14] = 0
    threshold(im, 14, 17, False)
    threshold(im, 14, 3)
    actors = [
        actor((7, 6), "挑战接待员", "venue_tower_sign", "clerk"),
        actor((20, 6), "租借队管理员", "venue_tower_rental", "scientist"),
        actor((23, 7), "BP兑换员", "venue_tower_bp", "clerk"),
    ]
    save(
        lobby,
        "宫门市・对战塔大厅",
        im,
        g,
        (14, 16),
        [
            gate(14, 17, "galar_wyndon", (11, 6), "down"),
            gate(14, 3, arena, (12, 16), "door"),
        ],
        actors,
        fx,
    )
    im, g, d = room(25, 19, "pave", "#8196a3")
    fx = []
    rug(d, 3, 4, 19, 12, "#769b8e", "#d7d3ab")
    l, t, r, b = 65, 75, 335, 237
    d.rectangle((l, t, r, b), outline="#c9d7b8", width=2)
    d.line((200, t, 200, b), fill="#c9d7b8", width=2)
    d.ellipse((174, 130, 226, 182), outline="#d9d8b4", width=2)
    d.ellipse((194, 150, 206, 162), outline="#e0d6af", width=2)
    for x in (1, 3, 21, 23):
        fixprops(g, fx, [("banner", x, 3)])
    g[18, 12] = 0
    threshold(im, 12, 18, False)
    save(
        arena,
        "对战塔・对战场",
        im,
        g,
        (12, 16),
        [gate(12, 18, lobby, (14, 4), "down")],
        [actor((12, 8), "对战裁判", "venue_tower_fight", "expert_m")],
        fx,
    )
    return [lobby, arena]


FLOORS = [
    (
        "RRRCCRRR/RCCCCCCR/CCLLLCCC/RRCCLCCC/CCCLLCCR/RRCCCRRR",
        "RRRRCCRR/RCCCDCCR/RCDDDCCR/RRCCCDCR/CCCDDDCR/RRRCCRRR",
    ),
    (
        "RRRCCRRR/RCCCCCCR/CCSWWCCR/CCWWCCCR/RCCCCRRC/RRRCCRRR",
        "RRRCCRRR/RCCIIICR/RCCCICCR/CCIICCCR/RCCCCICR/RRRCCRRR",
    ),
    (
        "RRRCCRRR/RCMCCMCR/RCCCMCCR/CMCCMCCR/RCCMCCCR/RRRCCRRR",
        "RRRCCRRR/RCRCCCCR/RCSSCCCR/RCCCRCCR/RCCSSCCR/RRRCCRRR",
    ),
]


def lair(em):
    field_mon((13, 8), "传说反应", "venue_lair_boss", 800)
    camp = "crown_max_lair"
    prefix = "crown_adventure_"
    mids = []
    add_to(camp, gate(14, 4, prefix + "fork_1", (12, 15), "door"))
    mark_door(camp, 14, 4)
    for i, branches in enumerate(FLOORS, 1):
        fork = prefix + "fork_" + str(i)
        w, h = 25, 18
        ex, ey = 12, 15
        a = relief(
            "RRRCCCRRR/RRCCCRCCR/RCCRCCCCR/RCCCCCCRR/RRCCCWCCR/RRRCCCRRR".split("/"),
            w,
            h,
            612 + i,
        )
        # Carve the two signed fork approaches and the southern retreat.
        a[4:16, 4:21] = "C"
        a[3:6, 4:7] = "C"
        a[3:6, 18:21] = "C"
        a[16:, 11:14] = "C"
        g = np.where(a == "R", 1, np.where(a == "W", 2, 0)).astype("uint8")
        g[[0, -1], :] = 1
        g[:, [0, -1]] = 1
        im = surface(em, a, 362 + i)
        d = ImageDraw.Draw(im)
        props = []
        x = 12
        g[-1, x] = 0
        threshold(im, x, h - 1, False)
        warps = [gate(12, 17, camp, (14, 5), "down")]
        for side, lx in enumerate([5, 19]):
            target = prefix + str(i) + "_" + ("left" if side == 0 else "right")
            threshold(im, lx, 3)
            warps.append(gate(lx, 3, target, (13, 16), "door"))
            d.line(
                (
                    (12) * 16,
                    15 * 16 + 8,
                    (12) * 16,
                    11 * 16 + 8,
                    lx * 16 + 8,
                    6 * 16 + 8,
                    lx * 16 + 8,
                    4 * 16 + 8,
                ),
                fill="#b4a08a",
                width=4,
            )
            prop(props, ("crystal", "ore")[side], lx + 2, 5)
            room_a = relief(branches[side].split("/"), 27, 19, 975 + i * 2 + side)
            room_a[6:17, 11:16] = "C"
            room_a[16:, 12:15] = "C"
            room_a[2:7, 12:15] = "C"
            room_g = np.where(room_a == "R", 1, np.where(room_a == "W", 2, 0)).astype(
                "uint8"
            )
            room_g[[0, -1], :] = 1
            room_g[:, [0, -1]] = 1
            room_g[18, 13] = 0
            picture = surface(em, room_a, 661 + i * 2 + side)
            rp = []
            for kind, cx, cy in [("crystal", 8, 6), ("ore", 19, 10)]:
                prop(rp, kind, cx, cy)
                room_g[cy, cx] = 1
            threshold(picture, 13, 3)
            threshold(picture, 13, 18, False)
            onward = prefix + ("fork_" + str(i + 1) if i < 3 else "nest")
            landing = (12, 15) if i < 3 else (13, 16)
            mids.append(
                save(
                    target,
                    "极巨巢穴・"
                    + ["第一层", "第二层", "第三层"][i - 1]
                    + ["西支洞", "东支洞"][side],
                    picture,
                    room_g,
                    (13, 16),
                    [
                        gate(13, 18, fork, (lx, 4), "down"),
                        gate(13, 3, onward, landing, "door"),
                    ],
                    [
                        field_mon(
                            (13, 8),
                            "极巨反应",
                            "venue_lair_raid",
                            [(324, 437), (350, 460), (621, 663)][i - 1][side],
                        )
                    ],
                    rp,
                )
            )
        mids.append(
            save(
                fork,
                "极巨巢穴・" + ["第一处分岔", "第二处分岔", "第三处分岔"][i - 1],
                im,
                g,
                (ex, ey),
                warps,
                props=props,
            )
        )
    a = relief(
        "RRRCCCRRR/RCCCMCCCR/RCCMMCCCR/CCMCCCMCC/RCCMCCMCR/RRRCCCRRR".split("/"),
        27,
        19,
        777,
    )
    a[5:18, 10:16] = "C"
    g = np.where(a == "R", 1, 0).astype("uint8")
    g[[0, -1], :] = 1
    g[:, [0, -1]] = 1
    g[18, 13] = 0
    im = surface(em, a, 113)
    d = ImageDraw.Draw(im)
    for radius in [39, 36, 23]:
        d.ellipse(
            (216 - radius, 139 - radius // 2, 216 + radius, 139 + radius // 2),
            outline="#b18597",
            width=2,
        )
    threshold(im, 13, 18, False)
    mids.append(
        save(
            prefix + "nest",
            "极巨巢穴・最深处",
            im,
            g,
            (13, 16),
            [gate(13, 18, camp, (14, 5), "down")],
            [field_mon((13, 8), "传说反应", "venue_lair_boss", 245)],
        )
    )
    return mids


def build(em):
    from galar_atlas.fashion import build as dress_shops

    added = hotels(em) + cafes() + tower(em) + lair(em) + dress_shops()
    for r in ["galar", "crown"]:
        p = MAPS / r / "region.json"
        d = json.loads(p.read_bytes())
        for mid in added:
            if mid.startswith(r + "_") and mid not in d["maps"]:
                d["maps"].append(mid)
        p.write_text(json.dumps(d, ensure_ascii=False, separators=(",", ":")) + "\n")
    return added
