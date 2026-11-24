"""Emerald-scale furnishings for the three native Canalave Library floors."""

from PIL import Image, ImageColor, ImageDraw
from platinum_layout import ROOT
from platinum_library_furniture import casework, donor, reading_table, reception

FLOORS = ("sinnoh_library", "sinnoh_canalave_library_2f", "sinnoh_canalave_library_3f")
ART = ROOT / "assets/platinum_native/library"
EDGE = "#544e4b"
DARK = "#705b50"
WOOD = "#aa7f5e"
LIGHT = "#ceac81"
PAPER = "#efe4bc"


def timber(draw, rect):
    left, top, right, bottom = rect
    draw.rectangle(rect, fill=WOOD, outline=DARK)
    draw.line((left + 1, top + 1, right - 1, top + 1), fill=LIGHT)
    draw.line((left + 1, bottom - 1, right - 1, bottom - 1), fill="#916c53")


def write_png(name, img):
    file = ART / (name + ".png")
    img.save(file, optimize=True)
    return "res://" + str(file.relative_to(ROOT))


def stairs(pic, tile, right):
    """The stairwell beside each landing runs left/right in the DS warp data."""
    x, y = tile
    # The player steps sideways off the native landing. The flight turns at
    # that landing and recedes into the wall, exposing each horizontal riser.
    # Retain the open dark well and staggered treads of Brendan's staircase.
    cx, cy = x * 16 + 8, y * 16 + 6
    left = cx + 10 if right else cx - 48
    p = ImageDraw.Draw(pic)
    p.rectangle((left, cy - 23, left + 36, cy + 8), fill="#796858", outline="#554c48")
    p.rectangle((left + 3, cy - 20, left + 32, cy + 4), fill="#53545a")
    p.line((left + 3, cy - 20, left + 32, cy - 20), fill="#41464a", width=2)
    for i in range(6):
        tread_y = cy - 16 + i * 4
        inset = (5 - i) if not right else i // 2
        px = left + 4 + inset
        end = left + 31 - (5 - i) // 2
        p.rectangle((px, tread_y, end, tread_y + 3), fill="#aa8a65")
        p.line((px, tread_y, end, tread_y), fill="#dac4a0" if not right else "#cfb697")
        p.line((px, tread_y + 3, end, tread_y + 3), fill="#866a50")
    # Projecting newel and broad landing at the side where the warp is taken.
    outer = left + 34 if right else left + 1
    p.rectangle((outer, cy - 23, outer + 2, cy + 6), fill="#b09978")
    p.line((outer, cy - 22, outer, cy + 5), fill="#d6bd96")
    for bottom in (cy - 20, cy + 7):
        p.rectangle(
            (outer - 2, bottom - 5, outer + 3, bottom),
            fill="#907358",
            outline="#665748",
        )
        p.line((outer - 1, bottom - 5, outer + 2, bottom - 5), fill="#dbc09a")
    a, b = sorted((cx, left if right else left + 36))
    p.rectangle((a, cy + 4, b, cy + 8), fill="#bca37b")
    p.line((a, cy + 7, b, cy + 7), fill="#d7bf96")


def rug(pic, box):
    x, y, r, b = box
    p = ImageDraw.Draw(pic)
    p.rectangle((x + 1, y + 2, r + 1, b + 2), fill="#9b816c")
    p.rectangle(box, fill="#637d77", outline="#576564")
    p.rectangle((x + 1, y + 1, r - 1, b - 1), outline="#baa984")
    p.rectangle((x + 3, y + 3, r - 3, b - 3), outline="#c6b892")
    p.rectangle((x + 5, y + 5, r - 5, b - 5), outline="#799087")
    # Low-contrast running stitches in the weave and a border motif scaled
    # to a footprint. The reading rugs extend *under* the groups of desks.
    for cy in range(y + 8, b - 6, 6):
        for cx in range(x + 8 + (cy % 4), r - 7, 7):
            p.line((cx, cy, cx + 1, cy), fill="#6a827a")
    for cx in range(x + 9, r - 5, 12):
        for cy in (y + 3, b - 3):
            p.line((cx - 2, cy, cx, cy - 1, cx + 2, cy), fill="#e0cfa5")
    for cy in range(y + 10, b - 6, 13):
        for cx in (x + 3, r - 3):
            p.point((cx, cy), fill="#eadbb3")


def background(level, doc):
    back = 48 if level < 3 else 32
    pic = Image.new("RGBA", (352, 200))
    p = ImageDraw.Draw(pic)
    p.rectangle((13, back - 28, 338, 198), fill="#514a49")
    # Real bedroom plank joints, set in the library's warm oak ramp. Stagger
    # the seams over multiple tiles instead of restarting the grid at each door.
    raw = donor("littleroot_west_home_2f", (48, 48, 64, 64))
    colors = sorted((v for _, v in raw.getcolors()), key=lambda rgb: sum(rgb[:3]))
    ramp = ("#a38366", "#b59975", "#bfa17c", "#c8ab84", "#ceb18b")
    recolor = {
        v: ramp[round(i * (len(ramp) - 1) / max(1, len(colors) - 1))]
        for i, v in enumerate(colors)
    }
    chip = Image.new("RGB", raw.size)

    chip.putdata([ImageColor.getrgb(recolor[c]) for c in raw.getdata()])
    for row, yy in enumerate(range(back, 192, 16)):
        for col, xx in enumerate(range(16, 336, 16)):
            pic.paste(
                chip.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                if (row + col // 3) % 2
                else chip,
                (xx, yy),
            )
    # Fit the plank-end grain to the boards instead of a broad ruled floor.
    for row, y in enumerate(range(back + 1, 190, 8)):
        for x in range(20 + ((row * 19) % 43), 333, 48):
            p.line((x, y, x, y + 5), fill="#af8b64")
            p.point((x + 1, y + 1), fill="#d1ae81")
    top = back - 27
    p.rectangle((13, top, 338, back + 12), fill="#cdd0b7", outline=EDGE)
    p.rectangle((15, top + 1, 336, top + 3), fill="#786a60")
    p.line((15, top + 4, 336, top + 4), fill="#e5dfc6")
    for x in range(16, 336, 8):
        p.line((x, top + 6, x, back + 4), fill="#c1c6ad")
        for y in range(top + 7, back, 7):
            p.point((x + 2, y), fill="#d4d6bc")
    p.rectangle((14, back + 4, 337, back + 12), fill="#a38a69")
    p.line((15, back + 4, 336, back + 4), fill=LIGHT)
    for x in range(21, 330, 16):
        p.rectangle((x, back + 7, x + 12, back + 10), outline="#957d60")
    window = donor("em_rustboro_city_pokemon_school", (14, 13, 50, 39))
    for x in (39, 186, 277) if level < 3 else (38, 209, 281):
        pic.alpha_composite(window, (x, top + 5))
    for x in (14, 335):
        p.rectangle((x, top + 2, x + 2, 191), fill="#978268")
    if level == 1:
        # Entry and returns desk. The attendant stands *inside* the native U.
        rug(pic, (163, 116, 204, 191))
        reception(pic)
    else:
        rug(pic, (97, 110, 160, 174) if level == 2 else (32, 110, 213, 180))
    for warp in doc["warps"]:
        if warp["trigger"] in ("left", "right"):
            stairs(pic, warp["at"], warp["trigger"] == "right")
    p.line((14, 191, 337, 191), fill="#a08462")
    p.rectangle((14, 192, 337, 197), fill="#867360")
    p.line((14, 193, 337, 193), fill="#aa9273")
    p.line((14, 197, 337, 197), fill=DARK)
    if level == 1:
        p.rectangle((175, 190, 192, 197), fill="#beaa89")
        p.line((175, 193, 192, 193), fill="#e4d4ad")
    return pic


def dress_library(doc):
    level = FLOORS.index(doc["id"]) + 1
    ART.mkdir(parents=True, exist_ok=True)
    art = doc["hoenn_art"]
    picture = background(level, doc)

    art["camera_bounds"] = [10, 19 if level < 3 else 5, 342, 204]
    props = []
    # Stacks align with both faces of every original readable shelf; keep the
    # source BG events, script flags, stairs and receptionist untouched.
    wall, islands = {
        1: ([(1, 6, 4), (15, 20, 4)], [(1, 4, 9)]),
        2: ([(1, 2, 4), (15, 20, 4)], [(1, 4, 9), (13, 20, 9)]),
        3: ([(9, 12, 3), (17, 20, 3)], [(15, 20, 9)]),
    }[level]
    for deep, rows in ((False, wall), (True, islands)):
        for left, right, y in rows:
            width = (right - left + 1) * 16
            img = casework(width, deep)
            uri = write_png(f"case_{width}_{'island' if deep else 'wall'}", img)
            props.append([uri, left, y, [8, img.height]])
    reading_tables = {1: (), 2: (7,), 3: (3, 7, 11)}
    for x in reading_tables[level]:
        img = reading_table()
        props.append([write_png("reading_table", img), x, 9, [8, img.height]])
    if level == 1:
        props.append(["plant_indoor", 20, 11])
    if level == 3:
        props.append(["plant_indoor", 1, 3])
    # The upper floors' wall plaques are also readable BG events.
    for obj in doc["objects"]:
        if obj.get("source_script", "").endswith("BgSign"):
            x, y = obj["at"]
            p = ImageDraw.Draw(picture)
            timber(p, (x * 16 + 1, y * 16 + 3, x * 16 + 14, y * 16 + 12))
            p.rectangle((x * 16 + 3, y * 16 + 5, x * 16 + 12, y * 16 + 10), fill=PAPER)
            p.line((x * 16 + 5, y * 16 + 7, x * 16 + 10, y * 16 + 7), fill="#98876d")
    art["scene"] = [write_png("floor_" + str(level), picture), 0, 0]
    art["p"] = sorted(props, key=lambda p: (p[2], p[1]))
