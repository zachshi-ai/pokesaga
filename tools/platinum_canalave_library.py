"""Canalave's blue-roofed library, on the five-tile footprint of Platinum prop C2_S02."""
from PIL import Image, ImageDraw, ImageOps

from platinum_layout import ROOT


def facade():
    field = ROOT / "assets/emerald/field"
    with Image.open(field / "home_blue.png") as home, Image.open(field / "academy.png") as academy:
        # Slate from an Emerald roof and the cut-stone courses of the Rustboro landmark.
        slate = home.convert("RGB").crop((8, 12, 24, 31))
        stone = academy.convert("RGB").crop((9, 40, 18, 57))
    slate = ImageOps.colorize(ImageOps.grayscale(slate), "#26477c", "#75a4cc")
    stone = ImageOps.colorize(ImageOps.grayscale(stone), "#868a82", "#c7c5a5")
    image = Image.new("RGBA", (80, 99))
    draw = ImageDraw.Draw(image)
    ink, shade, stone_light = "#4a5158", "#737975", "#dbd7b6"
    sill, bronze, glass = "#b0ad91", "#b69963", "#435d72"

    def surface(vertices, texture):
        mask = Image.new("L", image.size)
        ImageDraw.Draw(mask).polygon(vertices, fill=255)
        panel = Image.new("RGB", image.size)
        for y in range(0, image.height, texture.height):
            for x in range(0, image.width, texture.width):
                panel.paste(texture, (x, y))
        image.paste(panel, (0, 0), mask)
        draw.line([*vertices, vertices[0]], fill=ink)

    def arched_window(x, y):
        # Recessed stone surrounds, leaded panes and a protruding sill.
        draw.polygon([(x,y+3),(x+3,y),(x+7,y),(x+10,y+3),(x+10,y+14),(x,y+14)], fill=shade)
        draw.line([(x,y+12),(x,y+4),(x+3,y+1),(x+7,y+1),(x+9,y+3)], fill=stone_light)
        draw.polygon([(x+2,y+5),(x+4,y+3),(x+6,y+3),(x+8,y+5),(x+8,y+12),(x+2,y+12)], fill=glass)
        draw.line((x+3,y+6,x+3,y+11),fill="#87a7ad")
        draw.line((x+5,y+3,x+5,y+12),fill="#b4b5a0")
        draw.line((x+2,y+7,x+8,y+7),fill=shade)
        draw.line((x,y+13,x+10,y+13),fill=stone_light)
        draw.line((x-1,y+14,x+11,y+14),fill=ink)

    # The seaward return recedes to the right. Its foot remains within the blocked lot.
    draw.polygon([(70,33),(78,27),(78,87),(70,95)], fill=shade, outline=ink)
    for y in range(39,91,7):
        draw.line([(71,y),(77,y-5)], fill="#969983")
    surface([(2,36),(70,36),(70,94),(2,94)],stone)
    for x in (3,67):
        draw.rectangle((x,36,x+2,91),fill=sill)
        draw.line((x,36,x,91),fill=stone_light)
        for y in range(42,90,6):
            draw.point((x+1,y),fill=shade)

    # Hipped slate roof, with a stepped ridge, alternating tiles and a shaded far slope.
    surface([(2,32),(14,5),(61,5),(71,32)],slate)
    draw.polygon([(61,5),(70,2),(79,25),(71,33)],fill="#405b88",outline=ink)
    for j in range(4,24,5):
        draw.line([(63+j//4,5+j),(70+j//3,2+j)],fill="#697fa1")
    draw.line([(13,5),(20,2),(69,2)],fill="#65758d",width=2)
    draw.line([(14,5),(61,5),(69,2)],fill="#b2bbc0")
    draw.line([(3,31),(14,6)],fill="#a5afba")
    draw.rectangle((0,32,71,36),fill=ink)
    draw.line((1,32,71,32),fill="#a3adba")
    draw.line((1,34,70,34),fill="#73869c")
    draw.line([(71,32),(79,25),(79,28),(71,36)],fill="#626d7b")

    # Two rows of glazed reading-room windows and a third floor in the central dormer.
    for x in (8,23,39,55):
        arched_window(x,39)
    draw.rectangle((2,55,70,58), fill=shade)
    draw.line((2,55,70,55),fill=stone_light)
    draw.line((3,58,70,58),fill=ink)
    for x in (8,55):
        arched_window(x,64)
        draw.line((x-1,83,x+10,83),fill=shade)
    draw.polygon([(26,24),(38,11),(50,24),(50,34),(26,34)],fill=sill,outline=ink)
    draw.line([(23,25),(38,10),(53,25)],fill="#414d67",width=3)
    draw.line([(24,23),(38,9),(52,23)],fill="#bac0bd")
    arched_window(33,18)

    # A stone portico at eaves height, with a gilt open book and a recessed double door.
    draw.polygon([(20,67),(20,62),(40,49),(59,62),(59,67)],fill=shade,outline=ink)
    draw.polygon([(20,62),(40,48),(59,62),(54,62),(40,53),(25,63)],fill="#647b96")
    draw.line([(19,62),(40,47),(60,62)],fill=stone_light)
    draw.polygon([(28,62),(40,54),(52,62)],fill=ink)
    for wing in ([(33,56),(36,56),(38,57),(39,58),(39,61),(36,60),(33,60)],
                 [(41,58),(42,57),(44,56),(47,56),(47,60),(44,60),(41,61)]):
        draw.polygon(wing,fill="#e4c688")
    draw.line((34,57,36,57),fill=stone_light)
    draw.line((44,57,46,57),fill=stone_light)
    draw.rectangle((20,63,59,67),fill=sill)
    draw.line((20,63,59,63),fill=stone_light)
    draw.line((21,67,58,67),fill=ink)
    for x in (22,52):
        draw.rectangle((x,68,x+5,92),fill=shade)
        draw.rectangle((x+1,69,x+3,90),fill=stone_light)
        draw.line((x+3,71,x+3,90),fill=sill)
        draw.line((x-1,69,x+6,69),fill=bronze)
        draw.rectangle((x-1,90,x+6,93),fill=sill,outline=shade)
    draw.polygon([(29,94),(29,78),(32,72),(36,69),(44,69),(48,72),(51,78),(51,94)],fill=ink)
    draw.polygon([(32,94),(32,78),(35,74),(38,72),(42,72),(46,74),(48,78),(48,94)],fill="#8b7159")
    draw.line([(31,77),(35,72),(38,70),(43,70),(48,74),(50,78)],fill=bronze)
    for x in (33,41):
        draw.rectangle((x,77,x+5,83),fill=glass,outline="#575c60")
        draw.line((x+1,78,x+1,81),fill="#9db1ab")
        draw.rectangle((x,86,x+5,92),outline="#695c51")
    draw.line((40,73,40,94),fill=ink)
    for x in (38,42):
        draw.point((x,85),fill="#ead097")
    draw.rectangle((2,93,20,94),fill=shade)
    draw.rectangle((60,93,70,94),fill=shade)
    for i in range(2):
        draw.rectangle((22-i*2,94+i*2,58+i*2,95+i*2),fill=sill)
        draw.line((22-i*2,94+i*2,58+i*2,94+i*2),fill=stone_light)
    return image
