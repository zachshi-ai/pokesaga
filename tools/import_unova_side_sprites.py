"""Extract the down-facing pose of original Unova field encounters, scaled to the 16px map grid."""
from pathlib import Path
import argparse
from PIL import Image
from import_unova_side import ROOT,load,constants

# Numeric names are the original field-object codes. The Lake trio uses six-frame followers.
MODELS={278:'pokemon/wingull',494:'125',518:'127',612:'344',637:'124',638:'115',639:'116',640:'117',644:'365',645:'120',646:'121',377:'350',378:'351',379:'352',381:'pokemon/latios',480:'pokemon/uxie',481:'pokemon/mesprit',482:'pokemon/azelf',485:'349',486:'356',488:'347'}

def build(src):
    registry=MODELS.copy()
    items=load(ROOT/'content/unova_side_items.json')
    species=constants(src/'generated/species.txt','SPECIES_')
    for cave in items['grottos']:
        for group in cave[3]:
            for id,*_ in group:
                if id not in registry:registry[id]='pokemon/'+species[id].lower()
    registry['item_ball']='110'
    for id,model in registry.items():
        native=src/'res/field/actors'/model/'sprite.png'
        if not native.exists():
            # Gen V followers without an external walking sprite retain their own project portrait.
            img=Image.open(ROOT/f'assets/party/{id}.png').convert('RGBA')
            img=img.crop(img.getbbox());img.thumbnail((23,27),Image.Resampling.NEAREST)
            canvas=Image.new('RGBA',(32,32));canvas.alpha_composite(img,((32-img.width)//2,31-img.height))
            canvas.save(ROOT/f'assets/npc/unova_pokemon_{id}.png')
            continue
        sheet=Image.open(native).convert('RGBA')
        size=sheet.height
        poses=sheet.width//size
        # Six-pose followers face the camera in the third frame. The twelve-
        # and fifteen-pose field objects group their forward stance in frames 3–5.
        frame=2 if poses==6 else 3
        img=sheet.crop((size*frame,0,size*(frame+1),size))
        box=img.getbbox()
        if not box:
            img=next(c for i in range(poses) if (c:=sheet.crop((size*i,0,size*(i+1),size))).getbbox())
            box=img.getbbox()
        img=img.crop(box)
        img.thumbnail((28,30),Image.Resampling.NEAREST)
        canvas=Image.new('RGBA',(32,32))
        canvas.alpha_composite(img,((32-img.width)//2,31-img.height))
        canvas.save(ROOT/('assets/npc/unova_item_ball.png' if id=='item_ball' else f'assets/npc/unova_pokemon_{id}.png'))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path)
    build(parser.parse_args().source)
