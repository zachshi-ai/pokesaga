"""Compile Sinnoh events from a pret/pokeplatinum checkout. Run with its path as argv[1]."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[1])
MAPS = SRC / "res/field/maps"
TRAINERS = SRC / "res/trainers/data"
OUT = ROOT / "content/sinnoh_campaign.json"


def read(p):
    return json.loads(p.read_text())


species = {x['key']: x['id'] for x in read(ROOT / 'content/species.json')}
moves = {x['key']: x['id'] for x in read(ROOT / 'content/moves.json')}
species.update({key.removeprefix('SPECIES_'): i for i, key in enumerate((SRC / 'generated/species.txt').read_text().splitlines()) if key.startswith('SPECIES_')})
moves.update(SOFTBOILED=135, SMOKE_SCREEN=108, HI_JUMP_KICK=136, FAINT_ATTACK=185)
events, actors, trainers, gates = [], {}, {}, {}
previous = 's_started'


def flag(k):
    return 's_' + k


def load_events(m):
    path = MAPS / m / 'events.json'
    return read(path) if path.exists() else {}


def trainer(key):
    if key not in trainers:
        party = []
        for mon in read(TRAINERS / (key + '.json'))['party']:
            row = {'species': species[mon['species'][8:]], 'level': mon['level']}
            if mon.get('moves'):
                row['moves'] = [moves[move[5:]] for move in mon['moves'] if move != 'MOVE_NONE']
            held = (mon.get('item') or 'ITEM_NONE')[5:].lower()
            if held.endswith('_berry'):
                row['berry'] = held[:-6]
            elif held != 'none':
                row['held'] = held.upper()
            party.append(row)
        trainers[key] = party
    return key


def branches(base):
    return [trainer(base + '_' + x) for x in ('turtwig', 'chimchar', 'piplup')]


def fight(name, key, ally='', **extra):
    cfg = {'name':name, **extra}
    if key.endswith('*'):
        cfg['s_starter_teams'] = branches(key[:-1])
    else:
        cfg['s_teams'] = [trainer(x) for x in key.split('+')]
        if len(cfg['s_teams']) > 1:
            cfg['double'] = True
    if ally:
        cfg['ally'] = 'sinnoh'
        cfg['s_ally'] = branches(ally)
        cfg['ally_name'] = '阿驯' if ally.startswith('rival') else '小光'
    return {'battle':cfg}


def say(who, *lines):
    return {'who':who, 'say':list(lines)}


def item(name, category='key', count=1):
    return {'give_item':{'name':name, 'category':category, 'count':count}}


def hm(n):
    return {'sinnoh_hm':n}


def warp(m, x, z):
    return {'sinnoh_warp':{'header':m, 'at':[x,z]}}


def e(k, m, anchor, speaker, line, *actions, require=None, following=True, at=None):
    """@object, #coord script suffix, &background script, !map script, or custom overlay anchor."""
    global previous
    script = (MAPS / m / 'scripts.s').read_text()
    data = load_events(m)
    req = [previous] if require is None else [flag(x) for x in require.split()]
    id_ = flag(k)
    trigger = {}
    if anchor.startswith('@'):
        local = 'LOCALID_' + anchor[1:]
        row = next(x for x in data['object_events'] if x.get('id') == local)
        trigger = {'kind':'talk', 'actor':local, 'at':at or [row['x'],row['z']], 'source_script':row.get('script','')}
    elif anchor[0] in '#&':
        group = 'coord_events' if anchor[0]=='#' else 'bg_events'
        rows = [x for x in data.get(group,[]) if str(x.get('script','')).endswith('_'+anchor[1:])]
        assert rows, (m,anchor)
        trigger = {'kind':'step' if anchor[0]=='#' else 'field','areas':[[x['x'], x['z'], x.get('width',1),x.get('length',1)] for x in rows], 'source_script':rows[0]['script']}
    elif anchor.startswith('!'):
        entry = next((x for x in re.findall(r'\bScriptEntry (\w+)',script) if x.endswith('_'+anchor[1:])),None)
        assert entry, (m,anchor)
        trigger = {'kind':'enter','source_script':entry}
    elif anchor.startswith('~'):
        assert at
        trigger = {'kind':'talk','actor':anchor[1:],'at':at}
    else:
        raise ValueError(anchor)
    steps = ([say(speaker,line)] if line else []) + list(actions) + [{'flag':id_}]
    # Save the completed step before loading the destination map.
    if len(steps)>1 and 'sinnoh_warp' in steps[-2]:
        steps[-2:] = [steps[-1],steps[-2]]
    event = {'id':id_, 'map':'MAP_HEADER_'+m.upper(), 'require':req, 'trigger':trigger, 'steps':steps}
    events.append(event)
    if trigger['kind']=='talk':
        show(m, trigger['actor'], req, [id_], speaker, trigger['at'], absolute=True)
    if following:
        previous = id_
    return event


def show(m, local, req, until, name, at=None, absolute=False, sprite=None):
    local = local if absolute else 'LOCALID_'+local
    req = req if absolute else list(map(flag,req.split()))
    until = until if absolute else list(map(flag,until.split()))
    stage = {'require':req, 'until':until, 'name':name}
    if at is not None:
        stage['at'] = at
    if sprite:
        stage['sprite'] = sprite
    actors.setdefault('MAP_HEADER_'+m.upper(),{}).setdefault(local,[]).append(stage)


def badge(n, m, leader, person, name, tm):
    tr = 'leader_'+leader
    if leader=='crasher_wake':
        tr = 'leader_wake'
    e('badge_'+str(n),m,'@'+leader.upper(),person,'准备好了吗？让我看看你和伙伴一起走到这里的本领。',fight(person,tr),
      say(person,'你赢了。收下'+name+'，还有我的招式学习器。'),{'sinnoh_badge':name},{'sinnoh_tm':tm})


e('broadcast','twinleaf_town_player_house_2f','!OnFrame_ConcludeSpecialProgram','电视','祝庆电视台的特别节目《向山梨博士请教！》到此结束。窗外的神奥正等着你去看看。')
e('rival_visit','twinleaf_town_player_house_2f','#CoordEvent_RivalNorth','阿驯','小悠！山梨博士回来了！快到我家会合，一起去找博士吧。')
# The bedroom places four equivalent movement triggers around the TV.
for row in load_events('twinleaf_town_player_house_2f')['coord_events'][1:]:
    events[-1]['trigger']['areas'].append([row['x'],row['z'],1,1])
e('thud','twinleaf_town','#CoordEvent_RivalThud','阿驯','砰！原来是你！我把东西落楼上了，稍等我一下！')
e('invited','twinleaf_town_rival_house_2f','!OnFrame_Rival','阿驯','包拿好了！这回真要出发了，在镇北的２０１号道路见！')
e('rowan','route_201','#CoordEvent_ChooseStarterScene','山梨博士','站住！你们打算没有宝可梦就冲进草丛吗？如果真的愿意照顾宝可梦，就从公文包里选一位伙伴吧。')
e('first_battle','route_201','@BRIEFCASE','山梨博士的公文包','三个精灵球安静地躺在公文包里。',{'sinnoh_starter':True},
  say('阿驯','那我选这只！来吧，我们的第一场宝可梦对战！'),
  fight('阿驯','rival_route_201*',sinnoh_starter_only=True,finish_on_loss=True,lose_say=['好险！下次我们再比。']),{'heal':True},warp('twinleaf_town_player_house_1f',2,6))
e('running','twinleaf_town_player_house_1f','!OnFrame_CutsceneAfterRivalBattle','妈妈','你遇到山梨博士了？换上这双跑步鞋吧。出门去向博士道谢，路上多小心。')
e('lake_trip','route_201','#CoordEvent_RivalStartFollowing','阿驯','先到西边的心齐湖看看吧！也许湖里真的有传说中的宝可梦！')
e('verity_intro','lake_verity_low_water','!OnFrame_Cyrus','赤日','湖中传来一声啼鸣。蓝发男子自称赤日，凝视湖面片刻，独自离开了。')
e('sandgem_escort','sandgem_town','#CoordEvent_CounterpartLeadToLab','小光','博士在研究所等你。我带路！')
e('dex','sandgem_town_pokemon_research_lab','!OnFrame_GetPokedex','山梨博士','把各地相遇的宝可梦记录下来，完成神奥图鉴。小光也会帮你。先回双叶镇和家人道别吧。')
e('parcel','twinleaf_town_player_house_1f','@PLAYER_HOUSE_MOM','妈妈','旅行日记带上。阿驯的妈妈还托你把这个包裹交给他，他大概已经到祝庆市了。',item('冒险笔记'),item('包裹'))
e('tutorial','route_202','#CoordEvent_CatchingTutorial','小光','看好了！先削弱野生宝可梦，再投精灵球。这五个球给你试试。',item('精灵球','ball',5))
e('looker','jubilife_city','#CoordEvent_FirstArrival','帅哥','我在调查可疑的人。请叫我“帅哥”！这个对战记录器送你。训练家学校就在前面。',item('对战记录器'))
e('town_map','trainers_school','@RIVAL','阿驯','是妈妈的包裹？里面有两份城镇地图，给你一份！我先去黑金市挑战道馆了。',{'remove_item':'包裹'},item('城镇地图'))
e('promotion','jubilife_city','#CoordEvent_PoketchCampaign','宝可表公司社长','找到城里的三位小丑，答对他们的问题，再来用三张兑换券领一块宝可表。')
for i,line in enumerate(['宝可梦打倒对手，会得到经验值吗？','和宝可梦一样，招式也有属性吗？','宝可梦能携带道具吗？'],1):
    e('coupon_'+str(i),'jubilife_city','@CLOWN_'+str(i),'促销小丑',line,{'sinnoh_quiz':True},item('兑换券'+str(i)),require='promotion',following=False)
e('poketch','jubilife_city','@POKETCH_CO_PRESIDENT','宝可表公司社长','三张齐了！戴上你的宝可表，旅途愉快。',*[{'remove_item':'兑换券'+str(i)} for i in (1,2,3)],item('宝可表'),require='coupon_1 coupon_2 coupon_3')
e('rival_203','route_203','#CoordEvent_Rival','阿驯','来得正好！看看谁先在神奥迈出了第一步！',fight('阿驯','rival_route_203*'))
e('mine','oreburgh_mine_b2f','@ROARK','瓢太','你看，碎岩就能打通被岩石挡住的路。我的工作结束了，道馆见！')
badge(1,'oreburgh_city_gym','roark','瓢太','石炭徽章',76)
e('jubilife_grunts','jubilife_city','#CoordEvent_TeamGalactic','山梨博士','这些人想夺走我的研究。小悠、小光，拜托你们了！',
  fight('银河队手下','galactic_grunt_jubilife_city_1+galactic_grunt_jubilife_city_2',ally='dawn_jubilife_city'),item('饰品盒'))
e('wind_guard','valley_windworks_outside','@GRUNT_M','银河队手下','这里由银河队接管！就算你赢了，我也会从里面把门锁上！',fight('银河队手下','galactic_grunt_valley_windworks_1'))
e('works_key','floaroma_meadow','#CoordEvent_Grunts','花田主人','他们想抢走我的甜甜蜜！',
  fight('银河队手下','galactic_grunt_floaroma_meadow_1'),fight('银河队手下','galactic_grunt_floaroma_meadow_2'),say('花田主人','他们落下了发电厂钥匙。请去救被困的父亲！'),item('发电厂钥匙'),item('甜甜蜜','other'))
e('mars_wind','valley_windworks_building','#CoordEvent_Mars','伙星','银河队收集的能源可不能让人妨碍。就由干部伙星来陪你过招！',fight('伙星','commander_mars_valley_windworks'),say('小女孩','爸爸！太好了，我们终于能一起回家了。'))
e('cheryl','eterna_forest','#CoordEvent_CherylStartFollowing','芽米','森林里的银河队让我有些不安。能跟你一起穿过森林吗？我会替伙伴恢复体力。',{'heal':True})
e('forest_exit','eterna_forest','#CoordEvent_CherylLeavePlayer','芽米','看见出口了！谢谢你陪我走到这里。收下这颗安抚之铃吧。',item('安抚之铃','held'))
e('statue','eterna_city','#CoordEvent_Rival','阿驯','去看看百代的神像吧！那个蓝发的人也在……他一提到时间和空间，眼神就变了。')
e('cut','eterna_city','#CoordEvent_CynthiaGiveCut','竹兰','你也在收集图鉴？我叫竹兰。这个学习器能斩开细树，得到百代徽章后就可以在野外使用。',hm(1))
e('garden_door','eterna_city','@GARDENIA','菜种','我是菜种！道馆里的花钟会随着挑战者前进而转动。我在最里面等你。')
for key,local,who in [('lass_caroline','LASS_CAROLINE','短裙少女'),('aroma_lady_jenna','AROMA_LADY_JENNA','芳香姐姐'),('aroma_lady_angela','AROMA_LADY_ANGELA','芳香姐姐')]:
    e(key,'eterna_city_gym','@'+local,who,'战胜我，花钟就会把路指向下一位训练家。',fight(who,key))
badge(2,'eterna_city_gym','gardenia','菜种','森林徽章',86)
e('jupiter','team_galactic_eterna_building_4f','@JUPITER','岁星','偷来的宝可梦只是实验材料。你想从岁星手里把它们夺回去？',fight('岁星','commander_jupiter_team_galactic_eterna_building'),say('自行车店老板','皮皮回来了！请到我的店里来一趟。'))
e('togepi','eterna_city','#CoordEvent_CynthiaTryGiveEgg','竹兰','这颗宝可梦的蛋需要信赖的训练家照顾。小悠，你愿意带它踏上旅程吗？',{'sinnoh_egg':175})
e('bike','cycle_shop','@POKEFAN_M','自行车店老板','你救了我的宝可梦！这辆自行车就送给你，骑着它向南旅行吧。',item('自行车'))
e('seeker','route_207','#CoordEvent_Counterpart','小光','这是对战搜寻器，还有宝可表的探宝器应用。有机会再和以前的对手切磋吧！',item('对战搜寻器'),item('探宝器'))
e('coronet_cyrus','mt_coronet_1f_south','#CoordEvent_Cyrus','赤日','天冠山曾见证神奥的诞生。人类的心让世界变得残缺……总有一天，我会改变它。')
e('keira','hearthome_city','#CoordEvent_BunearyAndKeira','美棠','卷卷耳！谢谢你帮我拦住它。有空来华丽大赛会场坐坐吧！')
e('contest','contest_hall_lobby','!OnFrame_FirstEntry','妈妈','美棠邀请我来看比赛。礼服就交给你了。道馆馆主梅丽莎也喜欢华丽大赛。',item('礼服'))
e('fantina_ready','contest_hall_lobby','@FANTINA','梅丽莎','华丽大赛真精彩！想挑战我吗？那就在家缘道馆见！')
badge(3,'hearthome_city_gym_leader_room','fantina','梅丽莎','遗迹徽章',65)
e('rival_209','route_209_gate_to_hearthome_city','#CoordEvent_Rival','阿驯','下一站随意镇！出发前先和我比一次！',fight('阿驯','rival_route_209*'))
e('solaceon','solaceon_town','#CoordEvent_Rival','阿驯','你见过随意遗迹吗？我准备去帷幕市，下一枚徽章归我了！')
e('veil_wake','veilstone_city','#CoordEvent_CrasherWake','小光','刚才从道馆出来的是野原道馆的吉宪。阿李就在里面，挑战加油！')
badge(4,'veilstone_city_gym','maylene','阿李','圆石徽章',60)
e('dex_lost','veilstone_city','@COUNTERPART','小光','糟了，我的图鉴让银河队抢走了！他们就在仓库旁，请和我一起去。',at=[682,614])
e('dex_recovered','veilstone_city','@GRUNT_M_WAREHOUSE_NORTH','银河队手下','想拿回图鉴？那就试试看！',fight('银河队手下','galactic_grunt_veilstone_city_1+galactic_grunt_veilstone_city_2',ally='dawn_veilstone_city'),say('小光','图鉴拿回来了！帅哥先生想和你进仓库调查。'))
e('fly','veilstone_city_galactic_warehouse','@ITEM_HM02','秘传学习器','仓库的地面上有一个学习器。你捡起了秘传学习器０２「飞翔」。',hm(2),require='dex_recovered',following=False)
e('rival_pastoria','pastoria_city','#CoordEvent_RivalBattle','阿驯','师父的道馆就在这里！在那之前，先让我试试你的本事！',fight('阿驯','rival_pastoria_city*'))
badge(5,'pastoria_city_gym','crasher_wake','吉宪','沼泽徽章',55)
e('marsh_bomb','pastoria_city','#CoordEvent_Bomb','吉宪','大湿地里爆炸了！阿驯守住入口，小悠，追上那个银河队手下！')
e('chase_west','route_213','@GRUNT_M','银河队手下','别跟着我！能量已经送到该送的地方了。')
e('chase_east','route_213','@GRUNT_M','银河队手下','又是你！别以为能追得上我。',at=[683,833])
e('secret','valor_lakefront','@GRUNT_M','银河队手下','这次可跑不掉了……那就对战吧！',fight('银河队手下','galactic_grunt_valor_lakefront'),say('竹兰','２１０号道路的可达鸭还在头痛吗？带上这份秘传之药，它能治好它们。'),item('秘传之药'))
e('ducks','route_210_south','@PSYDUCK_1','可达鸭','给可达鸭用了秘传之药。它们晃晃脑袋，排成一列走开了。',{'remove_item':'秘传之药'},say('竹兰','能顺路帮我把古代护符送给神和镇的奶奶吗？'),item('古代护符'))
e('celestic_grunt','celestic_town','@GRUNT_M','银河队手下','这个小镇和遗迹全都碍事！',fight('银河队手下','galactic_grunt_celestic_town'))
e('old_charm','celestic_town','@ELDER','竹兰的奶奶','是竹兰托你带来的古代护符！谢谢你，进洞窟看看古老的壁画吧。',{'remove_item':'古代护符'},at=[463,523])
e('surf','celestic_town_cave','&Painting','竹兰的奶奶','这三只宝可梦围在一起……你看，它们中间的光，照亮了整幅壁画。',say('赤日','人们总把心灵当作宝物。在我眼里，正是它让这个世界残缺。我会从这里抹去这段传说。'),fight('赤日','galactic_boss_cyrus_celestic_town_ruins'),say('竹兰的奶奶','为了保护遗迹，你做得很好。这是冲浪，以后也能从水路旅行了。'),hm(3))
e('canalave_rival','canalave_city','#CoordEvent_Rival','阿驯','我在钢铁岛修行过了！在这座吊桥上试试成果吧！',fight('阿驯','rival_canalave_city*'))
badge(6,'canalave_city_gym','byron','东瓜','矿山徽章',91)
e('library_entry','canalave_city','@RIVAL_LIBRARY','阿驯','',{'sinnoh_strength_pass':True},say('阿驯','好慢！快进来，博士在图书馆三楼等我们。'))
e('library','canalave_library_3f','!OnFrame_Explosion','山梨博士','我想请你们分别去三座湖，找一找传说中的宝可梦。',say('阿驯','哇！连书架都在晃！刚才那声巨响是从哪儿传来的？'),say('山梨博士','是立志湖的方向！小悠，你去立志湖。小光和我去心齐湖。阿驯，睿智湖就拜托你了。'))
e('valor_saturn','valor_cavern','@SATURN','镇星','立志湖的水被炸干了。亚克诺姆已经落入银河队手里。',fight('镇星','commander_saturn_valor_cavern'))
e('verity_mars','lake_verity','@MARS','伙星','又是你！即使打倒我，艾姆利多也回不来了。',fight('伙星','commander_mars_lake_verity'),say('山梨博士','我们的宝可梦都平安。但阿驯还在北方，去睿智湖看看吧。'))
e('acuity_ledge','acuity_lakefront','#CoordEvent_Rival','阿驯','我先爬上去了！拿到雪峰道馆的徽章，你也能用攀岩上来！')
badge(7,'snowpoint_city_gym','candice','小菘','冰河徽章',72)
e('acuity','lake_acuity','!CoordEvent_JupiterRival','岁星','由克希也属于银河队了。想救它们，就来帷幕总部吧。',say('阿驯','只想着成为最强，却没有保护好它。我会变得更可靠。'))
e('storage','veilstone_city','@GRUNT_M_STORAGE_KEY','银河队手下','我、我可不知道什么仓库钥匙！你别跟着我！',say('帅哥','你瞧，他慌得把钥匙掉了。去仓库门口碰头，接下来可要放轻脚步。'))
e('warehouse_open','veilstone_city_galactic_warehouse','#CoordEvent_LookerOpenDoor','帅哥','上次这扇门挡住了我们。现在有了仓库钥匙，进去调查吧！')
e('galactic_key','galactic_hq_b2f','@ITEM_GALACTIC_KEY','银河队钥匙','你在地下通道发现了银河队钥匙。现在可以从主楼进入总部深处。',item('银河队钥匙'))
e('hq_entrance','galactic_hq_1f','@GALACTIC_HQ_DOOR_WEST','电子门','银河队钥匙插入锁孔。两扇门向左右滑开了。')
e('speech','galactic_hq_hall','#CoordEvent_Speech','赤日','银河队的诸位！两条红色锁链已在我们手中。到了天冠山顶，我们就能亲手创造新世界！',say('帅哥','创造世界？事情比我想的还严重。我留下查查演说的事。你往里走时千万小心。'))
e('hq_office','galactic_hq_4f','@GALACTIC_HQ_DOOR_WEST','电子门','使用银河队钥匙，通往首领办公室的门打开了。')
e('hq_cyrus','galactic_hq_4f','#CoordEvent_Cyrus','赤日','想解救三个湖泊的宝可梦？让我看看你依靠情感到底能做什么。',fight('赤日','galactic_boss_cyrus_galactic_hq'),say('赤日','大师球给你吧。在天冠山上，我需要的是红色锁链。'),item('大师球','ball'))
e('hq_saturn','galactic_hq_control_room','@SATURN','镇星','它们被关在机器里。打赢我，就让你按下开关。',fight('镇星','commander_saturn_galactic_hq'))
e('lakes_freed','galactic_hq_control_room','&Button','控制装置','按下红色按钮。三座容器打开了，由克希、艾姆利多、亚克诺姆飞出了总部！')
e('spear_grunts','spear_pillar','#CoordEvent_Grunts','银河队手下','往前就是枪之柱，没有人能妨碍赤日大人！',fight('银河队手下','galactic_grunt_spear_pillar_1+galactic_grunt_spear_pillar_2'))
e('spear_tag','spear_pillar','#CoordEvent_MarsJupiter','阿驯','别一个人逞强！伙星和岁星交给我们两个！',fight('伙星与岁星','commander_mars_spear_pillar+commander_jupiter_spear_pillar',ally='rival_spear_pillar'),{'heal':True},{'sinnoh_seen':[483,484]},say('赤日','帝牙卢卡！帕路奇亚！以这两条锁链之名，将时间和空间交给我！'),say('阿驯','小悠！刚才地上那团影子……它把赤日拖进去了！'),warp('spear_pillar_distorted',30,30))
e('distortion','spear_pillar_distorted','@CYNTHIA','竹兰','那股力量是骑拉帝纳！裂缝还没合上，我们一起进去吧。',warp('distortion_world_1f',55,40))
e('dist_enter','distortion_world_1f','!OnFrame_FirstEntry','竹兰','这里的方向和重力都与现实不同。沿着石台继续向下，跟着湖之宝可梦走。')
e('dist_cyrus','distortion_world_b3f','~DIST_WORLD_MAP_OBJECT_B3F_CYRUS','赤日','你也追来了吗？这如影子般的世界，和我们的世界连在一起。',at=[65,49])
puzzles = [
    ('uxie','由克希',[86,56],[86,57],[85,60],[86,58],[82,60]),
    ('mesprit','艾姆利多',[75,68],[76,68],[68,67],[77,68],[68,64]),
    ('azelf','亚克诺姆',[98,67],[97,67],[96,68],[96,67],[96,71]),
]
for floor in ('B5F','B6F'):
    for spirit,zh,at,drop,pit,hint5,hint6 in puzzles:
        upper = floor=='B5F'
        name = 'drop_'+spirit if upper else 'boulder_'+spirit
        obj = 'DIST_WORLD_MAP_OBJECT_'+floor+'_'+spirit.upper()
        m = 'distortion_world_'+floor.lower()
        prereq = 'dist_cyrus' if upper else 'drop_'+spirit
        e(name,m,'~'+obj+('_BOULDER' if upper else '_BOULDER_OUTSIDE'),zh+'的岩石','',
          {'sinnoh_boulder':{'spirit':spirit,'pit':drop if upper else pit}},require=prereq,following=False,at=at)
        show(m,obj,[flag(prereq)],[flag(name)],zh,hint5 if upper else hint6,absolute=True,sprite=spirit.upper())
e('dist_lift','distortion_world_b6f','~DIST_WORLD_MAP_OBJECT_B6F_CYNTHIA','竹兰','三只湖之宝可梦回去了！那边的石台动了，我们可以下到最后一层。',require='boulder_uxie boulder_mesprit boulder_azelf',at=[85,80])
e('dist_boss','distortion_world_b7f','~DIST_WORLD_MAP_OBJECT_B7F_CYRUS','赤日','这个被遗弃的世界也妨碍着我的计划。最后再与你一战！',fight('赤日','galactic_boss_cyrus_distortion_world'),say('竹兰','我来治疗你的宝可梦。前面就是骑拉帝纳。'),{'heal':True},require='dist_lift',at=[85,70])
e('giratina','distortion_world_giratina_room','~DIST_WORLD_MAP_OBJECT_GIRATINA_ROOM_GIRATINA','骑拉帝纳','巨大的影子浮现了。骑拉帝纳以起源形态望着你！',{'battle':{'name':'骑拉帝纳','team':[{'species':487,'level':47}],'wild':True,'finish_on_escape':True,'form':'origin','capture_flag':'s_caught_487'}},at=[15,13])
e('portal','distortion_world_giratina_room','~DIST_WORLD_MAP_OBJECT_GIRATINA_ROOM_PORTAL','空间裂缝','扭曲的空间恢复平静。透过裂缝，能够看见现实世界的泉水。',warp('sendoff_spring',32,17),at=[15,13])
e('spring','sendoff_spring','!OnFrame_Cynthia','竹兰','我们回到送行之泉了！现实与毁坏的世界都平安了。去告诉山梨博士吧。')
e('reported','sandgem_town_pokemon_research_lab','!OnFrame_ReturnedFromDistortionWorld','山梨博士','你和宝可梦一起保护了神奥。往滨海市去吧，最后一枚徽章正等着你。')
e('flint_visit','sunyshore_city','!OnFrame_Flint','大叶','我是四天王的大叶！我的朋友电次最近打不起精神。去灯塔找他，好好来一场道馆赛吧。')
e('lighthouse','vista_lighthouse','@VOLKNER','电次','又有挑战者了吗？你的眼神不错。我回道馆，期待一场让我心跳加速的对战。')
badge(8,'sunyshore_city_gym_room_3','volkner','电次','灯塔徽章',57)
e('waterfall','sunyshore_city','#CoordEvent_RivalAndJasmine','阿蜜','从这里向北就是宝可梦联盟。收下攀瀑，有了最后的徽章，就能越过那里的瀑布了。',hm(7))
e('league_rival','pokemon_league_north_pokecenter_1f','#CoordEvent_Rival','阿驯','等一等！走到联盟门前，再和我全力以赴地比一次！',fight('阿驯','rival_pokemon_league*'))
e('league_admitted','pokemon_league_north_pokecenter_1f','@LEAGUE_NORTH_DOOR_GUARD','联盟守卫','石炭、森林、遗迹、圆石、沼泽、矿山、冰河、灯塔。八枚神奥徽章齐全！挑战者，请向前。',require='league_rival '+' '.join('badge_'+str(n) for n in range(1,9)))
show('pokemon_league_north_pokecenter_1f','LEAGUE_NORTH_DOOR_GUARD','started','league_admitted','联盟守卫',[11,3])
show('pokemon_league_north_pokecenter_1f','LEAGUE_NORTH_DOOR_GUARD','league_admitted','','联盟守卫',[12,3])
for name,who,line in [('aaron','阿柳','让你看看虫宝可梦的生命力！'),('bertha','菊野','年轻人，让我看看你一路积累的本领。'),('flint','大叶','终于在联盟见面了！让这场对战燃烧起来吧！'),('lucian','悟松','书可以稍后再读。请，让我见识你和伙伴的智慧。')]:
    e(name,'pokemon_league_'+name+'_room','@'+name.upper(),who,line,fight(who,'elite_four_'+name))
e('cynthia','pokemon_league_champion_room','!OnFrame_EnterRoom','竹兰','从百代市到毁坏的世界，我们经历了许多。现在我是冠军。让我们竭尽全力，一决胜负！',fight('竹兰','champion_cynthia'),say('竹兰','你和宝可梦的默契，配得上神奥冠军的称号。一起去名人堂吧！'),warp('pokemon_league_hallway_to_hall_of_fame',5,23))
e('hall_walk','pokemon_league_hallway_to_hall_of_fame','!OnFrame_EnterHallOfFame','山梨博士','小悠，还记得我交给你的第一只宝可梦吗？看看今天站在你身边的伙伴们。来，我们和竹兰一起进去。',warp('pokemon_league_hall_of_fame',8,15))
e('champion','pokemon_league_hall_of_fame','!OnFrame_EnterHallOfFame','山梨博士','恭喜你，小悠。把一起踏上巅峰的每一位伙伴，记录在神奥的名人堂吧。',{'hall_of_fame':'sinnoh'},{'sinnoh_hall_team':True},warp('twinleaf_town_player_house_2f',4,6))

# Reuse the original league scripts on every later entry. The Stark Mountain arrest,
# rather than the first title, enables the second trainer set in Platinum.
main_count=len(events)
prior='champion'
for name,who in [('aaron','阿柳'),('bertha','菊野'),('flint','大叶'),('lucian','悟松'),('cynthia','竹兰')]:
    m='pokemon_league_'+('champion' if name=='cynthia' else name)+'_room'
    key='champion_cynthia' if name=='cynthia' else 'elite_four_'+name
    encounter=fight(who,key)
    encounter['battle']['s_strong_team']=trainer(key+'_rematch')
    after=[warp('pokemon_league_hallway_to_hall_of_fame',5,23)] if name=='cynthia' else []
    e('again_'+name,m,'!OnFrame_EnterRoom' if name=='cynthia' else '@'+name.upper(),who,'欢迎再次挑战神奥联盟。让我看看你的伙伴们现在的实力吧！',encounter,*after,require=prior,following=False)
    prior='again_'+name
e('again_hall_walk','pokemon_league_hallway_to_hall_of_fame','!OnFrame_EnterHallOfFame','竹兰','向前走吧，新的优胜队伍将在这里留下记录。',warp('pokemon_league_hall_of_fame',8,15),require=prior,following=False)
e('again_hall','pokemon_league_hall_of_fame','!OnFrame_EnterHallOfFame','山梨博士','欢迎再次登上名人堂。',{'sinnoh_repeat_hall':True},warp('twinleaf_town_player_house_2f',4,6),require='again_hall_walk',following=False)
e('fight_area_arrived','fight_area','!OnFrame_Rival','阿驯','你终于来了！在对战开拓区的入口，有两个非常厉害的家伙正等着挑战我们。',warp('fight_area',655,427),require='champion',following=False)
e('fight_area_tag','fight_area','@RIVAL','阿驯','我和你组队，挑战电次和大叶！',fight('电次与大叶','leader_volkner_fight_area+elite_four_flint_fight_area',ally='rival_fight_area'),say('桄榔','我是对战塔大君。想更上一层楼，就来对战开拓区。'),say('麦可','对你的冒险很感兴趣！以后到生存区来找我。'),require='fight_area_arrived',following=False,at=[655,426])
for local,who in [('VOLKNER','电次'),('FLINT','大叶'),('BUCK','麦可')]:
    show('fight_area',local,'champion','fight_area_tag',who)
show('fight_area','RIVAL','champion','fight_area_arrived','阿驯')
for layer,m in [('b2f','galactic_hq_b2f'),('3f','galactic_hq_3f')]:
    e('hq_lock_'+layer,m,'@GALACTIC_HQ_DOOR_WEST','电子门','银河队钥匙打开了这扇电子门。',require='galactic_key',following=False)
e('villa_deed','resort_area','#CoordEvent_SchoolKidM','男孩','我正要搬走。这栋别墅想交给懂得珍惜它的人。',{'sinnoh_villa_offer':True},warp('villa',10,6),require='national_dex',following=False)
e('villa_order','villa','!OnFrame_FirstEntry','男孩','原来的主人带走了家具。这张订货单可以免费选一张桌子。',{'sinnoh_villa':'orders'},require='villa_deed',following=False)
postgame=events[main_count:]
del events[main_count:]

# Play the departure movements that the original scripts apply to these actors.
# A named movement block can contain idle turns or visibility commands; the
# field renderer handles facing and removes the actor when the event commits.
def original_steps(m, *labels):
    source = (MAPS/m/'scripts.s').read_text()
    path = ''
    for label in labels:
        block = re.search(r'^\w+_Movement_'+label+r':\n(.*?)EndMovement',source,re.M|re.S)
        assert block, (m,label)
        for direction, steps in re.findall(r'Walk(?:Fast|Normal)(North|South|West|East)(?: (\d+))?',block[1]):
            path += {'North':'U','South':'D','West':'L','East':'R'}[direction]*int(steps or 1)
    assert path, (m,labels)
    return path


def movement(stage, local, m, *labels):
    entry = next(e for e in events if e['id']==flag(stage))
    path = original_steps(m, *labels)
    entry['steps'].insert(-1,{'sinnoh_walk':{'actor':'LOCALID_'+local,'path':path}})


movement('invited','RIVAL','twinleaf_town_rival_house_2f','RivalLeave')
movement('library_entry','RIVAL_LIBRARY','canalave_city','EnterDoor')
movement('mine','ROARK','oreburgh_mine_b2f','RoarkLeave')
movement('garden_door','GARDENIA','eterna_city','GardeniaEnterGym')
movement('seeker','COUNTERPART','route_207','CounterpartLeave')
movement('lighthouse','VOLKNER','vista_lighthouse','VolknerWalkToDoorNorth','VolknerLeave')
# These rooms run OnFrame as soon as the south doorway is crossed. Walk from
# that entry to the original conversation tile before opening the dialogue.
for stages, room, local, entry_y, label in [
    (('cynthia','again_cynthia'),'pokemon_league_champion_room','CYNTHIA',18,'PlayerApproachCynthia'),
    (('hall_walk','again_hall_walk'),'pokemon_league_hallway_to_hall_of_fame','CYNTHIA',23,'PlayerEnterHallway'),
    (('champion','again_hall'),'pokemon_league_hall_of_fame','PROF_ROWAN',15,'WalkUp'),
]:
    path = original_steps(room,label)
    assert set(path)=={'U'}
    for stage in stages:
        entry = next(event for event in events+postgame if event['id']==flag(stage))
        entry['steps'].insert(0,{'sinnoh_walk':{'actor':'LOCALID_'+local,'path':'','player_lane':[entry_y,entry_y-len(path)]}})
for local, who, x in [('CYNTHIA','竹兰',6),('PROF_ROWAN','山梨博士',4)]:
    show('pokemon_league_hallway_to_hall_of_fame',local,'cynthia','',who,[x,6])
    show('pokemon_league_hall_of_fame',local,'champion','',who)
# Non-interactive cast members are staged separately from the event's trigger.
# Their source objects are sometimes parked off-screen until the native script moves them.
for m,local,req,end,name,pos in [
 ('twinleaf_town_rival_house_2f','RIVAL','thud','invited','阿驯',None),
 ('lake_acuity','JUPITER','badge_7','acuity','岁星',None),
 ('galactic_hq_hall','LOOKER','galactic_key','speech','帅哥',None),
 ('galactic_hq_hall','CYRUS','galactic_key','speech','赤日',None),
 ('pokemon_league_champion_room','CYNTHIA','lucian','cynthia','竹兰',None),
 ('twinleaf_town_player_house_2f','RIVAL','broadcast','rival_visit','阿驯',[7,5]),
 ('twinleaf_town','RIVAL','rival_visit','thud','阿驯',None),
 ('twinleaf_town_player_house_1f','PLAYER_HOUSE_MOM','started','','妈妈',None),
 ('twinleaf_town_player_house_1f','RIVAL_MOM','dex','parcel','阿驯的妈妈',None),
 ('route_201','RIVAL','invited','first_battle','阿驯',None),
 ('route_201','RIVAL','running','verity_intro','阿驯',[111,855]),
 ('route_201','PROF_ROWAN','rowan','first_battle','山梨博士',[112,852]),
 ('route_201','COUNTERPART','rowan','first_battle','小光',[113,853]),
 ('lake_verity_low_water','CYRUS','lake_trip','verity_intro','赤日',None),
 ('lake_verity_low_water','RIVAL','lake_trip','verity_intro','阿驯',[45,53]),
 ('sandgem_town','COUNTERPART','verity_intro','dex','小光',None),
 ('sandgem_town_pokemon_research_lab','PROF_ROWAN','sandgem_escort','','山梨博士',None),
 ('sandgem_town_pokemon_research_lab','COUNTERPART','sandgem_escort','dex','小光',[8,6]),
 ('route_202','COUNTERPART','parcel','tutorial','小光',None),
 ('jubilife_city','LOOKER','tutorial','looker','帅哥',[177,774]),
 ('jubilife_city','COUNTERPART','tutorial','looker','小光',None),
 ('jubilife_city','COUNTERPART','badge_1','jubilife_grunts','小光',[176,739]),
 ('jubilife_city','PROF_ROWAN','badge_1','jubilife_grunts','山梨博士',None),
 ('jubilife_city','GRUNT_M_1','badge_1','jubilife_grunts','银河队手下',None),
 ('jubilife_city','GRUNT_M_2','badge_1','jubilife_grunts','银河队手下',None),
 ('route_203','RIVAL','poketch','rival_203','阿驯',None),
 ('oreburgh_city','RIVAL','rival_203','mine','阿驯',None),
 ('floaroma_meadow','GRUNT_M_EAST','wind_guard','works_key','银河队手下',None),
 ('floaroma_meadow','GRUNT_M_WEST','wind_guard','works_key','银河队手下',None),
 ('valley_windworks_building','MARS','works_key','mars_wind','伙星',None),
 ('valley_windworks_building','CHARON','works_key','mars_wind','冥王',None),
 ('eterna_forest','CHERYL','mars_wind','cheryl','芽米',None),
 ('eterna_forest','CHERYL','cheryl','forest_exit','芽米',[81,36]),
 ('eterna_city','CYNTHIA','statue','cut','竹兰',[306,521]),
 ('eterna_city','RIVAL','forest_exit','statue','阿驯',None),
 ('eterna_city','CYRUS','forest_exit','statue','赤日',None),
 ('eterna_city','CYNTHIA','jupiter','togepi','竹兰',[309,541]),
 ('route_207','COUNTERPART','bike','seeker','小光',[341,714]),
 ('mt_coronet_1f_south','CYRUS','seeker','coronet_cyrus','赤日',None),
 ('hearthome_city','BUNEARY','coronet_cyrus','keira','卷卷耳',None),
 ('hearthome_city','KEIRA','coronet_cyrus','keira','美棠',[469,725]),
 ('contest_hall_lobby','MOM','keira','contest','妈妈',None),
 ('contest_hall_lobby','KEIRA','keira','contest','美棠',None),
 ('route_209_gate_to_hearthome_city','RIVAL','badge_3','rival_209','阿驯',None),
 ('solaceon_town','RIVAL','rival_209','solaceon','阿驯',None),
 ('veilstone_city','COUNTERPART','solaceon','veil_wake','小光',None),
 ('veilstone_city','COUNTERPART','dex_lost','dex_recovered','小光',[696,596]),
 ('veilstone_city','CRASHER_WAKE','solaceon','veil_wake','吉宪',None),
 ('veilstone_city','GRUNT_M_WAREHOUSE_SOUTH','dex_lost','dex_recovered','银河队手下',None),
 ('pastoria_city','RIVAL','dex_recovered','rival_pastoria','阿驯',[590,828]),
 ('pastoria_city','CRASHER_WAKE','badge_5','marsh_bomb','吉宪',[611,809]),
 ('pastoria_city','GRUNT_M','badge_5','marsh_bomb','银河队手下',None),
 ('route_213','LOOKER','chase_west','secret','帅哥',[684,832]),
 ('valor_lakefront','CYNTHIA','chase_east','secret','竹兰',[723,761]),
 ('route_210_south','CYNTHIA','secret','ducks','竹兰',[560,596]),
 ('celestic_town_cave','ELDER','old_charm','','竹兰的奶奶',None),
 ('celestic_town_cave','CYRUS','old_charm','surf','赤日',[9,6]),
 ('canalave_city','RIVAL_BRIDGE','surf','canalave_rival','阿驯',None),
 ('canalave_library_3f','PROF_ROWAN','badge_6','library','山梨博士',None),
 ('canalave_library_3f','COUNTERPART','badge_6','library','小光',None),
 ('canalave_library_3f','RIVAL','badge_6','library','阿驯',None),
 ('lake_verity','COUNTERPART','valor_saturn','verity_mars','小光',None),
 ('lake_verity','PROF_ROWAN','valor_saturn','verity_mars','山梨博士',None),
 ('acuity_lakefront','RIVAL','verity_mars','acuity_ledge','阿驯',None),
 ('lake_acuity','RIVAL','badge_7','acuity','阿驯',None),
 ('veilstone_city_galactic_warehouse','LOOKER','storage','warehouse_open','帅哥',[9,9]),
 ('galactic_hq_4f','CYRUS','speech','hq_cyrus','赤日',None),
 ('galactic_hq_control_room','CHARON','hq_cyrus','lakes_freed','冥王',None),
 ('spear_pillar','GRUNT_M','lakes_freed','spear_grunts','银河队手下',None),
 ('spear_pillar','GRUNT_F','lakes_freed','spear_grunts','银河队手下',None),
 ('spear_pillar','MARS','lakes_freed','spear_tag','伙星',None),
 ('spear_pillar','JUPITER','lakes_freed','spear_tag','岁星',None),
 ('spear_pillar','CYRUS','lakes_freed','spear_tag','赤日',None),
 ('spear_pillar','RIVAL','spear_grunts','spear_tag','阿驯',None),
 ('sendoff_spring','CYNTHIA','portal','spring','竹兰',None),
 ('sunyshore_city','FLINT','reported','lighthouse','大叶',None),
 ('sunyshore_city','JASMINE','badge_8','','阿蜜',None),
 ('pokemon_league_north_pokecenter_1f','LEAGUE_NORTH_RIVAL','waterfall','league_rival','阿驯',None),
 ('pokemon_league_hall_of_fame','CYNTHIA','cynthia','champion','竹兰',None),
 ('pokemon_league_hall_of_fame','PROF_ROWAN','cynthia','champion','山梨博士',None),
]:
    show(m,local,req,end,name,pos)
for spirit in ['UXIE','AZELF','MESPRIT']:
    show('galactic_hq_control_room',spirit,'hq_cyrus','lakes_freed',{'UXIE':'由克希','AZELF':'亚克诺姆','MESPRIT':'艾姆利多'}[spirit])
for duck in load_events('route_210_south')['object_events']:
    if 'PSYDUCK' in duck.get('id',''):
        show('route_210_south',duck['id'][8:],'started','ducks','可达鸭')
for n,m,leader,name in [(1,'oreburgh_city_gym','ROARK','瓢太'),(2,'eterna_city_gym','GARDENIA','菜种'),(3,'hearthome_city_gym_leader_room','FANTINA','梅丽莎'),(4,'veilstone_city_gym','MAYLENE','阿李'),(5,'pastoria_city_gym','CRASHER_WAKE','吉宪'),(6,'canalave_city_gym','BYRON','东瓜'),(7,'snowpoint_city_gym','CANDICE','小菘'),(8,'sunyshore_city_gym_room_3','VOLKNER','电次')]:
    show(m,leader,'badge_'+str(n),'',name)
for who,name in [('aaron','阿柳'),('bertha','菊野'),('flint','大叶'),('lucian','悟松'),('champion','竹兰')]:
    show('pokemon_league_'+who+'_room',('CYNTHIA' if who=='champion' else who.upper()),'cynthia' if who=='champion' else who,'',name)

# The same guard applies to an ordinary door, a Fly destination and a regional transfer.
source_index = read(ROOT / 'content/platinum_native/index.json')


def gates_for(req, prefixes, message):
    for prefix in prefixes.split():
        prefix = 'MAP_HEADER_'+prefix.upper()
        for header,mid in source_index.items():
            if header==prefix or header.startswith(prefix+'_'):
                gates[mid] = {'require':[flag(x) for x in req.split()], 'message':message}


gates_for('invited','route_201','阿驯还在双叶镇家里等你。')
gates_for('lake_trip','verity_lakefront lake_verity_low_water','先和阿驯在２０１号道路会合。')
gates_for('verity_intro','sandgem_town','先陪阿驯去心齐湖，再到真砂镇找博士。')
gates_for('dex','route_219','先向真砂镇研究所的山梨博士报到。')
gates_for('parcel','route_202','先回双叶镇和妈妈道别。')
gates_for('tutorial','jubilife_city trainers_school jubilife_tv route_218_gate_to_jubilife_city','小光在２０２号道路等你。')
gates_for('poketch','route_203 oreburgh_gate oreburgh_city oreburgh_mine','祝庆市的宝可表活动还没结束。')
gates_for('jubilife_grunts','route_204 ravaged_path floaroma_town floaroma_meadow valley_windworks route_205_south','先在祝庆市北门帮助博士和小光。')
gates_for('works_key','valley_windworks_building','门从里面锁住了。到花苑花田找另一把钥匙。')
gates_for('mars_wind','eterna_forest route_205_north','银河队仍控制着发电厂。')
gates_for('forest_exit','eterna_city cycle_shop eterna_condominiums','先和芽米一起穿过百代森林。')
gates_for('badge_2 cut','team_galactic_eterna_building','得到森林徽章，用居合斩打开银河队百代大楼前的路。')
gates_for('bike','cycling_road route_206 route_207','从自行车店领车，才能向南穿过自行车道。')
# The Oreburgh side of Route 207 is open before the bike shop.
gates.pop(source_index['MAP_HEADER_ROUTE_207'],None)
gates_for('bike','mt_coronet_1f_south route_208','前往天冠山之前，先解决百代市的银河队事件。')
gates_for('coronet_cyrus','hearthome_city contest_hall amity_square','先经过２０７号道路和天冠山南侧。')
gates_for('fantina_ready','hearthome_city_gym_entrance_room hearthome_city_gym_trainer_room hearthome_city_gym_leader_room','梅丽莎还在华丽大赛会场。')
gates_for('badge_3','route_209_gate_to_hearthome_city','先在家缘道馆赢得遗迹徽章。')
gates_for('rival_209','route_209 solaceon_town solaceon_ruins lost_tower route_210_south route_215','阿驯正在家缘市东边的关卡等你。')
gates[source_index['MAP_HEADER_ROUTE_209_GATE_TO_HEARTHOME_CITY']]={'require':['s_badge_3'],'message':'先在家缘道馆赢得遗迹徽章。'}
gates_for('solaceon','veilstone_city veilstone_department_store game_corner route_214 ruin_maniac_cave','先经过随意镇。')
gates_for('dex_recovered','pastoria_city great_marsh route_213 valor_lakefront grand_lake','小光正在帷幕市等你帮忙找回图鉴。')
gates_for('ducks','route_210_north celestic_town','２１０号道路的可达鸭还需要治疗。')
gates_for('surf','route_218 canalave_city canalave_library iron_island','先帮竹兰把护符送到神和镇，取得冲浪。')
gates_for('tutorial','route_218_gate_to_jubilife_city','先到祝庆市。')
gates_for('library','lake_valor_drained valor_cavern','水脉图书馆还没有传出爆炸消息。')
gates_for('valor_saturn','lake_verity','先到立志湖空洞阻止镇星。')
gates_for('lake_trip','lake_verity_low_water','先和阿驯约好去心齐湖。')
gates_for('verity_mars','mt_coronet_1f_north_room mt_coronet_b1f route_216 route_217 snowpoint_city acuity_lakefront','心齐湖的博士和小光还需要帮助。')
gates_for('badge_7','lake_acuity','要去睿智湖，请先取得冰河徽章并攀上岩壁。')
gates_for('warehouse_open','galactic_hq','银河队仓库的门锁着。先和帅哥调查仓库。')
gates_for('galactic_key','galactic_hq_hall galactic_hq_4f','需要先从总部地下层找到银河队钥匙。')
gates_for('hq_cyrus','galactic_hq_control_room','赤日还在总部四层。')
gates_for('lakes_freed','mt_coronet_2f mt_coronet_3f mt_coronet_4f mt_coronet_4f_rooms_1_and_2 mt_coronet_5f mt_coronet_6f mt_coronet_outside spear_pillar','先在银河队总部释放三只湖之宝可梦。')
gates_for('spear_tag','spear_pillar_distorted','枪之柱的银河队干部挡住了道路。')
gates_for('distortion','distortion_world','枪之柱的空间裂缝还没有打开。')
gates_for('dist_lift','distortion_world_b7f','让三块岩石都落入湖之宝可梦指示的洞里。')
gates_for('dist_boss','distortion_world_giratina_room','赤日在毁坏的世界深处等着你。')
gates_for('giratina','sendoff_spring spring_path','毁坏的世界尚未恢复平静。')
gates_for('reported','route_222 sunyshore_city vista_lighthouse','先将毁坏的世界的事情告诉山梨博士。')
gates_for('lighthouse','sunyshore_city_gym','电次去了滨海市的灯塔。')
gates_for('waterfall','route_223 victory_road pokemon_league','联盟水路需要滨海徽章和攀瀑。')
for member,required in [('aaron','league_admitted'),('bertha','aaron'),('flint','bertha'),('lucian','flint'),('champion','lucian')]:
    gates_for(required,'pokemon_league_elevator_to_'+member+'_room pokemon_league_'+member+'_room','先战胜上一位联盟挑战者。')
gates_for('cynthia','pokemon_league_hall_of_fame pokemon_league_hallway_to_hall_of_fame','先战胜冠军竹兰。')
gates_for('champion','route_224 route_225 route_226 route_227 route_228 route_229 route_230 fight_area resort_area survival_area stark_mountain battle_frontier','进入名人堂后，神奥的东部岛屿才会开放。')

# Use the actual new-game script instead of treating every hidden_flag as hidden.
# Snapshot only flags that field objects read. Scene completion commits the native
# flag changes together, so reopening a map, loading a save and crossing regions agree.
used_flags = set()
for header in source_index:
    for row in load_events(header.removeprefix('MAP_HEADER_').lower()).get('object_events',[]):
        if row.get('hidden_flag'): used_flags.add(row['hidden_flag'])
flag_commands = re.compile(r'^\s*(SetFlag|ClearFlag) (FLAG_\w+)',re.M)
initial = {k:True for instruction,k in flag_commands.findall((SRC/'res/field/scripts/init_new_game.s').read_text()) if instruction=='SetFlag' and k in used_flags}
sources = {
    **{'badge_'+str(i+1):m for i,m in enumerate(('oreburgh_city_gym','eterna_city_gym','hearthome_city_gym_leader_room','veilstone_city_gym','pastoria_city_gym','canalave_city_gym','snowpoint_city_gym','sunyshore_city_gym_room_3'))},
    'mars_wind':'valley_windworks_building', 'jupiter':'team_galactic_eterna_building_4f',
    'library':'canalave_library_3f', 'verity_mars':'lake_verity', 'lakes_freed':'galactic_hq_control_room',
    'spring':'sendoff_spring','distortion':'spear_pillar_distorted',
}
changes = {}
for scene,m in sources.items():
    values = {}
    for op,k in flag_commands.findall((MAPS/m/'scripts.s').read_text()):
        if k in used_flags: values.setdefault(k,set()).add(op=='SetFlag')
    changes[flag(scene)] = {k:next(iter(v)) for k,v in values.items() if len(v)==1}
explicit = {
    'invited':'+HIDE_TWINLEAF_TOWN_RIVAL',
    'fantina_ready':'+HIDE_HEARTHOME_CITY_GYM_GUIDE',
    'rowan':'-HIDE_ROUTE_201_PROF_ROWAN -HIDE_ROUTE_201_COUNTERPART',
    'first_battle':'+HIDE_ROUTE_201_PROF_ROWAN +HIDE_ROUTE_201_COUNTERPART +HIDE_ROUTE_201_BRIEFCASE',
    'verity_intro':'+HIDE_LAKE_VERITY_LOW_WATER_CYRUS +HIDE_LAKE_VERITY_LOW_WATER_RIVAL',
    'looker':'+HIDE_JUBILIFE_CITY_LOOKER',
    'jubilife_grunts':'+HIDE_JUBILIFE_CITY_TEAM_GALACTIC',
    'wind_guard':'+DEFEATED_VALLEY_WINDWORKS_OUTSIDE_GRUNT +HIDE_FLOAROMA_TOWN_GRUNTS',
    'works_key':'+DEFEATED_FLOAROMA_MEADOW_GRUNTS +OBTAINED_FLOAROMA_MEADOW_WORKS_KEY',
    'mars_wind':'+HIDE_VALLEY_WINDWORKS_BUILDING_TEAM_GALACTIC +HIDE_VALLEY_WINDWORKS_BUILDING_GALACTIC_GRUNT_1',
    'jupiter':'+TEAM_GALACTIC_LEFT_ETERNA_BUILDING',
    'dex_recovered':'+HIDE_VEILSTONE_CITY_GRUNTS_BLOCKING_WAREHOUSE',
    'warehouse_open':'+HIDE_VEILSTONE_CITY_GALACTIC_WAREHOUSE_GALACTIC_HQ_DOOR',
    'ducks':'+HIDE_ROUTE_210_SOUTH_PSYDUCK',
    'rival_pastoria':'+HIDE_ROUTE_212_BLOCKADE',
    'surf':'+HIDE_ROUTE_218_BLOCKADE',
    'spear_grunts':'+HIDE_SPEAR_PILLAR_GRUNTS',
    'spear_tag':'+HIDE_SPEAR_PILLAR_MARS_JUPITER',
    'celestic_grunt':'+HIDE_CELESTIC_TOWN_GRUNT_M',
    'fight_area_tag':'+HIDE_FIGHT_AREA_BATTLERS_AND_SPECTATORS +HIDE_FIGHT_AREA_RIVAL +HIDE_FIGHT_AREA_BUCK',
    'library_entry':'+HIDE_CANALAVE_CITY_RIVAL_LIBRARY',
    'library':'+LAKE_VALOR_EXPLODED',
    'valor_saturn':'+DEFEATED_COMMANDER_SATURN_VALOR_CAVERN',
    'speech':'+HIDE_GALACTIC_HQ_HALL_GRUNTS +HIDE_GALACTIC_HQ_HALL_CYRUS +HIDE_GALACTIC_HQ_HALL_LOOKER',
    'hq_entrance':'+HIDE_GALACTIC_HQ_1F_DOOR',
    'hq_office':'+HIDE_GALACTIC_HQ_4F_DOOR',
    'hq_lock_3f':'+HIDE_GALACTIC_HQ_3F_DOOR',
    'hq_lock_b2f':'+HIDE_GALACTIC_HQ_B2F_DOOR',
    'hq_cyrus':'+DEFEATED_GALACTIC_BOSS_CYRUS_GALACTIC_HQ',
    'lakes_freed':'+FREED_GALACTIC_HQ_POKEMON +HIDE_GALACTIC_HQ_TEAM_GALACTIC',
    'spring':'+HIDE_LAKE_VALOR_GALACTIC +HIDE_LAKE_VERITY_TEAM_GALACTIC',
}
for scene,words in explicit.items():
    for word in words.split():
        key = 'FLAG_'+word[1:]
        if key in used_flags: changes.setdefault(flag(scene),{})[key]=word.startswith('+')
for source_map in ('galactic_hq_1f','galactic_hq_3f','galactic_hq_4f','galactic_hq_b2f'):
    door_arcs=actors['MAP_HEADER_'+source_map.upper()]
    door_arcs.pop('LOCALID_GALACTIC_HQ_DOOR_WEST',None)
# Native cutscenes can remove crowds without ever setting their graphics' hide
# flag. Replay unconditional object writes in the actual anchored script (including
# helper calls) after that milestone. Explicit later appearances still take precedence.
def object_lifetime(script, label):
    chunks=re.split(r'^(\w+):[^\n]*\n',script,flags=re.M)
    blocks=dict(zip(chunks[1::2],chunks[2::2]))
    writes={}
    def visit(label,chain):
        if label in chain or label not in blocks:return
        for raw in blocks[label].splitlines():
            fields=raw.strip().split()
            if not fields:continue
            op=fields[0]
            if op in ('AddObject','RemoveObject') and fields[1].startswith('LOCALID_'):
                writes[fields[1]]=op=='RemoveObject'
            elif op in ('Call','GoTo'):
                visit(fields[1],chain|{label})
                if op=='GoTo':break
            elif op in ('End','Return','EndCommonScript'):break
    visit(label,set())
    return writes

departures={}
for ev in events+postgame:
    m=ev['map'].removeprefix('MAP_HEADER_').lower()
    src=MAPS/m/'scripts.s'
    if not src.exists():continue
    writes=object_lifetime(src.read_text(),ev['trigger'].get('source_script',''))
    if writes:departures.setdefault(ev['map'],{})[ev['id']]=writes
book = dict(departures=departures,events=events,postgame=postgame, actors=actors, teams=trainers, gates=gates, initial_visibility=initial, changes=changes)
OUT.write_text(json.dumps(book,ensure_ascii=False,indent=1)+'\n')
print(f'{len(events)} events; {len(trainers)} Platinum trainer parties; {len(gates)} destination guards')
