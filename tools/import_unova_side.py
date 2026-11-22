#!/usr/bin/env python3
"""Build field collectibles, trades, Hidden Grottos and battle facilities from the two Black-version field archives."""
import argparse
import csv
import json
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def narc(path):
    contents = path if isinstance(path,bytes) else path.read_bytes()
    assert contents[:4] == b'NARC' and contents[16:20] == b'BTAF'
    count, = struct.unpack_from('<H', contents, 24)
    base = contents.index(b'GMIF') + 8
    return [contents[base+a:base+b] for a,b in
            (struct.unpack_from('<II', contents, 28+i*8) for i in range(count))]


def original(src, path):
    file=src/path
    return file.read_bytes() if file.exists() else subprocess.check_output(['git','-C',str(src),'show','HEAD:'+path])


def text_strings(bank):
    # Text records use a 16-bit rolling xor key. The trailing terminator supplies its last value.
    section,=struct.unpack_from('<I',bank,12)
    count,=struct.unpack_from('<H',bank,2)
    names=[]
    for i in range(count):
        offset,length,_=struct.unpack_from('<IHH',bank,section+4+8*i)
        values=list(struct.unpack_from('<'+'H'*length,bank,section+offset))
        key=values[-1]^65535
        for j in reversed(range(length)):
            values[j]^=key
            key=((key>>3)|(key<<13))&65535
        names.append(''.join(chr(v) for v in values if v!=65535))
    return names


def constants(path, prefix):
    result=[]
    for line in path.read_text().splitlines():
        code=line.partition('#')[0].strip().partition(' = ')[0]
        if code.startswith(prefix):
            result.append(code[len(prefix):])
    return result


def scripts(binary, hidden):
    result={}
    for offset in range(0, len(binary), 4):
        if struct.unpack_from('<H',binary,offset)[0] == 0xfd13: break
        start = offset + 4 + struct.unpack_from('<i',binary,offset)[0]
        if start+12>len(binary):break
        lock,cmd,var,item,_,_,qty = struct.unpack_from('<7H',binary,start)
        if lock==46 and (cmd,var) == ((42,0x8000) if hidden else (40,0x800c)):
            result[offset//4 + (8000 if hidden else 7000)]=(item,qty)
    return result


def bw1_pickups(bw, items):
    archives = narc(bw / 'files/a/0/5/7')
    visible=scripts(archives[864], False)
    hidden=scripts(archives[865], True)
    zones={}
    for bank,raw in enumerate(narc(bw/'files/a/1/2/5')):
        if len(raw)<8:continue
        bg,npc=raw[4:6]
        pos=8
        rows=[]
        for _ in range(bg):
            sid,_,_,rail,x,z,_ = struct.unpack_from('<4H3i',raw,pos)
            pos+=20
            if not rail and sid in hidden:
                item,count=hidden[sid]; rows.append([x,z,sid,items[item],count])
        for _ in range(npc):
            row=struct.unpack_from('<12HIHHi',raw,pos);pos+=36
            sid=row[5]
            if not row[12] and sid in visible:
                item,count=visible[sid];rows.append([row[13],row[14],sid,items[item],count])
        if rows:zones[str(bank)]=rows
    return zones


def bw2_pickups(src, items):
    # The scripts and event objects use zero-based global script numbers.
    lookup={}
    for base,verb,args in ((7000,'WorkSetConst', ('0x800c','0x800d')),(8000,'WorkSet',('0x8000','0x8001'))):
        source=(src/f'res/field/scripts/global_{base}.s').read_text()
        for match in re.finditer(r'^Script_(\d+):\n([\s\S]*?)(?=^\w+:|\Z)',source,re.M):
            nums=[re.search(r'\b'+verb+' '+arg+r', (\d+)',match[2]) for arg in args]
            if all(nums):
                lookup[base+int(match[1])-1]=(items[int(nums[0][1])],int(nums[1][1]))
    zones={}
    for path in sorted((src/'res/field/events').glob('*.json')):
        ev=json.loads(path.read_text())
        if not isinstance(ev,dict):continue
        rows=[]
        for e in ev.get('npcs',[])+ev.get('bg_events',[]):
            if e['script'] in lookup and 'grid' in e:
                item,count=lookup[e['script']]
                coord=e['grid']
                rows.append([coord['x'],coord['z'] if 'id' in e else coord['y'],e['script'],item,count])
        if rows:zones[path.stem]=rows
    return zones


def load(path): return json.loads(path.read_text())


def write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')


def compile_all(bw,b2,csv_dir):
    items=constants(b2/'generated/items.txt','ITEM_')
    species=constants(b2/'generated/species.txt','SPECIES_')
    moves=constants(b2/'generated/moves.txt','MOVE_')
    # PokeAPI's English display name resolves game constants with older spellings.
    names={}
    translations={}
    for row in csv.DictReader((csv_dir/'item_names.csv').open()):
        key=row['item_id']
        if row['local_language_id']=='9':names[row['name'].casefold()]=key
        if row['local_language_id']=='12':translations[key]=row['name']
    meta={}
    sinnoh=load(ROOT/'content/sinnoh_side.json')['items']
    common=load(ROOT/'content/items.json')
    held={row['key']:row['name'] for row in common if row.get('key')}
    for raw in (b2/'res/items').glob('*/data.json'):
        d=load(raw);key=raw.parent.name.upper()
        item_id=names.get(d['name'].casefold(),'')
        zh=translations.get(item_id,d['name'])
        category={'BAG_POCKET_MEDICINE':'heal','BAG_POCKET_BERRIES':'berry','BAG_POCKET_KEY_ITEMS':'key'}.get(d['field_pocket'],'other')
        if key in sinnoh:zh,category=sinnoh[key]
        if key in held:zh,category=held[key],'held'
        if key.endswith('_BALL') and key not in ('SMOKE_BALL','IRON_BALL','LIGHT_BALL'):category='ball'
        if key.endswith('_WING'):
            modern=names.get(d['name'].casefold().replace(' wing',' feather'),'')
            zh=translations.get(modern,zh)
        if key.endswith('_GEM') and d.get('hold_effect'):category='held'
        meta[key]=[zh,category,d['price']]
    field={'bw':bw1_pickups(bw,items),'b2':bw2_pickups(b2,items)}
    text=subprocess.check_output(['git','-C',str(b2),'show','HEAD:src/entralink/hidden_hollow.c'],text=True)
    entry=re.findall(r'\{ZONE_(\w+), (\d+), \d+, (\d+)\}',text)
    hollows=[]
    for i,(zone,x,z) in enumerate(entry[:20]):
        h=load(b2/f'res/field/hidden_hollows/{i:02}.json')
        sets=h['pokemon']['black_2'] if 'black_2' in h['pokemon'] else h['pokemon'][next(k for k in h['pokemon'] if 'black' in k)]
        slots=[[[species.index(s[8:]),v['min_level'][j],v['max_level'][j],v['female_below'][j],v['form'][j]] for j,s in enumerate(v['species'])] for v in sets]
        hollows.append([zone.lower(),int(x),int(z),slots,[[v[5:] for v in r] for r in h['items']],[[v[5:] for v in r] for r in h['hidden_items']]])
    trades=[]
    for key in constants(b2/'generated/trades.txt','TRADE_'):
        t=load(b2/f'res/field/trades/{key.lower()}.json')
        trades.append({'species':species.index(t['species'][8:]),'wanted':species.index(t['wanted_species'][8:]),'level':t['level'],'name':t['nickname'],'ot':t['trainer_name'],'id':t['trainer_id'],'item':t['held_item'][5:], 'ability_slot':t['ability_slot'],'nature':t['nature'],'ivs':t['ivs']})
    bw_trades=[]
    labels=text_strings(narc(original(bw,'files/a/0/0/2'))[35])
    natures=constants(b2/'generated/natures.txt','NATURE_')
    stats=['hp','attack','defense','speed','special_attack','special_defense']
    for raw in narc(original(bw,'files/a/1/6/5'))[:7]:
        row=struct.unpack('<27I',raw)
        bw_trades.append({'species':row[1],'wanted':row[23],'form':row[2],'level':row[3],'name':labels[row[25]],'ot':labels[row[26]],
                          'id':row[13],'item':items[row[19]],'ability_slot':row[10],'nature':'NATURE_'+natures[row[11]],'ivs':dict(zip(stats,row[4:10]))})
    abilities=constants(b2/'generated/abilities.txt','ABILITY_')
    hidden_abilities={}
    for i,key in enumerate(species[:650]):
        raw=b2/'res/pokemon'/key.lower()/'data.json'
        if raw.exists():
            ability=load(raw).get('hidden_ability')
            if ability: hidden_abilities[str(i)]=abilities.index(ability[8:])
    for key,name,cat in [('DOWSING_MCHN','探宝器','key'),('REVEAL_GLASS','现形镜','key'),('THUNDERSTONE','雷之石','evo'),('DNA_SPLICERS_FUSE','基因之楔','key'),('LIBERTY_PASS','自由船票','key')]:
        if key in meta:meta[key][:2]=[name,cat]
    db={'items':meta,'pickups':field,'grottos':hollows,'trades':trades,'hidden_abilities':hidden_abilities,'bw_trades':bw_trades}
    write(ROOT/'content/unova_side_items.json',db)
    print('pickups',[(v,sum(map(len,z.values()))) for v,z in field.items()],'grottos',len(hollows),'trades',len(trades))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('black',type=Path);p.add_argument('black2',type=Path);p.add_argument('csv',type=Path)
    args=p.parse_args();compile_all(args.black,args.black2,args.csv)
