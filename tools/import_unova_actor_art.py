"""Build the 16-pixel Unova field character sheets from BW2 and GBA redraws."""
import argparse
import json
from pathlib import Path
from PIL import Image
from import_platinum_cast import rgba, read_gba
from unova_source import names

ROOT=Path(__file__).resolve().parents[1]
POSES=(0,1,2,4,8,5,9,6,10,3,7,11)
NAMES={
    "白露": "bianca",
    "黑连": "cheren",
    "修": "hugh",
    "N": "n",
    "Ｎ": "n",
    "魁奇思": "ghetsis",
    "阿克罗玛": "colress",
    "阿戴克": "alder",
    "芦荟": "lenora",
    "亚堤": "burgh",
    "小菊儿": "elesa",
    "菊老大": "clay",
    "风露": "skyla",
    "哈奇库": "brycen",
    "夏卡": "drayden",
    "艾莉丝": "iris",
    "天桐": "cilan",
    "伯特": "chili",
    "寇恩": "cress",
    "霍米加": "roxie",
    "西子伊": "marlon",
    "婉龙": "shauntal",
    "越橘": "grimsley",
    "连武": "marshal",
    "嘉德丽雅": "caitlin",
    "等离子队团员": "plasma_grunt_m",
    "等离子队员": "plasma_grunt_m",
    "新等离子队员": "neo_plasma_grunt_m"
}

def named_sheets(rogue):
    source=rogue/'graphics/object_events/pics/rogue/npc'
    files={p.stem:p for p in sorted((source/'unova').glob('*.png'))}
    files['grimsley']=files.pop('grimsly')
    for key in ('bianca','cheren','hugh','n'):
        files[key]=source/'rival'/(key+'.png')
    for key,stem in [('colress','neo_plasma_colress'),('ghetsis','plasma_ghetsis')]:
        files[key]=source/'team'/(stem+'.png')
    for key in ('plasma_grunt_m','plasma_grunt_f','neo_plasma_grunt_m','neo_plasma_grunt_f'):
        files[key]=source/'team'/(key+'.png')
    return {key:read_gba(path) for key,path in files.items()}

def adapt_strip(path,palette):
    strip=rgba(path)
    count=strip.width//strip.height
    # Larger assets and single-frame props are drawn by the map/object renderer.
    if strip.height!=32 or count<4:return None
    tiles=[strip.crop((i*32,0,(i+1)*32,32)) for i in range(min(count,12))]
    order=POSES if count>=12 else (0,1,2,0,0,1,1,2,2,3,2,2)
    frames=[tiles[i] for i in order]
    bounds=[frame.getbbox() for frame in frames if frame.getbbox()]
    if not bounds:return None
    x=min(b[0] for b in bounds);y=min(b[1] for b in bounds)
    ex=max(b[2] for b in bounds);ey=max(b[3] for b in bounds)
    scale=min(16/(ex-x),25/(ey-y),1)
    size=(max(1,round((ex-x)*scale)),max(1,round((ey-y)*scale)))
    posing=[]
    for frame in frames:
        frame=frame.crop((x,y,ex,ey)).resize(size,Image.Resampling.NEAREST)
        color=frame.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGB')
        color.putalpha(frame.getchannel('A'))
        pose=Image.new('RGBA',(16,32))
        pose.paste(color,((16-size[0])//2,32-size[1]))
        posing.append(pose)
    return posing

def build(b2,rogue,out):
    sheets=named_sheets(rogue)
    sample=Image.new('RGB',(16,len(sheets)*32))
    for i,poses in enumerate(sheets.values()):
        sample.paste(poses[0],(0,32*i),poses[0])
    palette=sample.quantize(192,method=Image.Quantize.MEDIANCUT)
    for i,name in enumerate(names(b2,'obj_codes','OBJ_CODE_')):
        path=b2/'res/field/actors'/name/'sprite.png'
        if path.exists():
            poses=adapt_strip(path,palette)
            if poses:sheets[str(i)]=poses
    atlas=Image.new('RGBA',(1536,32*((len(sheets)+7)//8)));records={}
    for i,(name,frames) in enumerate(sorted(sheets.items())):
        x=(i%8)*192;y=(i//8)*32
        records[name]=[x,y,16]
        for j,frame in enumerate(frames):atlas.paste(frame,(x+j*16,y))
    for alias,key in NAMES.items():records[alias]=records[key]
    out.mkdir(parents=True,exist_ok=True)
    atlas.save(out/'cast.png',optimize=True)
    (out/'cast.json').write_text(json.dumps(records,ensure_ascii=False,separators=(',',':')))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('black2',type=Path);parser.add_argument('rogue',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'assets/unova')
    args=parser.parse_args();build(args.black2,args.rogue,args.output)
