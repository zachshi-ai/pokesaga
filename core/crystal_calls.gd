extends RefCounted
## Executes the original trainers' phone decision trees. Dialogue is localized for this game.
const DAYS:=["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
const NEWS:={"ENGINE_DUNSPARCE_SWARM":"anthony","ENGINE_YANMA_SWARM":"arnie","ENGINE_QWILFISH_SWARM":"ralph"}
const CHAT:={
	"jack":"做完学校的功课，我又来公园记招式笔记了。","beverly":"玛力露摇着尾巴的样子多可爱！你的伙伴也精神吗？","huey":"灯塔下海风真大。水手想站稳脚跟，得靠每天的锻炼。",
	"gaven":"沿着26号道路走下去就是联盟。我的队伍一直在这里训练。","beth":"和你对战后，我总在想哪一步可以做得更好。下回让我再试试！","jose":"有些宝可梦身上藏着特别的东西。我会再留心。",
	"reena":"我可不想输给同一位训练家两次！最近的练习很顺利。","joey":"我的小拉达今天又赢了！我觉得它在小拉达里面也是最顶尖的。","wade":"草叶底下经常藏着树果。发现好东西我会给你打电话。",
	"ralph":"安静地守着浮标，鱼儿才肯咬钩。你的旅行还顺利吗？","liz":"旅行碰到好玩的事，记得也告诉我！","anthony":"山路上的岩壁会回响。我和伙伴一边登山一边练习。",
	"todd":"满金百货楼顶偶尔有特卖。遇到好价钱我会告诉你。","gina":"有些宝可梦需要进化石。散步时我总会看看附近有没有闪光的石头。","irwin":"我是你的忠实听众！最近又去了哪些地方？",
	"arnie":"蜻蜻蜓飞得特别快。草丛里要是忽然热闹起来，我会马上联系你。","alan":"课本以外的事情，到道路上和宝可梦一起走走才能知道。","dana":"我的伙伴今天又精神了许多。对战也要每天认真练习呀。",
	"chad":"我想成为大木博士那样的研究员，最近正在观察野生宝可梦。","derek":"皮卡丘今天也和我一起散步。训练的路上有它陪着就开心了。","tully":"我的宝可梦在水下发现过特别的石头。真想知道水底还有些什么。",
	"brent":"一说起正辉，我就停不下来。你见过他本人吗？","tiffany":"我的皮皮真可爱！休息时帮它梳理一下，它就会开心起来。","vance":"今天风向很好。我的鸟宝可梦一下子就飞得看不见了。",
	"wilton":"钓鱼偶尔也会钓上宝贝来。我会替你留意精灵球。","kenji":"我在45号道路修行。有空的时候，来这里聊几句。","parry":"山风一吹，精神马上就来了。再来一场对战怎么样？","erin":"我还记着上次的对战呢。我的伙伴也很期待再见到你！"
}
const GOSSIP:={
	"jack":["雷雨天里，打雷更容易命中。","滚动连续命中时，威力会一击比一击强。","阳光强烈时，日光束可以立刻攻击。","变小的对手很怕踩踏。","碰到飞在半空的对手，可以用起风追击。","龙卷风也能打到飞到半空中的伙伴。","对方钻进地下时，地震依然能打到。","震级的强弱每次都可能不同。","沙暴会在战斗中持续造成伤害。","天气会影响招式的表现，记得看一眼天空。"],
	"liz":["阿鲁福遗迹的石壁藏着秘密。你去拼过石板吗？","阿速最喜欢他的鸟宝可梦。","桔梗市的训练家学校里，有位会跳舞的老师。","你见过会冲浪的皮卡丘吗？","哞哞鲜奶喝下去很有精神。","满金地下街有人帮宝可梦剪头发。","小茜的宝可梦个个都挺可爱。","自然公园定期办捕虫大会，你报名了吗？","最近路过的训练家打扮得真漂亮。","我本来有件很要紧的事……一下子又忘了。"],
	"brent":["正辉的家人住在满金市。","正辉的爷爷对各种宝可梦都很好奇。","满金市是正辉的老家。","正辉在关都的住处就在25号道路。","正辉和凯西很有缘分，你听说过吗？","正辉有个妹妹。你在他家见过她吗？","正辉家里的人聊起他，连饮食习惯也说得一清二楚。","别看正辉总在忙电脑，他对宝可梦也很了解。","满金花店的人说不定也认识正辉。","圆朱的舞场里，有人听说过正辉的事。"],
	"chad":["青绿是大木博士的孙子。","娜娜美最会照顾宝可梦了。","空木博士和大木博士常常讨论研究。","大木博士年轻的时候也有过远大的理想。","钢铁很了解用球果制作精灵球的方法。","宝可梦联盟里也能听到大木博士的故事。","你听了博士主持的宝可梦讲座吗？","大木博士也有丰富的对战经验。","有空去真新镇探望娜娜美吧。","博士为了研究去过许多地方。"]
}

static func datum(g,key:String)->Dictionary:return preload("res://core/crystal_phone.gd").data()[key]
static func period(h:int)->String:return preload("res://core/crystal_phone.gd").period(h)
static func value(g,s:Dictionary,key:String,t:String,date:int)->bool:
	if t in NEWS:return int(s.swarm.get(NEWS[t],-1))==date
	if t=="ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON":return int(s.get("sale",-1))==date
	if t=="ENGINE_FLYPOINT_GOLDENROD":return g._flags().get("fly_满金市",false)
	if t=="ENGINE_DAILY_BUG_CONTEST":return g._flags().get("js_contest_date","")==Time.get_date_string_from_system()
	if t=="ENGINE_ROCKETS_IN_RADIO_TOWER":return g._flags().get("j_radio_takeover",false) and not g._flags().get("j_radio_free",false)
	if "_GAVE_" in t:return s.gift_done.get("received_"+key,false)
	if "_HAS_" in t:return str(s.pending.get(key,"")).begins_with("gift/")
	if t.ends_with("_READY_FOR_REMATCH"):return s.pending.get(key,"")=="fight"
	return int(s.weekdays.get(key,-1))==date

static func assign(g,s:Dictionary,key:String,t:String,date:int):
	if t in NEWS:s.swarm[NEWS[t]]=date
	elif t=="ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON":s.sale=date;g._flags().js_roof_sale=date
	elif t.ends_with("_READY_FOR_REMATCH"):s.pending[key]="fight"
	elif "_HAS_" in t:
		var what:=t.get_slice("_HAS_",1)
		if what=="ITEM":what=datum(g,key).gifts[0]
		s.pending[key]="gift/"+what
	else:s.weekdays[key]=date

static func story(g)->String:
	for row in [["j2_silver_pass","竟然获准进入白银山了！"],["j2_snorlax","连睡在地鼠洞口的卡比兽都醒了！"],["j2_train_pass","你乘过磁浮列车了吗？"],["johto_champion","现在打来电话的是联盟冠军！"],["j_gym8","最后一场道馆战我也听说了！"],["j_radio_free","我在广播塔听到你的名字啦！"],["j_plant_clear","卡吉的怪电波消失了，真了不起。"],["j_badge_4","你在圆朱市的对战我都听说了！"],["j_badge_3","听说你拿下了满金道馆的徽章！"]]:
		if g._flags().get(row[0],false):return row[1]
	return CHAT.irwin

static func message(g,s:Dictionary,key:String,target:String,day:Dictionary)->String:
	var host=preload("res://core/crystal_phone.gd")
	var date:=host.current_day(day)
	if key=="kenji":
		if date>int(s.get("break_day",-1)):
			s.break_day=date+g.rng.randi_range(2,5)
			if s.pending.get(key,"")=="gift/PP_UP":s.pending.erase(key)
		if date==int(s.break_day) and period(day.hour)=="DAY":s.pending[key]="gift/PP_UP"
		elif date+1==int(s.break_day):return "明天白天我可以歇一会儿。到时候再给我打电话吧。"
	var place:String=host.map_name(g,datum(g,key).map)
	if target in ["RalphItemScript","AnthonySwarmScript","ArnieSwarmScript","ToddItemScript"] or ("Hurry" in target and int(s.swarm.get(key,-1))==date):
		if key=="todd":return "满金百货楼顶正在特卖，今天有空赶快去。"
		if key in host.SWARMS:return "%s正在大量出现！"%host.SWARMS[key][1]
	if "RocketRumor" in target:return "收音机怎么只播火箭队的声音了？快去满金市看看。"
	if s.pending.get(key,"")=="fight":return "要再比一场吗？我在%s等你。"%place
	if str(s.pending.get(key,"")).begins_with("gift/"):return "我在%s替你留了一份礼物。记得过来领取。"%place
	if "WrongNumber" in target:return "喂，是妈妈吗？……啊，打错号码了！"
	if ("Gossip" in target or "Trivia" in target or "PhoneTips" in target) and GOSSIP.has(key):
		var rows:Array=GOSSIP[key];return rows[g.rng.randi_range(0,rows.size()-1)]
	if key=="irwin":return story(g)
	if "UnseenRare" in target or "MonFlavorText" in target:
		var pool:Array=g.get_node("/root/Data").load_map("johto",datum(g,key).map).get("encounters",[])
		if not pool.is_empty():
			var r:Dictionary=pool[g.rng.randi_range(0,pool.size()-1)]
			return "我在%s发现了%s。下回经过时也留意一下！"%[place,g.get_node("/root/Data").species_of(r.species).name]
	if key=="todd" and int(s.get("sale",-1))==date:return "满金百货楼顶今天特卖，赶快去逛逛吧。"
	if NEWS.values().has(key) and int(s.swarm.get(key,-1))==date:return "%s正在大量出现！"%host.SWARMS[key][1]
	return CHAT[key]

static func run(g,s:Dictionary,key:String,incoming:bool,day:Dictionary)->String:
	var tree:Dictionary=datum(g,key).program
	var pc:=int(tree["in" if incoming else "out"])
	var v:Variant=false
	var date:=preload("res://core/crystal_phone.gd").current_day(day)
	for _step in 160:
		var op:Array=tree.ops[pc];pc+=1
		match op[0]:
			"readvar":v=DAYS[day.weekday]
			"checktime":v=period(day.hour)==op[1]
			"checkevent","checkflag":v=value(g,s,key,op[1],date)
			"setevent","setflag":assign(g,s,key,op[1],date)
			"clearevent":pass # A later setevent picks the new berry/ball for this request.
			"random":v=g.rng.randi_range(0,int(op[1])-1)
			"sjump":pc=int(op[1])
			"iftrue":
				if v:pc=int(op[1])
			"iffalse":
				if not v:pc=int(op[1])
			"ifequal":
				if str(v)==str(op[1]):pc=int(op[2])
			"ifnotequal":
				if str(v)!=str(op[1]):pc=int(op[2])
			"farsjump":return message(g,s,key,op[1],day)
	return CHAT[key]
