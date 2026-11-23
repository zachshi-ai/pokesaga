"""Build versioned island-challenge events. Dialogue is an original Chinese adaptation."""
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[1]
VERSIONS=('sun','moon','ultra_sun','ultra_moon')
MOVE_INDEX={row['key']:row['id'] for row in json.loads((ROOT/'content/moves.json').read_text())}
def moves(*keys):return [MOVE_INDEX[k] for k in keys]
def mon(sid,level,moves=(),form=''):
    m={'species':sid,'level':level}
    if moves:m['moves']=list(moves)
    if form:m['form']=form
    return m
def battle(name,team,**extra):
    cfg={'name':name,**extra}
    if isinstance(team,int):cfg['alola_team']=team
    elif isinstance(team[0],int):cfg['alola_variants']=team
    else:cfg['team']=team
    return {'battle':cfg}
def z(key):return {'alola_crystal':key+'_Z'}
def item(name):return {'alola_key':name}
def flag(key):return {'flag':'a_'+key}
def quiz(question,choices,correct):return {'alola_quiz':{'question':question,'choices':choices,'correct':correct}}
def wild(name,sid,lv,**cfg):return battle(name,[mon(sid,lv)],wild=True,**cfg)
def chapter(version):
    ultra=version.startswith('ultra')
    day=version.endswith('sun')
    mascot='索尔迦雷欧' if day else '露奈雅拉'
    cover=791 if day else 792
    recon,pal=('达尔斯','阿玛茉') if day else ('米翎','西奥尼拉')
    events=[]; gates={}; last='a_started'
    def event(key,place,actor,speech,*actions,guests='',need=None,slot='story',optional=False,pose=None):
        nonlocal last
        req=([last] if need is None else ['a_'+n for n in need.split()])
        key='a_'+key
        steps=[{'who':actor,'say':[speech]}] if speech else []
        for act in actions:
            if 'item' in act:
                act={'give_item':{'name':act['item'],'count':act['count'],'category':'ball' if '球' in act['item'] else 'heal'}}
            steps.append(act)
        steps.append({'flag':key})
        e={'id':key,'map':'alola_'+place,'who':actor,'steps':steps,'require':req,'anchor':slot}
        if guests:e['guests']=guests.split()
        if optional:e['optional']=True
        if pose:e['costume']=pose
        events.append(e)
        if not optional:last=key
    def gate(places,req,message):
        for area in places.split():gates['alola_'+area]={'require':'a_'+req,'message':message}
    def totem(key,place,sid,crystal,name,msg,slot='story',extra=()):
        event(key,place,name,msg,{'battle':{'name':'霸主'+name,'alola_totem_id':sid}},z(crystal),*extra,slot=slot)
    event('home','home_1f','妈妈','小悠，箱子晚点再收吧。库库伊博士约了你，沿着１号道路去看看。')
    if ultra:
        event('starter_gift','1','库库伊','刚才猫鼬少从草里冲出来，就是这三个小家伙把它拦住了。谁来陪你走接下来的路？',{'alola_starter':True})
        event('first_battle','1','哈乌','阿罗拉！轮到我来挑搭档啦。我们来比一场吧！',battle('哈乌',[491,492,493],alola_starter_only=True,finish_on_loss=True),{'heal':True})
    event('search_hala','iki','库库伊','岛屿之王哈拉还没回来。去马哈罗山路上问一问，那座桥就在遗迹前面。')
    rescue=[battle('烈雀',[mon(21,4,[64,45])])] if ultra else []
    event('bridge','mahalo_bridge','莉莉艾','小星云！桥上的烈雀围住它了。拜托你，把它带回来！',*rescue,
          {'say':['你把小星云护在怀里。它放出的光震断吊桥，一道黄色的身影在落水前接住了你们。'],'who':'卡璞・鸣鸣'},item('光辉石'),guests='小星云')
    if not ultra:
        event('starter_gift','iki','哈拉','卡璞・鸣鸣选中了你。来吧，挑一位愿意和你结伴的宝可梦。',{'alola_starter':True},guests='库库伊 莉莉艾')
        event('first_battle','iki','哈乌','我的搭档也决定好啦！出发前，先陪我对战吧！',battle('哈乌',[6,7,8],alola_starter_only=True,finish_on_loss=True),{'heal':True})
    event('stone','iki','哈拉','这颗光辉石能借我一晚上吗？明晚的祭典，请带上你的搭档。',{'alola_take':'光辉石'},item('阿罗拉图鉴'))
    event('catch_lesson','1','库库伊','先削弱野生宝可梦，再投球。看看岩狗狗怎么做！',{'alola_demo':True},{'item':'精灵球','count':10})
    if ultra:event('recon_festival','1',recon,'祭典附近的气场……和记录中一样。先把这些数值送回去。',guests=pal)
    event('festival','iki','哈乌','今晚要让守护神看到我们全力对战的样子！',battle('哈乌',[9,10,11],finish_on_loss=True),{'heal':True},
          {'say':['光辉石打磨好了。戴上它，等你取得Ｚ纯晶，就能和伙伴一起引出招式的力量。'],'who':'哈拉'},
          item('Ｚ强力手环' if ultra else 'Ｚ手环'),flag('z_ring'),*([flag('power_ring')] if ultra else []),guests='哈拉 莉莉艾 妈妈')
    event('rotom','lab','库库伊','洛托姆，进图鉴里来吧！岛屿巡礼的第一站在葱郁洞窟，先去训练家学校看看。',item('洛托姆图鉴'),item('诸岛巡礼之证'),guests='莉莉艾')
    event('school_intro','school','库库伊','学习装置会让没有出战的伙伴也分到经验。先去找学校的四位训练家切磋吧。',item('学习装置'),flag('exp_share'))
    for key,who,tid,place,slot in [('student_athlete','运动少女广美',21,'school','side1'),('student_joey','短裤小子乔伊',22,'school','side2'),('student_mia','幼儿园小朋友米娅',24,'school','side3')]:
        event(key,place,who,'来场练习赛吧！',battle(who,tid),need='school_intro',slot=slot)
    event('student_joseph','school','希望训练家约瑟夫','其他三位都和你较量过了。轮到我守住球场！',battle('希望训练家约瑟夫',436),need='student_athlete student_joey student_mia',slot='side4')
    event('school','school','宝可梦学校老师','要带着巡礼之证出门，先让我看看你会不会抓住属性克制的机会。',battle('宝可梦学校老师',[485,486,487] if ultra else 15))
    event('port_grunt','hauoli_marina','骷髅队员','来到港口还想躲开我们？把巡礼之证交出来！',battle('骷髅队员',47),guests='伊利马')
    event('ilima','hauoli_marina','伊利马','队员们走了。让我确认你的实力，再到２号道路的洞窟找我吧。',battle('伊利马',[52,215,216]))
    event('trial_cave','cavern','伊利马','去调查三处洞穴，找齐藏在里面的宝可梦。考验中的宝可梦不能捕捉。')
    rodent='猫鼬少' if day else '小拉达'
    sid=734 if day else 19;f='' if day else 'RATTATA_ALOLA'
    for i,slot in enumerate(['side1','side2','side3']):
        if i==2:event('cave_grunt','cavern','骷髅队员','我们把另外两个洞口堵住了！……喂，那家伙怎么从你面前出来了？',battle('骷髅队员',43),slot='guest1')
        event('den'+str(i+1),'cavern',rodent if i<2 else ('猫鼬探长' if day else '拉达'),'洞口里传来爪子刨土的声音。',battle(rodent if i<2 else '巢穴首领',[mon(sid if i<2 else (735 if day else 20),11,[33,44],f if i<2 or day else 'RATICATE_ALOLA')]),slot=slot)
    totem('normal','cavern_den',735 if day else 20,'NORMALIUM','猫鼬探长' if day else '拉达','你伸向台座时，巨大的身影从背后跃下。',extra=[{'item':'超级球','count':10},{'heal':True}])
    if ultra:event('recon_den','cavern',recon,'我们看到霸主的气场，也看到了你得到的纯晶。这种光和我们家乡的光很像。',guests=pal)
    event('z_lesson','2','库库伊','双臂交叉，再伸向伙伴。岩狗狗已经带上一般Ｚ，请你来指挥：点「战斗」、打开「特殊行动」，选择「Z 招式」里的撞击。',{'alola_z_demo':True})
    event('nebby_meadow','melemele_meadow','莉莉艾','小星云又从包里钻出去了！我在入口等你。')
    if ultra:event('recon_cave','seaward_cave',recon,'这种生物能穿过究极之洞。我们需要知道它的力量。',battle(recon,649 if day else 648),guests=pal+' 小星云')
    event('get_nebby','seaward_cave' if ultra else 'melemele_meadow','小星云','噗呦！小星云欢快地回到了莉莉艾的包里。')
    event('route3_hau','3','哈乌','太好了，小星云回来了。我的队伍也变强了，再来一场吧！',battle('哈乌',[12,13,14]),{'heal':True})
    event('hala','iki','哈拉','美乐美乐的大考验，就由我哈拉迎战！',battle('哈拉',23),z('FIGHTINIUM'),item('骑行装置'),flag('ride_tauros'),{'alola_stamp':'美乐美乐大考验印章'})
    event('sail','big_wave_beach' if ultra else 'hauoli_marina','库库伊','抓稳巨翅飞鱼的背鳍，浪头会送你去阿卡拉。' if ultra else '哈奇老人造的船已经修好了。登船，到阿卡拉继续巡礼！',guests='哈乌')
    event('akala','heahea','丽姿','欢迎来到阿卡拉！水莲、卡奇、玛奥会分别等着你。',guests='玛奥 哈乌')
    event('dexio','heahea','德克希欧' if day else '吉娜','我们从卡洛斯来调查阿罗拉的生态。让我看看你的伙伴吧。',battle('德克希欧' if day else '吉娜',74 if day else 75),*([item('基格尔德多面体')] if not ultra else [{'item':'全复药','count':1}]))
    event('paniola_rival','paniola','哈乌','牧场的牛奶要趁冰凉的时候喝！把伙伴恢复好，我们开始吧。',{'heal':True},battle('哈乌',[76,77,78]))
    event('stoutland','paniola_ranch','玛奥','长毛狗能嗅出埋在地里的东西。骑行装置上已经登记好了，向北就是潺潺之丘。',flag('ride_stoutland'))
    event('gladion','5','格拉吉欧','属性：空，上吧。我需要知道我们离目标还有多远。',battle('格拉吉欧',79),guests='哈乌')
    event('brooklet','brooklet','水莲','请骑乘拉普拉斯，去调查水面搅动的地方。',flag('ride_lapras'))
    for i in range(2):
        sid=751 if ultra else 746
        event('splash'+str(i),'brooklet','滴蛛' if ultra else '弱丁鱼','涟漪突然炸开，鱼群往下游的霸主居处移动了。',battle('水中的宝可梦',[mon(sid,17,[55,44] if ultra else [55,45])]),slot='side'+str(i+1))
    totem('water','brooklet_den',752 if ultra else 746,'WATERIUM','滴蛛霸' if ultra else '弱丁鱼','雨水落到湖面。一片黑影从水底浮上来。',extra=[item('垂钓竿'),flag('rod')])
    if ultra:event('recon_ranch','paniola_ranch',recon,'为了调查光辉大神，我们也在学习运用宝可梦的力量。',battle(recon,652 if day else 651),guests=pal)
    event('hapu_drifloon','6','哈普乌','他们想抢走飘飘球！你应付一个，另一个交给我的重泥挽马。',battle('骷髅队员',80))
    event('royal','royal_dome','皇家蒙面人','四名训练家同时登场！和哈乌、格拉吉欧一起体验皇家对战，第一名训练家的队伍倒下时就结算。',{'alola_royal':True},guests='哈乌 格拉吉欧')
    event('dance','wela_den','卡奇','仔细看嘎啦嘎啦的两支舞。记住位置、队形和混进来的家伙。',quiz('哪只嘎啦嘎啦改变了站姿？',['左边','中间','右边'],1),battle('嘎啦嘎啦',[mon(105,18,[29,125],'MAROWAK_ALOLA')]),quiz('第二支舞混进了谁？',['登山男','怪力','卡奇'],0),battle('登山男大卫',186),quiz('谁在最后一排跳得格外起劲？',['嘎啦嘎啦','霸主宝可梦','登山男'],1))
    totem('fire','wela_den',105 if ultra else 758,'FIRIUM','嘎啦嘎啦' if ultra else '焰后蜥','山顶的火苗猛地窜高。',extra=[flag('ride_charizard')])
    if ultra:event('recon_route8','8',recon,'隧道的气场数值升高了。阿克罗玛，拜托你协助我们继续追踪它。',guests=pal+' 阿克罗玛')
    event('jungle','lush','玛奥','今天一起做玛奥特制料理。去丛林里把食材找齐吧。')
    ingredients=['芒芒果','甜甜蜜','大根茎'] if ultra else ['小蘑菇','文柚果','复活草','奇迹种子']
    for i,ing in enumerate(ingredients):event('ingredient'+str(i),'lush',ing,'你在叶片下面找到了'+ing+'，放进食材袋里。',slot='side'+str(i+1))
    totem('grass','lush',754,'GRASSIUM','兰螳花','料理刚刚出锅，粉红色的镰刀就从树叶后探了出来。')
    event('burnet','dimensional_lab','芭内特','传说中的究极之洞有时会通到别的世界。莉莉艾刚来时，小星云就是这样出现的。去可霓可市找丽姿吧。',guests='莉莉艾 库库伊')
    event('plumeria','akala_outskirts','布尔美丽','别总拿那些孩子练手。骷髅队的大姐会照看他们！',battle('布尔美丽',89))
    event('olivia','life','丽姿','这里是卡璞・蝶蝶的遗迹。我的岩石伙伴已经准备好了。',battle('丽姿',90),z('ROCKIUM'),{'alola_stamp':'阿卡拉大考验印章'})
    event('aether_invite','hano','扎奥博','我是以太基金会的分部长。豪诺豪诺的船，今天为你们留了座位。',guests='哈乌')
    event('welcome_aether','aether_docks','碧珂','电梯上方便是保护区。请照顾好这里受过伤的宝可梦。')
    event('nihilego','aether_conservation','露莎米奈','我会保护这里所有需要爱的孩子……等等，头顶的光是什么？',battle('虚吾伊德',[mon(793,27,[491,29,474])]),guests='哈乌 '+(recon+' '+pal if ultra else '碧珂'))
    event('malie','malie','哈乌','原来那就是究极异兽。从码头穿过马利埃，博士在庭园等我们。',battle('哈乌',[217,218,219]))
    event('garden','malie_garden','库库伊','拉纳基拉山顶在建一座联盟。巡礼的人，也可以在那里成为冠军。先去辉克拉尼的天文台。')
    event('hokulani','hokulani','马睿因','我们得把装置准备好。马玛内在观测室里等你。',*([] if ultra else [battle('马睿因',167)]))
    if ultra:
        for i in range(3):event('battery'+str(i),'observatory','虫电宝','你抱起走散的虫电宝，把它带回充电车。',slot='side'+str(i+1))
    if ultra:
        for i,sid in enumerate((239,125,0)):
            event('electric_puzzle' if i==0 else 'circuit'+str(i),'observatory_151','马玛内','按下四角磁铁，让虫电宝转到指定的位置。',{'alola_circuit':i},*([battle('电击怪' if i==0 else '电击兽',[mon(sid,29+i)])] if sid else []))
    else:
        for i,(noise,opts,answer,sid) in enumerate([('咚、咚、咚咚咚！对应哪一种设备？',['精灵球','宝可梦中心','电脑'],1,736),('滋啦……洛托！是哪个装置的声音？',['宝可搜寻镜','洛托姆图鉴','治疗机器'],1,737),('嗡——吱、吱。什么宝可梦在发声？',['虫电宝','锹农炮虫','电击怪'],0,737),('门外响起了考验的音乐，谁来了？',['队长','岛屿之王','霸主宝可梦'],2,0)]):
            event('electric_puzzle' if i==0 else 'sound'+str(i),'observatory_151','马玛内','停电了！听设备发出的声音，打开下一道安全门。',quiz(noise,opts,answer),*([battle('闯入的宝可梦',[mon(sid,27)])] if sid else []))
    totem('electric','observatory_151',777 if ultra else 738,'ELECTRIUM','托戈德玛尔' if ultra else '锹农炮虫','霸主循着电流冲进了观测室。',extra=[z('STEELIUM')])
    event('guzma_garden','malie_garden','古兹马','巡礼和联盟到底有什么了不起的？让我的具甲武者试试你。',battle('古兹马',138),{'alola_starter_crystal':True},guests='库库伊')
    event('mudsdale','12','哈普乌','骑上重泥挽马，就可以踩过这片崎岖的岩石了。',flag('ride_mudsdale'))
    if ultra:event('recon_tapu','tapu',recon,'这里曾经也失去了光。我们的世界一直被黑暗笼罩，我想知道人和宝可梦能做些什么。',guests=pal)
    event('house','aether_house','阿塞萝拉','店铺关门之后，里面还有声音。拿好宝可搜寻镜，跟我到旧址去。')
    for i,(who,sid) in enumerate([('鬼斯',92),('鬼斯通',93),('耿鬼',94)]):
        event('photo'+str(i),'megamart',who,['传送带自己转了起来。','购物车正在滑动。','玩偶飘到了半空。'][i],quiz('用搜寻镜对准哪一处？',['收银台的传送带','购物车','悬空的玩偶'],i),battle(who,[mon(sid,(30 if ultra else 27)+i,[101,109])]),slot='side'+str(i+1))
    totem('ghost','megamart_134',778,'GHOSTIUM','谜拟丘','后屋的相片贴满了墙。背后传来很轻的一声「皮卡」。')
    event('kidnapped','aether_house','布尔美丽','想把猫鼬少带回去？你一个人来魄镇。',battle('布尔美丽',238))
    event('sharpedo','15','越橘','回答我，你相信的是硬币，还是自己的判断？巨牙鲨可以冲破海上的岩礁。',flag('ride_sharpedo'))
    event('po_entry','po','默丹','进去之前想清楚，魄镇里没有人会来救你。')
    event('shady','shady_house','骷髅队员','暗号呢？老大最爱的招式、饮料和宝可梦是？',quiz('老大喜欢的饮料？',['树果汁','哞哞鲜奶','美味之水'],0),quiz('你敢保证吗？',['当然！','不敢保证。'],1))
    event('guzma_po','shady_house_131','古兹马','你跟到这里，就是为了那只猫鼬少？那就打赢我。',battle('古兹马',235),z('BUGINIUM'),guests='猫鼬少')
    event('lillie_taken','aether_house','哈乌','莉莉艾为了保护我们，跟布尔美丽走了。小星云也在她的包里。',battle('格拉吉欧',239),guests='格拉吉欧 阿塞萝拉')
    event('nanu','malie_marina','默丹','先别上船。乌拉乌拉的大考验就在码头办，让我看看你有没有救人的本事。',battle('默丹',154),z('DARKINIUM'),{'alola_stamp':'乌拉乌拉大考验印章'},guests='格拉吉欧 哈乌')
    event('faba','aether_entrance','扎奥博','你们还真敢回来。地下研究区？先过我这一关。',battle('扎奥博',132))
    event('secret_lab','aether_lab_b','以太研究员','被封锁的报告写着「科斯莫古」与「属性：空」。你们不能把资料带走！',battle('以太研究员',242,alola_other=243,alola_ally=[220,221,222],ally='alola',double=True),guests='哈乌')
    event('lobby_guards','aether_entrance','以太职员','格拉吉欧的属性：空来到你的身边。先从正门的守卫之间打开一条路！',battle('以太职员',455,alola_other=456,alola_ally=[441,441,441],ally='alola',double=True),guests='格拉吉欧')
    event('faba_key','aether_entrance','扎奥博','研究所有没有你们要找的人？上层的钥匙卡可不会白给！',battle('扎奥博与以太职员',241,alola_other=442,alola_ally=[450,451,452],ally='alola',double=True),guests='以太职员 哈乌')
    event('guzma_mansion','aether_mansion','古兹马','这里由我守着。想找理事长，先拿出你的实力。',battle('古兹马',236),guests='格拉吉欧')
    if ultra:event('recon_mansion','aether_mansion',recon,'理事长要去追光辉大神。我们得确定你能保护这里。',battle(recon,500 if day else 498),guests=pal)
    event('lusamine','aether_mansion','露莎米奈','我要用小星云的力量打开究极之洞，把奈克洛兹玛挡在阿罗拉外面。' if ultra else '属于我的美丽世界就在洞的另一边。莉莉艾，别来妨碍我！',battle('露莎米奈',131),{'say':['强光过后，两人消失在究极之洞里。小星云蜷缩成了坚硬的茧。'],'who':'莉莉艾'},guests='莉莉艾 格拉吉欧 小星云')
    event('flute1','aether_docks','格拉吉欧','带莉莉艾去波尼岛。和另一支笛子一起吹响，也许就能让小星云醒来。',{'item':'大师球','count':1},item('月亮之笛' if day else '太阳之笛'),guests='莉莉艾',pose='after')
    event('seafolk','seafolk','莉莉艾','我想靠自己的脚走过去，一起去找波尼岛的岛屿女王吧。',pose='after')
    event('machamp','ancient_path','哈普乌的祖母','把怪力登记到骑行装置上，它可以帮你推开遗迹的大石块。',flag('ride_machamp'))
    event('hapu_chosen','hope','哈普乌','卡璞・鳍鳍认可我了。我将继承爷爷的职责，成为波尼岛的岛屿女王。',guests='莉莉艾',pose='after')
    event('flute2','exeggutor','莉莉艾','石台上还有一支笛子。请你拿上它，到祭坛时我们一起吹响。',item('太阳之笛' if day else '月亮之笛'),guests='阿罗拉椰蛋树',pose='after')
    event('skull_apology','ancient_path','布尔美丽','队员们只想找回老大。之前是我们做错了。带上毒Ｚ，拜托你们。',z('POISONIUM'),guests='骷髅队员')
    if ultra:event('recon_canyon','canyon',recon,'我愿把剩下的希望交给你。再和毒贝比交手一次吧。',battle(recon,501 if day else 499),guests=pal)
    else:event('hapu','canyon','哈普乌','这是我当上岛屿女王后的第一场大考验。重泥挽马，我们一起上！',battle('哈普乌',155),z('GROUNDIUM'),{'alola_stamp':'波尼大考验印章'})
    if not ultra:event('mina_gift','canyon','茉莉','我是波尼岛的队长。考验还在构思呢，现在就收下妖精Ｚ吧。',z('FAIRIUM'))
    for i,(sid,who) in enumerate([(782,'心鳞宝'),(783,'鳞甲龙')]):
        event('dragon_guard'+str(i),'canyon',who,'峡谷壁上留下了宝可梦锋利的爪痕。',battle(who,[mon(sid,(42 if ultra else 40)+i,[337,29])]),slot='side'+str(i+1))
    totem('dragon','canyon_175',784,'DRAGONIUM','杖尾鳞甲龙','洞中的鳞片发出响亮的金属声。那是霸主的战书。')
    altar='altar' if day else 'moone'
    event('altar',altar,'莉莉艾','太阳之笛、月亮之笛……小星云，我们一起把你唤醒。',{'say':['两道笛声相遇，小星云冲破光茧，变成了'+mascot+'。']},guests='小星云',pose='after')
    if ultra:
        form='NECROZMA_DUSK_MANE' if day else 'NECROZMA_DAWN_WINGS'
        event('fusion',altar,'奈克洛兹玛','古兹马和露莎米奈被甩出洞口。黑色棱镜扑向小星云，吞没了祭坛的光！',battle('奈克洛兹玛',[mon(800,50,(moves('SUNSTEEL_STRIKE','MORNING_SUN','PSYCHO_CUT','NIGHT_SLASH') if day else moves('MOONGEIST_BEAM','MOONLIGHT','PSYCHIC','POWER_GEM')),form)]),guests='莉莉艾 露莎米奈 古兹马',pose='after')
        event('wormhole',altar,recon,'坐上我们的'+('露奈雅拉' if day else '索尔迦雷欧')+'。黑暗的另一端是我们的家乡，究极大都会。',flag('ultra_ride'),guests=pal)
        event('tower','megalopolis','西奥尼拉' if day else '达尔斯','光辉大神在塔顶。请你把光带回两个世界。')
        event('ultra_necrozma','megalo_tower','奈克洛兹玛','棱镜张开双翼，塔顶在顷刻间亮如白昼。',battle('究极奈克洛兹玛',[mon(800,60,moves('PHOTON_GEYSER','SMART_STRIKE','POWER_GEM','DRAGON_PULSE'),'NECROZMA_ULTRA')],alola_totem={'stat':'all','stages':1,'allies':[]}))
        event('poipole','megalopolis',recon,'毒贝比也想看看阿罗拉的阳光。你愿意带上它吗？',{'alola_poipole':True})
        event('poipole_return','megalopolis',recon,'毒贝比还在等你，要带上它吗？',{'alola_poipole':True},optional=True,need='poipole')
        event('light',altar,'莉莉艾','阿罗拉的阳光回来了。我和母亲先带小星云回去，你的岛屿巡礼还差最后一场。',{'item':'究极球','count':3},guests='露莎米奈 茉莉',pose='after')
        event('pink','mina_house','茉莉','我的考验是把七色花瓣组合成虹色之花。打赢我，粉红色的花瓣就给你。',battle('茉莉',507),item('粉红花瓣'))
        event('orange','cemetery','伊利马','去好奥乐墓园找到我，就能得到第二种颜色。来，让我看看你的成长。',battle('伊利马',502),item('橙色花瓣'))
        event('green','lush','玛奥' if day else '水莲','在树影下交换花瓣吧，我们两个人的颜色都在这里。',battle('玛奥' if day else '水莲',505 if day else 503),item('绿色花瓣'),item('蓝色花瓣'),guests='水莲' if day else '玛奥')
        event('red','wela','卡奇','红色属于山上的火焰。登山男大卫也在等着你。',*([battle('卡奇',504),battle('登山男大卫',535)] if day else []),item('红色花瓣'))
        event('yellow','observatory','马玛内','马睿因要出发了。我想好好和他告别，也想把这片黄色交给你。',*([battle('马玛内',506)] if not day else []),item('黄色花瓣'))
        event('purple','aether_house','默丹','阿塞萝拉有联盟的事。她把紫色花瓣托给了我。',*([battle('默丹',508)] if not day else []),item('紫色花瓣'))
        event('rainbow','mina_house','茉莉','七色都齐了！虹色之花会引来波尼岛最后的霸主。',{'alola_petals':True})
        totem('fairy','mina_house',743,'FAIRIUM','蝶结萌虻','翅膀扇起了浓烈的花粉。')
        event('hapu','exeggutor','哈普乌','我就在椰蛋树岛等你。用最后一场大考验结束四岛巡礼吧！',battle('哈普乌',497),z('GROUNDIUM'),{'alola_stamp':'波尼大考验印章'})
        event('mount_necrozma','lanakila_117','奈克洛兹玛','它受了伤，手环中的光让它重新抬起头。',{'alola_capture':800,'level':65},z('ULTRANECROZIUM'),{'who':'阿克罗玛','say':['这两台仪器能让奈克洛兹玛借用日月的力量。保管好它们。']},item('奈克洛索尔合体器'),item('奈克洛露奈合体器'),need='hapu',optional=True,slot='side3')
        event('nebby','mahalo','莉莉艾','小星云恢复精神了。它一直想和你并肩旅行。',{'alola_capture':cover,'level':60},z('SOLGANIUM' if day else 'LUNALIUM'),need='hapu',optional=True,pose='after')
    else:
        event('ultra_sea','ultra_deep_sea','露莎米奈','这里才是我的归属。谁都别想夺走我和这些孩子的世界。',battle('露莎米奈',158,alola_mother_beast=True),guests='莉莉艾 古兹马 虚吾伊德',pose='after')
        event('nebby',altar,'莉莉艾','谢谢你把母亲带回来。小星云抬起头了，它希望你亲自接住它的力量。',{'alola_capture':cover,'level':55},guests=mascot,pose='after')
    event('gladion_last','lanakila','格拉吉欧','妈妈和莉莉艾都在寻找自己的答案。我也有我的路。让我和银伴战兽再战一次。',battle('格拉吉欧',[240,415,416]))
    if not ultra:event('hau_last','lanakila','哈乌','离山顶只剩最后一段了。我们从祭典走到这里，我还想再和你比一次。',battle('哈乌',[482,483,484]))
    event('league','league','库库伊','阿罗拉第一次迎来联盟的挑战者。四扇门，你可以按自己的顺序走。')
    for room,who,idx in [('fighting','马睿因' if ultra else '哈拉',489 if ultra else 152),('rock','丽姿',153),('ghost','阿塞萝拉',149),('flying','卡希丽',156)]:
        event('elite_'+room,'e4_'+room,who,'欢迎来到阿罗拉联盟。让我的伙伴看看你巡礼的成果！',battle(who,idx),need='league')
    event('champion','champion_room','哈乌' if ultra else '库库伊','我们一起从美乐美乐走到这里了。最后一次挑战，就由我来！' if ultra else '冠军的座位是你的。但你愿意再和我较量一场吗？这就是我盼了许久的联盟！',
          battle('哈乌' if ultra else '库库伊',[494,495,496] if ultra else [129,413,414]),{'alola_hall':True},need='elite_fighting elite_rock elite_ghost elite_flying')
    event('festival_final','iki','哈乌','你是阿罗拉第一位冠军！快来，岛上的大家都到了。',guests='库库伊 哈拉 莉莉艾',pose='after')
    if not ultra:event('guardian','conflict','莉莉艾','来，向卡璞・鸣鸣说声谢谢。要是没有它，吊桥上的我们早就落进河里了。',wild('卡璞・鸣鸣',785,60,finish_on_escape=True,capture_flag='a_tapu_koko_caught'),z('TAPUNIUM'),guests='卡璞・鸣鸣',pose='after')
    event('credits','hauoli_marina','格拉吉欧' if ultra else '莉莉艾','替我和大家说声再见。妈妈……谢谢你能来送行。' if ultra else '我想带母亲去关都找治疗的方法。下一次见面，我一定也能成为训练家。',{'alola_warp':'alola_home'},guests='露莎米奈 哈乌' if ultra else '哈乌 库库伊',pose='after')
    gate('lab school','festival','先参加利利小镇的祭典。')
    gate('cavern','ilima','伊利马在好奥乐港口等你来证明实力。')
    gate('3 melemele_meadow seaward_cave','normal','葱郁洞窟的考验还没有完成。')
    gate('heahea 4 paniola paniola_ranch 5 brooklet','sail','先完成美乐美乐的大考验，再到海边出发。')
    gate('6 royal royal_dome 7 wela','water','先取得水莲的水Ｚ。')
    gate('8 lush','fire','维拉火山的考验仍在进行。')
    gate('memorial_hill akala_outskirts life konikoni','grass','先完成树荫丛林里的料理。')
    gate('aether_docks aether_conservation','aether_invite','需要扎奥博在豪诺豪诺度假地的邀请。')
    gate('malie malie_marina malie_garden 10 hokulani observatory','nihilego','先完成以太乐园的首次访问。')
    gate('11 12 13 14 15 tapu aether_house megamart','electric','先完成天文台的电之考验。')
    gate('16 17 po shady_house','ghost','先在废弃超市旧址完成考验。')
    gate('aether_lab aether_lab_b aether_mansion','nanu','莉莉艾还未被带走，研究区暂时关闭。')
    gate('seafolk wilds ancient_path hope exeggutor','flute1','等格拉吉欧备好前往波尼岛的船。')
    gate('canyon','flute2','需要在椰蛋树岛找到另一支笛子。')
    gate('altar moone','dragon','峡谷深处的霸主正守着祭坛之路。')
    gate('megalopolis megalo_tower','wormhole','前往究极大都会需要究极调查队的坐骑。')
    gate('ultra_deep_sea','altar','需要与小星云一起打开究极之洞。')
    gate('lanakila','hapu' if ultra else 'nebby','先走完波尼岛的大考验并解决祭坛事件。')
    gate('league e4_fighting e4_rock e4_ghost e4_flying','gladion_last' if ultra else 'hau_last','还没通过上山路上的约定对战。')
    gate('champion_room','elite_flying','冠军之座须先通过本轮四天王。')
    gate('cavern_den','den3','三个巢穴里的宝可梦都被找出来后，才能进入霸主居处。')
    gate('brooklet_den','splash1','请先清查水莲标出的两处涟漪。')
    gate('wela_den','water','需要先完成潺潺之丘的水之考验。')
    gate('observatory_151','hokulani','先到天文台外与马睿因会合。')
    gate('megamart_133','house','请先和阿塞萝拉一起准备好宝可搜寻镜。')
    gate('megamart_134','photo2','在卖场里拍下三只幽灵宝可梦后，才能进入后屋。')
    gate('shady_house_131','shady','请先通过屋内的暗号。')
    gate('aether_mansion','faba_key','扎奥博掌管着通往理事长宅邸的钥匙卡。')
    gate('canyon_175','dragon_guard1','先通过心鳞宝和鳞甲龙守护的试炼地。')
    gate('megalo_tower','tower','先和塔下的究极调查队会合。')
    # Native zone subdivisions and public transit can each be approached from multiple sides.
    families={'canyon':'canyon_171 canyon_172 canyon_173 canyon_174','shady_house':'shady_house_122 shady_house_123 shady_house_124 shady_house_125 shady_house_127 shady_house_129',
              'lanakila':'lanakila_117 lanakila_118 lanakila_119 center_lanakila','aether_docks':'aether_entrance pass_aether_dock',
              'heahea':'paniola_ranch center_heahea center_paniola center_5 nursery tide_song','wela':'center_royal','lush':'lush_60 lush_61 lush_62 lush_63 center_8 aether_base_8',
              'konikoni':'center_konikoni diglett_tunnel 9','malie':'center_malie center_hokulani center_10 malie_cape','tapu':'center_tapu 13 14 blush_mountain motel_13',
              '16':'center_16 17 zygarde_lab ulaula_meadow','seafolk':'center_seafolk seafolk_restaurant poni_breaker_coast mina_house','megalopolis':'pass_ultra_megalopolis'}
    for base,rooms in families.items():
        for room in rooms.split():gates.setdefault('alola_'+room,gates['alola_'+base])
    return {'events':events,'gates':gates}
if __name__=='__main__':
    versions={v:chapter(v) for v in VERSIONS}
    out=ROOT/'content/alola_campaign.json'
    out.write_text(json.dumps(versions,ensure_ascii=False,separators=(',',':'))+'\n')
    print({k:len(d['events']) for k,d in versions.items()})
