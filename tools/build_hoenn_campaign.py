#!/usr/bin/env python3
"""Compile the Chinese Emerald campaign against a pret/pokeemerald source checkout."""
import base64
import struct
import zlib
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
args = parser.parse_args()
source = args.source
maps = {p.parent.name: json.loads(p.read_text()) for p in (source / "data/maps").glob("*/map.json")}
index = json.loads((ROOT / "content/hoenn_native/index.json").read_text())
species = {row["key"]: row["id"] for row in json.loads((ROOT / "content/species.json").read_text())}
moves = {row["key"].replace("_",""): row["id"] for row in json.loads((ROOT / "content/moves.json").read_text())}
moves["FAINTATTACK"] = moves["FEINTATTACK"]
trainers = dict(re.findall(r'\[TRAINER_(\w+)\]\s*=\s*\{(?:(?!\[TRAINER_).)*?\.party = \w+\((sParty_\w+)\)', (source/"src/data/trainers.h").read_text(), re.S))
party_source = dict(re.findall(r'(sParty_\w+)\[\] = \{(.*?)\n\};', (source / "src/data/trainer_parties.h").read_text(), re.S))
teams = {}
events = []
cast = {}
gates = {}

def team(key):
    if key not in teams:
        roster = []
        for mon in party_source[trainers[key]].split(".iv")[1:]:
            kind = re.search(r'SPECIES_(\w+)', mon)[1]
            row = {"species":species[kind], "level":int(re.search(r'\.lvl = (\d+)', mon)[1])}
            if ".moves" in mon:
                row["moves"] = [moves[t.replace("_","")] for t in re.findall(r'MOVE_(\w+)', mon) if t!="NONE"]
            berry = re.search(r'ITEM_(\w+)_BERRY', mon)
            if berry:
                row["berry"] = berry[1].lower()
            roster.append(row)
        assert roster, key
        teams[key] = roster
    return key

def battle(trainer, name):
    if trainer.endswith("*"):
        keys = [team(trainer[:-1]+k) for k in ["TREECKO","TORCHIC","MUDKIP"]]
        return {"battle":{"name":name,"starter_teams":keys}}
    return {"battle":{"name":name,"emerald_team":team(trainer)}}

def say(who, *lines):
    return {"who":who,"say":list(lines)}

def item(name): return {"hoenn_item":"ITEM_"+name}
def take(name): return {"hoenn_take":"ITEM_"+name}
def warp(mp, x, y): return {"warp":{"region":"hoenn","map":index[maps[mp]["id"]],"at":[x,y],"hoenn_native":True}}
def tr_step(*rect): return {"kind":"step","area":list(rect if len(rect)==4 else [*rect,rect[0]+1,rect[1]+1])}
def bg(x,y): return {"kind":"field","at":[x,y]}
def talk(i): return {"kind":"talk","actor":i}
def st(id, mp, trigger, req, *actions, repeat=False):
    if isinstance(trigger,int): trigger=talk(trigger)
    if isinstance(trigger,str): trigger={"kind":trigger}
    if "actor" in trigger:
        actor=maps[mp]["object_events"][trigger["actor"]-1]
        trigger["at"]=[actor["x"],actor["y"]]
    events.append({"id":"h_"+id,"map":mp,"map_id":index[maps[mp]["id"]],"trigger":trigger,
                   "require": ["h_"+f for f in req.split()], "repeat":repeat,
                   "steps":list(actions)+([] if repeat else [{"flag":"h_"+id}])})

def actors(mp, ids, req="", until="", name="", at=None):
    for i in ids:
        src=maps[mp]["object_events"][i-1]
        cast.setdefault(mp,{}).setdefault(str(i),[]).append({"require":["h_"+r for r in req.split()],
            "until":["h_"+r for r in until.split()],"name":name, "at":at or [src["x"],src["y"]]})

def gate(mp, req, msg):
    gates[index[maps[mp]["id"]]]={"require":["h_"+r for r in req.split()],"message":msg}

def badge(n, mp, actor, req, who, trainer, label, tm, intro, end):
    st("badge_"+str(n),mp,actor,req,say(who,intro),battle(trainer,who),say(who,end,"获得了"+label+"！"),{"hoenn_badge":label},{"hoenn_tm":tm})

home="LittlerootTown_BrendansHouse_1F"
lab="LittlerootTown_ProfessorBirchsLab"
st("moved","LittlerootTown","enter","started",say("妈妈","小悠，搬家车里可闷了吧？到家啦。上二楼看看自己的房间，把爸爸买的钟调好。"))
st("clock","LittlerootTown_BrendansHouse_2F",bg(5,1),"moved",say("小悠","墙上的时钟开始走动了。"),say("妈妈","房间收拾得怎么样？楼下好像在播橙华道馆的新闻呢。"))
st("tv",home,"enter","clock",say("妈妈","小悠，快看电视！橙华道馆……哎呀，爸爸受访的画面已经播完了。","隔壁住着小田卷博士一家，去打个招呼吧。"))
st("may_intro","LittlerootTown_MaysHouse_2F",bg(5,4),"tv",{"hoenn_actor_walk":{"id":1,"path":"DD","cast":"may_appears"}},say("小遥","啊，那是我的精灵球！你就是刚搬来的小悠吧？","我得去帮爸爸调查野生宝可梦。我们下次见！"))
st("birch_call","Route101",tr_step(10,19,12,20),"may_intro",say("小田卷博士","糟了，这只蛇纹熊追上来了！那边的小朋友，快从我的背包里拿一个精灵球！"))
st("rescued","Route101",3,"birch_call",{"hoenn_starter":True},{"battle":{"name":"野生蛇纹熊","wild":True,"team":[{"species":263,"level":2}]}},say("小田卷博士","得救了！你就是小悠吧？我们回研究所慢慢谈。"),{"flag":"h_rescued"},warp(lab,6,5))
st("partner",lab,2,"rescued",say("小田卷博士","你和刚才的搭档合作得很好。让它跟着你吧！","小遥在103号道路做调查，去找她比一场吧。"))
st("may103","Route103",2,"partner",say("小遥","爸爸把宝可梦交给你啦？我们来场对战，看看你和它有多合拍！"),battle("MAY_ROUTE_103_*","小遥"),say("小遥","我们先回研究所吧！"),{"heal":True})
st("dex",lab,2,"may103",say("小田卷博士","小遥说你很有天分。这本图鉴交给你，每一次相遇都会留下记录。"),say("小遥","这些精灵球给你。去高草里寻找新伙伴吧！"),{"give_item":{"name":"精灵球","count":5,"category":"ball"}})
st("shoes","LittlerootTown",tr_step(8,1,12,10),"dex",say("妈妈","小悠，等等！穿上这双跑步鞋。按住 B 就能跑了。一路小心！"),item("RUNNING_SHOES"))
pg="PetalburgCity_Gym"
st("wally_intro",pg,1,"dex",say("千里","来到我的道馆啦，小悠。满充要去绿荫镇养病，却还没有自己的宝可梦。带他去102号道路看看吧。"),{"flag":"h_wally_outing"},warp("Route102",5,4))
st("wally_catch","Route102","enter","wally_outing",{"hoenn_wally_tutorial":True},say("满充","草丛动了，是拉鲁拉丝！蛇纹熊，先用撞击……现在扔精灵球！","抓到了！这是我第一个伙伴。我得回去把蛇纹熊还给千里先生。"),{"hoenn_seen":280},{"flag":"h_wally_catch"},warp(pg,4,108))
st("father_challenge",pg,1,"wally_catch",say("千里","你先从卡那兹道馆开始修行吧。集齐四枚徽章，再来跟爸爸正式对战。"))
st("woods","PetalburgWoods",tr_step(26,23,28,24),"father_challenge",say("得文研究员","那边穿蓝制服的人一直跟踪我！"),battle("GRUNT_PETALBURG_WOODS","海洋队手下"),say("得文研究员","多亏了你！这个超级球送给你。我得赶回得文公司了。"),{"give_item":{"name":"超级球","count":1,"category":"ball"}})
badge(1,"RustboroCity_Gym",1,"woods","杜鹃","ROXANNE_1","岩石徽章","ROCK_TOMB","我想知道，用学校里学到的岩石系战术能走多远。","你让我学到了一课。这枚岩石徽章属于你。")
st("theft","RustboroCity","enter","badge_1",say("得文研究员","站住！我的包裹！小悠，那个海洋队员往东边的116号道路逃了！"))
st("peeko","RusturfTunnel",6,"theft",say("海洋队手下","前面是条死路……连这只长翅鸥也派不上用场！"),battle("GRUNT_RUSTURF_TUNNEL","海洋队手下"),item("DEVON_GOODS"),say("哈奇老人","小皮！原来你在这儿。小悠，要坐船就来海边的小屋找我。"))
st("devon_invite","RustboroCity",9,"peeko",say("得文研究员","包裹总算找回来了。社长想亲自谢谢你，请跟我到三楼。"),warp("RustboroCity_DevonCorp_3F",14,5))
st("devon","RustboroCity_DevonCorp_3F",3,"devon_invite",say("兹伏奇社长","这封信请交给武斗镇附近的大吾，得文的物品请送到凯那市的造船厂。","这台宝可导航送给你。要渡海，可以找哈奇老人帮忙。"),item("LETTER"),item("POKENAV"))
st("dewford","Route104_MrBrineysHouse",1,"devon",say("哈奇老人","原来要送信！小皮，我们开船去武斗镇！"),warp("DewfordTown",11,9))
badge(2,"DewfordTown_Gym",1,"dewford","滕树","BRAWLY_1","拳击徽章","BULK_UP","来吧！我的拳法是在海浪里磨练出来的！","你们没有被浪头打倒。收下拳击徽章吧。")
st("letter","GraniteCave_StevensRoom",1,"devon dewford",say("大吾","这是父亲托你带来的信？辛苦了。我喜欢来这里寻找珍稀石头。这招钢翼送给你。"),take("LETTER"),{"hoenn_tm":"STEEL_WING"})
st("slateport","DewfordTown",2,"letter",say("哈奇老人","给大吾的信送到了？下一站，凯那市南边的沙滩！"),warp("Route109",22,24))
st("dock","SlateportCity_SternsShipyard_1F",1,"slateport",say("阿渡","包裹是给楠木馆长的。他去海洋科学博物馆了，在那儿找找。"))
st("stern","SlateportCity_OceanicMuseum_2F",1,"dock",say("楠木馆长","这就是潜水艇要用的零件！……等等，这些人要干什么？"),battle("GRUNT_MUSEUM_1","海洋队手下"),battle("GRUNT_MUSEUM_2","海洋队手下"),say("水梧桐","住手。海洋孕育了万物，总有一天，你也会明白我们的理想。"),take("DEVON_GOODS"),say("楠木馆长","我收下零件了。有了它，就能继续探索海底。"))
st("may110","Route110",tr_step(33,56,36,57),"stern",say("小遥","小悠，好久不见！给我看看你在海边遇见的新伙伴吧。"),battle("MAY_ROUTE_110_*","小遥"),item("ITEMFINDER"),say("小遥","探宝器能找到埋在附近的道具。我们在紫堇市见！"))
st("wally_mauville","MauvilleCity",6,"may110",say("满充","叔叔，我已经可以和拉鲁拉丝并肩作战了！小悠，请和我打一场！"),battle("WALLY_MAUVILLE","满充"),say("满充","我明白自己还差得很远。我们先回绿荫镇，总有一天我会再向你挑战。"))
badge(3,"MauvilleCity_Gym",1,"wally_mauville","铁旋","WATTSON_1","电力徽章","SHOCK_WAVE","哈哈哈！能走过这些电路，就让我看看你的本事。","真痛快！接下这枚电力徽章。")
st("cozmo_report","FallarborTown_CozmosHouse",2,"badge_3",say("索蓝斯博士的妻子","一群红制服的人找过他。他们说要去西南边的流星瀑布找陨石。"))
st("meteor_falls","MeteorFalls_1F_1R",tr_step(14,18),"badge_3",say("索蓝斯博士","我以为他们会把陨石交给我研究……"),say("熔岩队手下","陨石到手！趁海洋队赶来之前，回烟囱山启动机器！"),say("水梧桐","我们追！他们要是动了火山，海和陆地都会受影响。"))
st("chimney_tabitha","MtChimney",3,"meteor_falls",say("火村","别想靠近山顶的装置！"),battle("TABITHA_MT_CHIMNEY","火村"))
st("chimney","MtChimney",2,"chimney_tabitha",say("赤焰松","陨石能唤醒沉睡在火山里的力量。只要扩大大地，人类与宝可梦就有了新的家。"),battle("MAXIE_MT_CHIMNEY","赤焰松"),say("赤焰松","竟然失败了。撤退！"),say("水梧桐","火山恢复平静了。谢谢你，小悠。"))
machine=next(t for t in maps["MtChimney"]["bg_events"] if "MeteoriteMachine" in t.get("script",""))
st("meteorite","MtChimney",bg(machine["x"],machine["y"]),"chimney",say("小悠","关闭的机器里有一块暗色的陨石。"),item("METEORITE"))
st("meteorite_return","FallarborTown_CozmosHouse",1,"meteorite",say("索蓝斯博士","这正是被抢走的那块陨石！请收下这枚报恩的招式学习器。"),take("METEORITE"),{"hoenn_tm":"RETURN"})
badge(4,"LavaridgeTown_Gym_1F",1,"chimney","亚莎","FLANNERY_1","烈焰徽章","OVERHEAT","第一次当馆主也好，我一定要用自己的方式战斗！","这份对搭档的信任……我也要学着相信自己。")
st("goggles","LavaridgeTown","enter","badge_4",say("小遥","你打赢了釜炎道馆？这些防沙护目镜给你，戴上就可以走进111号道路的沙漠了。"),item("GO_GOGGLES"))
badge(5,pg,1,"father_challenge badge_1 badge_2 badge_3 badge_4","千里","NORMAN_1","天秤徽章","FACADE","你真的集齐四枚徽章了。现在站在你面前的是橙华道馆馆主。来吧，小悠！","我输了。作为对手我很不甘心，作为父亲，我很为你高兴。满充的爸爸在等你。")
st("surf","PetalburgCity_WallysHouse",1,"badge_5",say("满充的爸爸","满充交到伙伴，多亏了你和千里先生。这枚冲浪，可以带你渡过118号道路的河。"),item("HM_SURF"))
st("steven118","Route118",tr_step(42,7,48,14),"surf",say("大吾","又见面了，小悠。培育喜欢的宝可梦，和不同的搭档一起生活，这也许正是训练家的意义。"))
wi="Route119_WeatherInstitute_2F"
st("weather",wi,3,"surf",say("阿泉","天气研究所的研究成果关系到海洋队的计划。你又来坏我们的事？"),battle("SHELLY_WEATHER_INSTITUTE","阿泉"),say("海洋队手下","紧急消息！熔岩队已经赶往送神山。"),say("阿泉","什么？全体撤退！"))
st("castform",wi,5,"weather",say("研究员","谢谢你救下研究所。这只飘浮泡泡会随天气改变模样，请带它一起旅行。"),{"give_mon":{"species":351,"level":25}})
st("may119","Route119",tr_step(25,31,27,32),"weather",say("小遥","咦，你已经走到这里了？来试试我的新阵容！"),battle("MAY_ROUTE_119_*","小遥"),item("HM_FLY"),say("小遥","这招飞翔给你。赢下茵郁道馆后，就能飞回去过的城镇。"))
st("scope","Route120",31,"may119",say("大吾","桥上有东西挡着路。用得文观测镜看看吧！"),{"battle":{"name":"变隐龙","wild":True,"team":[{"species":352,"level":30}]}},item("DEVON_SCOPE"),say("大吾","这副观测镜归你了。茵郁道馆前也许有同样的障碍。"))
st("fortree_clear","FortreeCity",7,"scope",say("小悠","透过得文观测镜看见了一只变隐龙！它被发现了，悄悄让开了路。"))
badge(6,"FortreeCity_Gym",1,"fortree_clear","娜琪","WINONA_1","白羽徽章","AERIAL_ACE","我和鸟宝可梦一起在丰缘的天空修行。让我见识你的飞翔吧。","这座道馆承认你和搭档的实力。收下白羽徽章。")
st("aqua121","Route121",tr_step(25,5,26,9),"weather",say("海洋队手下","收到命令！全队出发，去送神山！"),{"flag":"h_aqua121"},repeat=True)
st("lilycove_may","LilycoveCity",17,"may119",say("小遥","巧遇！在进百货商店之前，要不要再比一次？"),battle("MAY_LILYCOVE_*","小遥"),say("小遥","我想先回未白镇，陪爸爸继续完成图鉴。"))
st("pyre","MtPyre_Summit",tr_step(22,7,25,8),"weather may119",say("水梧桐","赤焰松带走了蓝色宝珠。那么，这颗红色宝珠就是海洋队的了！去凯那市！"),say("老奶奶","守了这么久的两颗宝珠，还是都被带走了……刚才那些人好像落下了什么。"))
st("emblem","MtPyre_Summit",3,"pyre",say("老奶奶","这是先来那群人掉下的熔岩标志。请你收下吧，也许能找到他们的去向。"),item("MAGMA_EMBLEM"))
st("magma_gate","JaggedPass",tr_step(15,17,20,22),"emblem",say("小悠","熔岩标志在震动！山壁传来低响，石门露了出来。"))
st("magma_tabitha","MagmaHideout_4F",5,"magma_gate",say("火村","都追到这里来了？我不会让你妨碍老大！"),battle("TABITHA_MAGMA_HIDEOUT","火村"))
st("groudon","MagmaHideout_4F",6,"magma_tabitha",say("赤焰松","沉眠于岩浆中的固拉多，以蓝色宝珠的力量苏醒吧！","等等……你要去哪里？是你搞的鬼吗，小悠！"),battle("MAXIE_MAGMA_HIDEOUT","赤焰松"),say("赤焰松","蓝色宝珠怎么会无法控制它？我们必须追上固拉多。"))
st("stern_interview","SlateportCity",11,"groudon",say("楠木馆长","我们在128号水路的海底发现了洞窟。海渊一号终于可以出航了。"),say("广播里的声音","谢谢你准备好的潜水艇，楠木馆长！"),say("楠木馆长","那个声音……从船厂里传来的！"))
st("sub_stolen","SlateportCity_Harbor",4,"stern_interview",say("水梧桐","海渊一号由我们接收了！有胆量就到水静市的基地来找我。"),say("楠木馆长","他们把潜水艇开走了。小悠，拜托你了！"))
st("hideout","AquaHideout_B2F",1,"sub_stolen",say("阿潮","老大正在准备出发。我奉命在这里陪你玩玩！"),battle("MATT","阿潮"),say("阿潮","我输了。可潜水艇已经开走了！往深海去找吧，哈哈！"))
badge(7,"MossdeepCity_Gym",1,"hideout","枫和南","TATE_AND_LIZA_1","心灵徽章","CALM_MIND","我们不用说话，就知道彼此在想什么。让你见识我们的默契！","你和宝可梦的心意也是相通的呢。收下心灵徽章吧！")
space="MossdeepCity_SpaceCenter_2F"
st("rocket","MossdeepCity","enter","badge_7",say("熔岩队手下","去宇宙中心！老大要用那里的火箭燃料。"))
space1="MossdeepCity_SpaceCenter_1F"
st("space_stairs",space1,9,"rocket",say("熔岩队手下","楼上正在办事，别想打扰老大！"),battle("GRUNT_SPACE_CENTER_2","熔岩队楼梯守卫"),{"hoenn_actor_walk":{"id":9,"stairs":True}})
st("space_grunts",space,"enter","space_stairs",{"hoenn_challenge":True},
   battle("GRUNT_SPACE_CENTER_5","熔岩队手下"),{"hoenn_actor_walk":{"id":6,"path":"D"}},
   battle("GRUNT_SPACE_CENTER_6","熔岩队手下"),{"hoenn_actor_walk":{"id":5,"path":"L"}},
   battle("GRUNT_SPACE_CENTER_7","熔岩队手下"),{"hoenn_actor_walk":{"id":7,"path":"R"}})
st("space",space,4,"space_grunts",say("大吾","小悠，和我一起保护宇宙中心！"),say("赤焰松","既然宝珠没用，就把燃料投入烟囱山的火山口！"),{"battle":{"name":"赤焰松和火村","emerald_teams":[team("MAXIE_MOSSDEEP"),team("TABITHA_MOSSDEEP")],"ally":"steven"}},say("赤焰松","扩大陆地，真的是对人类和宝可梦好吗？……我得想想。"),say("大吾","多谢帮忙。到我在绿岭市西北的家里来一趟吧。"))
st("dive","MossdeepCity_StevensHouse",1,"space",say("大吾","你能在深蓝色的海域潜水，从水底找到他们的去向。这枚潜水交给你。"),item("HM_DIVE"))
st("kyogre","SeafloorCavern_Room9",tr_step(17,42),"dive hideout",say("水梧桐","在海底沉睡了这么久！盖欧卡，让海洋恢复它应有的辽阔吧！"),battle("ARCHIE","水梧桐"),say("水梧桐","红色宝珠自己发光了……怎么回事？这场暴雨根本停不下来！"),say("赤焰松","你现在明白了吗？海洋和大地都不能任我们支配！"),{"flag":"h_kyogre"},warp("Route128",38,22))
st("duel","SootopolisCity","enter","kyogre",say("琉璃市居民","一下烈日，一下暴雨……固拉多和盖欧卡在湖中央对峙！"),say("小悠","大吾站在湖西岸，在等我过去。"))
st("origin","SootopolisCity",7,"duel",say("大吾","传说中能安抚它们的宝可梦，会在世界面对危机时出现。米可利在觉醒祠堂等你。"),warp("CaveOfOrigin_Entrance",9,20))
st("wallace_origin","CaveOfOrigin_B1F",1,"origin",say("米可利","有一只宝可梦，能平息固拉多和盖欧卡。你觉得烈空坐现在会在哪里？"),{"hoenn_pillar_choice":True},say("米可利","天空之柱！对，我也这样想。我们在131号水路见。"))
st("pillar","SkyPillar_Outside",1,"wallace_origin",say("米可利","天色越来越不对了。天空之柱的大门已经打开，拜托你去顶端唤醒烈空坐！"))
st("rayquaza","SkyPillar_Top",tr_step(14,9),"pillar",{"hoenn_actor_walk":{"id":1,"path":"UUUUU"}},say("小悠","塔顶的烈空坐睁开了双眼。它腾空而起，朝琉璃市飞去了！"))
st("peace","SootopolisCity","enter","rayquaza",{"hoenn_weather_scene":True},say("小悠","烈空坐从云层间俯冲而下。吼声传遍湖面，固拉多和盖欧卡停了下来。","一只沉入大地，一只回到海里。风雨平息，烈空坐消失在云端。"))
st("maxie_peace","SootopolisCity",16,"peace",say("赤焰松","我以为扩大大地就能造福大家。直到今天，我才明白人类的力量有多渺小。"))
st("archie_peace","SootopolisCity",17,"peace",say("水梧桐","海与大地原本就在互相支撑。差点毁掉我想要保护的世界……我要回送神山归还宝珠。"))
st("teams_leave","SootopolisCity","enter","maxie_peace archie_peace",{"hoenn_actor_walk":{"id":16,"path":"UU"}},{"hoenn_actor_walk":{"id":17,"path":"UU"}},say("小悠","赤焰松和水梧桐离开了道馆前的湖岸。"))
st("waterfall","SootopolisCity",18,"teams_leave",say("米可利","我们把世界从灾难边缘拉了回来，谢谢你。攀瀑交给你，道馆里的亚当正在等你。"),item("HM_WATERFALL"),{"hoenn_actor_walk":{"id":18,"gym_door":True}})
badge(8,"SootopolisCity_Gym_1F",1,"waterfall","亚当","JUAN_1","雨滴徽章","WATER_PULSE","你对宝可梦的指挥，能像水一样刚柔并济吗？","多么优雅的一战！雨滴徽章能让你越过瀑布，抵达彩幽市。")
st("wally_road","VictoryRoad_1F",tr_step(2,23,4,24),"badge_8",say("满充","小悠，你还记得我们第一次一起走进草丛吗？我的伙伴们带我走到了这里。请认真和我对战！"),battle("WALLY_VR_1","满充"),say("满充","尽管输了，我还会继续前进。你一定要挑战联盟成功！"))
all_badges=" ".join("badge_"+str(i) for i in range(1,9))
st("league","EverGrandeCity_PokemonLeague_1F",3,all_badges+" wally_road",say("联盟守卫","八枚丰缘徽章均已确认。穿过这道门，挑战四天王和冠军吧！"))
previous="league"
for id,room,who,intro,after in [
        ("sidney","SidneysRoom","花月","终于见到你了！痛痛快快地战一场吧！","好样的！让下一位天王见识你的本领吧。"),
        ("phoebe","PhoebesRoom","芙蓉","我在送神山修行，学会了与幽灵宝可梦沟通。你和伙伴又有怎样的默契呢？","真是深厚的羁绊。我认输了。"),
        ("glacia","GlaciasRoom","波妮","我远道而来，在丰缘的炎热气候中磨炼冰之力量。","你有着足以融化坚冰的热情。请继续前进。"),
        ("drake","DrakesRoom","源治","训练家必须明白自己的宝可梦想要什么。证明给我看！","你明白什么是与宝可梦并肩战斗。冠军在等你。"),
        ("wallace","ChampionsRoom","米可利","我们在琉璃市见证过奇迹。现在，作为丰缘联盟冠军，我接受你的挑战！","恭喜你，小悠！从今天起，你和伙伴们就是丰缘的新冠军。")]:
    room="EverGrandeCity_"+room
    actions=[say(who,intro),battle(id.upper(),who),say(who,after)]
    if id=="wallace": actions.extend([{"flag":"h_wallace"},warp("EverGrandeCity_HallOfFame",7,16)])
    st(id,room,1,all_badges+" "+previous,*actions)
    previous=id
st("champion","EverGrandeCity_HallOfFame","enter","wallace",say("米可利","这里记载着超越联盟的训练家和他们的搭档。让我把你们的名字刻在丰缘的历史里。"),{"hall_of_fame":"hoenn"},{"hoenn_hall_team":True},{"heal":True},{"flag":"h_champion"},warp(home,5,7))
st("ticket",home,"enter","champion",say("千里","这是哈奇先生留下的船票。水流号已经开航，凭它可在凯那市和水静市乘船。"),item("SS_TICKET"))
# Object identities are local to a map. A single ID can move between scenes.
actors("LittlerootTown",[4],"started","moved","妈妈")
actors("LittlerootTown",[5],"started","clock")
actors(home,[1],"moved",name="妈妈")
actors(home,[2,3],"moved","clock")
actors(home,[5],"champion","ticket","千里")
actors("LittlerootTown_MaysHouse_2F",[1],"may_appears","may_intro","小遥")
actors("LittlerootTown_MaysHouse_2F",[1],"may_intro","rescued","小遥",[8,2])
actors("LittlerootTown_MaysHouse_2F",[16],"tv","may_intro")
actors("LittlerootTown_MaysHouse_1F",[4],"started",name="小遥的妈妈")
actors("Route101",[2,3,4],"may_intro","rescued")
actors(lab,[2],"rescued",name="小田卷博士")
actors(lab,[3],"may103",name="小遥")
actors("Route103",[2],"partner","may103","小遥")
actors(pg,[1],"dex","badge_4","千里",[4,107])
actors(pg,[1],"badge_4",name="千里")
actors(pg,[10],"wally_outing","wally_catch","满充",[5,108])
actors("PetalburgWoods",[3,4],"father_challenge","woods")
actors("RustboroCity",[9],"theft","devon_invite","得文研究员")
actors("Route116",[11],"theft","peeko","哈奇老人")
actors("Route116",[21],"started","peeko")
actors("Route116",[21],"peeko","devon",at=[38,10])
actors("RusturfTunnel",[6,7],"theft","peeko")
actors("RustboroCity_DevonCorp_3F",[3],"peeko",name="兹伏奇社长")
actors("RustboroCity_DevonCorp_3F",[1],"__disabled")
actors("Route104_MrBrineysHouse",[1,2],"peeko")
actors("Route104",[7],"peeko")
actors("DewfordTown",[2,4],"dewford")
actors("Route109",[1,2],"slateport")
actors("GraniteCave_StevensRoom",[1],"dewford","letter","大吾")
actors("SlateportCity",[5,18,19,26,27,28,29,30,31,32,33],"slateport","dock")
actors("SlateportCity_OceanicMuseum_2F",[1],"dock","stern","楠木馆长")
actors("Route110",[22,23,24,25],"slateport","stern")
actors("Route110",[28],"stern","may110","小遥")
actors("MauvilleCity",[6,7],"dex","wally_mauville")
actors("FallarborTown_CozmosHouse",[1],"meteor_falls",name="索蓝斯博士")
actors("MeteorFalls_1F_1R",[5,6,10],"badge_3","meteor_falls")
actors("MtChimney",[2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,29],"meteor_falls","chimney")
actors("MtChimney",[1],"meteor_falls","chimney","水梧桐")
actors("LavaridgeTown",[8],"badge_4","goggles","小遥")
actors("Route118",[19],"surf","steven118","大吾")
actors("Route119",[23,24],"surf","weather")
actors("Route119",[16],"weather","may119","小遥")
actors(wi,[1,2,3,7,8],"surf","weather")
actors(wi,[5],"weather",name="研究员")
actors("Route120",[31],"may119","scope","大吾")
actors("FortreeCity",[7],"started","fortree_clear")
actors("Route121",[12,13,14],"weather","aqua121 pyre")
actors("LilycoveCity",[17],"may119","lilycove_may","小遥")
actors("MtPyre_Summit",[2,4,5,6,7],"weather","pyre")
actors("MagmaHideout_4F",[5,6,7],"magma_gate","groudon")
actors("SlateportCity",[11],"groudon","stern_interview","楠木馆长")
actors("SlateportCity_Harbor",[4,7],"stern_interview","sub_stolen")
actors("AquaHideout_B2F",[1,2,5,6],"sub_stolen","hideout")
actors("LilycoveCity",[10,12,13,14,15],"pyre","hideout")
actors("MossdeepCity",[10,11,12,13],"badge_7","rocket")
for local,xy in [(1,[3,4]),(3,[1,9]),(4,[1,6]),(5,[0,8])]:
    actors(space1,[local],"started","rocket")
    actors(space1,[local],"rocket","space",at=xy)
    actors(space1,[local],"space")
actors(space1,[6,7,8,9],"rocket","space")
actors(space,[4,8,9],"rocket","space")
for local,xy in [(5,[11,2]),(6,[13,4]),(7,[15,2])]:
    actors(space,[local],"rocket","space_grunts")
    actors(space,[local],"space_grunts","space",at=xy)
actors("MossdeepCity_StevensHouse",[1],"space","dive","大吾")
actors("SeafloorCavern_Room9",[7],"dive","kyogre")
actors("SootopolisCity",[1],"started","origin","守祠长老")
actors("SootopolisCity",[1],"origin","peace","守祠长老",[30,18])
actors("SootopolisCity",[1],"peace",name="守祠长老")
actors("SootopolisCity",[7],"kyogre","origin","大吾")
actors("SootopolisCity",[7],"origin","peace","大吾",[32,18])
actors("SootopolisCity",[9,10],"kyogre","peace")
actors("SootopolisCity",[11],"rayquaza scene","peace")
actors("SootopolisCity",[16,17],"duel","peace")
actors("SootopolisCity",[16],"peace","teams_leave","赤焰松",[33,35])
actors("SootopolisCity",[17],"peace","teams_leave","水梧桐",[34,35])
actors("SootopolisCity",[7],"peace",name="大吾",at=[29,33])
actors("SootopolisCity",[18],"peace","waterfall","米可利",[31,33])
actors("SootopolisCity",[18],"waterfall",name="米可利",at=[32,33])
actors("CaveOfOrigin_B1F",[1],"origin","wallace_origin","米可利")
actors("SkyPillar_Outside",[1],"wallace_origin","pillar","米可利")
actors("SkyPillar_Top",[1],"pillar","rayquaza")
actors("VictoryRoad_1F",[4],"badge_8","wally_road","满充")
actors("EverGrandeCity_ChampionsRoom",[1],"drake",name="米可利")
actors("EverGrandeCity_HallOfFame",[1],"wallace",name="米可利")
# Repeatable original scripted transport. Static doors only cover land travel.
for id,mp,actor,req,to,x,y in [
        ("boat_home","Route104_MrBrineysHouse",1,"dewford","DewfordTown",11,9),
        ("boat_dewford","DewfordTown",2,"dewford","Route104",16,52),
        ("boat_beach","Route109",2,"slateport","DewfordTown",11,9),
        ("cable_up","Route112_CableCarStation",1,"meteor_falls","MtChimney_CableCarStation",6,7),
        ("cable_down","MtChimney_CableCarStation",1,"meteor_falls","Route112_CableCarStation",6,7)]:
    options = [{"name":"烟囱山" if id=="cable_up" else "112号道路","target":warp(to,x,y)["warp"]}] if id.startswith("cable") else [
        {"name":name, "target":warp(dest,ax,ay)["warp"],"require":flag}
        for name,dest,ax,ay,flag in [("武斗镇","DewfordTown",11,9,"h_dewford"),("104号道路","Route104",16,52,"h_dewford"),("凯那海滩","Route109",22,24,"h_slateport")]
        if dest!=mp and (mp!="Route104_MrBrineysHouse" or dest!="Route104")]
    st(id,mp,actor,req,{"hoenn_transport":options},repeat=True)
st("safari_exit","SafariZone_South",1,"started",say("退场服务员","现在要结束探险，回到入口大厅吗？"),
   {"hoenn_transport":[{"name":"退出野生原野区","target":warp("Route121_SafariZoneEntrance",2,5)["warp"]}]},repeat=True)
actors("Route112_CableCarStation",[1],"started",name="缆车乘务员")
actors("MtChimney_CableCarStation",[1],"started",name="缆车乘务员")
# Mandatory warps enforce local flags even on an established multi-region save.
for mp,req,reason in [
    ("Route101","may_intro","隔壁的小遥还没见过你。先去她家二楼打个招呼吧。"),
    ("OldaleTown","rescued","博士还在101号道路求救！背包里有精灵球。"),
    ("Route102","dex","小田卷博士正在研究所等你。"),
    ("MauvilleCity_Gym","wally_mauville","满充想在道馆门前和你比一场。"),
    ("MtChimney","meteor_falls","熔岩队封锁了山路。先去流星瀑布。"),
    ("LavaridgeTown_Gym_1F","chimney","先阻止烟囱山顶的熔岩队。"),
    ("FortreeCity_Gym","fortree_clear","有什么东西挡在道馆前的那条路上。"),
    ("CaveOfOrigin_Entrance","origin","入口由长老守护。先与湖西岸的大吾交谈。"),
    ("SkyPillar_1F","pillar","天空之柱的大门紧闭。米可利知道开启的方法。"),
    ("SootopolisCity_Gym_1F","waterfall","道馆仍未开放。米可利在琉璃市等你。"),
    ("MossdeepCity_Gym","hideout","水静市海洋队基地的潜水艇尚未出港。"),
    ("MagmaHideout_1F","magma_gate","山壁上有熔岩队的标志。"),
    ("AquaHideout_1F","sub_stolen","入口被海洋队把守。去凯那市港口看看。"),
    ("MossdeepCity_SpaceCenter_2F","space_stairs","熔岩队手下堵在楼梯口。"),
    ("SeafloorCavern_Entrance","dive","先在绿岭市拿到潜水，追踪被盗的潜水艇。"),
    ("VictoryRoad_1F","badge_8","取得丰缘雨滴徽章，才能攀上彩幽市的瀑布。")]:
    gate(mp,req,reason)
for i,(room,flag) in enumerate([("SidneysRoom","league"),("PhoebesRoom","sidney"),("GlaciasRoom","phoebe"),
        ("DrakesRoom","glacia"),("ChampionsRoom","drake"),("HallOfFame","wallace")]):
    gate("EverGrandeCity_"+room,all_badges+" "+flag,"请先通过丰缘联盟的徽章检查，并按顺序战胜前一位训练家。")
    if i<5: gate("EverGrandeCity_Hall"+str(5 if i==0 else i),all_badges+" "+flag,"丰缘联盟尚未向你开启下一道门。")

for e in events:
    if e["trigger"]["kind"]=="talk":
        t=e["trigger"]; entries=cast.get(e["map"],{}).get(str(t["actor"]),[])
        for row in entries:
            if set(row["require"])<=set(e["require"]):
                t["at"]=row["at"]
    for a in e["steps"]:
        if "hoenn_tm" in a: a["hoenn_tm"]=moves[a["hoenn_tm"].replace("_","")]
# The same object plays Norman in the lobby and in his official battle room.
for e in events:
    if e["id"] in ("h_wally_intro","h_father_challenge"): e["trigger"]["at"]=[4,107]
    if e["id"]=="h_maxie_peace": e["trigger"]["at"]=[33,35]
    if e["id"]=="h_archie_peace": e["trigger"]["at"]=[34,35]
    if e["id"]=="h_badge_7": e["steps"][1]["battle"]["double"]=True
    if e["id"]=="h_space":
        for step in e["steps"]:
            if "battle" in step: step["battle"]["double"]=True
jagged=json.loads((ROOT/"content/hoenn_native/maps/em_jagged_pass.json").read_text())
layout=source/"data/layouts/JaggedPass/map.bin"
raw=layout.read_bytes()
blocks=struct.unpack(f"<{len(raw)//2}H",raw)
closed_i=next(i for i,b in enumerate(blocks) if b & 1023 == 0x274)
art=jagged["hoenn_art"]
layers=[]
for key in ("t","a"):
    layer=zlib.decompress(base64.b64decode(art[key]))
    layers.append(struct.unpack(f"<{len(layer)//2}H",layer))
def tile(x,y,i,collision):
    return [x,y,layers[0][i],layers[1][i],collision]
wall={"closed":[tile(16,y,closed_i,1) for y in (17,18)],
      "open":[tile(16,y,y*jagged["size"][0]+16,1 if y==17 else 0) for y in (17,18)]}
steven_src=(source/"src/battle_tower.c").read_text().split("static const sStevenMons[MULTI_PARTY_SIZE] =",1)[1].split("};",1)[0]
steven=[]
for row in steven_src.split(".species = SPECIES_")[1:]:
    steven.append({"species":species[row.split(",",1)[0]],"level":int(re.search(r"\.level = (\d+)",row)[1]),"moves":[moves[m.replace("_","")] for m in re.findall(r"MOVE_(\w+)",row)]})
assert len(steven)==3
actor_catalog=json.loads((ROOT/"content/hoenn_native/maps"/(index[maps["PetalburgCity"]["id"]]+".json")).read_text())
wally=next(n for n in actor_catalog["npcs"] if n.get("source_gfx")=="OBJ_EVENT_GFX_WALLY").copy()
wally.update(at=[6,5],facing="up",name="满充",role="h_tutorial_wally")
# These original story scripts change groups across maps, including the Route 112
# cable car guards, weather institute scientists, Space Center staff and Wailmer.
scene_scripts={
    "moved":("LittlerootTown","StepOffTruckMale GoInsideWithMom"),
    "rescued":("Route101","BirchsBag HideMayInBedroom"),
    "partner":(lab,"AgreeToSeeRival"),
    "may103":("Route103","RivalEnd"),
    "wally_outing":(pg,"BeginWallyTutorial"),
    "wally_catch":(pg,"ReturnFromWallyTutorial"),
    "theft":("RustboroCity","StolenGoodsScene"),
    "peeko":("RusturfTunnel","Grunt"),
    "devon_invite":("RustboroCity","ReturnGoods"),
    "devon":("RustboroCity_DevonCorp_3F","MeetPresident"),
    "dock":("SlateportCity_SternsShipyard_1F","Dock"),
    "stern":("SlateportCity_OceanicMuseum_2F","CaptStern"),
    "wally_mauville":("MauvilleCity","DefeatedWally"),
    "meteor_falls":("MeteorFalls_1F_1R","MagmaStealsMeteoriteScene"),
    "chimney":("MtChimney","Maxie"),
    "goggles":("LavaridgeTown","RivalExit ShowMtChimneyTrainers"),
    "badge_5":(pg,"NormanBattle WallysDadArrives"),
    "weather":(wi,"ShellyDefeated"),
    "may119":("Route119","MoveInstituteWorkersDownstairs"),
    "lilycove_may":("LilycoveCity","DefeatedMay"),
    "pyre":("MtPyre_Summit","TeamAquaExits"),
    "groudon":("MagmaHideout_4F","Maxie"),
    "sub_stolen":("SlateportCity_Harbor","AquaEscapeScene"),
    "hideout":("AquaHideout_B2F","SubmarineEscape"),
    "badge_7":("MossdeepCity_Gym","TateAndLizaDefeated"),
    "space":(space,"DefeatedMaxieTabitha"),
    "kyogre":("SeafloorCavern_Room9","ArchieAwakenKyogre"),
    "wallace_origin":("CaveOfOrigin_B1F","AtSkyPillar"),
    "teams_leave":("SootopolisCity","MaxieArchieLeave"),
}
visibility=[]
for stage,(mapname,labels) in scene_scripts.items():
    scripts=(source/"data/maps"/mapname/"scripts.inc").read_text()
    state={}
    for label in labels.split():
        block=re.search(r"^"+re.escape(mapname+"_EventScript_"+label)+r"::?\n((?:\t[^\n]+\n)+)",scripts,re.M)[1]
        for cmd,key in re.findall(r"\b(setflag|clearflag) (FLAG_HIDE_\w+)",block):
            if key!="FLAG_HIDE_MAP_NAME_POPUP": state[key]=cmd=="setflag"
    visibility.append({"flag":"h_"+stage,"changes":state})
league_back={}
for room in ("SidneysRoom","PhoebesRoom","GlaciasRoom","DrakesRoom","ChampionsRoom"):
    name="EverGrandeCity_"+room
    mid=index[maps[name]["id"]]
    league_back[mid]=index[maps[name]["warp_events"][0]["dest_map"]]
out={"league_back":league_back,"source_visibility":visibility,"tutorial_wally":wally,"steven":steven,"jagged":wall,"events":events,"actors":cast,"gates":gates,"teams":teams}
(ROOT/"content/hoenn_campaign.json").write_text(json.dumps(out,ensure_ascii=False,indent=1)+"\n")
print(f"Compiled {len(events)} events, {len(teams)} trainer parties and {len(gates)} map gates")
