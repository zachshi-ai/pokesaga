extends RefCounted
## Story following the Grass Badge, including the Champion Cup and the royal heirs.
const Party := preload("res://core/party.gd")
const Growth := preload("res://core/growth.gd")
const Dex := preload("res://core/dex_variants.gd")
const Hoenn := preload("res://core/hoenn_campaign.gd")
const Forms := {888:"ZACIAN_CROWNED",889:"ZAMAZENTA_CROWNED"}
const BIKE := "洛托姆自行车"
const LANDMARKS := {
	"galar_hulbury":"galar_hulbury","galar_5_":"galar_5","galar_stow":"galar_stow",
	"galar_ballonlea":"galar_ballonlea","galar_circhester":"galar_circhester",
	"galar_spikemuth":"galar_spikemuth","galar_hammerlocke":"galar_hammerlocke","galar_wyndon":"galar_wyndon"}
const VERSION_NAMES := {"@贵族":["索德","西尔迪"],"@兄弟":["西尔迪","索德"],
	"@己方狼":["苍响","藏玛然特"],"@另一只狼":["藏玛然特","苍响"],"@溯传馆主":["彩豆","欧尼奥"],"@战竞馆主":["玛瓜","美蓉"]}
const RELICS := {888:["腐朽的剑","RUSTED_SWORD"],889:["腐朽的盾","RUSTED_SHIELD"]}
static var book: Dictionary
static var teams: Dictionary
static var field_book: Dictionary

static func field_data() -> Dictionary:
	if field_book.is_empty():
		field_book=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_later_field.json"))
		field_book.retaliate_species=PackedInt32Array(field_book.retaliate_species)
		field_book.retaliate_excluded_base=PackedInt32Array(field_book.retaliate_excluded_base)
	return field_book

static func data() -> Dictionary:
	if book.is_empty():book=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_later_campaign.json"))
	return book

static func name_for(raw: String,flags: Dictionary)->String:
	if VERSION_NAMES.has(raw):return VERSION_NAMES[raw][1 if flags.get("g_version")=="shield" else 0]
	return raw

static func encounter_data(mid: String,flags: Dictionary) -> Dictionary:
	var habitats: Dictionary=field_data().encounters
	if not habitats.has(mid):return {}
	var field: Dictionary=habitats[mid]
	var pool: Array=field.shared+field.get(str(flags.get("g_version","sword")),[])
	if flags.get("g_champion",false) and (mid.begins_with("galar_wild_") or mid=="galar_lake_out"):
		pool=pool.duplicate(true)
		for mon in pool:mon.min=60;mon.max=60
	return {"rate":field.rate,"pool":pool}

static func gate(mid: String,flags: Dictionary) -> Dictionary:
	if mid in ["galar_energy_plant","galar_tower_summit"] and flags.get("g_lab_theft",false) and not flags.get("g_plant_unlock",false):
		return {"message":"能源工厂的电梯已上锁。先处理各地竞技场的极巨化异常，回拳关竞技场见索妮亚。"}
	if mid.begins_with("galar_pass_"):return {"message":""}
	if mid.begins_with("galar_gym_"):
		var n:=int(mid.get_slice("_",2))
		return {"message":"" if flags.get("g_badge_"+str(n-1),false) else "先取得前一座道馆的徽章。"}
	var all_rules: Dictionary=data().gates
	var key:=mid
	if not all_rules.has(key):
		for prefix: String in LANDMARKS:
			if mid.begins_with(prefix):key=LANDMARKS[prefix];break
	if not all_rules.has(key):return {}
	var rule: Dictionary=all_rules[key]
	return {"message":"" if flags.get(rule.require,false) else str(rule.message)}

static func resolve(e: Dictionary,flags: Dictionary)->Dictionary:
	if not e.has("galar_later"):return e
	var copy:=e.duplicate(true)
	copy.who=name_for(e.who,flags)
	for guest in copy.guests:guest.name=name_for(guest.name,flags)
	for step in copy.steps:
		if step.has("who"):step.who=name_for(step.who,flags)
	return copy

static func team(cfg: Dictionary,flags: Dictionary)->Dictionary:
	if not cfg.has("galar_team"):return cfg
	if teams.is_empty():teams=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_later_teams.json"))
	var c:=cfg.duplicate(true)
	var shield: bool=flags.get("g_version")=="shield"
	var index:=maxi(0,[810,813,816].find(int(flags.get("g_starter",810))))
	var key: String=c.get("galar_shield_team",c.galar_team) if shield else c.galar_team
	if c.has("galar_variant"):
		var variants: Array=c.get("galar_shield_variant",c.galar_variant) if shield else c.galar_variant
		key=variants[index]
	c.team=teams[key].duplicate(true)
	c.name=name_for(c.name,flags)
	if c.get("galar_select_version_mon",false):c.team=[c.team[1 if shield else 0]]
	if c.has("galar_other"):
		for mon in c.team:mon.trainer_group="first"
		for mon in teams[c.galar_other].duplicate(true):
			mon.trainer_group="second"
			c.team.append(mon)
		c.ally_team=teams[c.galar_allies[index]].duplicate(true)
	if c.get("galar_power_spot",false) and not c.has("galar_raid"):
		var ace: Dictionary=c.team.back()
		if ace.has("gmax") or c.get("galar_ordinary_max",false):
			c.galar_ace=int(ace.species)
			c.galar_gmax=ace.has("gmax")
			c.galar_gmax_form=ace.get("gmax","")
	return c

static func wolf(flags: Dictionary)->int:
	return 889 if flags.get("g_version")=="shield" else 888

static func _room(g)->bool:
	if Hoenn.has_room(g.save_data):return true
	Hoenn.abort_event(g)
	g._dialog(["先在队伍或电脑里留出一个空位，准备好后随时再来。"])
	return false

static func _then(g,lines: Array,speaker: String="")->void:
	g._dialog(lines,speaker).closed.connect(g._story_step,CONNECT_ONE_SHOT)

static func _eternatus(g)->void:
	if not _room(g):return
	var balls: Array=[]
	for item in g.bag_items:
		if item.get("category","")=="ball" and int(item.get("count",0))>0:balls.append(str(item.name))
	if balls.is_empty():
		g._give_item("精灵球",1,"ball")
		balls=["精灵球"]
	g._pick("用哪个球接住无极汰那？",balls,func(i):
		var mon:=Party.make(890,60,[690,406,53,440])
		mon.capture_ball=balls[i]
		g._consume_item(balls[i])
		g._store_mon(mon)
		g._flags().g_eternatus_received=true
		g._persist()
		_then(g,["球停住了。无极汰那被收服了！"]),func():Hoenn.abort_event(g))

static func _collection(save: Dictionary)->Array:
	var members: Array=save.party.duplicate()
	for box in save.get("boxes",[]):members.append_array(box.get("mons",[]))
	return members

static func _capture_wolf(g)->void:
	if not _room(g):return
	var sid:=wolf(g._flags())
	var previous:=_collection(g.save_data).filter(func(m):return m is Dictionary and int(m.get("species_id",0))==sid)
	g._start_wild_battle(sid,70,Forms[sid],func(result):
		if result=="caught":
			for member in _collection(g.save_data):
				if not member is Dictionary or int(member.get("species_id",0))!=sid:continue
				if previous.any(func(older):return is_same(older,member)):continue
				member.galar_hero=true
				member.held=RELICS[sid][1]
				Party.set_form(member,"")
				Dex.record(g.save_data,member,true)
				if g._bag_count(RELICS[sid][0]):g._consume_item(RELICS[sid][0])
				break
			g._flags().g_wolf_received=true
			g._persist()
			_then(g,[name_for("@己方狼",g._flags())+"认可了你，带着遗物加入队伍。"])
		else:
			Hoenn.abort_event(g)
			g._dialog(["传说的宝可梦静静等在塔顶。准备好精灵球，再走到它面前吧。"]),"none")

static func prompt(g,act: Dictionary)->bool:
	if act.has("galar_eternatus_ball"):
		if g._flags().get("g_eternatus_received",false):return false
		_eternatus(g)
	elif act.has("galar_wolf_catch"):
		if g._flags().get("g_wolf_received",false):return false
		_capture_wolf(g)
	elif act.has("galar_toxel"):
		if g._flags().get("g_toxel_received",false):return false
		if _room(g):
			g._store_mon(Party.make(848,1,[45,175,51,609]))
			g._flags().g_toxel_received=true
			g._persist()
			_then(g,["毒电婴加入了你的伙伴！"],"培育家")
	else:return false
	return true

static func action(g,act: Dictionary)->void:
	if act.has("galar_hall"):
		g.johto_league.register_team(g.save_data,"galar")
		g._flags().g_hall_recorded=true
	elif act.has("galar_relic"):
		var item_name: String=RELICS[wolf(g._flags())][0]
		if not g._bag_count(item_name):g._give_item(item_name,1,"key")
	elif act.has("galar_return_relic"):
		g._consume_item(RELICS[wolf(g._flags())][0])
	elif act.has("galar_card"):
		var who:=name_for(act.galar_card,g._flags())
		var card:=who+("的稀有联盟卡" if act.get("rare",false) else "的联盟卡")
		if not g._bag_count(card):g._give_item(card,1,"key")
	elif act.has("galar_machine"):
		var title:="伽勒尔招式学习器79·报仇"
		if not g._bag_count(title):g._give_item(title,1,"tm")
	elif act.has("galar_water_bike"):
		g._flags().g_water_bike=true
		g._show_toast("洛托姆自行车已加装浮囊！")

static func use(g,nm: String)->bool:
	if nm==BIKE:
		if g.world.map_data.region not in ["galar","armor","crown"]:g._dialog(["把洛托姆自行车带回伽勒尔的道路或旷野骑行。"],nm)
		elif g.world.surfing:g._dialog(["浮囊已经展开。骑回陆地就能下车。"],nm)
		elif g.world.map_data.get("biome","")=="interior":g._dialog(["请先到户外，再骑洛托姆自行车。"],nm)
		else:g._toggle_bike()
	elif nm=="单轨列车钥匙":
		if g.world.map_data.id in ["galar_wyndon_station_room","galar_rose"] and g._flags().get("g_staff_3",false):
			var destination:="galar_wyndon_station_room" if g.world.map_data.id=="galar_rose" else "galar_rose"
			var title:="宫门市车站" if destination=="galar_wyndon_station_room" else "洛兹大厦"
			g._pick("乘坐单轨列车？",["前往"+title,"留在这里"],func(i):
				if i==0:
					var m: Dictionary=g.get_node("/root/Data").load_map("galar",destination)
					g._do_warp({"region":"galar","map":m.id,"at":m.spawn,"facing":"down"}))
		else:g._dialog(["到宫门市车站或洛兹大厦入口使用钥匙，可以乘坐单轨列车往返。"],nm)
	elif nm=="经验糖果XS":
		var slots: Array=[]
		var labels: Array=[]
		for i in g.save_data.party.size():
			var m=g.save_data.party[i]
			if m is Dictionary and not m.is_empty() and int(m.level)<Growth.MAX_LEVEL:
				slots.append(i);labels.append(str(m.name)+"  Lv"+str(int(m.level)))
		if slots.is_empty():g._dialog(["队伍里没有需要经验糖果的伙伴。"],nm)
		else:g._pick("把经验糖果给谁？",labels,func(i):
			var m: Dictionary=g.save_data.party[slots[i]]
			var old:=int(m.level)
			var gained:=Growth.add_exp(m,100)
			if gained>0:
				Party.recalc(m,true)
				g._learn_new_moves(m,old,int(m.level))
				var evolution:=Growth.evolution_of(m)
				if not evolution.is_empty() and Party.evolve(m,int(evolution.to),str(evolution.get("form",""))):Dex.record(g.save_data,m,true)
			g._consume_item(nm);g._persist()
			g._dialog(["%s获得了100点经验值。"%m.name],nm))
	elif nm=="索妮亚的书":
		g._dialog(["第三章　两位王者与剑盾","挂毯让我们看见两位少年，溯传遗迹让我们认出与他们一同战斗的宝可梦。微寐森林深处，石碑仍在守候它们。"],nm)
	elif nm in ["腐朽的剑","腐朽的盾"]:
		g._dialog(["微寐森林的石台保存着这件遗物。塔顶对战时能唤来传说的伙伴；它会认出携带遗物的训练家。"],nm)
	elif nm=="伽勒尔招式学习器79·报仇":
		var slots: Array=[];var labels: Array=[]
		var compat:=field_data()
		for i in g.save_data.party.size():
			var mon: Dictionary=g.save_data.party[i]
			if retaliate_compatible(mon,compat):
				slots.append(i);labels.append(str(mon.name))
		if slots.is_empty():g._dialog(["目前队伍里没有能够学习报仇的伙伴。"],nm)
		else:g._pick("让谁学习报仇？",labels,func(i):g._tm_teach_one(514,int(slots[i]),"报仇",true))
	elif nm.ends_with("的联盟卡") or nm.ends_with("的稀有联盟卡"):
		g._dialog([card_text(nm)],nm)
	else:return false
	return true

static func retaliate_compatible(mon: Dictionary,compat: Dictionary)->bool:
	var sid:=int(mon.get("species_id",0))
	var form:=str(mon.get("form",""))
	return sid in compat.retaliate_species and form not in compat.retaliate_excluded_forms and (form!="" or sid not in compat.retaliate_excluded_base)

static func card_text(nm: String)->String:
	var who:=nm.split("的")[0]
	var profiles:={"露璃娜":"水舟镇的模特与水系馆主。","卡芜":"从丰缘来到伽勒尔，始终坚持锻炼。","奇巴纳":"从未停止向丹帝发起挑战。","彩豆":"坚持每日练拳，在擂台上从不退让。","欧尼奥":"擅长与幽灵宝可梦交朋友。","玛瓜":"战竞镇岩石系馆主，拥有自己的粉丝团。","美蓉":"在战竞镇的冰路上磨练挑战者。","聂梓":"和乌贼王一起守护尖钉镇的舞台。","波普菈":"为妖精道馆找到了新的继承人。","彼特":"从洛兹的挑战者成长为妖精道馆馆主。","赫普":"和自己的搭档一起，踏上宝可梦研究之路。","亚洛":"和毛辫羊一起照看草路镇的牧场。","洛兹":"曾担任伽勒尔联盟会长，出身普通矿工家庭。"}
	return who+"　｜　"+str(profiles.get(who,"伽勒尔联盟登记的训练家。"))
