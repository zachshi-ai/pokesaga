extends RefCounted
## Optional offline Crystal events, using the same party, PC, field and calendar as the main game.
const Daily:=preload("res://core/crystal_daily.gd")
const REWARDS := {
	"claw":"先制之爪","king":"王者之证","glasses":"黑色眼镜","curse":"城都招式学习器 03",
	"steel_wing":"城都招式学习器 47","roar":"城都招式学习器 05","headbutt":"城都招式学习器 02","seed":"奇迹种子",
}
const STONES := [[108,"不变之石"],[43,"叶之石"],[120,"水之石"],[58,"火之石"],[172,"雷之石"]]
const TRADE_BERRIES := {"GOLD_BERRY":"sitrus","BITTER_BERRY":"persim","PRZCUREBERRY":"cheri","MYSTERYBERRY":"leppa"}
static var content: Dictionary
static func data() -> Dictionary:
	if content.is_empty(): content=JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/sidequests.json"))
	return content

static func today() -> Dictionary:
	return Time.get_datetime_dict_from_system()

static func stamp(day: Dictionary) -> String:
	return "%04d-%02d-%02d" % [day.year,day.month,day.day]

static func visible(key: String, flags: Dictionary, day: Dictionary) -> bool:
	if key.begins_with("sibling_"): return day.weekday==int(key.get_slice("_",1))
	match key:
		"bargain":return day.weekday==1 and day.hour>=4 and day.hour<10
		"herbal":return day.weekday in [0,6]
		"den_rival":return flags.get("j2_rival_moon",false) and day.weekday in [2,4]
		"lottery": return not flags.get("j_radio_takeover",false) or flags.get("j_radio_free",false)
		"roof_sale": return int(flags.get("js_roof_sale",-1))==preload("res://core/crystal_phone.gd").current_day(day)
		"bill_visit": return not flags.get("js_bill_met",false)
		"bill_home": return flags.get("js_bill_met",false)
		"older": return day.weekday in [2,4,6]
		"younger": return day.weekday in [0,3,5]
		"lapras": return day.weekday==5 and flags.get("js_lapras_day","")!=stamp(day)
		"week_tm": return day.weekday==0
		"tutor": return day.weekday in [3,6] and flags.get("johto_champion",false) and flags.get("j_coin_case",false) and flags.get("js_tutor_day","")!=stamp(day)
	return true

static func roster(mid: String, rows: Array, flags: Dictionary, day: Dictionary) -> Array:
	if mid=="johto_lake_of_rage" and not flags.get("j_plant_clear",false):
		rows=rows.filter(func(n):return n.get("trainer","") not in ["FisherAndre","FisherRaymond","CooltrainerMAaron","CooltrainerFLois"])
	rows=preload("res://core/crystal_home.gd").roster(mid,rows,flags,day)
	rows=preload("res://core/crystal_tower.gd").roster(mid,rows)
	rows=preload("res://core/crystal_bug_contest.gd").roster(mid,rows)
	if mid=="johto_ruins_of_alph_research_center" and not rows.is_empty():
		rows=rows.duplicate(true)
		rows[0].crystal_quest="ruins_scientist"
		rows[0].name="遗迹研究员"
	var specs: Array=data().maps.get(mid,[])
	if specs.is_empty(): return rows
	var remaining:=rows.duplicate(true)
	for spec in specs:
		var take:=remaining.find_custom(func(n): return n.at==spec.at)
		var actor: Dictionary=remaining.pop_at(take) if take>=0 else {"at":spec.at,"gfx":"man"}
		if not visible(spec.actor,flags,day): continue
		actor["name"]=spec.name
		actor["crystal_quest"]=spec.actor
		if Daily.ANCHORS.has(spec.actor):
			actor.native_anchor=Daily.ANCHORS[spec.actor]
		if spec.actor=="cal": actor.role="js_house_cal"
		if spec.actor in ["lapras","moomoo"]:
			actor["field_art"]="crystal_"+str(spec.actor)
			actor["native_anchor"]={"at":[18,88] if spec.actor=="lapras" else [7,5],"facing":"down"}
		for k in ["battle","sight","heal","shop"]: actor.erase(k)
		remaining.append(actor)
	return remaining

static func refresh(g):
	g.world.refresh_story_actors(g._flags())
	g._persist()

static func reward(g,key: String,item: String,who: String):
	g._give_item(item,1,"tm" if item.contains("学习器") else "other")
	g._flags()["js_"+key]=true
	refresh(g)
	g._dialog(["获得了%s！" % item],who)

static func give_mon(g, key: String, species: int, level: int, person: String, extra: Dictionary={}):
	if g.PartyScript.occupied(g.save_data.party)>=g.PartyScript.MAX_SIZE:
		g._dialog(["请先给伙伴留一个队伍空位，再来找我。"],person)
		return
	var mon: Dictionary=g.PartyScript.make(species,level,g.EncounterScript.moves_for(species,level))
	mon.berry=""
	mon.merge(extra,true)
	mon["crystal_gift"]=key
	g._store_mon(mon)
	g._flags()["js_"+key]=true
	refresh(g)
	g._dialog(["%s加入了队伍！"%mon.name],person)

static func choose_partner(g,title: String,predicate: Callable,on_select: Callable):
	var slots: Array=[]
	var options: Array=[]
	for i in g.save_data.party.size():
		var mon=g.save_data.party[i]
		if mon is Dictionary and not mon.is_empty() and predicate.call(mon):
			slots.append(i)
			options.append("%d　%s　Lv.%d"%[i+1,mon.name,int(mon.level)])
	if slots.is_empty():
		g._dialog(["随行队伍里没有符合条件的宝可梦。"])
		return
	options.append("先离开")
	g._pick(title,options,func(index):
		if index>=0 and index<slots.size(): on_select.call(slots[index]))

static func npc_trade(g,key: String,person: String):
	var t: Array=data().trades[key]
	var offered: String=g.get_node("/root/Data").species_of(int(t[1])).name
	var wanted: String=g.get_node("/root/Data").species_of(int(t[0])).name+("（雌性）" if t[6] else "")
	choose_partner(g,"想用%s交换%s吗？"%[wanted,offered],func(m): return int(m.species_id)==int(t[0]) and (not t[6] or m.get("sex","")=="female"),func(slot):
		var old: Dictionary=g.save_data.party[slot]
		var mon: Dictionary=g.PartyScript.make(int(t[1]),int(old.level),g.EncounterScript.moves_for(int(t[1]),int(old.level)))
		mon.merge({"name":t[2],"ot":t[5],"ot_id":t[4],"held":"" if TRADE_BERRIES.has(t[3]) else t[3],"berry":TRADE_BERRIES.get(t[3],"")},true)
		var ratio:=int(g.get_node("/root/Data").species_of(int(t[1])).get("gender",255))
		if ratio!=255:
			mon.sex="female" if ratio==254 or ((int(t[7])>>4)*16)<ratio else "male"
		mon.js_dvs=int(t[7])*256+int(t[8])
		g.save_data.party[slot]=mon
		g.DexVariants.record(g.save_data,mon,true)
		g._flags()["js_"+key]=true
		refresh(g)
		g._dialog(["%s接过了%s。你收到了%s，昵称是%s。"%[person,old.name,offered,mon.name]],person))

static func mail(g,who: String):
	if not g._flags().get("js_kenya",false):
		g._dialog(["朋友住在满金市的北门，他会不会托人带信呢？"],who)
		return
	choose_partner(g,"把带信的宝可梦交给他？",func(m):return m.get("crystal_gift","")=="kenya" and m.get("held","")=="FLOWER_MAIL",func(slot):
		if not can_return(g.save_data.party,slot):
			g._dialog(["请留下至少一只还能战斗的伙伴。"],who)
			return
		g.save_data.party[slot]={}
		reward(g,"letter","城都招式学习器 50",who))

static func can_return(party: Array,slot: int) -> bool:
	for i in party.size():
		if i!=slot and party[i] is Dictionary and int(party[i].get("hp",0))>0: return true
	return false

static func shuckle(g,who: String,day: String):
	if not g._flags().get("js_shuckie",false):
		g._pick("可以替我照看壶壶吗？",["照看壶壶","先离开"],func(i):
			if i==0:
				give_mon(g,"shuckie",213,15,who,{"name":"SHUCKIE","ot":"MANIA","ot_id":518,"berry":"oran"})
				if g._flags().get("js_shuckie",false):
					g._flags().js_shuckie_date=day
					g._persist())
	elif g._flags().get("js_shuckie_done",false) or g._flags().get("js_shuckie_date","")==day:
		g._dialog(["谢谢你照顾壶壶。"],who)
	else:
		choose_partner(g,"让我看看寄托给你的壶壶吧。",func(m):return m.get("crystal_gift","")=="shuckie",func(slot):
			var m: Dictionary=g.save_data.party[slot]
			if int(m.friendship)>=150:
				g._dialog(["它已经很喜欢你了，往后也请继续和它旅行吧。"],who)
			elif not can_return(g.save_data.party,slot):
				g._dialog(["你还需要一个能战斗的伙伴。"],who)
				return
			else:
				g.save_data.party[slot]={}
				g._dialog(["壶壶平安回来了！谢谢。"],who)
			g._flags().js_shuckie_done=true
			refresh(g))

static func stones(g,who: String):
	var index:=int(g._flags().get("js_grandpa_seen",0))
	if index>=STONES.size():
		g._dialog(["谢谢你带来这么多不同的宝可梦。"],who)
		return
	var entry: Array=STONES[index]
	choose_partner(g,"带来%s给爷爷看看。"%g.get_node("/root/Data").species_of(entry[0]).name,func(m):return int(m.species_id)==entry[0],func(_slot):
		g._flags().js_grandpa_seen=index+1
		reward(g,"grandpa_"+str(index),entry[1],who))

static func grooming(g,key: String,who: String,date: String,hour: int):
	var daisy:=key=="daisy"
	var stamp_key:="js_daisy" if daisy else "js_haircut"
	if daisy and hour!=15:
		g._dialog(["每天午后三点，我会给宝可梦梳毛。"],who)
		return
	if g._flags().get(stamp_key,"")==date:
		g._dialog(["今天已经护理过啦。"],who)
		return
	var price:=0 if daisy else (500 if key=="older" else 300)
	if int(g.save_data.money)<price:
		g._dialog(["这次理发需要%d元。"%price],who)
		return
	choose_partner(g,"为谁梳理毛发？" if daisy else "选一位理发的伙伴　¥%d"%price,func(_m):return true,func(slot):
		var m: Dictionary=g.save_data.party[slot]
		var roll: int=g.rng.randi_range(0,255)
		var gains: Array = ([1,1,1] if roll<77 else ([3,3,1] if roll<205 else [5,5,2])) if key=="older" else ([1,1,1] if roll<154 else ([3,3,1] if roll<230 else [10,10,4]))
		var old:=int(m.get("friendship",70))
		m.friendship=mini(255,old+int(([3,3,1] if daisy else gains)[mini(2,old/100)]))
		g.save_data.money-=price
		g._flags()[stamp_key]=date
		refresh(g)
		g._dialog(["%s看起来精神多了。"%m.name],who))

static func milk(g,key: String,who: String):
	var flags: Dictionary=g._flags()
	var fed:=int(flags.get("js_milk_berries",0))
	if key=="moomoo":
		if fed>=7: g._dialog(["哞！大奶罐已经康复了。"],who)
		else:
			g._pick("给生病的大奶罐喂一颗普通树果？",["喂树果","先离开"],func(i):
				if i!=0:return
				var fruit: String="树果" if g._bag_count("树果")>0 else "橙橙果"
				if g._bag_count(fruit)<=0:
					g._dialog(["背包里没有普通树果或橙橙果。"],who)
					return
				g._consume_item(fruit)
				flags.js_milk_berries=fed+1
				refresh(g)
				g._dialog(["它恢复精神，已经能生产哞哞鲜奶了！" if fed==6 else "它吃下了树果。"],who))
	elif fed<7: g._dialog(["牧场的大奶罐生病了，到旁边的牛棚看看它吧。"],who)
	elif key=="snore": reward(g,key,"城都招式学习器 13",who)
	else:
		g._pick("一瓶哞哞鲜奶500元。",["买一瓶","先离开"],func(i):
			if i==0:
				if int(g.save_data.money)<500: g._dialog(["钱不够。"],who)
				else:
					g.save_data.money-=500
					g._give_item("哞哞鲜奶",1,"heal")
					refresh(g)
					g._dialog(["得到了一瓶哞哞鲜奶。"],who))

static func talk(g,npc: Dictionary,day: Dictionary) -> bool:
	if npc.get("trainer","")=="CooltrainerFKate" and g.world.map_data.id=="johto_route_34" and not g._flags().get("js_soft_sand",false):
		var beaten: Array=g.save_data.get("defeated",{}).get("johto/johto_route_34",[])
		if npc.get("defeated",false) or npc.name in beaten:
			reward(g,"soft_sand","柔软沙子",npc.name)
			return true
	if not npc.has("crystal_quest"): return false
	var key: String=npc.crystal_quest
	var who: String=npc.name
	var flags: Dictionary=g._flags()
	var date:=stamp(day)
	if key in ["cal_desk","cal"]:Daily.cal(g,day)
	elif key in ["bargain","herbal"]:Daily.store(g,key,day)
	elif key=="resale":Daily.counter(g)
	elif key=="lake_elder":g._dialog(["又有鲤鱼王咬钩啦！" if flags.get("j_plant_clear",false) else "湖里的暴鲤龙怎么这么生气？这可不是好兆头。"],who)
	elif key=="lake_scholar":g._dialog(["传说发狂的暴鲤龙曾在这里留下一个大坑，雨水汇进去，才有了这片湖。"],who)
	elif key=="lake_visitor":g._dialog(["这地方很适合散步，沿湖走走吧。"],who)
	elif key=="karp":preload("res://core/crystal_wild_events.gd").magikarp(g,who)
	elif key=="den_rival":g._dialog(["我以前以为变强就够了。现在想试试，怎样才能让它们真正信任我。"],who)
	elif key=="bill_sister":preload("res://core/crystal_phone.gd").special_number(g,"bill")
	elif key=="moon_rock":preload("res://core/crystal_home.gd").smash(g)
	elif key=="home_doll":g._dialog(["妈妈买来的%s，摆在这里很有精神。"%who])
	elif key in ["game_mon","game_tm"]:preload("res://core/crystal_arcade.gd").prizes(g,key=="game_mon",true)
	elif key=="celadon_coins":preload("res://core/johto_items.gd").coins(g,false)
	elif key=="tower":preload("res://core/crystal_tower.gd").talk(g)
	elif key=="bug_officer":preload("res://core/crystal_bug_contest.gd").enroll(g,day)
	elif key=="lottery":preload("res://core/crystal_phone.gd").lottery(g,day)
	elif key=="roof_sale":preload("res://core/crystal_phone.gd").roof_sale(g,day)
	elif key=="ruins_scientist":preload("res://core/crystal_ruins.gd").research(g)
	elif key=="shuckie":
		shuckle(g,who,date)
	elif key=="grandpa": stones(g,who)
	elif key=="kenya" and flags.get("js_letter",false):
		if flags.get("js_kenya_thanks",false): g._dialog(["朋友读到我的信了，谢谢！"],who)
		else: reward(g,"kenya_thanks","HP 增强剂",who)
	elif key in ["older","younger","daisy"]: grooming(g,key,who,date,day.hour)
	elif key=="week_tm":
		var lead: Dictionary={}
		for m in g.save_data.party:
			if m is Dictionary and not m.is_empty():
				lead=m
				break
		var happiness:=int(lead.get("friendship",70))
		if flags.get("js_week_tm_date","")==date or lead.is_empty() or (happiness<150 and happiness>=50): g._dialog(["每个星期日，我会把招式学习器送给与训练家感情特别的伙伴。"],who)
		else:
			flags.js_week_tm_date=date
			reward(g,key,"城都招式学习器 27" if happiness>=150 else "城都招式学习器 21",who)
	elif key=="tutor": tutor(g,who,date)
	elif flags.get("js_"+key,false): g._dialog(["很高兴又见到你。"],who)
	elif key in ["moomoo","dairy","snore"]: milk(g,key,who)
	elif key.begins_with("trade_"): npc_trade(g,key,who)
	elif key.begins_with("sibling_"): reward(g,key,data().siblings[int(key.get_slice("_",1))],who)
	elif REWARDS.has(key):
		if key=="curse" and day.hour>=4 and day.hour<18: g._dialog(["天黑以后，再来听我的怪谈。"],who)
		elif key=="seed" and not flags.get("j_badge_1",false): g._dialog(["先到桔梗道馆证明自己的实力吧。"],who)
		else: reward(g,key,REWARDS[key],who)
	else:
		match key:
			"bill_visit":
				flags.js_bill_met=true
				refresh(g)
				g._dialog(["我是正辉！我要回满金市的家了，来我家看看伊布吧。"],who)
			"bill_home","kenya":
				var eevee:=key=="bill_home"
				g._pick("愿意带伊布一起旅行吗？" if eevee else "能把带信的烈雀送到31号道路吗？",["接受","先离开"],func(i):
					if i==0: give_mon(g,key,133 if eevee else 21,20 if eevee else 10,who,{} if eevee else {"name":"KENYA","ot":"RANDY","held":"FLOWER_MAIL"}))
			"letter": mail(g,who)
			"kiyo":
				if flags.get("js_kiyo_won",false): give_mon(g,key,236,10,who)
				else:
					g._start_battle({"name":who,"at":npc.at,"battle":{"team":[{"species":106,"level":34},{"species":107,"level":34}]}},func(result):
						if result=="b" and g._party_fainted():g._blackout()
						elif result=="a":
							flags.js_kiyo_won=true
							refresh(g)
							give_mon(g,key,236,10,who))
			"lapras":
				g._start_wild_battle(131,20,"",func(result):
					if result=="b": g._blackout()
					elif result in ["a","caught","fled"]:
						flags.js_lapras_day=date
						refresh(g))
	return true

static func tutor(g,who: String,date: String):
	if int(g.save_data.get("j_coins",0))<4000:
		g._dialog(["我在周三和周六教招式，一次4000枚代币。"],who)
		return
	g._pick("选一招　4000枚代币",["火焰放射","十万伏特","冰冻光束","先离开"],func(i):
		if i<0 or i>=3:return
		var move: int=[53,85,58][i]
		choose_partner(g,"教给哪位伙伴？",func(m):return g._can_learn_move(int(m.species_id),move) and move not in m.moves,func(slot):
			var mon: Dictionary=g.save_data.party[slot]
			if mon.moves.size()<4: teach(g,mon,move,mon.moves.size(),date,who)
			else:
				var labels: Array=[]
				for old in mon.moves: labels.append(g.get_node("/root/Data").move_of(old).name)
				labels.append("先离开")
				g._pick("忘记哪一招？",labels,func(index):
					if index>=0 and index<4:teach(g,mon,move,index,date,who))))

static func teach(g,mon: Dictionary,move: int,slot: int,date: String,who: String):
	var pp:=int(g.get_node("/root/Data").move_of(move).pp)
	if slot==mon.moves.size():
		mon.moves.append(move)
		mon.pp.append(pp)
	else:
		mon.moves[slot]=move
		mon.pp[slot]=pp
	g.save_data.j_coins-=4000
	g._flags().js_tutor_day=date
	refresh(g)
	g._dialog(["%s学会了%s。"%[mon.name,g.get_node("/root/Data").move_of(move).name]],who)
