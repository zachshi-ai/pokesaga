"""Author the shared Kalos X/Y campaign. Trainer numbers address original X/Y game records."""
import json
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
events = []
gates = {}
prior = 'k_started'


def qualified(value):
    return value if value.startswith('k_') else 'k_'+value


def say(name, line):
    return {'who':name,'say':[line]}


def key(name):
    return {'kalos_key':name}


def item(name, count=1, category='other'):
    return {'give_item':{'name':name, 'count':count, 'category':category}}


def tm(number):
    return {'kalos_tm':number}


def hm(number):
    return {'kalos_hm':number}


def fight(who, number, *, ally=None, other=None, **options):
    options['kalos_variants' if isinstance(number,list) else 'kalos_team'] = number
    if other is not None:
        options.update(kalos_other=other, double=True)
    if ally is not None:
        options.update(ally='kalos',kalos_ally=ally)
    return {'battle':dict(name=who,**options)}


def variants(first):
    return [first,first+1,first+2]


def scene(key, location, who, line, *actions, guests=(), anchor='story', require=None, resident='', route=True):
    global prior
    requires = [prior] if require is None else [qualified(x) for x in require.split()]
    identity = qualified(key)
    steps = ([say(who,line)] if line else []) + list(actions)
    # Persist before changing rooms, including the initial map gate and end credits.
    idx = len(steps)-1 if steps and 'kalos_warp' in steps[-1] else len(steps)
    steps.insert(idx, {'flag':identity})
    row={'id':identity,'map':'kalos_'+location,'who':who,'require':requires,'steps':steps,'anchor':anchor,
         'trigger':{'kind':'talk','actor':identity},'route':route}
    if guests:row['guests']=list(guests)
    if resident:row['resident']=resident
    events.append(row)
    if route:prior=identity


def gate(require, places, reason):
    for name in places.split():
        gates['kalos_'+name]={'require':[qualified(x) for x in require.split()], 'message':reason}


def gym(n,town,leader,badge,move,trainer,line,after):
    scene('badge_'+str(n),'gym_santalune_web' if n==1 else 'gym_'+town,leader,line,fight(leader,trainer),say(leader,after),
          {'kalos_badge':badge},tm(move),resident=after)


def build():
    scene('dressed','home_2f','镜子','小悠换好衣服。窗外传来小箭雀的叫声，楼下已经有人起来了。')
    scene('welcome','vaniville','莎莉娜','小悠？我是隔壁的莎莉娜。博士想把宝可梦托付给我们五个人，去名水镇露天桌旁集合吧。',guests=['莎娜'])
    scene('starter_gift','aquacorde','提耶鲁诺','莎娜、多罗巴、莎莉娜，都到了！博士把三个精灵球交给我，请你先挑一个吧。',{'kalos_starter':True},
          say('多罗巴','宝可梦图鉴交给你。遇到的每一位新伙伴，都可以在这里留下记录。'),key('卡洛斯图鉴'),key('博士的信'),
          say('提耶鲁诺','这封信是写给你妈妈的，出发前先带回家。'),guests=['莎莉娜','莎娜','多罗巴'])
    scene('first_battle','aquacorde','莎娜','等等，我也选好伙伴了！回家之前，和我打一场吧。',fight('莎娜',variants(137),kalos_starter_only=True,finish_on_loss=True),{'heal':True},anchor='guest1')
    scene('moms_map','home_1f','妈妈','布拉塔诺博士写来了邀请信。你要去那么远的地方，带上地图和伤药。铁甲犀牛也来送你了！',
          {'kalos_take':'博士的信'},key('城镇地图'),key('全息影像通讯器'),item('伤药',1,'medicine'))
    scene('catch_lesson','2','莎莉娜','你看，我先让伙伴削弱它的体力。等它慢下来再投球，更有把握。',{'kalos_catch_demo':True},item('精灵球',10,'ball'),guests=['莎娜'])
    scene('forest_friends','forest','莎娜','森林的草丛在摇晃。一起走吧！你的伙伴累了，我来帮它们恢复。',{'heal':True},guests=['多罗巴','提耶鲁诺'])
    scene('rules','3','莎莉娜','穿过森林就是白檀市。我们各走各的路之前，把大家商量的冒险心得也带上吧。',key('探险心得'),guests=['莎娜','提耶鲁诺','多罗巴'])
    scene('skates','santalune','轮滑手凛香','想试试轮滑鞋吗？先和我的蛇纹熊比一场！',fight('轮滑手凛香',166),key('轮滑鞋'))
    gym(1,'santalune','紫罗兰','虫子徽章',83,6,'站到蛛网上别着急，焦点就在你的宝可梦身上！','这场对战的瞬间，我会记在照片里。虫子徽章属于你了。')
    scene('alexa','santalune','三色堇','原来你就是赢过我妹妹的训练家！学习装置可以让没有上场的伙伴也分享经验。',key('学习装置'))
    scene('dex_helpers','4','德克希欧','橙色花海后面就是密阿雷。我们在博士的研究所工作，一起去见布拉塔诺博士吧。',tm(27),guests=['吉娜'])
    scene('sycamore','sycamore_lab','布拉塔诺','我在研究超级进化。先让我用来自关都的三位伙伴，看看你一路学到了什么。',fight('布拉塔诺',327),
          say('布拉塔诺','你和哪一位合得来？它和对应的超级石都交给你。'),{'kalos_kanto_gift':True},guests=['莎莉娜','莎娜'])
    scene('lysandre_intro','sycamore_lab_lobby','弗拉达利','博士所挑选的孩子？愿你把自己的才能用在更美好的世界上。',guests=['布拉塔诺'])
    scene('diantha_cafe','cafe_soleil','卡露妮','即使上了年纪，我也想演那时候的自己。对战也一样，每次相遇都会让我改变。',guests=['弗拉达利','莎莉娜'])
    scene('korrina_5','5','可尔妮','路卡利欧，回来！奇怪，它很少对刚认识的训练家这么亲近。我们一定会再相遇。',guests=['路卡利欧'])
    scene('dance','5','提耶鲁诺','我的龙虾小兵学会了新动作！你愿意陪我练练舞步吗？',fight('提耶鲁诺',573),guests=['多罗巴'])
    scene('castle','shabboneau_castle','城主','城堡中的宝物早被带走了……什么？七号道路的桥上又有宝可梦睡着了？我们到桥边去！',guests=['莎娜'])
    scene('sleeping','7','空手道王','卡比兽把路占得严严实实。唤醒它的宝可梦之笛在巴尔法姆香殿。',guests=['卡比兽','莎娜'])
    scene('palace','palace','香殿主人','我的多丽米亚不见了！它会不会跑进庭院的树篱？请帮我找找。',guests=['莎娜'])
    scene('garden_watch','parfum_garden','莎娜','我在岔路口挡住它。你从后面走，让它朝中间的树篱去。',anchor='guest1')
    scene('garden_lure','parfum_garden','多丽米亚','多丽米亚回头看了一眼，沿着树篱向另一边跑开了。',anchor='guest2',guests=['莎娜'])
    scene('garden_block','parfum_garden','莎娜','它到了另一头！这次我守着左边的出口，你从右边靠近。',anchor='guest3')
    scene('garden_dog','parfum_garden','多丽米亚','多丽米亚停在尽头，摇着尾巴回到莎娜身边。主人邀请你们一起去阳台看烟花。',anchor='guest2',guests=['莎娜','香殿主人'])
    scene('flute','zone_301','莎娜','烟花亮起来了！从前我是一个人看，多亏了你，这次可以和朋友一起记住它。',{'kalos_scene':'fireworks'},say('管家','既然要唤醒卡比兽，请借用这支宝可梦之笛。这是大家约定好的谢礼。'),key('宝可梦之笛'),tm(17),guests=['管家'])
    scene('snorlax','7','空手道王','你借到了笛子！小悠，请你接住醒来的卡比兽。',{'kalos_require_item':'宝可梦之笛'},
          {'battle':{'name':'卡比兽','wild':True,'finish_on_escape':True,'team':[{'species':143,'level':15}]}},
          {'kalos_take':'宝可梦之笛'},say('城主','谢谢你。笛子由我保管，桥上可以通行了。'),guests=['卡比兽','城主'])
    scene('route7_tag','7_west','提耶鲁诺','小悠和莎莉娜一组，我和多罗巴一组。两边同时指挥，要看好同伴的动作哦。',fight('提耶鲁诺与多罗巴',438,other=439,ally=variants(596)),guests=['多罗巴','莎莉娜'])
    scene('coastal','8','吉娜','中央卡洛斯以外还有海岸的生态。已经帮你打开海岸图鉴了！',guests=['德克希欧'])
    scene('fossil_lab','ambrette_fossil_lab','化石研究员','同事去闪耀洞窟实地考察，还没回来。出镇后，可以骑铁甲犀牛越过九号道路的石坡。',guests=['莎莉娜'])
    scene('glitter_grunts','glitter','闪焰队员','这洞窟里的化石就由闪焰队收下了。穿这么讲究，怎么能空手回去！',
          fight('闪焰队员',107),fight('闪焰队员',110),fight('闪焰队搭档',108,other=111,ally=variants(575)),guests=['莎莉娜','闪焰队女团员'])
    scene('fossil','glitter','化石研究员','刚才的骚动我还没注意到呢。我挖出了两块化石，请你选一块，把它带回实验室吧。',{'kalos_fossil':True},guests=['莎莉娜'])
    scene('grant_slope','cyllage','查克洛','抱歉，骑车比赛刚结束。这个秘传学习器给你，从岩壁向上爬，我们在道馆顶上见。',hm(4))
    gym(2,'cyllage','查克洛','岩壁徽章',39,76,'眼前的墙越高，登顶时就越能看清楚。让我看看你攀过了哪些困难！','岩壁徽章属于你了。有了它，怪力就能挪动挡路的大岩石。')
    scene('stones','10','闪焰队员','你在洞窟遇见过我们吧？这些列石埋着很久以前的秘密，小孩子少来打听。',fight('闪焰队员',109))
    scene('geosenge','geosenge','莎莉娜','那人往西北去了，可是石头后面明明没有路。先沿十一号道路去娑罗市吧。',guests=['闪焰队员'])
    scene('korrina_duo','geosenge','可尔妮','又见面了！我的两只路卡利欧都想和你切磋。',fight('可尔妮',613),guests=['路卡利欧'])
    scene('reflection','reflection','提耶鲁诺','镜壁照到了背后有人。侧着看影子，别在岔路绕回原地。带着闪光，到了昏暗的地方也能照亮前路。',tm(70))
    scene('gurkinn','mastery','可可布尔','超级进化不只需要超级石，还需要手持钥石的训练家。如今只有一枚手环可以托付。',guests=['可尔妮','莎莉娜','莎娜'])
    scene('ring_rival','mastery','莎莉娜','我们都想解开超级进化的秘密。这枚手环该交给谁，用一场对战来决定吧。',fight('莎莉娜',variants(581)),guests=['可可布尔','可尔妮'])
    gym(3,'shalour','可尔妮','战斗徽章',98,21,'我绕了这座轮滑场好多圈，一直在等这场道馆赛。我们都拿出真本事吧！','你已经获得战斗徽章。再上一次精练之塔，到顶上来练习超级进化吧！')
    scene('mega_ring','mastery_summit','可尔妮','给你超级环，里面嵌着钥石。它会和路卡利欧身上的超级石呼应。',key('超级环'),guests=['路卡利欧'])
    scene('mega_trial','mastery_summit','可尔妮','这只路卡利欧自己选择了你。借你试一次，在出招前通过钥石回应它！',fight('可尔妮',188,kalos_trial=True,finish_on_loss=True),guests=['路卡利欧'])
    scene('lucario','mastery_summit','可尔妮','它还想和你一起走。愿意让这只带着超级石的路卡利欧加入吗？',{'kalos_lucario':True},guests=['路卡利欧'])
    scene('reclaim_lucario','mastery_summit','可尔妮','它一直在塔上等你。今天要接它一起旅行吗？',{'kalos_reclaim':True},require='lucario',route=False,guests=['路卡利欧'])
    scene('surf','shalour','莎莉娜','你亲眼见到超级进化了！十二号道路前面有水，把冲浪教给合适的伙伴再出发吧。',hm(3))
    scene('monorail','coumarine_monorail_west','布拉塔诺','搭单轨列车越过山崖，才能抵达道馆所在的高地。这里还有一份飞翔的秘传学习器。',hm(2),guests=['卡露妮'])
    scene('coumarine_rival','coumarine_hill','莎莉娜','这次不是为了手环。我想知道，我们各自做出的选择会带来怎样的对战。',fight('莎莉娜',variants(578)))
    gym(4,'coumarine','福爷','植物徽章',86,22,'捧起泥土就知道根扎得深不深。你的伙伴，一定也在旅途中长出了自己的根。','植物徽章给你。飞过这片土地时，也望一望脚下的树。')
    scene('mountain','13','德克希欧','海岸的记录很漂亮。荒地通向山脉地带，我们把山岳图鉴也交给你。',guests=['吉娜'])
    scene('pass_grunt','13','闪焰队员','别靠近发电厂！糟了，我放行用的证件呢？刚才还在九步左右外的大石旁……',fight('闪焰队员',308))
    scene('power_pass','13','大岩石','石头背风的一侧卡着一张发电厂通行证。',key('发电厂通行证'),anchor='guest2')
    scene('plant','power_plant','闪焰队干部','密阿雷北部的电已经送到别处了。谁让你进来的？',fight('闪焰队干部',174),fight('阿可碧',175),
          say('工程师','供电恢复了！北边的街区和棱镜塔都能重新点亮。'),guests=['阿可碧','工程师'])
    scene('giant','13','ＡＺ','花的宝可梦……永恒之花的宝可梦……',anchor='guest1')
    scene('prism','lumiose_north','莎娜','快看！希特隆和柚丽嘉就站在塔下！',say('希特隆','供电稳定。准备好了，棱镜塔，亮起来吧！'),guests=['希特隆','柚丽嘉'])
    gym(5,'lumiose','希特隆','电压徽章',24,23,'我造了这些问答装置，想让大家用不同方式认识宝可梦。最后这一题，是我们来对战！','答案正确。请收下电压徽章和十万伏特。')
    scene('kings_rock','lysandre_cafe','弗拉达利','有位国王为了自己珍惜的一切，给这片土地留下了伤痕。愿你善用这块王者之证。',{'kalos_held':'KINGS_ROCK'},guests=['布拉塔诺'])
    scene('marsh_rival','14','莎莉娜','多罗巴想比图鉴。我倒更想和你比一场对战。',fight('莎莉娜',variants(584)),guests=['多罗巴'])
    scene('scary_house','scary_house','讲故事的老人','夜里独行的人敲响山屋的门。他们哪里知道，身后的路早已消失……',say('莎娜','你也听到最后了吗？出来才发现，大家挤得好近！'),guests=['莎娜','提耶鲁诺','多罗巴'])
    gym(6,'laverre','玛绣','妖精徽章',99,24,'站在这间屋子里，偶尔会觉得自己也变成了宝可梦。你听得见伙伴的声音吗？','请收下妖精徽章。希望这道光，也能照见你们之间的心意。')
    scene('factory_gate','factory_gate','莎娜','守卫拦着我们不让参观？我去问问！咦，他追过来了——小悠，你和莎莉娜趁现在进去！',guests=['多罗巴','提耶鲁诺','莎莉娜'])
    scene('factory','factory','闪焰队干部','我们给了会长一个选择。交出工厂，或者交出所有的精灵球。',fight('闪焰队干部',304),
          fight('克蕾儿与芭菈',348,other=350,ally=variants(607)),guests=['克蕾儿','芭菈','莎莉娜'])
    scene('factory_reward','factory','工厂会长','真是多亏你们。大师球和巨大金珠都拿去吧！有些东西的价值，可不是用金钱就能称量的。',item('大师球',1,'ball'),item('巨大金珠'),guests=['莎莉娜'])
    scene('frost_news','dendemille','布拉塔诺','传说中的宝可梦究竟何时醒来？对了，镇上的象牙猪似乎不肯离开冰结洞窟。',guests=['多罗巴'])
    scene('abomasnow','frost','茉蜜姬','这只暴雪王释放出的能量可以帮助我们的计划。你们偏偏要来干涉？',fight('闪焰队员',317),fight('茉蜜姬',346),
          say('多罗巴','暴雪王恢复了精神，你可以过去看看它。象牙猪现在能安心回雪道了。'),guests=['多罗巴','暴雪王'])
    scene('anistar_rival','anistar','莎莉娜','日晷的影子正好走到这里。道馆开门前，先看看我们这段时间的成长吧。',fight('莎莉娜',variants(587)),{'heal':True})
    gym(7,'anistar','葛吉花','精神徽章',4,25,'星轨交错。站在此刻的你，要怎样通往属于你的未来？','精神徽章，见证此刻。你的未来还有一次重大抉择。')
    scene('broadcast','anistar','全息影像通讯器','弗拉达利的影像占满屏幕：“我将启动最终兵器。只有闪焰队，能留在美丽的世界。”',say('莎莉娜','去密阿雷，红色的弗拉达利咖啡馆。他一定和那里有关！'),guests=['莎莉娜'])
    scene('cafe_password','lysandre_cafe','咖啡店员','这里没什么隐藏的研究所！更没有通往地下的书架……',fight('闪焰队员',326),fight('闪焰队女团员',352),
          say('咖啡店员','暗号是“向闪焰队致敬”。书架后的通路……被你找到了。'))
    scene('lysandre_lab','flare_labs','弗拉达利','宝可梦、人类、世界上的资源，都有极限。要阻止我，就先找到电梯钥匙。',fight('弗拉达利',303))
    scene('lab_aliana','flare_labs','阿可碧','我在发电厂见过你。红蓝传送装置间的这条路，可没那么好走。',fight('阿可碧',344),anchor='guest1')
    scene('lab_celosia','flare_labs','克蕾儿','我已经收集到了巨石的资料。你的招式能不能比我的计算更快？',fight('克蕾儿',349),anchor='guest2')
    scene('lab_bryony','flare_labs','芭菈','追踪能量数据是我的工作，拖住你也是。',fight('芭菈',351),anchor='guest3')
    scene('lift_key','flare_labs','茉蜜姬','电梯钥匙在我手里。想去地下二层，就来拿吧。',fight('茉蜜姬',347),key('电梯钥匙'))
    scene('az_cell','flare_labs_b2','ＡＺ','三千年前，我造出机器救回了最重要的伙伴。随后我又把它变成了武器。那朵花离开了我，直到今天。',say('ＡＺ','不要让同样的事情再发生。启动兵器的钥匙，就在弗拉达利身上。'),guests=['弗拉达利'])
    scene('two_buttons','flare_labs_b3','库瑟洛斯奇','蓝色与红色的按钮。先打赢我，再选择要不要启动最终兵器。',fight('库瑟洛斯奇',345),{'kalos_button_choice':True})
    scene('crater_gate','geosenge','闪焰队员','石香镇中心的巨石升起来了。秘密基地就在兵器下方，但你休想进去！',fight('闪焰队员',313),guests=['莎莉娜'])
    scene('lysandre_hq','flare_hq','弗拉达利','只要再汲取一点能量，最终兵器就会完成。你们还想说服我？',fight('弗拉达利',525),guests=['莎莉娜'])
    scene('hq_pairs','zone_340','闪焰队干部','关上通往能源室的门！',fight('闪焰队搭档',470,other=611,ally=variants(590)),
          fight('闪焰队搭档',476,other=612,ally=variants(590)),fight('闪焰队搭档',472,other=610,ally=variants(590)),
          say('莎娜','这个电子锁和解谜游戏里的好像。希特隆给我的机器能打开它！'),guests=['莎莉娜','莎娜'])
    scene('hq_admins','flare_hq_control','闪焰队干部','不能让任何人接近沉睡的宝可梦。',*[fight('闪焰队干部',n) for n in (478,477,479,473)])
    scene('legend','flare_hq_control','能源装置','供能管道断开了。传说宝可梦正在从沉眠中醒来……',{'kalos_legend':True},{'heal':True})
    scene('last_lysandre','flare_hq_control','弗拉达利','连传说宝可梦也选择了你？那就看看暴鲤龙和我的钥石！',fight('弗拉达利',526),
          {'kalos_final_shot':True},guests=['莎莉娜','莎娜'])
    scene('weapon','geosenge','ＡＺ','巨大的花沉入了地下。谢谢你把那些宝可梦从武器里解放出来。',guests=['莎莉娜','莎娜'])
    scene('couriway_prof','couriway','布拉塔诺','我没能早些看清老朋友的心事。小悠，陪我对战吧，我想亲眼看看你和伙伴将要走出的未来。',fight('布拉塔诺',328))
    scene('bridge_shauna','19','莎娜','一起走过这么多地方，还记得名水镇的第一战吗？我想让你看看，我们都长大了。',fight('莎娜',variants(321)))
    scene('bridge_tierno','19','提耶鲁诺','到我啦。这回我让舞蹈队的伙伴们一起上场！',fight('提耶鲁诺',324),{'heal':True},guests=['莎娜'])
    scene('bridge_trevor','19','多罗巴','以前我总在比较图鉴。今天希望你认识的是和我并肩走来的伙伴。',fight('多罗巴',325),hm(5),guests=['莎娜','提耶鲁诺'])
    scene('village','village','得抚','这里是受过伤的宝可梦能安心生活的地方。它们没有躲开你……我们回映雪道馆吧。')
    gym(8,'snowbelle','得抚','冰山徽章',13,26,'冰也有许多不同的样子，融化、凝结，再次改变。你准备怎么打破这层冰呢？','冰山徽章给你。八枚徽章都齐了，去挑战联盟吧。')
    scene('league_gate','league_gate','精英训练家','检查徽章，确认八枚齐全。还有一道考验，通过就能进入冠军之路！',fight('徽章关守卫',next_id('Robbie','Carbink',56)))
    scene('road_rival','zone_325','莎莉娜','联盟就在前面。这是属于我这个邻居的最后一场挑战，拿出你最好的队伍吧。',fight('莎莉娜',variants(593)),{'heal':True})
    scene('league','league_lobby','联盟向导','挑战厅设有四道门，各位天王的房间可以自由选择。全部获胜后，光之大厅才会开放。')
    elite=[('malva','帕琦拉',269,'火焰的新闻你一定看过。接下来，我会亲自采访这位打倒闪焰队的训练家。'),('siebold','志米',271,'料理和对战都是艺术。你能在这里呈现什么样的作品？'),('wikstrom','雁铠',187,'吾与钢铁之剑在此候战。堂堂正正，一分高下！'),('drasna','朵拉塞娜',270,'听说你走了很远才来到这里。欢迎来和我的龙们打个招呼。')]
    for slug,name,record,line in elite:
        scene('elite_'+slug,'e4_'+slug,name,line,fight(name,record),require='league',route=False)
    scene('diantha','champion_room','卡露妮','密阿雷的咖啡馆、比翼市的车站……原来在那些地方遇见的孩子，就是今天的挑战者。和我一同完成这场对战吧！',
          fight('卡露妮',276),say('卡露妮','这个瞬间，我会永远记住。来，一起去名人堂。'),{'kalos_warp':'kalos_hall_of_fame'},
          require=' '.join('elite_'+i[0] for i in elite))
    scene('champion','hall_of_fame','卡露妮','在这块石碑前，留下冠军和每一位同行伙伴的名字吧。',{'kalos_hall':True},{'heal':True},{'kalos_warp':'kalos_lumiose_north'})
    scene('parade','lumiose_north','布拉塔诺','今天的庆典献给这五位守护卡洛斯的朋友。这是卡洛斯勋章！',key('卡洛斯勋章'),
          say('ＡＺ','小悠，和我对战吧。我想重新知道，训练家和宝可梦一起前行是怎样的感觉。'),
          fight('ＡＺ',602,finish_on_loss=True),{'kalos_scene':'floette'},say('ＡＺ','你终于回来了……我的花叶蒂。'),
          say('莎娜','人群中，有一朵从天空缓缓飘下来的花。等待了三千年的两位伙伴，终于重逢了。'),
          {'heal':True},{'kalos_warp':'kalos_home_2f'},guests=['ＡＺ','莎娜','莎莉娜','提耶鲁诺','多罗巴'])
    for slug,name,record,line in elite:
        scene('again_'+slug,'e4_'+slug,name,line,fight(name,record),require='parade',route=False)
    scene('again_champion','champion_room','卡露妮','又见面了，我一直在等你下一场演出。',fight('卡露妮',276),
          {'kalos_repeat_hall':True},{'kalos_warp':'kalos_home_2f'},require=' '.join('again_'+i[0] for i in elite),route=False)


def next_id(name,species,level):
    # Route 22 badge gate Ace Trainer Robbie has three Pokemon; its original ID is stable.
    for k,n in trainers['people'].items():
        if n[0]==name and trainers['teams'][k][0]['species']==703:return int(k)
    raise ValueError(name)


def place_cast():
    """Stage meetings at doors, road junctions and the four positions of the NW hedge maze."""
    doors={'welcome':'home_1f','first_battle':'1','catch_lesson':'aquacorde','forest_friends':'2','rules':'forest',
           'skates':'gym_santalune','alexa':'4','dex_helpers':'lumiose','sleeping':'7_west','snorlax':'7_west',
           'korrina_duo':'11','coumarine_rival':'gym_coumarine','anistar_rival':'gym_anistar','broadcast':'gym_anistar',
           'crater_gate':'flare_hq','marsh_rival':'zone_73','village':'20'}
    targets={'garden_watch':(42,56),'garden_lure':(52,44),'garden_block':(31,43),'garden_dog':(42,31)}
    approaches={'welcome','first_battle','catch_lesson','forest_friends','rules','dex_helpers','korrina_5',
                'coastal','korrina_duo','coumarine_rival','marsh_rival','anistar_rival','road_rival'}
    paths={}
    maps=ROOT/'content/regions/kalos/maps'
    arrivals={}
    for p in maps.glob('*.json'):
        m=json.loads(p.read_text())
        for w in m.get('warps',[]):
            t=w['to']
            if t.get('at'):arrivals.setdefault(t['map'],set()).add(tuple(t['at']))
    for e in events:
        key=e['id'][2:]
        if key in ('broadcast','parade'):e['on_entry']=True
        if key in approaches:e['on_approach']=3
        if key not in doors and key not in targets:continue
        mid=e['map']
        if mid not in paths:
            m=json.loads((maps/(mid+'.json')).read_text())
            solids=m['physics']['collision']; water=m['physics'].get('water')
            w,h=m['size']
            blocked={tuple(a['at']) for a in m['warps']}
            start=tuple(m['spawn']); todo=deque([start]); component={start}
            while todo:
                x,y=todo.popleft()
                for xy in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                    i,j=xy
                    if xy in component or xy in blocked or not (0<=i<w and 0<=j<h) or int(solids[j][i]) or (water and int(water[j][i])):continue
                    component.add(xy);todo.append(xy)
            paths[mid]=(m,component,blocked|arrivals.get(mid,set())|{start})
        m,component,protected=paths[mid]
        reference=next((tuple(w['at']) for w in m['warps'] if w['to']['map']=='kalos_'+doors[key]),None) if key in doors else targets[key]
        if reference is None:continue
        # Leave doors and their incoming landing positions free, and keep large groups out of narrow passages.
        def space(p):
            x,y=p
            return sum(n in component for n in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
        available={p for p in component-protected if space(p)>=3}
        used=[]
        for dx,dy in [(0,2),(-2,2),(2,2),(0,4),(-3,0),(3,0)][:1+len(e.get('guests',[]))]:
            x,y=(reference if not used else used[0])
            choice=min(available,key=lambda p:(abs(p[0]-x-dx)+abs(p[1]-y-dy),-space(p),p))
            used.append(choice);available={p for p in available if abs(p[0]-choice[0])+abs(p[1]-choice[1])>=2}
        e['positions']=used


def roads():
    gate('dressed','vaniville','先在自己卧室的镜子前换好衣服。')
    gate('welcome','1 aquacorde','邻居在朝香镇自己家门口等你。')
    gate('moms_map','2','先把博士的信交给朝香镇家里的妈妈。')
    gate('catch_lesson','forest','莎莉娜在二号道路等着示范捕捉。')
    gate('forest_friends','3','莎娜还在森林里等你一起前进。')
    gate('rules','santalune','先在三号道路和一起穿过森林的伙伴道别。')
    gate('skates','gym_santalune','先在白檀道馆门外挑战轮滑手凛香。')
    gate('alexa','4','先取得虫子徽章，在白檀市北面找三色堇。')
    gate('dex_helpers','lumiose sycamore_lab cafe_soleil','吉娜和德克希欧在四号道路的花圃旁等你。')
    gate('diantha_cafe','5','莎莉娜约你去密阿雷南边的日轮咖啡馆。')
    gate('dance','camphrier shabboneau_castle','提耶鲁诺还在五号道路练习。')
    gate('castle','7','去古木镇的城堡，向城主打听七号道路。')
    gate('sleeping','6 palace parfum_garden','先到七号道路的桥边，看看是什么拦住了去路。')
    gate('snorlax','7_west cave','卡比兽正睡在七号道路的桥中央。')
    gate('route7_tag','8','莎莉娜、提耶鲁诺和多罗巴在七号道路等你。')
    gate('coastal','ambrette ambrette_fossil_lab','吉娜和德克希欧在八号道路等你。')
    gate('fossil_lab','9 glitter','化石研究员离开实验室去了闪耀洞窟。')
    gate('fossil','cyllage','先帮助闪耀洞窟内的化石研究员。')
    gate('grant_slope','gym_cyllage','查克洛在遥香市的车道上等你。')
    gate('badge_2','10','到遥香道馆取得岩壁徽章。')
    gate('stones','geosenge','十号道路列石间的闪焰队员还有行动。')
    gate('korrina_duo','11 reflection','可尔妮和路卡利欧在石香镇通往十一号道路的出口等你。')
    gate('reflection','shalour mastery','先穿过映穴。')
    gate('ring_rival','gym_shalour','娑罗市精练之塔的可可布尔在等你。')
    gate('badge_3','mastery_summit','可尔妮先在娑罗道馆接受挑战。')
    gate('surf','12 coumarine','先在精练之塔练习超级进化，再去娑罗市东出口找莎莉娜。')
    gate('coumarine_rival','gym_coumarine','莎莉娜在比翼道馆前等你。')
    gate('badge_4','13','先到比翼道馆挑战福爷。')
    gate('power_pass','power_plant','需要十三号道路岩石旁的发电厂通行证。')
    gate('plant','lumiose_north','密阿雷北部还在停电。要从十三号道路去发电厂恢复供电。')
    gate('prism','gym_lumiose','去北部棱镜塔下寻找莎娜和希特隆。')
    gate('badge_5','lysandre_cafe','弗拉达利邀请你在取得电压徽章后去咖啡馆。')
    gate('kings_rock','14 scary_house','先在弗拉达利咖啡馆与博士见面。')
    gate('scary_house','laverre','十四号道路边的屋子里，有人在等你们一起听故事。')
    gate('marsh_rival','gym_laverre','莎莉娜在十四号道路等你。')
    gate('factory_gate','factory','守卫还堵着精灵球工厂的正门。')
    gate('factory_reward','15 16 lost_hotel dendemille','到精灵球工厂找会长和莎莉娜。')
    gate('frost_news','frost','象牙猪似乎在冰结洞窟里感觉到了什么。')
    gate('abomasnow','17 anistar','暴雪阻挡了十七号道路，先去冰结洞窟查看。')
    gate('anistar_rival','gym_anistar','莎莉娜在百刻市道馆前等你。')
    gate('cafe_password','flare_labs','密阿雷红色咖啡馆的店员看守着书架后的门。')
    gate('lift_key','flare_labs_b2','研究所电梯要用茉蜜姬持有的钥匙。')
    gate('az_cell','flare_labs_b3','先在研究所地下二层探望被囚禁的巨人。')
    gate('crater_gate','flare_hq','石香镇西北入口仍被堵住。')
    gate('hq_pairs','flare_hq_control','通往能源室的电子锁还没有打开。')
    gate('weapon','18 couriway','闪焰队仍在威胁卡洛斯，十八号道路暂未开放。')
    gate('couriway_prof','19','布拉塔诺博士在连理镇的桥边等你。')
    gate('bridge_trevor','snowbelle 20 village','十九号道路桥上的伙伴还想与你见最后一面。')
    gate('village','gym_snowbelle','映雪道馆闭馆中。得抚去了二十号道路另一端的宝可梦村。')
    gate('badge_8','21 league_gate','冠军之路的守卫要查验卡洛斯的八枚徽章。')
    gate('league_gate','victory','联盟守卫的资格赛还没有完成。')
    gate('road_rival','league','莎莉娜在冠军之路的后半段等待挑战。')
    gate('league','e4_malva e4_siebold e4_wikstrom e4_drasna','先向联盟向导登记挑战。')
    gate('elite_malva elite_siebold elite_wikstrom elite_drasna','champion_room','只有本轮战胜四位天王的训练家，才能进入冠军大厅。')
    gate('diantha','hall_of_fame','名人堂只对赢得卡洛斯联盟挑战的队伍开放。')
    gate('parade','kiloude','先完成卡洛斯联盟及密阿雷的庆典。')


if __name__ == '__main__':
    trainers=json.loads((ROOT/'content/kalos_trainers.json').read_text())
    build()
    roads()
    place_cast()
    out={'events':events,'gates':gates}
    (ROOT/'content/kalos_campaign.json').write_text(json.dumps(out,ensure_ascii=False,indent=1)+'\n')
    print(len(events),'events;',len(gates),'map gates')
