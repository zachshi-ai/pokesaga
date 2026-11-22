"""Rebuild Super Contest parties, move effects, themes, Berry flavors and dress-up art."""
import json,re,struct,sys
from pathlib import Path
from PIL import Image

pt,zh=map(Path,sys.argv[1:3])
root=Path(__file__).resolve().parents[1]
def rows(name):
    return json.loads((zh/'texts/DP/zh_Hans'/f'{name}.json').read_text())
def names(name):
    return [r['translation'] for r in rows(name)]
narc=(pt/'res/prebuilt/contest/data/contest_data.narc').read_bytes()
base=narc.index(b'GMIF')+8
def member(i):
    start,end=struct.unpack_from('<II',narc,28+i*8)
    return narc[base+start:base+end]
raw=member(0)
labels=names('cmsg_breeder')
opponents=[]
for i in range(0,len(raw),48):
    moves=struct.unpack_from('<4H',raw,i+12)
    species,nick,ot=struct.unpack_from('<3H',raw,i+20)
    flags=struct.unpack_from('<H',raw,i+32)[0]
    opponents.append(dict(species=species,moves=[m for m in moves if m],name=labels[nick],trainer=labels[ot],rank=flags&7,
        categories=(flags>>3)&31,special=(flags>>10)&3,practice=bool(flags&512),display=bool(flags&256),condition=list(raw[i+26:i+32]),outfits=list(raw[i+34:i+46])))
effects=(pt/'src/unk_02094EDC.c').read_text()
appeal={k:int(n,0)//10 for k,n in re.findall(r'\[CONTEST_EFFECT_(\w+)\]\s*=\s*\{\s*\w+,\s*\w+,\s*(0x\w+|\d+)',effects)}
categories=['COOL','BEAUTY','CUTE','SMART','TOUGH']
moves={}
for i,k in enumerate((pt/'generated/moves.txt').read_text().splitlines()):
    path=pt/'res/moves'/k.removeprefix('MOVE_').lower()/'data.json'
    if i==0 or not path.exists():continue
    m=json.loads(path.read_text())['contest'];effect=m['effect'][15:]
    moves[i]=[categories.index(m['type'][13:]),effect,appeal[effect]]
berries={}
for p in (pt/'res/items/data').glob('*_berry.json'):
    b=json.loads(p.read_text()).get('berryData')
    if b:berries[p.stem[:-6]]=[b[k] for k in ['spiciness','dryness','sweetness','bitterness','sourness','smoothness']]
header=(pt/'include/constants/accessories.h').read_text().split('enum Accessory {')[1].split('    ACCESSORY_COUNT,')[0]
acc=re.findall(r'^\s*ACCESSORY_(\w+)',header,re.M)
acc_names=names('imageclip_acce')
prizes=[acc.index(a) for a in re.findall(r'accessoryID = ACCESSORY_(\w+);',(pt/'src/contest.c').read_text()) if a in acc]
outfits=member(2)
outfits=[list(outfits[i:i+outfits[i+80]*4:4]) for i in range(0,len(outfits),84)]
assert len(acc)==100 and len(prizes)==20 and len(moves)==467
atlas=Image.new('RGBA',(10*40,10*40))
for i,name in enumerate(acc):
    path=pt/'res/graphics/fashion_case/accessories'/('accessory_'+name.lower()+'.png')
    if not path.exists():
        path=next((p for p in path.parent.glob('*.png') if p.stem.replace('horn','hown')==path.stem),None)
    if not path:continue
    im=Image.open(path);im.info['transparency']=0;im=im.convert('RGBA');im=im.crop(im.getbbox()) if im.getbbox() else im
    im.thumbnail((36,36),Image.Resampling.NEAREST)
    atlas.alpha_composite(im,(i%10*40+(40-im.width)//2,i//10*40+(40-im.height)//2))
atlas.save(root/'assets/platinum/accessories.png')
shop_source=(pt/'src/overlay007/accessory_shop.c').read_text()
shop=[[acc.index(item),berry.lower(),int(cost)] for item,berry,cost in re.findall(r'{ ACCESSORY_(\w+), BERRY_ID\((\w+)\), (\d+) }',shop_source)]
massage=list(range(acc.index('PRETTY_DEWDROP'),acc.index('GLITTER_POWDER')+1))
assert len(shop)==22
picnic_source=(pt/'src/scrcmd_amity_square.c').read_text().split('sMonFindableAccessories')[1].split('};')[0]
pool_names=re.findall(r'ACCESSORY_(\w+)',picnic_source)[1:]
pool_ids=[acc.index(n) for n in pool_names if n in acc]
assert len(pool_ids)==60, pool_ids
square=(pt/'res/field/maps/amity_square/scripts.s').read_text()
square_events=json.loads((pt/'res/field/maps/amity_square/events.json').read_text())
huts={}
for event in square_events['coord_events']:
    m=re.fullmatch('AmitySquare_Warp(\d+)',event['script'])
    if not m:continue
    index=m[1]
    x,z=event['x'],event['z']
    block=re.search(rf'^AmitySquare_Movement_PlayerGoToDestinationWarp{index}:\n(.*?)EndMovement',square,re.M|re.S)[1]
    for direction,n in re.findall(r'WalkFaster(North|West|East|South)(?: (\d+))?',block):
        dx,dz={'North':(0,-1),'South':(0,1),'West':(-1,0),'East':(1,0)}[direction]
        x+=dx*int(n or 1);z+=dz*int(n or 1)
    huts[f"{event['x']},{event['z']}"]=[x,z+1]
gifts=re.search(r'sBerryAndAccessoryManOptions\[\] = \{(.*?)\};',(pt/'src/scrcmd_amity_square.c').read_text(),re.S)[1]
gift_items=[berry.lower() if berry else acc.index(deco) for berry,deco in re.findall(r'ITEM_(\w+)_BERRY|ACCESSORY_(\w+)',gifts)]
out=dict(huts=huts,park_gifts=gift_items,amity=[pool_ids[i:i+10] for i in range(0,60,10)],shop=shop,massage=massage,outfits=outfits,moves=moves,berries=berries,opponents=opponents,themes=[list(member(i)) for i in range(3,15)],accessories=acc_names[:100],prizes=prizes)
(root/'content/sinnoh_contests.json').write_text(json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n')
