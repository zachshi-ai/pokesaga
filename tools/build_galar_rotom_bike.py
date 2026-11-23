"""Convert Emerald Brendan's nine-frame Mach Bike art and add three water-mode pontoons."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/galar'

def pontoon(draw, cx, cy, side_view):
    outline, lower, body = '#243a4d', '#985357', '#df7561'
    if side_view:
        pts=[(cx-5,cy),(cx-3,cy-3),(cx+2,cy-3),(cx+5,cy-1),(cx+5,cy+2),(cx+3,cy+3),(cx-4,cy+3),(cx-5,cy+1)]
        draw.polygon(pts, fill=lower, outline=outline)
        draw.line([(cx-3,cy-1),(cx-2,cy-2),(cx+2,cy-2),(cx+3,cy-1)], fill=body)
        draw.line((cx-1,cy-2,cx-1,cy+1), fill='#e7dfc7', width=2)
    else:
        pts=[(cx-2,cy-5),(cx+1,cy-5),(cx+3,cy-2),(cx+3,cy+3),(cx+1,cy+5),(cx-2,cy+5),(cx-3,cy+2),(cx-3,cy-2)]
        draw.polygon(pts, fill=lower, outline=outline)
        draw.line([(cx-2,cy+2),(cx-2,cy-2),(cx-1,cy-4),(cx+1,cy-4)],fill=body)
        draw.line((cx-2,cy+1,cx+2,cy+1), fill='#e7dfc7', width=2)

def build(source):
    raw=Image.open(source)
    assert raw.size==(288,32) and raw.mode=='P'
    raw.info['transparency']=raw.getpixel((0,0))
    bike=raw.convert('RGBA')
    bike.save(OUT/'rotom_bike_land.png',optimize=True)
    water=Image.new('RGBA',(96,32))
    for direction in range(3):
        frame=bike.crop((direction*32,0,(direction+1)*32,32))
        # Retain Brendan, the bike frame and handlebars; the water modules take the place of the tires.
        if direction==2:
            frame.paste((0,0,0,0),(0,29,32,32))
            dr=ImageDraw.Draw(frame)
            for x in (8,22):pontoon(dr,x,28,True)
        else:
            frame.paste((0,0,0,0),(0,28,32,32))
            dr=ImageDraw.Draw(frame)
            dr.line((9,24,22,24),fill='#415b64',width=2)
            for x in (9,22):pontoon(dr,x,25,False)
        water.paste(frame,(direction*32,0))
    water.save(OUT/'rotom_bike_water.png',optimize=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mach_bike',type=Path,help='pokeemerald graphics/object_events/pics/people/brendan/mach_bike.png')
    build(parser.parse_args().mach_bike)
