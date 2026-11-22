extends RefCounted
## The saved phonebook is shared across regions. Crystal's appointments and callers are local to its map.
const FLAGS := {"EVENT_BEAT_ELITE_FOUR":"johto_champion","EVENT_CLEARED_RADIO_TOWER":"j_radio_free","EVENT_CLEARED_ROCKET_HIDEOUT":"j_plant_clear","EVENT_RESTORED_POWER_TO_KANTO":"j2_power","ENGINE_FLYPOINT_BLACKTHORN":"fly_烟墨市","ENGINE_FLYPOINT_CIANWOOD":"fly_湛蓝市","ENGINE_FLYPOINT_ECRUTEAK":"fly_圆朱市","ENGINE_FLYPOINT_GOLDENROD":"fly_满金市","ENGINE_FLYPOINT_LAKE_OF_RAGE":"js_visited_lake","ENGINE_FLYPOINT_MAHOGANY":"fly_卡吉镇","ENGINE_FLYPOINT_OLIVINE":"fly_浅葱市"}
const ITEMS := {"NUGGET":"金珠","FIRE_STONE":"火之石","THUNDERSTONE":"雷之石","LEAF_STONE":"叶之石","WATER_STONE":"水之石","PROTEIN":"攻击增强剂","HP_UP":"HP 增强剂","CALCIUM":"特攻增强剂","CARBOS":"速度增强剂","IRON":"防御增强剂","PP_UP":"PP 提升剂","STAR_PIECE":"星星碎片","PINK_BOW":"粉红丝带","POKE_BALL":"精灵球","GREAT_BALL":"超级球","ULTRA_BALL":"高级球"}
const BERRIES := {"BERRY":["橙橙果","oran"],"PSNCUREBERRY":["桃桃果","pecha"],"PRZCUREBERRY":["樱子果","cheri"],"BITTER_BERRY":["柿仔果","persim"]}
const SWARMS := {"anthony":["johto_dark_cave_violet_entrance","黑暗洞穴的土龙弟弟"],"arnie":["johto_route_35","35号道路的蜻蜻蜓"],"ralph":["johto_route_32","32号道路水里的千针鱼"]}
const DELAYS := [20,10,5,3]
static var contacts: Dictionary
static func data() -> Dictionary:
	if contacts.is_empty():contacts=JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/phone.json"))
	return contacts

static func period(hour: int)->String:
	return "MORN" if hour>=4 and hour<10 else ("DAY" if hour>=10 and hour<18 else "NITE")

static func state(g)->Dictionary:
	if not g.save_data.has("js_phone"):
		g.save_data.js_phone={"book":[],"pending":{},"wins":{},"weekdays":{},"swarm":{},"gift_done":{},"timer":0}
	return g.save_data.js_phone

static func current_day(day:Dictionary)->int:
	return int(Time.get_unix_time_from_datetime_dict({"year":day.year,"month":day.month,"day":day.day,"hour":0,"minute":0,"second":0}))/86400

static func map_name(g,m:String)->String:
	return str(g.get_node("/root/Data").load_map("johto",m).get("name",m))

static func key_for(g,npc:Dictionary)->String:
	var name_text:=str(npc.get("name",""))
	var partner:=name_text.get_slice(" ",name_text.get_slice_count(" ")-1).to_lower()
	if data().has(partner) and data()[partner].map==g.world.map_data.id and data()[partner].name==name_text:return partner
	return ""

static func talk(g,npc:Dictionary,day:Dictionary)->bool:
	if not g._flags().get("j_gear",false):return false
	var key:=key_for(g,npc)
	if key=="":return false
	var row: Dictionary=data()[key]
	if npc.has("battle") and not npc.get("defeated",false) and not npc.name in g.save_data.get("defeated",{}).get("johto/"+str(row.map),[]):return false
	var s:=state(g)
	if key not in s.book:
		if int(row.show)>0 and not g.save_data.party.any(func(p):return p is Dictionary and p.get("species_id",0)==row.show):
			g._dialog(["如果你也照顾%s，我们一定聊得来。" % g.get_node("/root/Data").species_of(row.show).name],row.name)
		elif s.book.size()>=8:g._dialog(["电话簿已经满了，可以在宝可装置里删除一位联系人。"],row.name)
		else:
			g._pick("和%s交换电话号码？"%row.name,["登录号码","先离开"],func(i):
				if i!=0 or key in s.book:return
				s.book.append(key)
				if key=="kenji":s.break_day=current_day(day)+g.rng.randi_range(2,5)
				if s.timer==0:s.timer=int(Time.get_unix_time_from_system())+1200
				g._persist()
				g._dialog(["号码已登录到宝可装置。"],row.name))
		return true
	var pending: String=s.pending.get(key,"")
	if pending.begins_with("gift/"):
		if key=="kenji" and (period(day.hour)!="DAY" or int(s.get("break_day",-1))!=current_day(day)):
			g._dialog(["白天休息的时候再来吧。"],row.name)
			return true
		deliver(g,key,pending.trim_prefix("gift/"))
	elif pending=="fight":battle(g,key,npc)
	else:g._dialog(["我有消息会打给你。有空也来电话吧。"],row.name)
	return true

static func deliver(g,key:String,kind:String):
	var s:=state(g)
	var item: String=ITEMS.get(kind,kind)
	if BERRIES.has(kind):
		item=BERRIES[kind][0]
		g._give_bag_item(item,"berry","",BERRIES[kind][1])
	else:g._give_item(item,1,"ball" if kind.ends_with("_BALL") else "other")
	s.pending.erase(key)
	s.gift_done["received_"+key]=true
	if key=="kenji":s.break_day=current_day(Time.get_datetime_dict_from_system())+g.rng.randi_range(2,5)
	g._persist()
	g._dialog(["特地给你留的。获得了%s！"%item],data()[key].name)

static func tier(flags:Dictionary,row:Dictionary,wins:int)->int:
	var stage:=mini(wins,row.rematches.size()-1)
	while stage>0 and not flags.get(FLAGS.get(row.gates.get(str(stage),""),""),false):stage-=1
	return stage

static func battle(g,key:String,npc:Dictionary):
	var s:=state(g)
	var row:Dictionary=data()[key]
	var chosen:=tier(g._flags(),row,int(s.wins.get(key,0)))
	g._start_battle({"name":npc.name,"at":npc.at,"battle":{"team":row.rematches[chosen]}},func(result):
		if result=="a":
			s.wins[key]=mini(chosen+1,row.rematches.size()-1)
			s.pending.erase(key)
			if chosen==row.rematches.size()-1 and not row.gifts.is_empty() and not row.incoming_gift and not s.gift_done.get(key,false):
				s.gift_done[key]=true
				deliver(g,key,row.gifts[0])
		elif result=="b" and g._party_fainted():g._blackout()
		g._persist())

static func call_contact(g,key:String,day:Dictionary)->String:
	if key=="bill":
		var boxes:Array=g.save_data.get("boxes",[])
		var count:=0
		for box in boxes:
			count+=box.get("mons",[]).filter(func(p):return p is Dictionary and not p.is_empty()).size()
		return "我刚查过储存系统，现在电脑里共有%d只伙伴。"%count
	if key=="buena":return "小葵的口令从晚上六点播到午夜。时间到了就把收音机调到10.5吧！"
	if data()[key].map==g.world.map_data.id:return "我就在这附近，过来聊吧。"
	return preload("res://core/crystal_calls.gd").run(g,state(g),key,false,day)

static func name_of(key:String)->String:
	if key=="bill":return "正辉"
	if key=="buena":return "小葵"
	return data()[key].name

static func special_number(g,key:String):
	var s:=state(g)
	if key in s.book:g._dialog(["号码在电话簿里。有空打给%s吧。"%name_of(key)]);return
	if s.book.size()>=8:g._dialog(["电话簿里没有空位，可以先删除一个号码。"]);return
	g._pick("要登录%s的号码吗？"%name_of(key),["登录号码","先离开"],func(i):
		if i==0 and not key in s.book:
			s.book.append(key);g._persist();g._dialog(["已登录%s。"%name_of(key)]))

static func book(g):
	var s:=state(g)
	var special:=["妈妈"]
	if g._flags().get("johto_elm_told",false):special.append("空木博士")
	var labels:=special.duplicate()
	for key in s.book:labels.append(name_of(key))
	g._pick("电话簿",labels,func(i):
		if i<0 or i>=labels.size():return
		if i<special.size():
			if labels[i]=="妈妈":preload("res://core/crystal_home.gd").management(g,true);return
			var line:="路上累了就回若叶镇休息。"
			if labels[i]=="空木博士":line="从蛋里孵出了宝可梦吗？带回来让我看看吧。" if g._flags().get("j_egg_aide",false) else "宝可梦爷爷住在吉花市以北的30号道路。"
			g._dialog([line],labels[i])
			return
		var key:String=s.book[i-special.size()]
		g._pick(name_of(key),["打电话","删除号码"],func(j):
			if j==0:
				var line:=call_contact(g,key,Time.get_datetime_dict_from_system())
				g._persist()
				g._dialog([line],name_of(key))
			elif j==1:
				g._pick("从电话簿删除%s？"%name_of(key),["删除","保留"],func(k):
					if k==0:
						s.book.erase(key)
						g._persist())))

static func field_step(g):
	if g.world.map_data.get("region","")!="johto":return
	if g.world.map_data.id=="johto_lake_of_rage":g._flags().js_visited_lake=true
	if not g.save_data.has("js_phone"):return
	var s:=state(g)
	var now:=int(Time.get_unix_time_from_system())
	if s.book.is_empty() or now<int(s.timer) or g.panel_open>0:return
	var cycles:=mini(3,int(s.get("cycles",0))+1)
	s.cycles=cycles
	s.timer=now+60*int(DELAYS[cycles])
	var site:=preload("res://core/crystal_radio.gd").local(g)
	if site.is_empty() or not site[2] or not g.world.warp_at(g.world.player_pos).is_empty() or g.rng.randi_range(0,1)==0:return
	var options: Array=s.book.filter(func(k):return k!="bill" and (k=="buena" or data()[k].map!=g.world.map_data.id))
	if options.is_empty():return
	var key:String=options[g.rng.randi_range(0,options.size()-1)]
	var day:=Time.get_datetime_dict_from_system()
	var line:=call_contact(g,key,day) if key=="buena" else preload("res://core/crystal_calls.gd").run(g,s,key,true,day)
	g._persist()
	g._dialog([line],"宝可装置来电 · "+name_of(key))

static func swarm_pool(g,base:Array,which:String)->Array:
	if not g.save_data.has("js_phone"):return base
	var s:=state(g)
	var date:=current_day(Time.get_datetime_dict_from_system())
	var place:String=g.world.map_data.id
	var weights:=[30,30,20,10,5,4,1]
	for key in ["anthony","arnie"]:
		if SWARMS[key][0]!=place or int(s.swarm.get(key,-1))!=date:continue
		var entries: Array=[[74,3],[206,3],[41,2],[74,2],[206,2],[206,4],[206,4]] if key=="anthony" else [[32,12],[29,12],[193,12],[193,14],[163 if which=="nite" else 16,14],[132,10],[132,10]]
		var result: Array=[]
		for i in entries.size():result.append({"species":entries[i][0],"min":entries[i][1],"max":entries[i][1],"weight":weights[i]})
		return result
	return base

static func fish_swarm(g)->bool:
	return g.world.map_data.id==SWARMS.ralph[0] and int(g.save_data.get("js_phone",{}).get("swarm",{}).get("ralph",-1))==current_day(Time.get_datetime_dict_from_system())

static func match_digits(id:int,ticket:int)->int:
	var a:="%05d"%id
	var b:="%05d"%ticket
	var n:=0
	while n<5 and a[4-n]==b[4-n]:n+=1
	return n

static func lottery_number(g,day:Dictionary)->int:
	var week:=current_day(day)-posmod(int(day.weekday)-5,7)
	var flags: Dictionary=g._flags()
	if not g.save_data.has("js_trainer_id"):g.save_data.js_trainer_id=g.rng.randi_range(0,65535)
	if int(flags.get("js_lottery_week",-1))!=week:
		flags.js_lottery_week=week
		flags.js_lottery_number=g.rng.randi_range(0,65535)
		flags.js_lottery_paid=false
	g._persist()
	return int(flags.js_lottery_number)

static func lottery(g,day:Dictionary):
	var n:=lottery_number(g,day)
	var flags:Dictionary=g._flags()
	var intro:="本周幸运号码是 %05d。每星期五更换。"%n
	g._persist()
	if flags.get("js_lottery_paid",false):
		g._dialog([intro,"这期的奖品已经领过了。"],"幸运号码主持人")
		return
	var best:=0
	var name_text:=""
	var owned:Array=g.save_data.party.duplicate()
	for box in g.save_data.get("boxes",[]):owned.append_array(box.get("mons",[]))
	for mon in owned:
		if not mon is Dictionary or mon.is_empty() or mon.get("is_egg",false):continue
		var count:=match_digits(int(mon.get("ot_id",g.save_data.js_trainer_id)),n)
		if count>best:
			best=count
			name_text=mon.name
	if best<2:g._dialog([intro,"队伍和电脑里的伙伴都没有对上末两位。"],"幸运号码主持人")
	else:
		var prize: String="大师球" if best==5 else ("学习装置" if best>=3 else "PP 提升剂")
		g._give_item(prize,1,"ball" if best==5 else "other")
		flags.js_lottery_paid=true
		g._persist()
		g._dialog([intro,"%s的训练家编号对上了末%d位。获得了%s！"%[name_text,best,prize]],"幸运号码主持人")

static func roof_sale(g,day:Dictionary):
	if int(g._flags().get("js_roof_sale",-1))!=current_day(day):
		g._dialog(["今天的特卖已经结束了。"])
		return
	var wares: Array=[["厉害伤药",1000],["全复药",2000],["万灵药",500],["高级球",1000],["攻击增强剂",7800]] if g._flags().get("johto_champion",false) else [["精灵球",150],["超级球",500],["好伤药",500],["万灵药",500],["活力碎片",1200]]
	var labels:Array=[]
	for w in wares:labels.append("%s　¥%d"%w)
	g._pick("百货楼顶特卖",labels,func(i):
		if i<0 or i>=wares.size():return
		var w:Array=wares[i]
		if g.save_data.money<int(w[1]):g._dialog(["钱不够。"]);return
		g.save_data.money-=int(w[1])
		g._give_item(w[0],1,"ball" if str(w[0]).ends_with("球") else "other")
		g._persist();g._dialog(["买到了%s。"%w[0]],"特卖会店员"))
