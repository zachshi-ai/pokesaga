"""Compile native Battle Subway, PWT, Black Tower parties and Pokéstar rentals."""
import argparse
import re
from pathlib import Path
from PIL import Image
from import_unova_side import ROOT,constants,load,write,original


def build(src):
    species=constants(src/'generated/species.txt','SPECIES_')
    moves=constants(src/'generated/moves.txt','MOVE_')
    base=src/'res/trainers/facilities'
    pwt=load(base/'pwt_trainers.json')['trainers']
    result={}
    for kind in ['battle_subway','pwt_regular','pwt_leaders','pwt_masters','pwt_rental','black_tower']:
        p=base/kind
        order=load(p/'order.json')
        ids={k:i for i,k in enumerate(order['pokemon'])}
        sets=[]
        for key in order['pokemon']:
            m=load(p/'pokemon'/(key+'.json'))
            sets.append([species.index(m['species'][8:]),[moves.index(v[5:]) for v in m['moves'] if v!='MOVE_NONE'],m['item'][5:],m['nature'][7:],list(k for k,b in m['ev_flags'].items() if b)])
        trainers=[]
        for i,key in enumerate(order['trainers']):
            t=load(p/'trainers'/(key+'.json'))
            if kind.startswith('pwt_') and i==0:continue  # File zero is a dummy before Cheren.
            who=pwt[i-1]['trainer_class'][14:] if kind.startswith('pwt_') and i-1<len(pwt) else key
            row=[who.lower(),[ids[x] for x in t['pokemon'] if x in ids and ids[x]!=0]]
            if kind.startswith('pwt_'):row.append(ids[t['single_set']])
            trainers.append(row)
        result[kind]={'sets':sets,'trainers':trainers}
    result['pwt_rules']=[[t['tournaments'],t['tournament'],str(t['expert_type']).removeprefix('TYPE_').lower(),t['rank'],t['iv'],t['special_pokemon'],t['type']] for t in pwt]
    names=original(src,'res/text/system/world_tournament_trainer_names.txt').decode('utf-8')
    result['pwt_names']=[line.split(' = ',1)[1].replace(chr(92)+'c','') for line in names.splitlines() if ' = ' in line]
    source=original(src,'src/field/script/scrcmd_leaves.c').decode()
    block=source.split('const WbtTournamentInfo PWT_TOURNAMENT_INFO[15] = {',1)[1].split('};',1)[0]
    fields=re.findall(r'WorldTournamentParty_Text_\w+, (\d+), (\d+), (\d+), (\d+), \{ ([\d, ]+) \}',block)
    result['pwt_modes']=[[int(kind),int(archive),list(map(int,bp.split(',')))] for _,_,kind,archive,bp in fields]
    assert len(result['pwt_modes'])==15
    native_types={}
    for n,key in enumerate(species[1:650],1):
        raw=load(src/'res/pokemon'/key.lower()/'data.json')
        native_types[str(n)]=list(dict.fromkeys(t[5:].lower() for t in raw['types']))
    result['pwt_types']=native_types
    movies=[]
    props={}
    asset_dir=ROOT/'assets/unova/film'
    asset_dir.mkdir(parents=True,exist_ok=True)
    for pid,key in enumerate(species):
        if not key.startswith('POKESTAR_'):continue
        slug=key[9:].lower()
        source=src/'res/pokemon/pokestar'/slug
        if not (source/'data.json').exists():continue
        raw=load(source/'data.json')
        props[str(pid)]={'slug':slug,'types':[t[5:].lower() for t in raw['types']],'stats':raw['base_stats']}
        img=Image.open(source/'front_single.png').convert('RGBA')
        img.save(asset_dir/(slug+'.png'))

    for n in range(40):
        p=src/f'res/pokewood/movies/{n}'
        row=load(p/'movie.json')
        cast=load(p/'cast.json')
        def mon(m):
            return [species.index(m['species'][8:]),m['level'],[moves.index(v[5:]) for v in m['moves'] if v!='MOVE_NONE'],m['held_item'][5:],m['shown_species'][8:],species.index(m['shown_species'][8:]),m['ivs'],m['evs'],m['nature'][7:]]
        movies.append({'player':[mon(m) for m in cast['player']],'enemy':[mon(m) for m in cast['opponent']],'turns':row['turn_limit'],'ideal':row['ideal_turn'],'rule':row['rule'],'stars':row['star_level'],'target':species.index(row['species'][1][8:]) if isinstance(row['species'][1],str) else 0,'move':row['unk16']})
    result['movies']=movies
    result['props']=props
    write(ROOT/'content/unova_side_activities.json',result)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    build(parser.parse_args().source)
