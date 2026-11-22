"""Bind Black/Black 2 optional story events to the original zone and actor position."""
import argparse
import json
import re
import struct
import subprocess
from pathlib import Path

from import_unova_side import ROOT, constants, load, narc, write
from unova_source import UnovaSource
from unova_locations import assign


def build(bw,b2):
    dex={r['id']:r['name'] for r in load(ROOT/'content/species.json')}
    entries=[]
    def add(era,key,zone,kind,who,req='',anchor='side1',**kw):
        row=dict(era=era,id=era+'_'+key,zone=zone,type=kind,name=who,requires=req.split(),anchor=anchor,**kw)
        if kind=='encounter':row.setdefault('until',['us_'+row['id']])
        entries.append(row)
        return row

    def actor(era,key,zone,kind,who,req='',anchor='side1',script=None,**kw):
        r=add(era,key,zone,kind,who,req,anchor,**kw)
        if era=='b2' and script is not None:
            obj=load(b2/'res/field/events'/(zone+'.json'))
            rows=[n for n in obj['npcs'] if n['script']==script and 'grid' in n]
            if rows:r['pos']=[rows[0]['grid'][v] for v in ['x','z']]
        return r

    for era,begin in [('bw','u1_badge_1'),('b2','u2_badge_1')]:
        pre='u1_' if era=='bw' else 'u2_'
        ending='u1_ghetsis' if era=='bw' else 'u2_champion'
        actor(era,'daycare','route_3_2','daycare','培育屋婆婆',begin if era=='bw' else ending)
        actor(era,'subway','gear_station','facility','对战地铁站务员',pre+'badge_3',facility='subway')
        actor(era,'fossil','nacrene_city_2','fossil','化石研究员',begin,script=2)
        actor(era,'museum_fossil','relic_castle' if era=='bw' else 'nacrene_city_2','choice_gift','背包客' if era=='bw' else '芦荟',pre+'badge_3' if era=='bw' else ending,'side2',script=3,options=['COVER_FOSSIL','PLUME_FOSSIL'],line='这是两块古代宝可梦的化石，你愿意研究哪一块？',after='把化石带到七宝博物馆的柜台，就能见到当年的宝可梦。')
        if era=='b2':actor(era,'rod','nuvema_town_lab','rod','帅哥' if era=='bw' else '红豆杉博士的爸爸',ending)
        actor(era,'musical','musical_theater','musical','音乐剧团长',pre+'badge_3')
        actor(era,'drive','p2_laboratory_2','drive','研究员',ending)
        actor(era,'meloetta','castelia_city_18','song','吉他手',begin)
        actor(era,'appraise','undella_town_2','appraise','古董收藏家',ending)
        actor(era,'magikarp','marvelous_bridge','fish','卖鲤鱼王的男人',ending)
        actor(era,'cynthia','undella_town_3','duel','竹兰',ending,trainer='cynthia')
        actor(era,'lostlorn','lostlorn_forest','zoroark','背包客',pre+'badge_3',line='树影里传来一声低鸣。')
        actor(era,'old_fossils','twist_mountain','daily_fossil','工人',ending)
        actor(era,'keldeo','moor_of_icirrus' if era=='bw' else 'pledge_grove','sword','刻痕岩壁',pre+'badge_3')
    actor('bw','magmaegg','route_18_2','egg','宝可梦巡护员','u1_badge_6')
    # The original distribution is offline; its ticket still opens the actual island encounter.
    add('bw','liberty_pass','castelia_city_14','gift','神秘礼物配送员','u1_badge_2',line='这张自由船票可以搭上飞云港开往自由庭园岛的船。')['key']='LIBERTY_PASS'
    actor('bw','liberty_boat','castelia_city','boat','自由庭园号水手','u1_badge_2','side2')
    actor('bw','liberty_return','liberty_garden','boat','自由庭园号水手','u1_badge_2')
    actor('bw','victini','liberty_garden_3','encounter','比克提尼','u1_badge_2',species=494,level=15,item='LIBERTY_PASS',line='灯塔地下室里，小小的宝可梦抬起耳朵看向你。')
    actor('bw','tornadus','route_7','storm','老婆婆','u1_badge_8')
    actor('bw','look','nuvema_town_2','look','帅哥','u1_ghetsis','side2')
    for name,zh,zone,tm in [('gorm','斯姆拉','dreamyard_2',75),('rood','罗德','route_18',32),('zinzolin','维奥','pwt_3',1),('giallo','约格斯','route_14',8),('ryoku','龙穆','relic_castle_24',4),('bronius','阿苏拉','chargestone_cave_3',69)]:
        actor('bw','sage_'+name,zone,'sage',zh,'us_bw_look',tm=tm,until=['us_bw_sage_'+name])
    actor('bw','musharna','dreamyard_2','weekday','梦梦蚀','u1_ghetsis','side2',species=518,level=50,weekday=5)
    actor('bw','ragebar','desert_resort','gift','红豆杉博士','u1_ghetsis',line='这些达摩狒狒靠冥想保存力量。给它们尝一口愤怒馒头试试。')['key']='RAGE_CANDY_BAR'
    actor('bw','statue','desert_resort','statues','达摩狒狒石像','u1_ghetsis','side2')
    # Black's field archive identifies these actors by the start-static-battle command (0x178).
    sources=UnovaSource(bw,b2,'bw')
    # Route 13 scripts 5–9 in Black's local script bank 740 control the three lost Grams.
    route13=next(z for z in sources.zones if z['key']=='route_13')
    for script,key,kind,who in [(5,'wingull_handler','grams','送信少女'),(6,'wingull','wingull','长翅鸥'),(7,'gram3','gram','阳伞姐姐'),(8,'gram1','gram','海边的老人'),(9,'gram2','gram','掉落的信件')]:
        obj=next(n for n in route13['npcs'] if n['script']==script)
        row=add('bw',key,'route_13',kind,who,'u1_ghetsis' if script in (5,6) else 'us_bw_gram_search',pos=[obj['grid']['x'],obj['grid']['z']])
        if kind=='gram':row['key']='GRAM_'+key[-1]
        if script==9:row.update(field_art='unova_item_ball',until=['us_bw_gram2'])
        if script==6:row.update(field_art='unova_pokemon_278',until=['us_bw_grams_sent'])

    banks=narc(bw/'files/a/0/5/7');headers=narc(bw/'files/a/0/1/2')[0]
    for z,h in zip(sources.zones,struct.iter_unpack('<BBHHHHH4HHHHHHHHHiii',headers)):
        binary=banks[h[4]]
        ptrs=[]
        for offset in range(0,len(binary)-3,4):
            if struct.unpack_from('<H',binary,offset)[0]==0xfd13:break
            start=offset+4+struct.unpack_from('<i',binary,offset)[0]
            if not 0<=start<len(binary):break
            ptrs.append(start)
        for m in re.finditer(b'\x78\x01(..)(..)\x01\x00',binary,re.S):
            species=struct.unpack('<H',m[1])[0];level=struct.unpack('<H',m[2])[0]
            prereq={637:'u1_ghetsis',638:'u1_badge_6',639:'us_bw_swords',640:'us_bw_swords',645:'u1_ghetsis',646:'u1_ghetsis'}
            if species not in prereq or not 1<=level<=100:continue
            start=max((a for a in ptrs if a<=m.start()),default=-1)
            if start<0:continue
            obj=next((n for n in z['npcs'] if n['script']==ptrs.index(start)+1),None)
            if not obj:continue
            add('bw','enc_'+str(species),z['key'],'encounter',dex[species],prereq[species],species=species,level=level,pos=[obj['grid'][a] for a in ('x','z')],line=dex[species]+'就站在你的面前。')
    # Original room scripts bind each sequel encounter to its object, trigger or background tile.
    gates={638:'u2_badge_6',639:'u2_badge_8',640:'u2_badge_6',637:'u2_badge_5',381:'u2_champion',488:'us_b2_lunar',646:'us_b2_enc_644',485:'us_b2_magma',644:'us_b2_dragonstone',377:'us_b2_ruin_switch',379:'us_b2_enc_377',486:'u2_champion',480:'us_b2_lakes',481:'us_b2_lakes',482:'us_b2_lakes'}
    for zone in ['celestial_tower','dragonspiral_tower_9','dreamyard','giant_chasm_6','iron_chamber','marvelous_bridge','nacrene_city','relic_castle_23','reversal_mountain_5','rock_peak_chamber','route_11','route_13','route_22','route_23','twist_mountain_8']:
        text=(b2/f'res/field/scripts/{zone}.s').read_text()
        obj=load(b2/f'res/field/events/{zone}.json')
        found=set()
        for block in re.finditer(r'^Script_(\d+):\n([\s\S]*?)(?=^Script_\d+:|\Z)',text,re.M):
            for sid,lv in re.findall(r'CallWildBattle (\d+), (\d+)',block[2]):
                species=int(sid)
                if species not in gates or species in found:continue
                found.add(species)
                row=actor('b2','enc_'+sid,zone,'encounter',dex[species],gates[species],script=int(block[1]),species=species,level=int(lv),line=dex[species]+'正注视着你。')
                if 'pos' not in row:
                    raw=next((x for x in obj['bg_events']+obj['triggers'] if x['script']==int(block[1]) and 'grid' in x),None)
                    if raw: row['pos']=[raw['grid']['x'],raw['grid'].get('z',raw['grid'].get('y',0)) if raw in obj['triggers'] else raw['grid']['y']]
    add('b2','lunar','strange_house_5','gift','透明的女孩','u2_badge_6',line='地上的羽毛泛着月光。请替我把它带到陌生人之桥。')['key']='LUNAR_WING'
    add('b2','magma','route_18','gift','火山镇石','u2_champion',line='深红的石头里凝着火山的热气。')['key']='MAGMA_STONE'
    add('b2','dragonstone','ns_castle_5','dragonstone','N','u2_champion')
    add('b2','splicers','giant_chasm_6','gift','基因之楔','us_b2_enc_646','side2',line='酋雷姆脚下留下了两半相扣的器具。')['key']='DNA_SPLICERS_FUSE'
    add('b2','lakes','cave_of_being','lakes','红豆杉博士的爸爸','u2_champion')
    add('b2','haxorus','nature_preserve','encounter','双斧战龙','us_b2_permit',species=612,level=60,shiny='star',line='湿地中央站着一只漆黑的双斧战龙。')
    add('b2','permit','nuvema_town_lab','permit','红豆杉博士','u2_champion','side2')
    add('b2','flight','mistralton_city','nature_flight','风露','us_b2_permit','side3')
    add('b2','return_flight','nature_preserve','nature_flight','风露','us_b2_permit','side2')
    add('b2','mirror','abundant_shrine','mirror','老人','u2_champion')
    add('b2','rood','driftveil_city_6','zoruagift','罗德','u2_rood')
    add('b2','tower','black_tower','facility','黑色摩天楼管理员','us_b2_alder',facility='tower')
    add('b2','pwt','pwt_2','facility','世界锦标赛接待员','u2_pwt',facility='pwt')
    add('b2','studios','pokestar_studios_2','cinema','制片人','u2_studio')
    add('b2','avenue','join_avenue','avenue','大道经理','u2_badge_3')
    add('b2','dropphone','nimbasa_city','phone','遗忘物','u2_badge_3','side2')
    add('b2','meet_yancy','nimbasa_city','yancy','琉璃','us_b2_has_number','side3')
    add('b2','medals','aspertia_city_pokemon_center','medals','奖章大叔','u2_badge_1')
    for zone,i,gate in [('route_4_5',24,'u2_badge_3'),('route_7_2',26,'u2_badge_5'),('humilau_city_3',27,'u2_badge_7'),('route_15_2',28,'u2_champion'),('accumula_town_2',29,'u2_champion'),('accumula_town_2',30,'us_b2_trade_29')]:
        s=(b2/f'res/field/scripts/{zone}.s').read_text()
        at=s.index('FieldTradeStart '+str(i)+',')
        script=int(re.findall(r'^Script_(\d+):',s[:at],re.M)[-1])
        actor('b2','trade_'+str(i),zone,'trade','交换训练家',gate,script=script,trade=i)
    for key,zone,req,want,offer,level in [('petilil','nacrene_city_5','u1_badge_1',546,548,15),('basculin','driftveil_city_3','u1_badge_4',572,550,25),('emolga','route_7_2','u1_badge_5',525,587,30),('rotom','route_15_2','u1_ghetsis',132,479,60),('munchlax','undella_town_2','u1_ghetsis',573,446,60)]:
        actor('bw','trade_'+key,zone,'trade','交换训练家',req,trade={'petilil':0,'basculin':3,'emolga':4,'munchlax':5,'rotom':6}[key])
    actor('b2','hanky','nacrene_city_10','hanky','咖啡馆店员','u2_champion',script=3)
    add('b2','hanky_guest','nacrene_city_10','hanky_guest','带着探探鼠的客人','us_b2_hanky','side2',until=['us_b2_hanky_guest'])
    actor('b2','gracidea','striaton_city_pokemon_center','gracidea','卖花的女士','u2_champion',script=5)
    actor('b2','charms','nuvema_town_lab','charms','红豆杉博士','u2_champion','side3')
    # All four shard counters use the native tutor script and the species tutor bits.
    for zone,code,color,gate in [('driftveil_city_2',2283,'RED','u2_badge_4'),('lentimas_town_2',2284,'BLUE','u2_badge_6'),('humilau_city_2',2285,'YELLOW','u2_badge_7'),('nacrene_city_8',2286,'GREEN','u2_champion')]:
        actor('b2','tutor_'+color.lower(),zone,'tutor','招式教学者',gate,script=code,shard=color+'_SHARD')
    actor('b2','red_shards','nimbasa_city_pokemon_center','gift','绅士','u2_badge_3',line='这些红色碎片送给你。在帆巴市，有人用它们教宝可梦招式。',count=10)['key']='RED_SHARD'
    add('bw','thunder_link','route_7_2','weather_link','白森林的旅行者','us_bw_roamer_caught',line='我旅行时遇上了雷电云。想让你见见它，和它约定一次对战。')
    actor('b2','ironkey','underground_ruins','keys','遗迹的石门','u2_champion')
    actor('b2','enc_378','iceberg_chamber','encounter','雷吉艾斯','us_b2_icekey',script=6,species=378,level=65,line='冰山神殿里的冰柱开始移动。')
    actor('b2','link_key','black_city','key_share','钥匙共享研究员','us_b2_enc_379','side2')
    add('b2','alder','floccesy_town_2','alder','阿戴克','u2_champion',trainer='alder')
    add('b2','tower_gift','floccesy_town_2','tower_gift','蕃石郎','us_tower_complete','side2')
    for chamber in ['rock_peak_chamber','iron_chamber','iceberg_chamber']:
        add('b2','leave_'+chamber,chamber,'ruin_exit','通往地下遗迹的门','u2_champion','side2')
    for era,source in [('bw',sources),('b2',UnovaSource(bw,b2,'b2'))]:
        assign(source)
        ids={z['key']:z['mid'] for z in source.zones}
        for row in [r for r in entries if r['era']==era]:
            if row['type']=='trade':row['until']=['us_'+row['id']]
            dest={'bw_liberty_boat':'liberty_garden','bw_liberty_return':'castelia_city','b2_flight':'nature_preserve','b2_return_flight':'mistralton_city'}.get(row['id'])
            if dest:row['destination']=ids[dest]
            if row['zone'] not in ids:raise ValueError(row)
            row['map']=ids[row['zone']]
    keys=constants(b2/'generated/species.txt','SPECIES_')
    moves=constants(b2/'generated/moves.txt','MOVE_')
    regional=[i for i,k in enumerate(keys[:650]) if (b2/f'res/pokemon/{k.lower()}/data.json').exists() and (load(b2/f'res/pokemon/{k.lower()}/data.json').get('regional_dex_number') or 0) in range(1,298)]
    source_teams={}
    for key in ['cynthia','n','alder','boss_trainer_benga_2','scientist_dudley','n_3','n_4','n_5','n_6']:
        raw=load(b2/f'res/trainers/data/{key}.json')['party']
        source_teams[key]=[{'species':keys.index(m['species'][8:]),'level':m['level'],'moves':[moves.index(v[5:]) for v in m.get('moves',[]) if v!='MOVE_NONE'],'held':m.get('held_item','ITEM_NONE')[5:]} for m in raw]
    catalogs={
        'RED_SHARD':{2:'COVET BUG_BITE',4:'DRILL_RUN BOUNCE SIGNAL_BEAM IRON_HEAD',6:'SUPER_FANG UPROAR SEED_BOMB DUAL_CHOP',8:'LOW_KICK GUNK_SHOT',10:'FIRE_PUNCH THUNDER_PUNCH ICE_PUNCH'},
        'BLUE_SHARD':{2:'LAST_RESORT IRON_DEFENSE',4:'MAGNET_RISE MAGIC_COAT',6:'BLOCK HYPER_VOICE ELECTROWEB ICY_WIND IRON_TAIL',8:'AQUA_TAIL EARTH_POWER ZEN_HEADBUTT FOUL_PLAY',10:'SUPERPOWER GRAVITY DRAGON_PULSE DARK_PULSE'},
        'YELLOW_SHARD':{2:'BIND SNORE',4:'HEAL_BELL KNOCK_OFF',6:'SYNTHESIS ROOST',8:'SKY_ATTACK ROLE_PLAY',10:'HEAT_WAVE GIGA_DRAIN DRAIN_PUNCH PAIN_SPLIT TAILWIND'},
        'GREEN_SHARD':{6:'WORRY_SEED GASTRO_ACID',8:'HELPING_HAND AFTER_YOU MAGIC_ROOM WONDER_ROOM SPITE',10:'RECYCLE TRICK STEALTH_ROCK OUTRAGE',12:'ENDEAVOR SLEEP_TALK SKILL_SWAP SNATCH'}}
    rates={shard:[[moves.index(move),cost] for cost,group in stock.items() for move in group.split()] for shard,stock in catalogs.items()}
    tutor={}
    breeding={}
    for i,key in enumerate(keys[:650]):
        file=b2/f'res/pokemon/{key.lower()}/data.json'
        if not file.exists():continue
        source=load(file)
        tutor[str(i)]=[moves.index(x[5:]) for x in source.get('learnset',{}).get('by_tutor',[])]
        if i and source.get('baby_species'):
            breeding[str(i)]={'baby':keys.index(source['baby_species'][8:]),'groups':list(dict.fromkeys(s[10:] for s in source['egg_groups'])),'cycles':source['hatch_cycles'],
                'moves':[moves.index(k[5:]) for k in source.get('learnset',{}).get('egg_moves',[])]}
    write(ROOT/'content/unova_side_special.json',{'regional':regional,'teams':source_teams,'shards':rates,'tutor':tutor,'breeding':breeding})
    write(ROOT/'content/unova_side_events.json',entries)
    print(len(entries),'optional event actors')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('black',type=Path);p.add_argument('black2',type=Path)
    a=p.parse_args();build(a.black,a.black2)
