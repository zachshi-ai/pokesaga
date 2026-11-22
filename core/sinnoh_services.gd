extends RefCounted
## Local shop, service and daily schedules. The caller supplies the Platinum item catalogue.
const Party:=preload("res://core/party.gd")
const FR:=preload("res://core/frlg_sidequests.gd")
const LABELS:={"heart":"爱心","star":"星星","fire":"火焰","ele":"电光","line":"线条","song":"音符","party":"彩纸","smoke":"烟雾","flower":"花朵","bubble":"泡泡","foamy":"泡沫","confetti":"彩纸"}
const WEEK:=["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
const DAY_RIBBONS:=["微笑奖章","警戒奖章","惊吓奖章","沮丧奖章","疏忽奖章","放松奖章","睡懒觉奖章"]

static func badges(f: Dictionary) -> int:
	var count:=0
	for i in 8:
		if f.get("s_badge_%d"%(i+1),false):count+=1
	return count

static func goods(side,script: String,flags: Dictionary) -> Array:
	var data: Dictionary=side.data()
	var id:=str(data.sellers.get(script,""))
	var keys: Array=[]
	if id=="common":
		var rank:=int([1,2,2,3,3,4,4,5,6][badges(flags)])
		for row in data.shops.common:
			if int(row[1])<=rank:keys.append(row[0])
	elif id!="":keys=data.shops[id]
	return keys

static func shop(g,side,script: String) -> void:
	var keys:=goods(side,script,g._flags())
	var labels: Array=[]
	for key in keys:labels.append("%s    ₽%d"%[side.item_name(key),int(side.data().prices[key])])
	labels.append_array(["进化材料产地","离开商店"])
	g._pick("特产柜台" if side.data().sellers[script]!="common" else "友好商店 · ₽%d"%int(g.save_data.get("money",0)),labels,func(i):
		if i==keys.size():
			g._open_shop()
			var panel=g.menu_layer.get_child(-1)
			for button in panel.find_children("*","Button",true,false):
				if button.text=="进化材料产地":
					button.button_pressed=true
					break
			return
		if i>=keys.size():return
		var key:=str(keys[i])
		var price:=int(side.data().prices[key])
		var max_count:=mini(99,int(g.save_data.get("money",0))/maxi(1,price))
		if max_count==0:
			FR.say(g,"钱不够。","店员")
			return
		var counts:=[1]
		for n in [5,10]:
			if max_count>=n:counts.append(n)
		if max_count>10:counts.append(max_count)
		var amounts: Array=counts.map(func(n):return "%d 件    ₽%d"%[n,n*price])
		amounts.append("取消")
		g._pick("购买"+side.item_name(key),amounts,func(j):
			if j>=counts.size():return
			var count:=int(counts[j])
			if int(g.save_data.money)<price*count:return
			g.save_data.money-=price*count
			side.give(g,key,count)
			if key=="POKE_BALL" and count>=10:side.give(g,"PREMIER_BALL")
			g._persist()
			g._show_toast("获得%s ×%d"%[side.item_name(key),count])))

static func first(g) -> Dictionary:
	for mon in g.save_data.get("party",[]):
		if mon is Dictionary and not mon.is_empty():return mon
	return {}

static func types_of_ribbons(g) -> int:
	var types: Dictionary={}
	for mon in g.save_data.get("party",[]):
		if not mon is Dictionary:continue
		for k in mon.get("sinnoh_awards",[]):types[k]=true
		for category in mon.get("sinnoh_ribbons",{}):
			for rank in int(mon.sinnoh_ribbons[category]):types["contest_%s_%d"%[category,rank]]=true
	return types.size()

static func ribbon(g,mon: Dictionary,name: String,speaker: String):
	var awards: Array=mon.get_or_add("sinnoh_awards",[])
	if awards.has(name):
		FR.say(g,"%s已经佩戴着%s。"%[mon.name,name],speaker)
		return
	awards.append(name)
	g._persist()
	FR.say(g,"%s获得了%s。"%[mon.name,name],speaker)

static func ribbon_shop(g):
	var mon:=first(g)
	if mon.is_empty():return
	var options: Array=[]
	var names: Array=[]
	var prices: Array=[]
	for pair in [["华丽奖章",10000],["高级奖章",100000],["顶级华丽奖章",999999]]:
		if not mon.get("sinnoh_awards",[]).has(pair[0]):
			options.append("%s    ₽%d"%pair)
			names.append(pair[0])
			prices.append(pair[1])
	options.append("离开")
	g._pick("奖章联合组织",options,func(i):
		if i>=names.size():return
		if int(g.save_data.get("money",0))<int(prices[i]):FR.say(g,"你的钱还不够。","柜员")
		else:
			g.save_data.money-=int(prices[i])
			ribbon(g,mon,names[i],"柜员"))

static func news(g,side) -> void:
	var state: Dictionary=g.save_data.get_or_add("s_press",{})
	var today:=Time.get_date_string_from_system()
	if state.get("day","")!=today:
		var seen: Array=g.save_data.get("dex",{}).get("seen",[]).filter(func(id):return int(id)>0 and int(id)<=493)
		if seen.is_empty():
			FR.say(g,"先记录一些宝可梦，再来看看征稿。","神奥新闻社")
			return
		state.day=today
		state.species=int(seen[g.rng.randi_range(0,seen.size()-1)])
		state.done=false
		g._persist()
		FR.say(g,"今天的稿件需要%s的照片。今天之内带它来新闻社吧！"%Data.species_of(int(state.species)).name,"神奥新闻社")
	elif state.get("done",false):FR.say(g,"今天的稿件已经发出了。明天再来吧。","神奥新闻社")
	elif not side.with_species(g,int(state.species)):FR.say(g,"我们在等%s的照片。"%Data.species_of(int(state.species)).name,"神奥新闻社")
	else:
		var balls:=["ULTRA_BALL","GREAT_BALL","POKE_BALL","NET_BALL","DIVE_BALL","NEST_BALL","REPEAT_BALL","TIMER_BALL","LUXURY_BALL","DUSK_BALL","HEAL_BALL","QUICK_BALL"]
		var key:=str(balls[g.rng.randi_range(0,balls.size()-1)])
		side.give(g,key,3)
		side.give(g,"HEART_SCALE")
		state.done=true
		g._persist()
		FR.say(g,"照片拍好了！请收下%s ×3 和心之鳞片。"%side.item_name(key),"神奥新闻社")

static func unown_seen(save: Dictionary) -> Dictionary:
	var forms: Dictionary={}
	for key in save.get("dex_variants",{}):
		var parts:=str(key).split("|",true)
		if parts.size()<4 or parts[0]!="201":continue
		var letter:=str(parts[1]).trim_prefix("UNOWN_")
		if letter.is_empty():letter="A"
		forms[letter]=true
	return forms

static func trader(g,side) -> void:
	var case_name: String=side.item_name("SEAL_CASE")
	if not side.has(g,case_name):
		FR.say(g,"先向我妈妈领取贴纸盒吧。","随意镇的男孩")
		return
	FR.pick_party(g,"给他看哪只未知图腾？",func(mon):return int(mon.species_id)==201,func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var letter:=str(mon.get("form","")).trim_prefix("UNOWN_")
		if letter.is_empty():letter="A"
		var seals: Dictionary=g.save_data.get_or_add("sinnoh_seals",{})
		var key:="LETTER_"+letter
		seals[key]=mini(99,int(seals.get(key,0))+10)
		g._persist()
		FR.say(g,"这种未知图腾真有意思！给你同样形状的字母贴纸 ×10。","随意镇的男孩"))

static func seal_name(key: String) -> String:
	if key.begins_with("LETTER_"):
		var letter:=key.trim_prefix("LETTER_")
		return "字母贴纸 "+("!" if letter=="EXCLAMATION" else "?" if letter=="QUESTION" else letter)
	var bits:=key.split("_SEAL_")
	return str(LABELS.get(bits[0].to_lower(),bits[0]))+"贴纸 "+str(bits[-1])

static func seals_shop(g,side) -> void:
	if not side.has(g,side.item_name("SEAL_CASE")):
		FR.say(g,"需要先在随意镇领取贴纸盒。","贴纸摊")
		return
	var today: Array=side.data().shops.seals[WEEK[int(Time.get_date_dict_from_system().weekday)]]
	var options:=today.map(func(k):return "%s    ₽%d"%[seal_name(k),int(side.data().seal_prices.get(k,50))])
	options.append("离开")
	g._pick("滨海市场 · 今日贴纸",options,func(i):
		if i>=today.size():return
		var key:=str(today[i])
		var cost:=int(side.data().seal_prices.get(key,50))
		var stock: Dictionary=g.save_data.get_or_add("sinnoh_seals",{})
		if int(g.save_data.get("money",0))<cost or int(stock.get(key,0))>=99:
			FR.say(g,"请确认余额与贴纸盒的容量。","贴纸摊")
			return
		g.save_data.money-=cost
		stock[key]=int(stock.get(key,0))+1
		g._persist()
		g._show_toast("获得了"+seal_name(key)))

static func seals_case(g) -> void:
	var stock: Dictionary=g.save_data.get("sinnoh_seals",{})
	FR.pick_party(g,"给哪只伙伴装饰球壳？",func(_mon):return true,func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var keys:=stock.keys().filter(func(k):return int(stock[k])>0)
		var options:=keys.map(func(k):return "%s  ×%d"%[seal_name(k),int(stock[k])])
		options.append("取下所有贴纸")
		options.append("完成")
		g._pick("球壳上的贴纸  %d／8"%mon.get("s_capsule",[]).size(),options,func(i):
			var capsule: Array=mon.get_or_add("s_capsule",[])
			if i==keys.size():
				for k in capsule:stock[k]=int(stock.get(k,0))+1
				capsule.clear()
			elif i<keys.size() and capsule.size()<8:
				stock[keys[i]]=int(stock[keys[i]])-1
				capsule.append(keys[i])
			g._persist()))

static func settings(g,side,name: String) -> bool:
	if name=="贴纸盒":
		seals_case(g)
		return true
	if name!="宝可表":return false
	var apps: Array=g.save_data.get("s_apps",[])
	var options:=["数字时钟","计步器","队伍状态"]
	options.append_array(apps)
	options.append("关闭")
	g._pick("宝可表",options,func(i):app_open(g,str(options[i])))
	return true

static func app_open(g,app: String):
	match app:
		"培育屋查看器": FR.say(g,preload("res://core/sinnoh_day_care.gd").report(g),app)
		"数字时钟":
			var t:=Time.get_time_dict_from_system()
			FR.say(g,"%02d:%02d:%02d"%[int(t.hour),int(t.minute),int(t.second)],app)
		"计步器":FR.say(g,"已记录 %d 步。"%int(g.save_data.get("s_pedometer",0)),app)
		"队伍状态":
			var labels: Array=[]
			for mon in g.save_data.party:
				if mon is Dictionary and not mon.is_empty():labels.append("%s    HP %d／%d"%[mon.name,int(mon.hp),int(mon.max_hp)])
			if not labels.is_empty():g._dialog(labels,app)
		"标记地图":
			var lines: Array=[str(g.world.map_data.name)]
			for id in g.save_data.get("sinnoh_roamers",{}):lines.append("%s   %d 号道路"%[Data.species_of(int(id)).name,int(g.save_data.sinnoh_roamers[id].route)])
			g._dialog(lines,app)
		"备忘录":
			var memo: Array=g.save_data.get_or_add("s_memo",[])
			g._pick("记下地点",["记录当前位置"]+memo+["清空备忘录"],func(n):
				if n==0:
					var marker:="%s (%d,%d)"%[g.world.map_data.name,g.world.player_pos.x,g.world.player_pos.y]
					if not memo.has(marker):memo.append(marker)
				elif n>memo.size():memo.clear()
				g._persist())
		"招式相性":
			FR.pick_party(g,"查看哪只伙伴的属性？",func(_m):return true,func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				var options2: Array=[]
				for mv in mon.moves:options2.append(str(Data.move_of(int(mv)).name))
				g._pick("招式属性",options2,func(n):
					var mv: Dictionary=Data.move_of(int(mon.moves[n]))
					FR.say(g,"%s    %s    威力 %d"%[mv.name,Data.type_name(mv.type),int(mv.get("power",0))],app)))
		"通信搜寻":
			FR.say(g,"附近没有正在进行本地通信的玩家。",app)

static func talk(g,side,script: String) -> bool:
	if side.data().sellers.has(script):
		shop(g,side,script)
		return true
	var mon:=first(g)
	match script:
		"Platinum_StoragePC":g._open_pc()
		"Route209LostTower5F_OldWoman1","Route209LostTower5F_OldWoman2":
			var first_woman:=script.ends_with("1")
			if not g._flags().get("s_defog_lost_tower",false):
				FR.say(g,"雾太浓了。先请宝可梦用清除浓雾驱散它。","老妇人")
			else:side.receive(g,"s_gift_"+script,"SPELL_TAG" if first_woman else "CLEANSE_TAG",1,"老妇人")
		"RuinManiacCaveShort_RuinManiac","RuinManiacCaveLong_RuinManiac","ManiacTunnel_RuinManiac":
			FR.say(g,"我挖掘洞穴，你去寻找不同模样的未知图腾。你已经见过 %d 种了！"%unown_seen(g.save_data).size(),"遗迹迷")
		"SolaceonTownPokemonNewsPress_GymGuide":news(g,side)
		"SolaceonTownEastHouse_NinjaBoy":trader(g,side)
		"SunyshoreMarket_SealShop":seals_shop(g,side)
		"SunyshoreMarket_EffortRibbonWoman":
			if mon.is_empty():return true
			var effort:=0
			for value in mon.get("effort",{}).values():effort+=int(value)
			if effort>=510:ribbon(g,mon,"努力奖章","努力奖章评定员")
			else:FR.say(g,"再多带%s一起锻炼吧。"%mon.name,"努力奖章评定员")
		"FootstepHouse_DrFootstep":
			if mon.is_empty():return true
			if int(mon.get("friendship",0))>=255:ribbon(g,mon,"足迹奖章","足迹博士")
			else:FR.say(g,"从%s的足迹能读出它对你的信赖。多陪它旅行吧。"%mon.name,"足迹博士")
		"SunyshoreCityEastHouse_Julia":
			if mon.is_empty():return true
			var now:=Time.get_date_string_from_system()
			if g._flags().get("s_julia_day","")==now:FR.say(g,"今天聊得很开心。我们明天再聊吧。","文子")
			else:g._pick("要陪文子聊聊今天的心情吗？",["坐下来聊聊","稍后再来"],func(i):
				if i==0:
					g._flags().s_julia_day=now
					ribbon(g,mon,DAY_RIBBONS[int(Time.get_date_dict_from_system().weekday)],"文子")
					g._persist())
		"ResortAreaRibbonSyndicate1F_CashierF":ribbon_shop(g)
		"PoketchCo1F_PoketchCoPresident":
			var n:=badges(g._flags())
			var apps: Array=g.save_data.get_or_add("s_apps",[])
			for reward in [[1,"备忘录"],[3,"标记地图"],[5,"通信搜寻"],[7,"招式相性"]]:
				if n>=int(reward[0]) and not apps.has(reward[1]):
					apps.append(reward[1])
					g._persist()
					FR.say(g,"已把%s安装到你的宝可表上了。"%reward[1],"宝可表公司社长")
					return true
			FR.say(g,"拿到更多神奥徽章，再来领取新的应用吧。","宝可表公司社长")
		_:return false
	return true
