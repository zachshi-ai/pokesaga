"""Draw the larger Totem Mimikyu poses from the shipped Emerald-style poses and shiny palettes."""
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
TILE=64


def build():
    result=Image.new('RGBA',(4*TILE,2*TILE))
    for back,prefix in enumerate(['','back_']):
        catalog=json.loads((ROOT/('content/dex_'+prefix+'art.json')).read_text())
        for shiny,palette in enumerate(['normal','shiny']):
            for pose,key in enumerate(['','MIMIKYU_BUSTED']):
                n=catalog['778'][key]
                page=Image.open(ROOT/('assets/dex/'+prefix+palette+'_'+str(n//256)+'.png')).convert('RGBA')
                x,y=(n%16)*TILE,(n%256//16)*TILE
                frame=page.crop((x,y,x+TILE,y+TILE))
                box=frame.getbbox()
                body=frame.crop(box)
                scale=min(2,(TILE-2)/max(body.size))
                body=body.resize((round(body.width*scale),round(body.height*scale)),Image.Resampling.NEAREST)
                tile=Image.new('RGBA',(TILE,TILE))
                tile.paste(body,((TILE-body.width)//2,TILE-1-body.height))
                result.paste(tile,((back*2+shiny)*TILE,pose*TILE))
                if not back and not shiny:
                    name='778_totem_'+('busted' if pose else 'disguised')
                    tile.save(ROOT/('assets/mon/forms/'+name+'.png'))
    result.save(ROOT/'assets/dex/alola_mimikyu_totem.png')


if __name__=='__main__':build()
