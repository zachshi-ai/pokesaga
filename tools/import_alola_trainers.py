"""Import four Gen VII trainer tables from PokeFeur's vanilla_exports at 012259145f9f29fb33d64ecc218dff1c966bb1fd."""
import json
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
def slug(text):
    return re.sub('[^a-z0-9]', '', text.lower())
moves={slug(m['key']):m['id'] for m in json.loads((ROOT/'content/moves.json').read_text())}
moves['vicegrip']=moves['visegrip']
species={m['id']:m['key'] for m in json.loads((ROOT/'content/species.json').read_text())}
forms=json.loads((ROOT/'content/oras_pokemon.json').read_text())['forms']
special={423:{1:'EAST'},741:{1:'POM_POM',2:'PAU',3:'SENSU'},773:{9:'FIRE',10:'WATER',11:'GRASS'},
    745:{1:'MIDNIGHT'},669:{1:'YELLOW'},671:{1:'YELLOW',4:'WHITE'},676:{5:'DANDY'},550:{1:'BLUE_STRIPED'},
    774:{7:'CORE_RED',9:'CORE_YELLOW',11:'CORE_BLUE'},718:{1:'10'}}
berries=json.loads((ROOT/'content/berries.json').read_text())
def transform(m):
    sid=m['speciesId'];form=m['formId']
    mon={'species':sid,'level':m['level'],'moves':[moves[slug(n)] for n in m['moveset']]}
    if form:
        name=({745:'LYCANROC',774:'MINIOR',741:'ORICORIO',423:'GASTRODON',550:'BASCULIN',669:'FLABEBE',671:'FLORGES',718:'ZYGARDE'}.get(sid,species[sid]))+'_'+special.get(sid,{}).get(form,'ALOLA')
        assert name in forms[str(sid)],name
        mon['form']=name
    if (m['heldItem'] or '').endswith(' Berry') and m['heldItem'][:-6].lower() in berries:mon['berry']=m['heldItem'][:-6].lower()
    elif m['heldItem']:mon['held']=re.sub('[^A-Z0-9]+','_',m['heldItem'].upper()).strip('_')
    if m['abilityIds']:mon['ability']=m['abilityIds'][0]
    return mon
def table(p):
    s=p.read_text()
    d=json.JSONDecoder().raw_decode(s[s.index('{"meta"'):])[0]
    return {str(t['trainerId']):[transform(m) for m in t['party']] for t in d['trainers']}
if __name__=='__main__':
    base=Path(sys.argv[1])
    teams={v:table(base/(v+'.js')) for v in ['sun','moon','ultra_sun','ultra_moon']}
    for a,b in [('sun','moon'),('ultra_sun','ultra_moon')]:
        teams[b]={k:t for k,t in teams[b].items() if t!=teams[a].get(k)}
    (ROOT/'content/alola_trainers.json').write_text(json.dumps(teams,ensure_ascii=False,separators=(',',':'))+'\n')
