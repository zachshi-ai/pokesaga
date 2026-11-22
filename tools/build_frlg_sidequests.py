"""Bind FireRed event scripts to their actual field positions, including merged routes."""
import argparse
import json
import re
from pathlib import Path
from PIL import Image
from frlg_tower_tables import compile_tower
from frlg_fame import extract as extract_fame

ROOT = Path(__file__).resolve().parents[1]
def read(p):
    return json.loads(p.read_text())
def compact(name):
    return re.sub('[^a-z0-9]', '', name.lower())
def blocks(text):
    return {m[1]:m[2] for m in re.finditer(r'^(\w+)::?\s*\n(.*?)(?=^\w+::?|\Z)',text,re.M|re.S)}

# Script names identify the speaker even on the combined Kanto outdoors map.
ACTORS = {
 'StickerMan':['stickers','四岛贴纸收藏家'], 'MagikarpSalesman':['buy_mon','鲤鱼王商人',129,5,500], 'EeveeBall':['gift_mon','伊布的精灵球',133,25],
 'HitmonleeBall':['dojo_gift','飞腿郎的精灵球',106,25], 'HitmonchanBall':['dojo_gift','快拳郎的精灵球',107,25],
 'Moltres':['wild','火焰鸟',146,50], 'Zapdos':['wild','闪电鸟',145,50], 'Articuno':['wild','急冻鸟',144,50],
 'Electrode1':['wild','顽皮雷弹',101,34],'Electrode2':['wild','顽皮雷弹',101,34],
 'HoOh':['wild','凤王',250,70],'Lugia':['wild','洛奇亚',249,70],'Triangle':['triangle','三角石'],
 'TwoIsland_JoyfulGameCorner_EventScript_InfoMan':['joyful','游戏角接待员'], 'CoinCaseMan':['gift_item','休息中的客人','代币盒','key'], 'ThirstyGirl':['drink_girl','口渴的女孩'],
 'CoinsClerk':['coins','代币柜台'],'PrizeClerkMons':['prizes','宝可梦奖品柜台','mons'],'PrizeClerkTMs':['prizes','招式奖品柜台','tms'],
 'PrizeClerkItems':['prizes','道具奖品柜台','items'], 'MoveManiac':['relearn','招式回忆者'],'StarterTutor':['starter_tutor','极限招式导师'],
 'MoveDeleter':['delete_move','遗忘爷爷'],'MemorialMan':['memorial_man','前来悼念的训练家'],
 'BerryPowderMan':['powder','树果粉末专家'],'DirectCornerAttendant':['link_battle','通信对战接待员'], 'WirelessClubAttendant':['powder_club','无线俱乐部接待员'],
 'ChanseyDanceMan':['dance','吉利蛋舞蹈家'], 'MrPsychic':['gift_item','超能力先生','招式学习器 29','tm'],
 'PalletTown_RivalsHouse_EventScript_Daisy':['map','奈奈美'],'Prospector':['prospector','采金人'],
 'PalletTown_RivalsHouse_EventScript_TownMap':['map','城镇地图'],
 'CeladonCity_GameCorner_EventScript_Fisher':['free_coins','钓鱼人',10],
 'CeladonCity_GameCorner_EventScript_Scientist':['free_coins','研究员',20],
 'CeladonCity_GameCorner_EventScript_Gentleman':['free_coins','绅士',20],
 'Copycat':['copycat','模仿少女'], 'FiveIsland_WaterLabyrinth':['egg','饲育家'],
 'Route12_NorthEntrance_2F':['gift_item','想念伙伴的女孩','招式学习器 27','tm'],
 'SixIsland_WaterPath_House1':['size_contest','喜爱赫拉克罗斯的女士',214,'巢穴球'],
 'Route10_PokemonCenter_1F_EventScript_Aide':['aide','大木博士的助手',20,'不变之石','EVERSTONE'],
 'Route11_EastEntrance_2F_EventScript_Aide':['aide','大木博士的助手',30,'探宝器',''],
 'Route16_NorthEntrance_2F_EventScript_Aide':['aide','大木博士的助手',40,'护符金币','AMULET_COIN'],
 'Route15_WestEntrance_2F_EventScript_Aide':['aide','大木博士的助手',50,'学习装置','EXP_SHARE'],
}
FIELDS={'ShowPokemonJumpRecords':['jump_record','跳绳纪录'], 'ShowDodrioBerryPickingRecords':['dodrio_record','嘟嘟利摘树果纪录'], 'Memorial':['memorial','纪念柱'],'VendingMachine':['vending','自动售货机'],'MagikarpRecordSign':['record','鲤鱼王钓鱼记录']}
def generate(source):
    sources={compact(p.parent.name):p for p in (source/'data/maps').glob('*/map.json')}
    species={s['key']:s['id'] for s in read(ROOT/'content/species.json')}
    moves={m['key']:m['id'] for m in read(ROOT/'content/moves.json')}
    for k,v in re.findall(r'^#define MOVE_(\w+)\s+(\d+)\b',(source/'include/constants/moves.h').read_text(),re.M):moves.setdefault(k,int(v))
    tutors=blocks((source/'data/scripts/move_tutors.inc').read_text())
    roster={}; fields={}; allow={};code=(source/'src/data/trainer_parties.h').read_text()
    learn=(source/'src/data/pokemon/tutor_learnsets.h').read_text()
    for sid,opts in re.findall(r'\[SPECIES_(\w+)\]\s*=\s*((?:TUTOR\(MOVE_\w+\)[\s|]*)+)',learn):
        for opt in re.findall(r'TUTOR\(MOVE_(\w+)\)',opts):
            if sid in species: allow.setdefault(moves[opt],[]).append(species[sid])
    def trade_table(version):
        code=(source/'src/data/ingame_trades.h').read_text()
        code=re.sub(r'#if defined\(FIRERED\)\n(.*?)#elif defined\(LEAFGREEN\)(.*?)#endif',lambda m:m[version],code,flags=re.S)
        trades={}
        for key,body in re.findall(r'\[(INGAME_TRADE_\w+)\]\s*=\s*\{(.*?)\n    \}',code,re.S):
            def val(name):return re.search(r'\.'+name+r'\s*=\s*(\w+)',body)[1]
            def label(name):return re.search(r'\.'+name+r'\s*=\s*_\("(.+?)"\)',body)[1]
            trades[key]=[species[val('requestedSpecies')[8:]],species[val('species')[8:]],label('nickname'),label('otName'),val('heldItem')[5:]]
        return trades
    trades=trade_table(1)
    leaf=trade_table(2)
    def select(m,o,script,body):
        short=script.split('EventScript_')[-1]
        if m=='SaffronCity_PokemonTrainerFanClub':
            member=re.search(r'setvar VAR_0x8004, FANCLUB_MEMBER([1-8])',body)
            if member:return ['fan','训练家爱好者',int(member[1]),o.get('flag')!='0']
        if m=='FourIsland_LoreleisHouse' and short=='Doll':
            mon=o['graphics_id'].removeprefix('OBJ_EVENT_GFX_').removesuffix('_DOLL')
            unlock={'MEOWTH':25,'CHANSEY':50,'NIDORAN_F':75,'JIGGLYPUFF':100,'NIDORAN_M':125,'FEAROW':150,'PIDGEOT':175,'LAPRAS':200}
            return ['doll','科拿的玩偶',species[mon],unlock.get(mon,0),o['graphics_id'].removeprefix('OBJ_EVENT_GFX_').lower()]
        if m=='TrainerTower_Lobby'  and short=='Receptionist':return ['tower_desk','训练家之塔接待员']
        if m=='TrainerTower_Roof' and short=='Owner':return ['tower_owner','塔主']
        if m=='CeladonCity_DepartmentStore_4F' and 'Clerk' in short:return ['doll_clerk','百货店员']
        if m=='SaffronCity_Dojo' and 'trainerbattle_single ' in body:
            member=short.removeprefix('Master')
            sub=re.search(r'sParty_BlackBelt'+member+r'\[\] = \{(.*?)\n\};',code,re.S)[1]
            team=[{'species':species[k],'level':int(lvl)} for lvl,k in re.findall(r'\.lvl = (\d+),\s*\.species = SPECIES_(\w+)',sub)]
            return ['dojo','空手道师父' if short.startswith('Master') else '空手道弟子',team]
        t=re.search(r'setvar VAR_0x8008, (INGAME_TRADE_\w+)',body)
        if t:
            pair=trades[t[1]]
            return ['trade','交换宝可梦的训练家',*pair]+([leaf[t[1]]] if pair!=leaf[t[1]] else [])
        if m=='CeladonCity_Condominiums_3F' and short=='Designer':return ['diploma','游戏设计师']
        if m=='CeladonCity_Condominiums_3F' and short=='Programmer':return ['comparison','程序员']
        tm=re.search(r'MOVETUTOR_(\w+)',tutors.get(script,body))
        if not tm:
            tm=re.search(r'MOVETUTOR_(\w+)',tutors.get('EventScript_'+short,''))
        if tm and short!='StarterTutor' and short!='Copycat':return ['tutor','招式导师',moves[tm[1]]]
        if m=='FiveIsland_WaterLabyrinth' and 'GetLeadMonFriendship' in body:return ACTORS[m]
        if m=='SixIsland_WaterPath_House1' and short=='Beauty':return ACTORS[m]
        if m=='Route12_NorthEntrance_2F' and short=='Lass':return ACTORS[m]
        if m=='CeladonCity_Condominiums_RoofRoom' and 'Eevee' in script:return ACTORS['EeveeBall']
        if m=='NavelRock_Summit' and o.get('graphics_id')=='OBJ_EVENT_GFX_HO_OH':return ACTORS['HoOh']
        if m=='PalletTown_RivalsHouse' and 'Daisy' in script:return ACTORS['PalletTown_RivalsHouse_EventScript_Daisy']
        if m=='Route12_FishingHouse' and short=='FishingGuruBrother':return ['size_contest','钓鱼兄弟',129,'捕网球']
        if short=='HoOh' or (m=='PalletTown_RivalsHouse' and short=='TownMap'):return None
        return ACTORS.get(script, ACTORS.get(short))
    for region in ('kanto','sevii'):
        for p in sorted((ROOT/'content/regions'/region/'maps').glob('*.json')):
            m=read(p);native=ROOT/'content/emerald_maps'/(m.get('emerald','')+'.json')
            components=(read(native).get('member_maps',{}) if native.exists() else {}) or {m.get('emerald',p.stem):[0,0]}
            key=f'{region}/{p.stem}'
            for name,(x,y) in components.items():
                path=sources.get(compact(name)) or sources.get(compact(p.stem))
                if not path:continue
                orig=read(path); text=blocks(path.with_name('scripts.inc').read_text()) if path.with_name('scripts.inc').exists() else {}
                for o in (orig.get('object_events') or []):
                    script=o.get('script',''); action=select(orig['name'],o,script,text.get(script,''))
                    if action:
                        at=f"{x+o['x']},{y+o['y']}";roster.setdefault(key,{})[at]={'at':[x+o['x'],y+o['y']],'side':action,'flag':'frs_'+script,'source':script}
                for o in orig.get('bg_events') or []:
                    script=o.get('script','');short=script.split('EventScript_')[-1]
                    a=FIELDS.get(short)
                    if short.startswith('SlotMachine'):a=['slots','游戏机']
                    if a:fields.setdefault(key,{})[f"{x+o['x']},{y+o['y']}"]=a
    info=(source/'src/data/pokemon/species_info.h').read_text()
    safari={species[c]:int(rate) for c,rate in re.findall(r'\[SPECIES_(\w+)\]\s*=\s*\{[^}]*?\.safariZoneFleeRate = (\d+)',info,re.S) if c in species}
    safari={}
    for chunk in re.split(r'(?=\[SPECIES_\w+\]\s*=)',info):
        sid=re.match(r'\[SPECIES_(\w+)\]',chunk)
        rate=re.search(r'\.safariZoneFleeRate = (\d+)',chunk)
        if sid and sid[1] in species and rate and int(rate[1]):safari[species[sid[1]]]=int(rate[1])
    roam_source=(source/'src/roamer.c').read_text().split('sRoamerLocations',1)[1].split('#undef ___',1)[0]
    paths={}
    for line in roam_source.splitlines():
        neighbors=[int(n) for n in re.findall(r'MAP_NUM\(MAP_ROUTE(\d+)(?:_NORTH)?\)',line)]
        if neighbors:paths[neighbors[0]]=neighbors[1:]
    # Put the original overworld art on stationary encounter actors.
    gfx={144:'articuno',145:'zapdos',146:'moltres',249:'lugia',250:'ho_oh'}
    for rows in roster.values():
        for row in rows.values():
            act=row['side']
            if act[0]=='wild' and act[2] in gfx: row['gfx']='fr_side_'+gfx[act[2]]
            elif act[0] in ('gift_mon','dojo_gift') or (act[0]=='wild' and act[2]==101):row['gfx']='fr_side_ball'
            elif act[0]=='triangle':row['gfx']='fr_side_triangle'
            elif act[0]=='doll':row['gfx']='fr_side_doll_'+act[4]
    folder=source/'graphics/object_events/pics'
    for name in [*gfx.values(),'ball','triangle']:
        path=(folder/'pokemon'/(name+'.png') if name not in ('ball','triangle') else next(folder.rglob('item_ball.png' if name=='ball' else 'birth_island_stone.png'),None))
        if path and path.exists():
            im=Image.open(path);im.info['transparency']=0
            im=im.convert('RGBA')
            n=16 if name=='ball' else 32
            im=im.crop((0,0,n,n))
            im.save(ROOT/'assets/npc'/('fr_side_'+name+'.png'))
    infos=(source/'src/data/object_events/object_event_graphics_info.h').read_text()
    for actors in roster.values():
        for row in actors.values():
            if row['side'][0]!='doll':continue
            kind=row['side'][4]
            img=folder/('misc' if kind=='lapras_doll' else 'pokemon')/(kind+'.png')
            entry=next((b for k,b in re.findall(r'gObjectEventGraphicsInfo_(\w+) = \{(.*?)\};',infos,re.S) if compact(k)==compact(kind)), '')
            w=int(re.search(r'\.width = (\d+)',entry)[1])
            h=int(re.search(r'\.height = (\d+)',entry)[1])
            im=Image.open(img);im.info['transparency']=0
            im.convert('RGBA').crop((0,0,w,h)).save(ROOT/'assets/npc'/(row['gfx']+'.png'))
    slot_code=(source/'src/slot_machine.c').read_text()
    strip=slot_code.split('sReelIconAnimByReelAndPos[NUM_REELS][REEL_LENGTH] = {',1)[1].split('};',1)[0]
    icons=['7','ROCKET','PIKACHU','PSYDUCK','CHERRIES','MAGNEMITE','SHELLDER']
    reels=[[icons.index(icon) for icon in re.findall(r'ICON_(\w+)',body)] for body in re.findall(r'\{([^}]+)\}',strip)]
    original=Image.open(source/'graphics/slot_machine/firered/reel_icons.png')
    rgba=original.convert('RGBA')
    rgba.putalpha(original.point(lambda idx: 255 if idx%16 else 0).convert('L') if original.mode=='L' else Image.frombytes('L',original.size,bytes(255 if i%16 else 0 for i in original.getdata())))
    rgba.save(ROOT/'assets/emerald/fr_reel_icons.png')
    tower=compile_tower(source,species,moves)
    for kind in {a[1] for course in tower.values() for floor_data in course for a in floor_data['actors']}:
        img=folder/'people'/(kind+'.png')
        if not img.exists():
            raise FileNotFoundError(img)
        im=Image.open(img);im.info['transparency']=0
        entry=next((b for k,b in re.findall(r'gObjectEventGraphicsInfo_(\w+) = \{(.*?)\};',infos,re.S) if compact(k)==compact(kind)),'')
        if not entry:raise ValueError(kind)
        w=int(re.search(r'\.width = (\d+)',entry)[1]);h=int(re.search(r'\.height = (\d+)',entry)[1])
        assert im.width>=3*w,(kind,im.size,w)
        im.convert('RGBA').crop((0,0,3*w,h)).save(ROOT/'assets/npc'/('fr_tower_'+kind+'.png'))
    demo_code=(source/'src/battle_controller_pokedude.c').read_text()
    lessons=[]
    for title in ['Battle','Status','Matchups','Catching']:
        party=re.search(r'sParties_'+title+r'\[\] =\s*\{(.*?)\n\};',demo_code,re.S)[1]
        cast=[]
        for side,lvl,mon,move_list in re.findall(r'\.side = B_SIDE_(\w+),\s*\.level = (\d+),\s*\.species = SPECIES_(\w+),\s*\.moves = \{(.*?)\}',party):
            cast.append([side,int(lvl),species[mon],[moves[k] for k in re.findall(r'MOVE_(\w+)',move_list)]])
        def inputs(name):
            section=re.search(r'sInputScripts_'+name+'_'+title+r'\[\] =\s*\{(.*?)\n\};',demo_code,re.S)[1]
            return [[int(a),int(b)] for a,b in re.findall(r'\.cursorPos = \{\s*(\d+),\s*(\d+)',section) if int(a) not in (255,4)]
        assert len(cast)>=2
        lessons.append({'party':cast,'actions':inputs('ChooseAction'),'moves':inputs('ChooseMove')})
    import struct
    diploma=source/'graphics/diploma'
    pic=Image.open(diploma/'diploma.png').convert('RGB')
    tilemap=[w[0] for w in struct.iter_unpack('<H',(diploma/'diploma.bin').read_bytes())]
    for sheet,name in enumerate(['kanto','national']):
        out=Image.new('RGB',(240,160))
        for y in range(20):
            for x in range(30):
                cell=tilemap[sheet*1024+y*32+x];tile=cell&1023
                sx=tile%(pic.width//8)*8;sy=tile//(pic.width//8)*8
                chip=pic.crop((sx,sy,sx+8,sy+8))
                if cell&1024:chip=chip.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                if cell&2048:chip=chip.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                out.paste(chip,(x*8,y*8))
        out.save(ROOT/'assets/emerald'/('fr_diploma_'+name+'.png'))
    jump=(source/'src/pokemon_jump.c').read_text().split('sPokeJumpMons[] =',1)[1].split('};',1)[0]
    jumpers={species[k]:speed for k,speed in re.findall(r'\.species = SPECIES_(\w+),\s*\.jumpType = JUMP_TYPE_(\w+)',jump) if k in species}
    (ROOT/'content/frlg_sidequests.json').write_text(json.dumps({'actors':roster,'field':fields,'tutor_compatibility':allow,'tower':tower,'safari':safari,'roam_paths':paths,'jumpers':jumpers,'fame':extract_fame(source,ROOT,read,compact,blocks),'reels':reels,'tv':lessons},ensure_ascii=False,separators=(',',':'))+'\n')
    print(sum(map(len,roster.values())),'actors;',sum(map(len,fields.values())),'field triggers')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);generate(p.parse_args().source)
