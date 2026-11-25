extends RefCounted

const FR := preload("res://core/frlg_sidequests.gd")
const Battle := preload("res://core/battle.gd")
const Field := preload("res://core/unova_field.gd")
const Facilities := preload("res://core/unova_side_facilities.gd")
const SONGS := ["华丽巨星","森林漫步","甜蜜舞会","活力雷文"]
const STYLES := ["帅气","优雅","可爱","活泼"]
const PROPS := [["礼帽","手杖","太阳镜"],["白花","丝带","珍珠项链"],["蝴蝶结","小花伞","桃心发夹"],["足球","手鼓","彩旗"]]
const SHOPS := ["抽奖店","市场","餐厅","道场","花店","古董店","美容院","孵化所"]
const MAPS := ["nimbasa_city","driftveil_city","mistralton_city","lacunosa_town","undella_town","lentimas_town","route_5","route_6","route_7","route_9","route_11","route_12","route_13","route_14","route_16"]
const FILMS := ["哈奇库侠","哈奇库侠归来","哈奇库侠的逆袭","全金属警察 1","全金属警察 2","全金属警察 3","全金属警察 4","侵略者 1","侵略者 2","侵略者 3","侵略者 4","大怪兽 1","大怪兽 2","大怪兽 3","大怪兽 4","时间门旅行者 1","时间门旅行者 2","时间门旅行者 3","时间门旅行者 4","忘不了你的名字 1","忘不了你的名字 2","忘不了你的名字 3","忘不了你的名字 4","魔法之国的神奇大门 1","魔法之国的神奇大门 2","魔法之国的神奇大门 3","异次元通道 1","异次元通道 2","异次元通道 3","异次元通道 4","红白捕获对决 1","红白捕获对决 2","红白捕获对决 3","红白捕获对决 4","幽灵清洁队 1","幽灵清洁队 2","幽灵清洁队 3","幽灵清洁队 4","巨大的女人","明星总动员"]
const RULES := ["每回合击倒一位对手","击败所有对手","用指定招式完成最后一击","击倒指定角色","只击倒指定角色","留下指定角色，击败其他对手","坚持到最后一个回合","全程不击倒对方，坚持到最后","让对方击倒我方全队"]
const FIRST := [0,3,7,11,15,19,23,26,30,34,38]
const MEDALS := [["初次纪念",0],["小小散步者",5000],["健脚散步者",10000],["伟大散步者",20000],["奇迹散步者",1000000]]
const PROP_NAMES := {"ufo":"飞碟","ufo_2":"飞碟Ⅱ","brycen_man":"哈奇库侠","mt":"机械班基拉斯","mt_2":"机械班基拉斯Ⅱ","transport":"时间机器","black_belt":"黑带","white_door":"白之门","black_door":"黑之门","giant_f":"巨大女主角","giant_f_2":"巨大女主角","spirit":"幽灵","monster":"怪兽","humanoid":"人偶","f_00":"F-00","f_002":"F-002"}

static func side():
	return load("res://core/unova_side.gd")

static func interact(g,r: Dictionary) -> void:
	match str(r.type):
		"musical":musical(g)
		"cinema":cinema(g)
		"avenue":avenue(g)
		"medals":medals(g,true)
		"phone":
			if not g._flags().get("us_b2_phone",false):
				side().give(g,"DROPPED_ITEM_FEMALE")
				side().mark(g,"us_b2_phone")
				g._dialog(["游乐场的地上有一台即时通讯器。机主琉璃正忙，请你先替她保管。"])
			else:g._dialog(["琉璃也许会从别的地方打来电话。"])
		"yancy":meet(g)

static func use_item(g,name: String) -> bool:
	match name:
		"奖牌盒":medals(g,false)
		"物品箱":
			var props: Array=g.save_data.get("unova_props",[])
			g._dialog(["、".join(props) if not props.is_empty() else "还没有演出用的装饰品。"],"音乐剧物品箱")
		"遗忘物","即时通讯器":
			if Field.era(g._flags())!="b2":return false
			var f: Dictionary=g._flags()
			var zone:=str(g.world.map_data.get("unova_zone",""))
			if not f.get("us_b2_phone",false):g._dialog(["通讯录里还没有琉璃的号码。"]);return true
			if not f.get("us_b2_returned_phone",false):
				g._dialog(["在雷文市的摩天轮前把通讯器还给琉璃吧。" if f.get("us_b2_has_number",false) else "失主会从合众各处打来电话。收到通话 %d / 10 次。"%g.save_data.get("us_call_areas",[]).size()]);return true
			if zone not in MAPS:g._dialog(["琉璃正忙，这里没有收到信号。"]);return true
			if f.get("us_last_outgoing","")==zone:g._dialog(["刚通完话，换个地方再试吧。"]);return true
			f.us_last_outgoing=zone
			f.us_outgoing=int(f.get("us_outgoing",0))+1
			g._persist()
			g._dialog(["好久不见！今天的工作结束后，我想和你一起坐摩天轮。" if int(f.us_outgoing)>=20 else "小悠，原来你走到那里了！等我下班，我们再多聊一会儿。"],"琉璃")
		_:return false
	return true

static func meet(g) -> void:
	var f: Dictionary=g._flags()
	if not f.get("us_b2_returned_phone",false):
		g._consume_item(side().item_name("DROPPED_ITEM_FEMALE"))
		if g._bag_count("即时通讯器")==0:g._give_item("即时通讯器",1,"key")
		side().mark(g,"us_b2_returned_phone")
		g._dialog(["谢谢你把通讯器送回来。我把号码留给你，以后也给我打电话吧。"],"琉璃");return
	if int(f.get("us_outgoing",0))<20:g._dialog(["今天还有工作。下次再约吧！"],"琉璃");return
	if not f.get("u2_champion",false):g._dialog(["挑战联盟的时候，我会给你加油。"],"琉璃");return
	var today:=Time.get_date_string_from_system()
	if f.get("us_yancy_day","")==today:g._dialog(["今天聊得很开心。下次再来交换吧。"],"琉璃");return
	var n:=int(f.get("us_yancy_trades",0))
	var flag:="us_b2_yancy_trade_%d"%n
	if f.get(flag,false):f.us_yancy_trades=n+1;g._persist();meet(g);return
	g._pick("和琉璃一起坐摩天轮？",["一起去","下次吧"],func(i):
		if i!=0:return
		load("res://core/unova_side_quests.gd").trade(g,side().data().trades[12+n%12],flag,true))

static func step(g) -> bool:
	var f: Dictionary=g._flags()
	g.save_data.unova_steps=int(g.save_data.get("unova_steps",0))+1
	if Field.era(f)!="b2" or not f.get("us_b2_phone",false) or f.get("us_b2_has_number",false):return false
	var zone:=str(g.world.map_data.get("unova_zone",""))
	if zone not in MAPS:return false
	var vis: Array=g.save_data.get_or_add("us_call_areas",[])
	if zone in vis:return false
	vis.append(zone)
	if vis.size()>=10:side().mark(g,"us_b2_has_number")
	g._persist()
	g._dialog(["终于能休息了！在雷文市的摩天轮旁见面好吗？" if vis.size()>=10 else "小悠，能听见吗？谢谢你帮我保管通讯器。下次我再打给你。"],"琉璃")
	return true

static func medals(g,collect: bool) -> void:
	var collected: Array=g.save_data.get_or_add("unova_medals",[])
	if collect:
		if g._bag_count("奖牌盒")==0:side().give(g,"MEDAL_BOX")
		var ready: Array=[]
		for rule in MEDALS:
			if int(g.save_data.get("unova_steps",0))>=int(rule[1]):ready.append(rule[0])
		if g._flags().get("u2_champion",false):ready.append("合众冠军")
		if g._flags().get("us_tower_complete",false):ready.append("黑色摩天楼")
		if g._flags().get("us_grotto_unlocked",false):ready.append("隐藏洞穴向导")
		if g.save_data.get("unova_films",{}).size()>=1:ready.append("新人演员")
		if int(g.save_data.get("unova_dances",0))>=1:ready.append("音乐剧新人")
		if int(g.save_data.get("us_record_b2单打列车",0))>=49:ready.append("地铁大师")
		for medal in ready:
			if medal not in collected:collected.append(medal)
		g._persist()
	g._dialog(["、".join(collected) if not collected.is_empty() else "到宝可梦中心向奖章大叔领取奖章。"],"奖牌盒 · %d 枚"%collected.size())

static func musical(g) -> void:
	if g._bag_count("物品箱")==0:side().give(g,"PROP_CASE")
	var owned: Array=g.save_data.get_or_add("unova_props",[])
	if owned.is_empty():
		for group in PROPS:owned.append(group[0])
		g._persist()
	FR.pick_party(g,"选择登台的伙伴",func(m):return not m.get("is_egg",false),func(slot):
		g._pick("想参加哪一出音乐剧？",SONGS,func(i):
			g._pick("为%s选择舞台装饰"%g.save_data.party[slot].name,owned,func(p):
				dance(g,i,0,2 if str(owned[p]) in PROPS[i] else 0,g.save_data.party[slot].name))))

static func dance(g,song: int,beat: int,score: int,name: String) -> void:
	if beat==3:
		var applause:=score>=4
		var props: Array=g.save_data.unova_props
		var extra: Array=PROPS[song].filter(func(p):return p not in props)
		var gift:=""
		if applause and not extra.is_empty():gift=extra[0];props.append(gift)
		g.save_data.unova_dances=int(g.save_data.get("unova_dances",0))+1
		g._persist()
		g._dialog(["%s向观众谢幕，收获了%s掌声。"%[name,"热烈的" if applause else "零星的"]]+(["一位观众送来了%s。"%gift] if gift!="" else []),SONGS[song]);return
	var cue:=int([song,(song+1)%4,song][beat])
	var options:=["潇洒亮相","轻盈转身","甜蜜挥手","活力跳跃"]
	g._pick("%s · 第%d拍 · %s"%( [SONGS[song],beat+1,STYLES[cue]]),options,func(choice):dance(g,song,beat+1,score+(1 if choice==cue else 0),name))

static func restore_dressing_room(save: Dictionary) -> void:
	var journal: Dictionary=save.get("unova_films",{})
	if journal.size()<FILMS.size():return
	for number in FILMS.size():
		if not journal.get(str(number),{}).get("hit",false):return
	save.get_or_add("flags",{})["us_dressing_room"]=true

static func cinema(g) -> void:
	var journal: Dictionary=g.save_data.get_or_add("unova_films",{})
	var available: Array=[]
	for i in FILMS.size():
		if i in FIRST or journal.get(str(i-1),{}).get("hit",false):available.append(i)
	var labels:=available.map(func(i):return FILMS[i]+(" ★" if journal.get(str(i),{}).get("hit",false) else ""))
	labels.append("查看上映记录")
	g._pick("宝可坞 · 剧本架",labels,func(i):
		if i>=available.size():
			var lines: Array=[]
			for key in journal:lines.append("%s · %s · %d 回合"%[FILMS[int(key)],"成功上映" if journal[key].hit else "未达成剧本",int(journal[key].turns)])
			g._dialog(lines if not lines.is_empty() else ["还没有上映过电影。"],"影库");return
		var number:=int(available[i])
		var film: Dictionary=Facilities.data().movies[number]
		var goal:=str(RULES[int(film.rule)])
		if int(film.target)>0:goal+="（目标：%s）"%cast_name(g,int(film.target))
		if int(film.move)>0:goal+=" · "+str(g.get_node("/root/Data").move_of(int(film.move)).name)
		g._pick("%s · %d 回合 · %s"%[FILMS[number],int(film.turns),goal],["使用租借队开拍","先看其他剧本"],func(choice):
			if choice==0:film_battle(g,number,film)
			else:cinema(g)))

static func cast_name(g,id: int) -> String:
	var prop: Dictionary=Facilities.data().props.get(str(id),{})
	if not prop.is_empty():return str(PROP_NAMES.get(prop.slug,"舞台道具"))
	return str(g.get_node("/root/Data").species_of(id).get("name","演员"))

static func cast_mon(g,row: Array) -> Dictionary:
	var id:=int(row[0])
	var lv:=int(row[1])
	var shown:=int(row[5])
	var mon:=Battle.make_combatant(id if id<=649 else 132,lv,row[2])
	mon.film_species=shown
	mon.held=str(row[3]) if row[3]!="NONE" else ""
	var prop: Dictionary=Facilities.data().props.get(str(id),{})
	var stats: Dictionary=g.get_node("/root/Data").species_of(id).get("base",{}) if prop.is_empty() else prop.stats
	var names:={"hp":"hp","attack":"atk","defense":"def","speed":"spe","special_attack":"spa","special_defense":"spd"}
	var nature_idx:=["HARDY","LONELY","BRAVE","ADAMANT","NAUGHTY","BOLD","DOCILE","RELAXED","IMPISH","LAX","TIMID","HASTY","SERIOUS","JOLLY","NAIVE","MODEST","MILD","QUIET","BASHFUL","RASH","CALM","GENTLE","SASSY","CAREFUL","QUIRKY"].find(str(row[8]))
	var nature_stats:=["atk","def","spe","spa","spd"]
	if not prop.is_empty():mon.types=prop.types
	for k in names:
		var stat: String=names[k]
		var base:=int(stats.get(k,stats.get(stat,1)))
		var val: int=(2*base+int(row[6].get(k,0))+int(row[7].get(k,0))/4)*lv/100
		if stat=="hp":mon.hp=val+lv+10;mon.max_hp=mon.hp
		else:
			var up: bool=nature_stats[nature_idx/5]==stat
			var down: bool=nature_stats[nature_idx%5]==stat
			mon.stats[stat]=(val+5)*(110 if up and not down else 90 if down and not up else 100)/100
	var image: Dictionary=Facilities.data().props.get(str(shown),{})
	if not image.is_empty():
		mon.film_asset="res://assets/unova/film/"+str(image.slug)+".png"
		mon.name=cast_name(g,shown)
	return mon

static func film_battle(g,number: int,film: Dictionary,on_finish:=Callable()) -> void:
	var ui_ref: Array=[]
	var mine: Array=film.player.map(func(row):return cast_mon(g,row))
	var foe: Array=film.enemy.map(func(row):return cast_mon(g,row))
	g._start_battle({"name":FILMS[number],"battle":{"platinum_battle":true,"tower":true,"unova_movie":film,"player":mine,"enemy":foe}},func(result):
		var turns:=0
		if not ui_ref.is_empty() and is_instance_valid(ui_ref[0]):turns=ui_ref[0].battle.completed_turns
		var journal: Dictionary=g.save_data.get_or_add("unova_films",{})
		var old: Dictionary=journal.get(str(number),{})
		journal[str(number)]={"hit":result=="a" or old.get("hit",false),"turns":turns}
		restore_dressing_room(g.save_data)
		if g.world.map_data.id=="unova_b2_zone_568":g.world.refresh_story_actors(g._flags())
		g._persist()
		var d=g._dialog(["你们的作品顺利上映了！" if result=="a" else "这一条没有达到剧本要求。可以重新拍摄。"],FILMS[number])
		if on_finish.is_valid():d.closed.connect(on_finish.bind(result),CONNECT_ONE_SHOT))
	ui_ref.append(g.active_battle)

static func avenue(g) -> void:
	var shops: Dictionary=g.save_data.get_or_add("unova_avenue",{})
	var labels:=["邀请路人开店","为客人推荐店铺"]+shops.keys()+["离开"]
	g._pick("加盟大道 · %d / 8 家店铺"%shops.size(),labels,func(i):
		if i==0:
			var free:=SHOPS.filter(func(k):return not shops.has(k))
			if free.is_empty():g._dialog(["店铺都已开张。"]);return
			g._pick("邀请哪位店主入驻？",free,func(p):
				shops[free[p]]={"reputation":0,"day":""}
				g._persist()
				g._dialog(["%s开业了！"%free[p]]))
		elif i==1:
			if shops.is_empty():g._dialog(["先邀请一位店主吧。"]);return
			var today:=Time.get_date_string_from_system()
			if g.save_data.get("unova_avenue_ref_day","")==today:g._dialog(["今天的客人已经找到想去的店。"]);return
			var request: String=shops.keys().pick_random()
			g._pick("这位客人想逛%s。"%request,shops.keys(),func(p):
				if str(shops.keys()[p])!=request:g._dialog(["这家好像没有我需要的东西。"]);return
				shops[request].reputation=int(shops[request].reputation)+1
				g.save_data.unova_avenue_ref_day=today
				g._persist()
				g._dialog(["推荐成功，%s的人气上升了。"%request]))
		elif i<labels.size()-1:shop(g,labels[i],shops[labels[i]]))

static func shop(g,name: String,state: Dictionary) -> void:
	var day:=Time.get_date_string_from_system()
	if state.day==day:g._dialog(["今天的服务售罄了，明天再来吧。"],name);return
	var price:=0 if name=="抽奖店" else 200
	g._pick("%s · %s"%[name,"每日抽奖" if price==0 else "今日服务　%d 元"%price],["使用","离开"],func(i):
		if i!=0:return
		if int(g.save_data.money)<price:g._dialog(["钱不够。"]);return
		var settle:=func():
			state.day=day
			g.save_data.money-=price
			g._persist()
		if name in ["道场","餐厅","美容院"]:
			FR.pick_party(g,"选择伙伴",func(m):return not m.get("is_egg",false),func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				if name=="美容院":mon.friendship=mini(255,int(mon.get("friendship",70))+10)
				elif name=="餐厅":mon.hp=mon.max_hp;mon.erase("status")
				else:
					var growth=load("res://core/growth.gd")
					growth.add_exp(mon,maxi(150,int(mon.level)*25))
					load("res://core/party.gd").recalc(mon,true)
				settle.call()
				g._dialog(["%s完成了今天的服务。"%mon.name],name));return
		if name=="孵化所":
			if int(g.save_data.get("unova_egg_steps",0))<=0:g._dialog(["身上没有等待孵化的燃烧虫蛋。"]);return
			g.save_data.unova_egg_steps=maxi(1,int(g.save_data.unova_egg_steps)/2)
			settle.call()
			g._dialog(["蛋的孵化进度加快了。"],name);return
		var choices: Array={"抽奖店":["POTION","FULL_HEAL","GREAT_BALL","MAX_REVIVE"],"市场":["SUPER_POTION","GREAT_BALL"],"花店":["ORAN_BERRY","SITRUS_BERRY"],"古董店":["PEARL","BIG_PEARL","HARD_STONE"]}[name]
		var key:=str(choices.pick_random())
		side().give(g,key)
		settle.call()
		g._dialog(["得到了%s。"%side().item_name(key)],name))
