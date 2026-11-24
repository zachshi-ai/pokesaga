"""Small pixel fixtures for the street, the ironworks and the castle approach."""

import math

from PIL import Image, ImageDraw


def bench():
    im = Image.new("RGBA", (32, 19))
    d = ImageDraw.Draw(im)
    d.ellipse((2, 15, 30, 18), fill=(83, 78, 67, 105))
    for x in (4, 25):
        d.line((x + 2, 3, x + 2, 14, x, 17), fill="#414b49", width=2)
        d.line((x + 2, 12, x + 4, 17), fill="#414b49", width=2)
    for y in (2, 6, 11):
        d.rectangle((3, y, 28, y + 2), fill="#75523e")
        d.line((4, y, 27, y), fill="#c69a60")
    for x in (2, 27):
        d.line((x, 10, x + 1, 8, x + 2, 9, x + 2, 12), fill="#465351")
        d.point((x + 1, 8), fill="#9a9c87")
    return im


def bollard():
    im = Image.new("RGBA", (15, 12))
    d = ImageDraw.Draw(im)
    d.ellipse((1, 7, 14, 11), fill=(69, 71, 65, 125))
    d.rectangle((3, 7, 11, 10), fill="#71695a")
    d.rectangle((5, 3, 10, 8), fill="#535c5a")
    d.ellipse((3, 1, 12, 5), fill="#606a67", outline="#414b4e")
    d.line((5, 2, 9, 2), fill="#acb1a3")
    d.line((4, 7, 10, 6), fill="#c6aa77", width=2)
    return im


def gatepier():
    im = Image.new("RGBA", (22, 39))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 33, 21, 38), fill=(84, 77, 61, 110))
    for y, l, r in [(34, 1, 20), (32, 2, 19), (30, 4, 18), (9, 4, 18), (7, 2, 19)]:
        d.rectangle((l, y, r, min(36, y + 3)), fill="#877969", outline="#605e55")
        d.line((l + 1, y, r - 2, y), fill="#d0bca0")
    d.rectangle((5, 11, 17, 31), fill="#ab9881")
    d.rectangle((14, 11, 17, 31), fill="#877b6c")
    for i, y in enumerate(range(13, 32, 5)):
        d.line((5, y, 17, y), fill="#827767")
        d.line((9 + (i % 2) * 3, y, 9 + (i % 2) * 3, y + 4), fill="#948775")
    d.polygon(
        [(2, 7), (6, 3), (17, 3), (20, 7), (15, 9), (4, 9)], fill="#cfb798", outline="#796e60"
    )
    for x in (4, 13):
        d.rectangle((x, 0, x + 4, 4), fill="#b59d81", outline="#776c5e")
        d.line((x + 1, 0, x + 3, 0), fill="#e0c6a2")
    return im


def chimney():
    im = Image.new("RGBA", (31, 52))
    d = ImageDraw.Draw(im)
    d.ellipse((1, 45, 30, 51), fill=(65, 61, 55, 105))
    d.polygon(
        [(4, 46), (7, 7), (20, 7), (24, 46), (18, 49), (6, 48)], fill="#aa6250", outline="#63504a"
    )
    d.polygon([(16, 8), (20, 7), (24, 46), (18, 49)], fill="#814d43")
    for i, y in enumerate(range(11, 45, 4)):
        l = 6 if y > 26 else 7
        r = 22 if y > 27 else 20
        d.line((l, y, r, y), fill="#805447")
        d.line((l + 2 + (i % 2) * 4, y, l + 2 + (i % 2) * 4, y + 3), fill="#87574a")
    for y in (10, 34):
        d.line((6, y, 21, y), fill="#5c5951", width=2)
    d.ellipse((4, 2, 22, 9), fill="#a77158", outline="#62554b")
    d.ellipse((7, 3, 19, 7), fill="#4c4640", outline="#d29570")
    return im


def hoist():
    im = Image.new("RGBA", (44, 35))
    d = ImageDraw.Draw(im)
    for x in (3, 32):
        d.polygon([(x, 30), (x + 3, 7), (x + 6, 7), (x + 8, 30)], fill="#886a58", outline="#5e5148")
        d.rectangle((x - 1, 29, x + 9, 33), fill="#8a8170", outline="#615f55")
        d.line((x + 3, 10, x + 2, 25), fill="#c19a76")
    d.rectangle((1, 3, 42, 8), fill="#8f735c", outline="#665449")
    d.line((3, 4, 40, 4), fill="#cfab7d")
    d.line((8, 13, 13, 8), fill="#675747", width=2)
    d.ellipse((26, 4, 32, 10), fill="#626d65", outline="#464d48")
    d.line((29, 9, 29, 20), fill="#665e50")
    d.line((29, 19, 31, 21, 28, 23, 26, 22), fill="#555d59")
    return im


def wall():
    im = Image.new("RGBA", (48, 24))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 9, 47, 22), fill="#aa9980", outline="#726f60")
    for row in range(3):
        y = 11 + row * 4
        d.line((1, y, 46, y), fill="#92836f")
        for x in range(4 + row % 2 * 7, 47, 14):
            d.line((x, y, x, y + 4), fill="#8f816f")
            d.point((x + 1, y + 1), fill="#c1af93")
    d.polygon(
        [(0, 9), (4, 6), (46, 6), (47, 9), (45, 11), (0, 11)], fill="#c2af94", outline="#7e7567"
    )
    for x in (2, 14, 26, 38):
        d.rectangle((x, 2, x + 6, 7), fill="#b5a185", outline="#807567")
        d.line((x + 1, 2, x + 5, 2), fill="#e2c6a2")
    d.line((0, 22, 47, 22), fill="#858375")
    return im


def pipes():
    im = Image.new("RGBA", (37, 22))
    d = ImageDraw.Draw(im)
    d.ellipse((1, 15, 35, 21), fill=(76, 70, 60, 100))
    for dx, dy in ((3, 11), (11, 13), (7, 5)):
        a, b = dx, dy
        d.polygon(
            [(a, b + 3), (a + 17, b - 4), (a + 20, b - 1), (a + 20, b + 3), (a + 2, b + 10)],
            fill="#8c7261",
            outline="#615b54",
        )
        d.line((a + 4, b + 1, a + 17, b - 3), fill="#c09377")
        d.ellipse((a, b + 2, a + 8, b + 10), fill="#a2876f", outline="#5c5953")
        d.ellipse((a + 2, b + 4, a + 6, b + 8), fill="#554e47")
    return im


def wheel():
    im = Image.new("RGBA", (67, 77))
    d = ImageDraw.Draw(im)
    cx, cy, r = 33, 31, 25
    d.ellipse((5, 69, 62, 76), fill=(67, 76, 75, 120))
    d.polygon([(10, 67), (38, 63), (59, 67), (56, 72), (13, 74)], fill="#96998a", outline="#65716e")
    d.rectangle((10, 66, 54, 70), fill="#aa9277", outline="#746d63")
    for x in (14, 47):
        d.line((cx + 2, cy + 3, x + 2, 65), fill="#48595e", width=4)
        d.line((cx + 2, cy + 3, x + 2, 65), fill="#8d9e9a", width=2)
    joints = []
    for i in range(10):
        angle = -math.pi / 2 + 2 * math.pi * i / 10
        x = round(cx + r * math.cos(angle))
        y = round(cy + r * math.sin(angle))
        joints.append((x, y))
        d.line((cx, cy, x, y), fill="#768582")
        d.line((cx, cy, x + 1, y), fill="#a3ada4")
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline="#5a6b6a", width=3)
    d.ellipse((cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1), outline="#b6bbac")
    for i, (x, y) in enumerate(joints):
        d.line((x, y, x, y + 3), fill="#596767")
        d.rounded_rectangle(
            (x - 5, y + 2, x + 5, y + 9),
            radius=2,
            fill=["#a76153", "#617d82", "#a88252"][i % 3],
            outline="#536260",
        )
        d.rectangle((x - 3, y + 3, x + 3, y + 5), fill="#b4ceca")
        d.point((x, y + 4), fill="#6e8888")
        d.line((x - 3, y + 8, x + 3, y + 8), fill="#826f5e")
    for x in (12, 49):
        d.line((cx, cy, x, 67), fill="#4f6363", width=3)
        d.line((cx, cy, x, 67), fill="#9aa99c")
    d.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill="#bd966a", outline="#5c6c66")
    d.point((cx - 1, cy - 1), fill="#e0cba3")
    return im


def write(root):
    folder = root / "assets/galar/street"
    folder.mkdir(parents=True, exist_ok=True)
    for make in (bench, bollard, gatepier, chimney, hoist, wall, pipes, wheel):
        make().save(folder / (make.__name__ + ".png"), optimize=True)
