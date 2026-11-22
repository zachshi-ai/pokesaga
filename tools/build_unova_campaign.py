#!/usr/bin/env python3
"""Compile the Black / Black 2 chapter, using normal-mode trainer records extracted from the games.

Download trainers/black_white.js and trainers/black2_white2.js from
https://github.com/Scotts-Thoughts/pokemon-data/tree/96107bb60fc031b699602483ce67fe201443af1d
into a directory, then pass the directory as the argument. The printed dialogue is an adaptation.
"""
import argparse
import json
import re
import subprocess
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
book = {"events": [], "teams": {}, "gates": {"1": {}, "2": {}}}
era = 1
prior = "u1_started"


def read(name):
    return json.loads((ROOT / "content" / name).read_text())


def norm(name):
    name = name.replace("♀", "f").replace("♂", "m")
    return re.sub(r"[^a-z0-9]", "", unicodedata.normalize("NFKD", name.lower()).encode("ascii", "ignore").decode())


def trainer_file(folder, game, filename):
    p = folder / (filename + ".js")
    if p.exists():
        js = "import fs from 'node:fs';const src=fs.readFileSync(process.argv[1],'utf8');const {trainers}=await import('data:text/javascript;base64,'+Buffer.from(src).toString('base64'));process.stdout.write(JSON.stringify(trainers))"
        return json.loads(subprocess.check_output(["node", "--input-type=module", "-e", js, str(p)]))
    return json.loads((folder / (game + ".json")).read_text())


def mon(species, level, moves, held=None, ability=None):
    species_name = species.split(" (")[0]
    out = {"species": species_ids[norm(species_name)], "level": level, "moves": [move_ids[norm(m)] for m in moves]}
    if held:
        out["held"] = norm_item(held)
    if ability and norm(ability) in ability_ids:
        out["ability"] = ability_ids[norm(ability)]
    return out


def norm_item(held):
    return re.sub(r"[^A-Z0-9]+", "_", held.upper()).strip("_")


def team(n):
    if isinstance(n, str):
        return n
    key = f"{era}/{n}"
    if key not in book["teams"]:
        row = originals[era][str(n)]
        book["teams"][key] = [mon(m["species"], m["level"], m["moves"], m.get("held_item"), m.get("ability")) for m in row["party"]]
    return key


def fight(who, trainer, *, other=None, ally=None, variants=False, **cfg):
    if variants:
        cfg["u_variants"] = [team(i) for i in trainer]
    else:
        cfg["u_teams"] = [team(trainer)]
    if other is not None:
        cfg["u_teams"].append(team(other))
        cfg["double"] = True
    if ally:
        cfg.update(ally="unova", u_ally=[team(i) for i in ally])
    return {"battle": dict(name=who, unova_era=era, **cfg)}


def rival(who, first, **cfg):
    return fight(who, range(first, first + 3), variants=True, **cfg)


def say(who, text):
    return {"who": who, "say": [text]}


def item(name, count=1, category="key"):
    if category=="key":
        return {"unova_key":name}
    return {"give_item": {"name": name, "count": count, "category": category}}


def machine(n, hm=False):
    return {"unova_hm" if hm else "unova_tm": n}


def warp(mid, at=None, facing="down"):
    action={"unova_warp":mid}
    if at is not None:action.update(at=at,facing=facing)
    return action


def flag(key):
    return key if key.startswith(("u1_", "u2_")) else f"u{era}_{key}"


def event(key, place, who, text, *actions, guests=(), need=None, route=True, resident=False, automatic=False, style=None):
    global prior
    ident = flag(key)
    requirements = [prior] if need is None else [flag(n) for n in need.split()]
    steps = ([say(who, text)] if text else []) + list(actions)
    # Set the checkpoint before a script changes maps, so gates see the new state.
    finish = {"flag": ident}
    if steps and "unova_warp" in steps[-1]:
        steps.insert(-1, finish)
    else:
        steps.append(finish)
    row = {"id": ident, "map": "unova_" + place, "era": era, "require": requirements,
           "trigger": {"kind": "enter" if automatic else "talk", "actor": ident}, "who": who, "steps": steps, "route": route}
    if guests:
        row["guests"] = list(guests)
    if resident:
        row["resident"] = True
    if style:
        row["style"] = style
    book["events"].append(row)
    if route:
        prior = ident
    return row


def gate(need, places, hint):
    for place in places.split():
        book["gates"][str(era)]["unova_" + place] = {"require": [flag(k) for k in need.split()], "message": hint}


def gym(index, city, who, badge, tm, record, intro, ending):
    event(f"badge_{index}", ("bw" if era == 1 else "b2") + "_gym_" + city, who, intro,
          fight(who, record, variants=isinstance(record, (list, tuple))), say(who, ending),
          {"unova_badge": badge}, *([machine(tm)] if tm else []), resident=True)


def elite(key, branch, levels):
    req = [flag(key)]
    for (local, who, line), trainer in zip([
        ("shauntal","婉龙","我总想把这样的相遇写进书里。今天，你来翻开新的一页吧。"),
        ("grimsley","越橘","赌局里要懂得接受输赢。对战也一样，让我们看看你会怎么出牌。"),
        ("caitlin","嘉德丽雅","能让我睁开眼睛的挑战者并不多。请你和伙伴一起，使出全力。"),
        ("marshal","连武","我从阿戴克师父身上学到，强大没有终点。让我领教你的本事！")], levels):
        event(branch+local,"e4_"+local,who,line,fight(who,trainer),need=key,route=False)
    return " ".join(branch+s for s in ("shauntal","grimsley","caitlin","marshal"))


def black():
    global prior
    event("first_battle","bw_home_2f","白露","博士的礼物送来了！盒子里有三个球。小悠，你先挑，我和黑连再选。",
          {"unova_starter":1},say("白露","它愿意跟我一起冒险！来，让我们的伙伴打一场见面赛！"),
          rival("白露",59,unova_starter_only=1,finish_on_loss=True),{"heal":True},guests=["黑连"])
    event("cheren_home","bw_home_2f","黑连","房间乱成这样了……先替大家恢复体力。小悠，接下来该轮到我们了。",
          rival("黑连",53,unova_starter_only=1,finish_on_loss=True),{"heal":True},guests=["白露"])
    event("watch","bw_home_1f","妈妈","我听到楼上的动静了。你们去见红豆杉博士吧，房间交给我。这只即时通讯器带上。",
          item("即时通讯器"))
    event("bianca_home","bw_bianca_home","白露","爸爸，我知道你担心我。我想自己走走看看。黑连和小悠都在等我，我会小心的。",guests=["白露的爸爸"])
    event("dex","juniper_lab","红豆杉博士","我想知道合众究竟住着多少宝可梦。你、黑连和白露愿意替我记录亲眼见到的伙伴吗？",
          item("合众图鉴"),say("妈妈","路上会用得着这张地图。三个人一起迈出第一步吧。"),item("城镇地图"),guests=["黑连","白露"])
    event("catch","1","红豆杉博士","先观察，再削弱它的体力，最后投球。这里有五个精灵球，剩下的就让你自己来试试。",item("精灵球",5,"ball"))
    event("rally","accumula","魁奇思","人们说自己爱宝可梦，可是谁听过它们的想法？等离子队要求诸位解放它们。",
          say("N","你身边的宝可梦在说话。我想听得更清楚一点……和我对战吧。"),fight("N",64),guests=["N","黑连"])
    event("shoes","2","妈妈","终于追上你了。这是跑步鞋！有了它，就能更快赶上朋友们了。",item("跑步鞋"))
    event("bianca_2","2","白露","想知道我们出发后进步了多少吗？让宝可梦告诉我们吧！",
          rival("白露",498))
    event("school","striaton_school","黑连","我在训练家学校研究道具。让我看看，你找到的伙伴都擅长什么。",rival("黑连",287))
    event("monkey","dreamyard","培育家","你最先得到的伙伴有不擅长的属性。这孩子正好可以补上它的弱点，要一起旅行吗？",
          {"unova_monkey":True},need="school",route=False)
    gym(1,"striaton","三曜道馆馆主","三元徽章",83,[11,13,12],"三曜道馆有三位馆主。今天由擅长你伙伴弱点属性的那一位接受挑战！","赢得漂亮！三元徽章和自我激励就交给你了。")
    event("cut","striaton","真菰","我正在研究梦的力量。请到梦之遗址找食梦梦；细树挡路时，让伙伴用居合斩。",machine(1,True))
    event("dream_mist","dreamyard","白露","听，那只食梦梦在叫！你们为什么要伤害它？",
          fight("等离子队队员",80),fight("等离子队队员",309),say("真菰","梦梦蚀带走了孩子，留下了梦之烟。这就是我需要的研究材料。"),guests=["等离子队队员","真菰"],need="cut dreamyard_cut")
    event("cgear","fennel_lab","真菰","有了梦之烟，研究终于能继续了。用 C 装置查看自己的伙伴和合众的行程吧。",item("C 装置"),guests=["松露"])
    event("route3","3","黑连","两个人都有了徽章，那就再来一场。",rival("黑连",56),
          say("白露","刚才那两个人抢走了小女孩的宝可梦！他们往地下水脉之穴去了。"),guests=["白露"])
    event("wellspring","wellspring","黑连","失主在等着我们。把宝可梦还回来！",fight("等离子队队员",294),
          fight("等离子队队员",62,other=63,ally=[56,57,58]),guests=["等离子队队员"])
    event("n_museum","nacrene","N","我想看见朋友们心里的世界。你的伙伴会说什么呢？",fight("N",65))
    gym(2,"nacrene","芦荟","基础徽章",67,21,"书架的尽头就是我的研究室。自己的战术被读透了，还能想出第二步吗？","你的基础打得很好。这枚徽章和报仇学习器属于你。")
    event("fossil_theft","museum","木立","馆长！等离子队进了展厅，那只快龙骨架的头被拿走了！",
          say("亚堤","我往矢车森林去，你跟着林中的小路追。"),guests=["芦荟","亚堤"])
    event("dowsing","nacrene","白露","前面就要进矢车森林了。我送你一台探宝器，能找到埋在身边的道具。",item("探宝器"),guests=["黑连"])
    event("skull","pinwheel","等离子队队员","我再拖你一会儿，贤人就能带走龙骨。",fight("等离子队队员",295),fight("等离子队队员",296),fight("等离子队队员",297),
          say("阿苏拉","这副骨头与我们寻找的传说不同。留下它，撤退。"),item("龙之骨"),guests=["阿苏拉"])
    event("skull_back","pinwheel","芦荟","这正是博物馆失去的龙骨。谢谢你，这颗月之石送给你。",{"remove_item":"龙之骨"},item("月之石",1,"evo"),guests=["亚堤"])
    event("port","castelia","白露","我的食梦梦被抢走了……艾莉丝，多亏你一直陪着我。",say("艾莉丝","他们跑向道馆那条街了！"),guests=["艾莉丝","亚堤"])
    event("munna_back","castelia_plasma","亚堤","前面那栋楼就是。你负责门口的一个，我来对付另外的人！",fight("等离子队队员",279),
          say("魁奇思","在这座城继续争执毫无益处。把那只食梦梦还给她。"),guests=["魁奇思","白露"])
    gym(3,"castelia","亚堤","甲虫徽章",76,22,"看啊，虫宝可梦也是艺术家。它们编织的战术可藏不住热情！","让它跟着你旅行吧。这是甲虫徽章和虫之抵抗。")
    event("bianca_gate","castelia_gate_north","白露","在连接四号道路的北门过一招吧！这次我想靠自己的力量再试试。",rival("白露",507))
    event("cheren_4","4","黑连","沙暴会改变对战的节奏，能让我看看你的应对吗？",rival("黑连",403))
    event("bike","nimbasa","培育屋爷爷","他们想从培育屋夺走宝可梦！",fight("等离子队队员",81),say("培育屋爷爷","这辆自行车给你，终于可以安心回去照顾孩子们了。"),item("自行车"))
    event("musical","bw_zone_77","白露","我也想试着在舞台上找到自己的长处。你看，馆长给我们准备了道具盒！",item("装饰物盒"))
    event("father","nimbasa","白露的爸爸","白露，跟我回家吧。外出旅行总是让我担心。",
          say("小菊儿","请也听听她自己的想法。她正在寻找想做的事情。"),
          say("白露","爸爸，我想再走走。等我回家，我有很多想讲给你听的故事。"),guests=["白露","小菊儿"])
    event("ferris","nimbasa","N","坐摩天轮吧。从最高处能把这座城市看得很清楚。我是等离子队的王。",fight("N",89),guests=["等离子队队员"])
    gym(4,"nimbasa","小菊儿","伏特徽章",72,23,"聚光灯亮了！能跟上我们伏特替换的节奏吗？","你们的闪耀不输给聚光灯。收好伏特徽章。")
    event("bridge","5","黑连","过桥之前，先检验你我之间的距离吧。",rival("黑连",90),
          say("阿戴克","成为最强之后呢？来，跟这两个孩子打一场，多想想你为什么和宝可梦在一起。"),fight("莎拉与比利",401,other=402,ally=[90,91,92]),say("小菊儿","吊桥已经可以通行了。"),guests=["阿戴克","小菊儿"])
    event("freezer","cold_storage","黑连","冷冻仓库深处的货柜里藏着等离子队。咱们把逃犯找出来！",
          fight("等离子队队员",298),fight("等离子队队员",299),fight("等离子队队员",300),fight("等离子队队员",301),say("菊老大","是维奥和他的手下。事情到这儿由我来管！"),guests=["维奥","菊老大"])
    event("release","driftveil","魁奇思","菊老大，把我的同伴还给我吧。你也不想整座城市为了他们动手。",guests=["菊老大","维奥"])
    gym(5,"driftveil","菊老大","震动徽章",None,24,"矿石只有往深处挖才能见到。把你的本事也给我挖出来！","震动徽章收好了。电气石洞穴入口见，我会替你把路清出来。")
    event("bianca_fly","driftveil","白露","让我看看道馆挑战后的你吧！",rival("白露",491),say("白露","我从家里带了两份飞翔学习器。你也拿一份吧。"),machine(2,True))
    event("web","chargestone","菊老大","这团丝是电蜘蛛留下的。龙头地鼠，把它劈开！我答应过你的重踏也给你。",machine(78))
    event("cave_n","chargestone","N","这些电气石聚在一起，宝可梦却有各自的声音。小悠，我要知道你的答案。",fight("N",218),guests=["红豆杉博士","白露"])
    event("tower","celestial","风露","受伤的宝可梦已经好些了。登上塔顶吧，让天堂之塔的钟声为它送行。")
    gym(6,"mistralton","风露","喷射徽章",62,25,"钟声把你的心意传到了这里。现在，要飞得比谁都高！","喷射徽章和杂技交给你了。七号道路北边通往罗斯山。")
    event("surf","7","黑连","我一直追求强大。阿戴克先生，你说过的答案，我还在找。",rival("黑连",539),
          say("阿戴克","这个是冲浪。山有山路，河有水路。你们的路也该自己去找。"),machine(3,True),guests=["阿戴克"])
    gym(7,"icirrus","哈奇库","冰柱徽章",79,131,"演员卸下妆容之后，就是一名训练家。就用招式来交流吧。","冰柱徽章见证了这一战。冰息会准确击中要害。")
    event("tower_alarm","icirrus","黑暗铁三角","奉王的命令前来。七贤人已向龙螺旋之塔出发。",guests=["哈奇库","黑连"])
    event("dragonspiral","bw_zone_212","等离子队队员","从塔底一路追到这里？我们四个人来拦住你！",*[fight("等离子队队员",n) for n in (303,304,305,306)],
          say("等离子队队员","王就在塔顶。已经来不及了！"))
    event("n_zekrom","bw_zone_213","N","捷克罗姆回应了我。若你也相信自己的道路，就去找能与你并肩的另一条龙。",guests=["捷克罗姆"])
    event("castle_stone","relic","阿戴克","古代城的底层已经找过了。魁奇思，你到底想让小悠做什么？",
          fight("等离子队队员",221),say("魁奇思","让另一条龙醒来的人，就是王要见的人。"),guests=["魁奇思"])
    event("relic_exit","bw_zone_165","阿戴克","走吧。我们到沙漠入口，再听听博士找到的线索。",warp("unova_bw_zone_158",[61,32]),automatic=True)
    event("light_stone","nacrene","芦荟","这块研究不出成分的白石头，原来就是光明石。我们相信它该由你带走。",item("光明石"),guests=["红豆杉博士","阿戴克"])
    event("bianca_8","8","白露","你要去双龙市了吧？出发之前我想再和你认真比一次。",rival("白露",494))
    event("bridge_ghetsis","tubeline_bridge","魁奇思","光明石已经到了你手上。接下来，会是两位英雄面对彼此的时候。",guests=["黑暗铁三角"])
    event("dragons","opelucid_house","夏卡","很久以前，两位追求真实与理想的英雄让一条龙分成了两条。我们愿意把这个故事告诉你。",guests=["艾莉丝"])
    gym(8,"opelucid","夏卡","传说徽章",82,133,"龙与训练家都不能只有力量。拿出你一路选择的答案吧。","八枚徽章都齐了。去挑战宝可梦联盟吧。")
    event("master_ball","opelucid","红豆杉博士","这一路你亲眼见过、亲手记录了许多事。这是大师球，只此一颗，交给你决定如何使用。",item("大师球",1,"ball"))
    event("last_rival","10","黑连","前面就是徽章检查关。最后一次，让我和你尽全力吧！",rival("黑连",588),guests=["白露"])
    event("league","league","联盟向导","八道徽章关都过了。四位天王的房间任你选择，四场全胜才能登上冠军殿堂。",need="last_rival "+" ".join(f"badge_{n}" for n in range(1,9)))
    req=elite("league","",[228,230,231,229])
    event("castle_rises","champion_room","阿戴克","我输了。N，为什么连听伙伴说话的你，也要让大家分离？",
          say("N","我的城堡已同联盟相连。小悠，我在王座前等你和另一位英雄。"),guests=["N"],need=req)
    event("reshiram","ns_castle","N","你的光明石在发光。雷希拉姆，醒来吧！先让它知道你的意志。",{"unova_dragon":True},{"remove_item":"光明石"},guests=["雷希拉姆"])
    event("n_final","ns_castle","N","现在，两位英雄和各自的龙都到了。来决定我们要走的道路吧。",{"heal":True},fight("N",587),guests=["捷克罗姆"])
    event("ghetsis","ns_castle","魁奇思","解放宝可梦？我是要其他人都失去伙伴，只有我能掌握力量！N，你竟然输了！",
          {"heal":True},fight("魁奇思",232),say("黑连","魁奇思由我们带走。N，你自己听到了他们的声音。"),
          say("N","原来宝可梦可以这样相信人类。小悠，你有自己的梦想。向着它走下去吧。再见。"),warp("unova_bw_home_2f"),guests=["N","黑连"])
    # The first visit ends at the castle. The Champion is a new, stronger postgame league.
    req=elite("ghetsis","again_",[563,565,566,564])
    event("alder","champion_room","阿戴克","这回擂台上的冠军是我。让我看看从那个城堡走出来的你和伙伴们！",fight("阿戴克",407),{"unova_hall":"bw"},need=req,route=False)
    event("alder_repeat","champion_room","阿戴克","欢迎回来！带上这回与四天王战斗过的伙伴，再来挑战冠军吧。",fight("阿戴克",407),{"unova_repeat_hall":"bw"},need=req+" alder",route=False)
    event("two_years","bw_home_1f","妈妈","后来，桧扇市也有了自己的道馆。想听两年后从那里开始的故事吗？你也可以先留在现在的合众。",
          {"unova_sequel":True},need="ghetsis")


def sequel():
    global era, prior
    era, prior = 2, "u2_started"
    event("home","b2_home","妈妈","红豆杉博士的助手白露到了。她戴着一顶绿帽，你去桧扇市的展望台看看！")
    event("first_battle","aspertia_lookout","白露","我是红豆杉博士的助手白露。站在能看见整个合众的地方，选一位一起出发的伙伴吧。",
          {"unova_starter":2},item("合众图鉴"),say("阿修","这孩子从蛋里孵出来，我一直带着它训练。小悠，就在这儿比一场！"),
          rival("阿修",161,unova_starter_only=2,finish_on_loss=True),{"heal":True},guests=["阿修"])
    event("maps","aspertia","妈妈","这是跑步鞋。阿修的妹妹也给你准备了两张地图，记得把另一份送给哥哥。",
          item("跑步鞋"),item("城镇地图"),item("给阿修的地图"),say("白露","到十九号道路找我，我来教你如何捕捉宝可梦。"),guests=["阿修的妹妹","白露"])
    event("catch","19","白露","先削弱体力，状态异常也能帮上忙。看看我怎么对付这只扒手猫。",item("精灵球",10,"ball"))
    event("alder_visit","floccesy","阿戴克","久等了！看得出你正赶着送东西。沿着二十号道路去牧场，你会碰上那孩子。")
    event("ranch_rival","ranch","阿修","你也到算木牧场了？来打一场，给我看看你和新伙伴练得怎么样！",rival("阿修",166),{"remove_item":"给阿修的地图"},
          say("牧场主人","哈约克不见了！拜托你们帮我在牧场深处找一找。"),guests=["牧场主人"])
    event("herdier","ranch","等离子队队员","找的就是这只哈约克？别追！给你个学习器，放我走！",machine(21),say("阿修","哈约克，平安就好。我绝不会放过夺走别人伙伴的家伙。"),guests=["哈约克","阿修"])
    event("school","floccesy","阿戴克","帮我给孩子们上一堂属性课。弱点、抵抗，都在交手时最容易理解。",{"unova_school":True},guests=["男学生","女学生"])
    gym(1,"aspertia","黑连","基础徽章",83,156,"我是桧扇道馆的新馆主黑连。第一次以馆主身份迎接挑战，心情和当年很不一样。","这是我亲手颁发的第一枚基础徽章。谢谢你和伙伴的精彩表现。")
    event("returns","aspertia","白露","黑连现在是可靠的老师了吧？这是报恩，宝可梦越亲近你，威力越强。",machine(27),guests=["黑连","阿修"])
    event("captain","virbank","霍米加","爸爸，船在码头等着，你却要去拍电影？我先回道馆。你可得给乘客一个交代。",guests=["船长"])
    gym(2,"virbank","霍米加","毒烟徽章",9,157,"让低音和毒气一起涌上来！我听得见你和伙伴合拍的声音。","能在这么大的音量中抓住节奏，你们值得毒烟徽章。")
    event("studio","film","哈奇库","摄影棚准备好了。借你的搭档是利欧路。看准驹刀小兵和秃鹰丫头的弱点，把两幕戏演完吧。",
          {"unova_studio":True},say("船长","现在我知道了，我最想当的是能让乘客安心的船长。码头见！"),guests=["船长"])
    event("port","virbank","阿修","那些黑衣人是等离子队！霍米加对付一个，另一个就拜托你了。",fight("等离子队队员",690),
          say("霍米加","别让他们跑了。这个居合斩送你，去二十号道路找找！"),machine(1,True),guests=["霍米加","等离子队队员"])
    event("pursuit","20","等离子队队员","怎么连这儿都让你找到了！",fight("等离子队队员",763),say("阿修","他们打算坐船去飞云。我们也回立涌的码头！"))
    event("ferry","virbank","船长","去飞云港的乘客上船了！多谢你们帮我找回掌舵的劲头。",warp("unova_castelia"),guests=["阿修"])
    event("iris_port","castelia","艾莉丝","亚堤去追一伙可疑的人了。你要找他？跟我来，飞云下水道的入口在码头旁。",guests=["阿修"])
    event("sewers","castelia_sewers","阿修","这里果然有等离子队！我来照顾队伍的体力，你和我一起上！",
          fight("等离子队队员",342,other=356,ally=[588,589,590]),say("亚堤","谢谢你们！我得回道馆了。"),
          say("阿修","这个怪力给你。只要想到我妹妹的扒手猫，我就不能停。"),machine(4,True),guests=["亚堤","阿克罗玛"])
    gym(3,"castelia","亚堤","甲虫徽章",76,154,"丝线把画室连在一起，虫宝可梦的变化让我画也画不完。轮到我们对战了！","甲虫徽章，送给从茧里走出来的伙伴。")
    event("dowsing","castelia_gate_north","白露","终于赶上你了！这台探宝器能指出附近藏着道具的方向。去四号道路的路上试试吧！",item("探宝器"))
    event("colress_4","4","阿克罗玛","堵住道路的岩殿居蟹，并非用蛮力才能赶走。我想知道，什么能让宝可梦发挥力量。请和我交手。",fight("阿克罗玛",358))
    event("subway","nimbasa","鸣依","那边是地铁总控官北尚和南厦。只有两个人组队才行，你愿意和我一起吗？",fight("北尚和南厦",732,other=733,ally=[363,364,365]),need="colress_4",route=False,guests=["北尚","南厦"])
    event("old_gym","nimbasa_old_gym","模特","你来晚了一步，小菊儿已经搬去新的舞台了。坐车到终点就知道下一步往哪儿走。")
    gym(4,"nimbasa","小菊儿","伏特徽章",72,153,"欢迎来到我的新舞台。灯光调好，让我们把最精彩的表演献给观众吧！","你们果然值得压轴出场。请收下伏特徽章。")
    event("plasma_park","nimbasa","阿修","我妹妹的扒手猫被他们抢走五年了。你问我为什么这么生气？我答应过要找回来。",fight("等离子队队员",359),guests=["等离子队队员"])
    event("grotto","5","白露","把飞翔收下吧。你看那两棵树之间！从这里钻进去，也许能发现平时看不到的宝可梦。",machine(2,True))
    event("charles","5","查尔斯","第一次在路上见到轮盘对战？三只伙伴同时出场，每回合由站到前面的伙伴出招。",fight("查尔斯",340,battle_type="rotation"))
    event("rood","driftveil","罗德","我曾是七贤人。现在我们照顾那些回不了家的伙伴。如果你愿意，请用对战让我看看你的心。",fight("罗德",346),guests=["阿修"])
    gym(5,"driftveil","菊老大","震动徽章",78,158,"我对嘴上说的漂亮话没兴趣。拿出你们真正的实力！","帆巴有个新会场叫宝可梦世界锦标赛。领了徽章，也去打场锦标赛吧。")
    event("pwt","pwt","菊老大","首届帆巴锦标赛开始！从队伍中选三只出场。三轮单打，对手都是二十五级。",{"unova_pwt":True},guests=["黑连","阿修"])
    event("frigate_port","frigate_driftveil","黑连","这是一艘武装船。小悠、阿修，守住彼此的背后。",fight("等离子队队员",372),
          fight("等离子队队员",374,other=375,ally=[371,371,371]),fight("等离子队队员",376,other=377,ally=[368,369,370]),say("维奥","黑暗铁三角，把这些不请自来的人送下船。"),guests=["阿修","维奥"])
    event("surf","6","黑连","十一度的异常低温已经在各处出现过。我会继续调查。这个冲浪学习器会帮你渡过阻路的水面。",machine(3,True))
    event("professor","mistralton","红豆杉博士","我一直想见见白露挑的训练家。这颗大师球交给你，我先去天堂之塔研究。",item("大师球",1,"ball"),guests=["风露"])
    gym(6,"mistralton","风露","喷射徽章",62,155,"站稳了吗？接下来迎着劲风和我对战！","有了喷射徽章，你可以骄傲地和伙伴一起飞越群山。")
    event("flight","mistralton","风露","窗外山脊的另一侧就是山路镇。博士和白露都准备好了，上飞机吧！",warp("unova_lentimas"),guests=["红豆杉博士","白露"])
    event("reverse","reverse","白露","反转山深处的洞，看起来像是什么宝可梦住过的地方。我们一起走吧，我会帮队员恢复体力。",{"heal":True})
    event("undella","undella","阿修","等离子队的船还在附近。你和伙伴有没有变得更强？让我试一试！",rival("阿修",378))
    event("lacunosa","lacunosa","红豆杉博士","相传巨人洞窟有一只随陨石而来的宝可梦。镇上的奶奶知道那个故事。",guests=["白露"])
    event("zinzolin","lacunosa","维奥","冰封的世界会让人们听从等离子队！",fight("维奥和等离子队队员",704,other=705,ally=[701,702,703]),guests=["阿修","等离子队队员"])
    gym(7,"opelucid","夏卡","传说徽章",82,159,"这座龙道馆换了模样。你能走到这里，我愿意以全部实力回应。","传说徽章归你。关于传说中的龙，我家里还有些事情想告诉你。")
    event("splicers","opelucid_house","夏卡","留下两头龙的传说之外，双龙市还保管着一件宝物，叫基因之楔。外边怎么会有炮声？")
    event("freeze","opelucid","维奥","等离子驱逐舰，发射！看吧，整座双龙市都将在寒冰中俯首。",*[fight("等离子队队员",n) for n in (585,586,587)],fight("维奥",584),guests=["夏卡"])
    event("shadow","opelucid","黑暗铁三角","基因之楔到手了。你只能追上我的影子。",fight("黑暗铁三角",583),say("黑连","他们还有别的同伴。我要追查驱逐舰的行踪。你从涟漪镇乘海洋隧道去青海波市。"),guests=["黑连"])
    event("marlon","humilau","西子伊","游泳游到忘了时间！你是来挑战道馆的吧？我这就回去。")
    gym(8,"humilau","西子伊","海浪徽章",55,160,"听一听海浪，跟水属性的伙伴们一起放开手脚吧！","八枚都集齐了！接下来你怎么帮那些陷入麻烦的人，由你自己来决定。")
    event("mchn","22","阿克罗玛","这台仪器能激发宝可梦的力量。海边洞穴里如果有岩殿居蟹拦路，不妨试试。",item("阿克罗玛机器"))
    event("crustle","seaside_cave","岩殿居蟹","岩石动了一下。打开阿克罗玛机器，挡住出口的岩殿居蟹醒了！",{"battle":{"name":"岩殿居蟹","wild":True,"finish_on_escape":True,"team":[{"species":558,"level":42}]}},{"remove_item":"阿克罗玛机器"})
    event("board_ship","frigate_seaside","西子伊","跳板已经放下来啦，你和阿修都能上船了。",fight("等离子队队员",798,other=799,ally=[794,795,796]),guests=["阿修"])
    event("ship_switches","b2_zone_553","电网","最后一道电网消失了。通往船舱深处的通道已经断电。",need="board_ship panel_1 panel_2 panel_3 panel_4",automatic=True)
    event("ship_ice","b2_zone_556","维奥","制冷装置里关着的宝可梦是酋雷姆。它的力量，就连双龙市也抵挡不住。",fight("维奥和等离子队队员",797,other=347,ally=[794,795,796]),say("黑暗铁三角","你们的航程到这里就结束了。"),warp("unova_21",[30,50],"right"),guests=["阿修"])
    event("chasm","giant","罗德","我们曾经犯过错。现在让我和同伴们挡住他们，你们去阻止那艘船！",guests=["阿修"])
    event("card","b2_zone_561","等离子队队员","想从传送装置进去？等离子卡在我身上！",fight("等离子队队员",439),item("等离子卡"))
    event("password","b2_zone_561","控制面板","在读卡器上刷等离子卡。密码提示亮了起来……",{"unova_password":True})
    event("zinzolin_last","b2_zone_561","维奥","我身后的装置能将酋雷姆的力量变成冰。你休想把它放出来！",fight("维奥",497))
    event("lab","colress_lab","阿克罗玛","可以用机器逼出力量，也可以相信伙伴。哪一种能引出它们全部的潜力？请用对战给我答案。",fight("阿克罗玛",344))
    event("purrloin","b2_zone_557","黑暗铁三角","五年前那只扒手猫？它已经进化成酷豹了。它还能认出原来的主人吗？",*[fight("黑暗铁三角",n) for n in (348,498,499)],
          say("阿修","我把妹妹的伙伴带回去。小悠，魁奇思跑进了巨人洞窟，拜托你了！"),guests=["阿修","酷豹"])
    event("fusion","giant_chamber","魁奇思","酋雷姆，冰封他！",say("N","捷克罗姆，挡住冰柱！"),
          say("魁奇思","我等的就是你。基因之楔，让酋雷姆吸收捷克罗姆！"),guests=["N","酋雷姆"])
    event("kyurem","giant_chamber","暗黑酋雷姆","冰面震动。与捷克罗姆合体的暗黑酋雷姆挡住了前路！",
          {"battle":{"name":"暗黑酋雷姆","team":[{"species":646,"level":55,"form":"KYUREM_BLACK","moves":[225,163,559,553]}]}},guests=["N","魁奇思"])
    event("ghetsis","giant_chamber","魁奇思","怎么可能，基因之楔让它们分开了！都是因为你……我亲自来结束这一切！",{"heal":True},fight("魁奇思",345),
          say("N","你的伙伴和你守住了未来。去联盟吧，那里的胜负该由你自己决定。"),guests=["N","黑暗铁三角"])
    event("waterfall","23","N","从这里继续向上就是胜利之路。我和伙伴走过自己的路，也把这个攀瀑学习器留给你。",machine(5,True))
    event("rival_road","victory","阿修","酷豹已经和妹妹重逢。现在，我也可以为了自己的目标向前。联盟之前，再跟我打一场吧！",
          rival("阿修",684),say("阿修","谢谢你陪我找回她的伙伴。这个十万伏特给你！"),machine(24))
    event("league","league","联盟向导","请出示这个时代在合众获得的八枚徽章。四个房间各有一位天王，次序由你自己决定。",need="rival_road "+" ".join(f"badge_{n}" for n in range(1,9)))
    req=elite("league","",[38,40,41,39])
    event("iris","champion_room","艾莉丝","我是合众冠军艾莉丝！不管是谁，都可以和珍爱的宝可梦一起变强。来吧，让我的龙也见识一下！",
          fight("艾莉丝",341),say("艾莉丝","太好了！你们都是闪闪发光的冠军。和我来，我带你们去名人堂。"),need=req)
    event("champion","champion_room","艾莉丝","把今天和你并肩作战的伙伴都记录下来。无论回到哪个地区，这份记忆都会一直跟着你。",{"unova_hall":"b2"},warp("unova_b2_home"))
    req=elite("champion","again_",[143,145,146,144])
    event("again_iris","champion_room","艾莉丝","欢迎再回来！这一次，让我们带着更加成熟的伙伴们一决胜负！",fight("艾莉丝",536),{"unova_repeat_hall":"b2"},need=req,route=False)


def gates():
    global era
    era=1
    gate("cheren_home","bw_home_1f","先和白露、黑连试一试刚选的伙伴。")
    gate("dex","1 accumula 2 striaton","先到鹿子镇的研究所领取合众图鉴。")
    gate("school","bw_gym_striaton","黑连正在三曜市的训练家学校等你。")
    gate("dream_mist","3 wellspring nacrene","去梦之遗址帮真菰找梦之烟。")
    gate("n_museum","bw_gym_nacrene","先在七宝博物馆入口见到 N。")
    gate("fossil_theft","pinwheel","先去博物馆看看龙骨。")
    gate("skull_back","skyarrow_bridge castelia castelia_plasma","馆长还在等你追回被夺走的龙骨。")
    gate("munna_back","bw_gym_castelia","白露的食梦梦还没有救回来。")
    gate("badge_3","4 nimbasa 5","飞云道馆的甲虫徽章尚未取得。")
    gate("ferris","bw_gym_nimbasa","N 想和你在摩天轮旁谈谈。")
    gate("bridge","driftveil_bridge driftveil cold_storage","帆巴吊桥还没放下。")
    gate("release","bw_gym_driftveil","去冷冻仓库处理等离子队的事。")
    gate("badge_5","6 chargestone mistralton celestial 7","先完成帆巴道馆的挑战。")
    gate("tower","bw_gym_mistralton","风露去了天堂之塔。")
    gate("surf","twist icirrus bw_gym_icirrus","黑连在七号道路通往罗斯山的台阶等你。")
    gate("tower_alarm","dragonspiral","龙螺旋之塔的入口还没有开启。")
    gate("light_stone","8 tubeline_bridge 9 opelucid opelucid_house","先向芦荟领取光明石。")
    gate("dragons","bw_gym_opelucid","先听夏卡和艾莉丝讲述两条龙。")
    gate("badge_8","10","先获得双龙道馆的徽章。")
    gate("last_rival","victory league","十号道路的徽章检查站尚未放行。")
    gate("league","e4_shauntal e4_grimsley e4_caitlin e4_marshal","请先在联盟入口接受徽章检查。")
    gate("shauntal grimsley caitlin marshal","champion_room","四位天王全部战胜后，大殿才会开放。")
    gate("castle_rises","ns_castle","N 的城堡尚未出现在联盟。")
    gate("ghetsis","black_city 11 12 13 14 15 lacunosa undella village giant","这条通往东合众的道路在等离子队事件平息之后开放。")
    era=2
    gate("home","aspertia_lookout","先在家里和妈妈谈谈。")
    gate("maps","19 floccesy","带上地图再出发。")
    gate("alder_visit","20 ranch","阿戴克在算木镇等你。")
    gate("school","b2_gym_aspertia","先把牧场的哈约克找回来，再到算木镇上完属性课。")
    gate("badge_1","virbank b2_gym_virbank","二十号道路的训练家会检查桧扇道馆徽章。")
    gate("badge_2","film","先接受立涌道馆的挑战。")
    gate("ferry","castelia","立涌市的联络船还没启航。")
    gate("iris_port","castelia_sewers","艾莉丝知道飞云下水道的入口。")
    gate("sewers","b2_gym_castelia","飞云馆主亚堤去了下水道。")
    gate("badge_3","4","先通过飞云道馆。")
    gate("colress_4","nimbasa nimbasa_old_gym","四号道路的岩殿居蟹还挡着路。")
    gate("charles","driftveil_bridge driftveil","五号道路的摩托车手查尔斯正在等你。")
    gate("old_gym","b2_gym_nimbasa","去旧过山车道馆问问小菊儿的去向。")
    gate("plasma_park","5","先和阿修处理雷文市路口的等离子队。")
    gate("rood","b2_gym_driftveil","先在帆巴市见一见旧等离子队的罗德。")
    gate("badge_5","pwt","菊老大尚未开放初次锦标赛。")
    gate("pwt","frigate_driftveil","驱逐舰要在初次帆巴锦标赛后才能登上。")
    gate("frigate_port","6 chargestone mistralton celestial 7","先和黑连、阿修调查帆巴码头的船。")
    gate("professor","b2_gym_mistralton","先见红豆杉博士和风露。")
    gate("flight","lentimas reverse undella","吹寄市飞往山路镇的飞机还未起飞。")
    gate("undella","13 lacunosa 12 village 11","阿修在涟漪镇等你。")
    gate("zinzolin","opelucid b2_gym_opelucid opelucid_house 9","先解救笼目镇。")
    gate("shadow","marine_tube humilau b2_gym_humilau 21","双龙市被冰封了，先找到基因之楔的下落。")
    gate("badge_8","22 seaside_cave","先拿到当地的海浪徽章。")
    gate("crustle","frigate_seaside","海边洞穴的出口有岩殿居蟹挡路。")
    gate("ship_switches","b2_zone_556","四道电网还没有全部关闭。")
    gate("ship_ice","giant","等离子驱逐舰还没有飞往巨人洞窟。")
    gate("chasm","frigate_giant b2_zone_561","罗德与伙伴还在巨人洞窟的入口。")
    gate("zinzolin_last","colress_lab","通往阿克罗玛的舱门仍被电网封锁。")
    gate("lab","b2_zone_557","另一侧的传送装置仍被封锁，先找到阿克罗玛。")
    gate("purrloin","giant_chamber","黑暗铁三角还在守着通往洞窟核心的路。")
    gate("ghetsis","23 victory league","巨人洞窟里的危机尚未解除。")
    gate("league","e4_shauntal e4_grimsley e4_caitlin e4_marshal","请先在联盟入口接受徽章检查。")
    gate("shauntal grimsley caitlin marshal","champion_room","集齐本轮四场胜利才能向冠军挑战。")
    gate("champion","nuvema bw_home_1f bw_home_2f striaton 1 2 3 nacrene icirrus black_city","这个时代的东南合众在联盟之后开放。")


def main():
    global originals,species_ids,move_ids,ability_ids
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path)
    folder=parser.parse_args().source
    originals={1:trainer_file(folder,"bw","black_white"),2:trainer_file(folder,"b2","black2_white2")}
    species_ids={norm(r["key"]):r["id"] for r in read("species.json")}
    move_ids={norm(r["key"]):r["id"] for r in read("moves.json")}
    ability_ids={norm(r["key"]):r["id"] for r in read("abilities.json")}
    black()
    sequel()
    for n in (169,170,747,748,749,750):team(n)
    def tournament(species, moves):
        return mon(species,25,moves.split("/"))
    bird=tournament("Tranquill","Taunt/Air Cutter/Roost/Detect")
    monkey_moves="Leer/Lick/Fury Swipes"
    book["pwt"]=[
        [
            [tournament("Pignite","Take Down/Smog/Heat Crash/Rollout"),tournament("Simipour","Scald/"+monkey_moves),bird],
            [tournament("Dewott","Aqua Jet/Water Pulse/Revenge/Fury Cutter"),tournament("Simisage","Seed Bomb/"+monkey_moves),bird],
            [tournament("Servine","Leech Seed/Leaf Blade/Slam/Mega Drain"),tournament("Simisear","Flame Burst/"+monkey_moves),bird],
        ],
        [[tournament("Stoutland","Tackle/Work Up/Bite/Odor Sleuth"),tournament("Cinccino","Work Up/Sing/Wake-Up Slap/Bullet Seed"),tournament("Watchog","Work Up/Confuse Ray/Hypnosis/Bite")]],
        [[tournament("Magneton","Thunder Wave/Supersonic/Thunder Shock/Mirror Shot"),tournament("Elgyem","Growl/Headbutt/Psybeam/Heal Block"),tournament("Klink","Charge/Thunder Shock/Gear Grind/Bind")]],
    ]
    gates()
    original_rooms={'u1_badge_2': 19, 'u1_port': 38, 'u1_munna_back': 56, 'u1_skull': 155, 'u1_skull_back': 155, 'u1_ferris': 64, 'u1_cave_n': 195, 'u1_tower': 342, 'u1_castle_stone': 165, 'u2_ranch_rival': 445, 'u2_herdier': 445, 'u2_school': 440, 'u2_studio': 567, 'u2_reverse': 533, 'u2_chasm': 233, 'u2_purrloin': 557, 'u2_fusion': 604, 'u2_kyurem': 604, 'u2_ghetsis': 604, 'u2_rival_road': 228, 'u2_waterfall': 573}
    for event_row in book["events"]:
        key=event_row["id"]
        if key in original_rooms:
            old=event_row["map"]
            new="unova_"+("bw" if event_row["era"]==1 else "b2")+"_zone_"+str(original_rooms[key])
            rule=book["gates"][str(event_row["era"])].get(old)
            if rule:book["gates"][str(event_row["era"])][new]=rule
            event_row["map"]=new
        # All four first-round opponents are mandatory, and may still be fought in any order.
        if event_row["id"] in {f"u{i}_{name}" for i in (1,2) for name in ("shauntal","grimsley","caitlin","marshal")}:
            event_row["route"]=True
    (ROOT/"content/unova_campaign.json").write_text(json.dumps(book,ensure_ascii=False,indent=1)+"\n")
    print(len(book["events"]),"events,",len(book["teams"]),"trainer parties")


if __name__=="__main__":
    main()
