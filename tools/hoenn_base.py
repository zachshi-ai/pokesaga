"""Compile Emerald's Secret Power sites, furniture, and map-specific PC positions."""
import re

def compile_base(m, row, puzzle, tile, labels, blocks, attrs, source):
    name = m['name']
    src = (source / 'src/secret_base.c').read_text()
    open_tiles = {labels[a]:labels[b] for a,b in re.findall(r'closedMetatileId = (METATILE_\w+),\s*\.openMetatileId = (METATILE_\w+)', src)}
    for obj in row['objects']:
        if 'secret_site' not in obj:
            continue
        x,y = obj['at']
        old = int(blocks[y][x])
        obj['open_tile'] = [x,y,*tile(open_tiles[old]),1]
    if not name.startswith('SecretBase_'):
        return
    pos = re.search(r'MAP_NUM\('+row['source_id']+r'\),\s*0,\s*(\d+),\s*(\d+)',src)
    x,y = map(int,pos.groups())
    row['objects'].append(dict(kind='sign', native_fixture=True,source_script='EmeraldBasePC',at=[x,y-1]))
    entrance = m['warp_events'][0]
    exit_at = [entrance['x'],entrance['y']]
    row['objects'].append(dict(kind='sign',native_fixture=True,source_script='EmeraldBaseExit',at=exit_at))
    puzzle['base'] = dict(pc_at=[x,y],exit=exit_at,furniture={})
    definitions = (source/'src/data/decoration/header.h').read_text()
    graphics = (source/'src/data/decoration/tiles.h').read_text()
    for key,body in re.findall(r'\[DECOR_(\w+)\]\s*=\s*\{(.*?)\}',definitions,re.S):
        if key=='NONE':
            continue
        width,height=map(int,re.search(r'DECORSHAPE_(\d+)x(\d+)',body).groups())
        price=int(re.search(r'\.price = (\d+)',body)[1])
        cells=re.search(r'DecorGfx_'+key+r'\[\] = \{(.*?)\};',graphics,re.S)[1]
        perm=re.search(r'\.permission = DECORPERM_(\w+)',body)[1]
        category=re.search(r'\.category = DECORCAT_(\w+)',body)[1]
        native=re.findall(r'DECOR_TILE\((\w+)\)',cells)
        glyph=re.search(r'OBJ_EVENT_GFX_\w+',cells)
        d=dict(size=[width,height],price=price,permission=perm,category=category)
        if glyph:
            d['gfx']=glyph.group()
        else:
            indices=[labels['METATILE_SecretBase_'+k] for k in native]
            assert len(indices)==width*height,(key,native)
            d['tiles']=[tile(v) for v in indices]
            d['surface']=[int(attrs[v]) & 255 for v in indices]
        puzzle['base']['furniture'][key]=d
    beh=re.findall(r'^\s*(MB_\w+),',(source/'include/constants/metatile_behaviors.h').read_text(),re.M)
    puzzle['base']['placement']={k:beh.index('MB_'+k) for k in ('SECRET_BASE_NORTH_WALL','HOLDS_SMALL_DECORATION','HOLDS_LARGE_DECORATION','SECRET_BASE_HOLE')}

def effect_tiles(art, source, output):
    """Allocate animation frames after the ordinary furniture and map atlas."""
    from PIL import Image
    with Image.open(source/'graphics/field_effects/pics/sparkle.png') as sprite:
        sprite.info['transparency'] = 0
        sprite.convert('RGBA').save(output/'base_sparkle.png')
    _, _, attrs, primary, secondary = art.rows('LAYOUT_SECRET_BASE_RED_CAVE1')
    text = (source / 'include/constants/metatile_labels.h').read_text()
    labels = {key: int(value, 16) for key,value in re.findall(r'METATILE_SecretBase_(\w+)\s+(0x[0-9A-Fa-f]+)',text)}

    def tile(index):
        upper = art.tile_id(primary, secondary, index, True) if (attrs[index] >> 12) != 1 else 0
        return [art.tile_id(primary, secondary, index), upper]

    effects = {}
    for item, key in [('RED_BALLOON','RedBalloon'),('BLUE_BALLOON','BlueBalloon'),('YELLOW_BALLOON','YellowBalloon'),('MUD_BALL','MudBall')]:
        effects[item] = [[tile(labels[key]+frame)] for frame in (1,2,3)]
    effects['BREAKABLE_DOOR'] = [[tile(labels['BreakableDoor_TopOpen']),tile(labels['BreakableDoor_BottomOpen'])]]
    effects['SAND_ORNAMENT'] = [[tile(labels['SandOrnament_BrokenTop']),tile(labels['SandOrnament_BrokenBase'])]]
    return effects


def side_tables(source,scripts):
    import json
    from pathlib import Path
    species={r['key']:r['id'] for r in json.loads((Path(__file__).resolve().parents[1]/'content/species.json').read_text())}
    src=(source/'src/pokemon.c').read_text().split('sHoennToNationalOrder[NUM_SPECIES - 1] =')[1].split('};')[0]
    species["CASTFORM"]=species["CASTFORM_NORMAL"]
    regional=[species[n] for n in re.findall(r'HOENN_TO_NATIONAL\((\w+)\)',src)[:200]]
    assert len(regional)==200 and regional[-1]==384
    roaming={}
    for line in (source/'src/roamer.c').read_text().splitlines():
        if not line.strip().startswith('{ MAP_NUM(MAP_ROUTE'):continue
        roads=['hoenn_'+n for n in re.findall(r'MAP_NUM\(MAP_ROUTE(\d+)\)',line)]
        roaming[roads[0]]=roads[1:]
    shops={}
    for sc,body in scripts.items():
        name=re.search(r'pokemartdecoration2? (\w+)',body)
        if name:
            store=sc.replace('PrettyPetalFlowerShop_EventScript_SellDecorations','PrettyPetalFlowerShop_EventScript_ShopOwner')
            shops[store]=re.findall(r'\.2byte DECOR_(?!NONE)(\w+)',scripts[name[1]])
    assert len(shops)==10 and len(roaming)>=15 and all(shops.values())
    return dict(regional=regional,roaming=roaming,decor_shops=shops)
