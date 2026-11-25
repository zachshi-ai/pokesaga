extends RefCounted
## The Galar chapter shares a party and boxes with the other regions.
const Later := preload("res://core/galar_later.gd")
const Hoenn := preload("res://core/hoenn_campaign.gd")
const Party := preload("res://core/party.gd")
const PARTNER_GIFTS := {810:["奇迹种子","MIRACLE_SEED"],813:["木炭","CHARCOAL"],816:["神秘水滴","MYSTIC_WATER"]}
const STARTERS := [810,813,816]
const NAMES := ["敲音猴","炎兔儿","泪眼蜥"]
const STARTER_MOVES := {810:[10,45],813:[33,45],816:[1,45]}
const RIVAL_MOVES := {810:[10,45,713,269],813:[33,45,52,98],816:[1,45,55,20]}
const TOWN_ROOMS := {"galar_hop":"galar_postwick","galar_wedgehurst":"galar_wedgehurst","galar_motostoke":"galar_motostoke","galar_4_":"galar_4","galar_turffield":"galar_turffield"}
static var book: Dictionary
static var by_map: Dictionary

static func data() -> Dictionary:
	if book.is_empty():
		book=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_campaign.json"))
		book.swift_species=PackedInt32Array(book.swift_species)
		for e in book.events+book.get("side_events",[]):by_map.get_or_add(e.map,[]).append(e)
		var later:=Later.data()
		for e in later.events+later.side_events:
			e.galar_later=true
			by_map.get_or_add(e.map,[]).append(e)
	return book

static func version(flags: Dictionary) -> String:
	return str(flags.get("g_version","sword"))

static func active(e: Dictionary,flags: Dictionary) -> bool:
	if not flags.get("g_started",false) or flags.get(e.id,false):return false
	for key in e.require:
		if not flags.get(key,false):return false
	return true

static func event(g,kind: String,ctx: Dictionary) -> Dictionary:
	data()
	var mid: String=g.world.map_data.id
	if kind=="map_enter" and mid in ["galar_mine","galar_mine2"]:
		var p: Vector2i=g.world.player_pos
		for warp in g.world.map_data.get("warps",[]):
			if p.distance_to(Vector2i(int(warp.at[0]),int(warp.at[1])))<=2:
				g._flags().g_mine_exit=warp.to.map
				break
	if kind=="talk":
		for e in by_map.get(mid,[]):
			if e.id in [ctx.get("actor",""),ctx.get("local_id","")] and active(e,g._flags()):return Later.resolve(e,g._flags())
	return {}

static func roster(m: Dictionary,flags: Dictionary,rows: Array=[]) -> Array:
	data()
	var result: Array=rows.duplicate()
	if flags.get("g_catching",false):
		result.append_array(data().get("trainers",{}).get(m.id,[]).duplicate(true))
	if flags.get("g_badge_1",false):
		result.append_array(Later.field_data().trainers.get(m.id,[]).duplicate(true))
	for row in by_map.get(m.id,[]):
		if not active(row,flags):continue
		var e:=Later.resolve(row,flags)
		var cast: Array=[{"name":e.who,"at":e.at}]+e.get("guests",[])
		for i in cast.size():
			var actor: Dictionary=cast[i]
			if actor.has("version") and actor.version!=version(flags):continue
			var id: String=e.id if i==0 else "%s_guest_%d"%[e.id,i]
			result=result.filter(func(row):return row.name!=actor.name and row.at!=actor.at)
			result.append({"at":actor.at,"name":actor.name,"galar_actor":actor.name,"gfx":"expert_m",
				"local_id":id,"role":id,"facing":"down","lines":[e.steps[0].say[0] if i==0 else "去听听%s怎么说吧。"%e.who]})
	return result

static func gate(target: Dictionary,flags: Dictionary,_current: Dictionary={}) -> String:
	if target.get("region","galar")!="galar":return ""
	var mid:=str(target.get("map",""))
	if mid.contains("_center_"):mid=mid.get_slice("_center_",0)
	for room in ["_cafe_room","_boutique_room","_salon_room"]:
		if mid.ends_with(room):mid=mid.trim_suffix(room);break
	if mid.begins_with("galar_ionia_"):mid="galar_circhester"
	if mid=="galar_player_home":return ""
	if not flags.get("g_started",false):return "第一次来伽勒尔，先到化朗镇的家和赫普碰面。"
	var later_gate:=Later.gate(mid,flags)
	if not later_gate.is_empty():return later_gate.message
	var gates: Dictionary=data().gates
	var key:=mid
	if mid in ["galar_turffield_pitch","galar_turffield_mission"]:
		key="galar_turffield_pitch_room"
	if not gates.has(key):
		for prefix: String in TOWN_ROOMS:
			if mid.begins_with(prefix):
				key=TOWN_ROOMS[prefix]
				break
	if gates.has(key):
		var rule: Dictionary=gates[key]
		return "" if flags.get(rule.require,false) else str(rule.message)
	return "" if flags.get("g_badge_1",false) else "先到草路镇完成第一场道馆挑战。"

static func team(cfg: Dictionary,flags: Dictionary) -> Dictionary:
	var stage:=str(cfg.get("galar_hop",""))
	if stage.is_empty():return Later.team(cfg,flags)
	var result:=cfg.duplicate(true)
	var index:=maxi(0,STARTERS.find(int(flags.get("g_starter",810))))
	var species: int=STARTERS[(index+2)%3]
	var level: int={"first":5,"lake":8,"city":14,"ally":12}[stage]
	var moves: Array=RIVAL_MOVES[species].slice(0,2 if stage=="first" else (3 if stage=="lake" else 4))
	var starter:={"species":species,"level":level,"moves":moves}
	if stage=="ally":
		result.ally_team=[{"species":831,"level":10,"moves":[33,45,111]},
			{"species":821,"level":11,"moves":[64,43]},starter]
	else:result.team.append(starter)
	return result

static func partner(save: Dictionary) -> Dictionary:
	var members: Array=save.get("party",[]).duplicate()
	for box in save.get("boxes",[]):
		if box is Dictionary:members.append_array(box.get("mons",[]))
	for mon in members:
		if mon is Dictionary and mon.get("galar_partner",false):return mon
	return {}

static func _say(g,lines: Array,speaker: String="") -> void:
	g._dialog(lines,speaker).closed.connect(g._story_step,CONNECT_ONE_SHOT)

static func _choose_starter(g) -> void:
	if not Hoenn.has_room(g.save_data):
		Hoenn.abort_event(g)
		g._dialog(["先在队伍或电脑里腾出一个位置，三个小家伙会在院子里等你。"],"丹帝")
		return
	g._pick("和谁一起踏上伽勒尔之旅？",NAMES,func(i):
		var sid: int=STARTERS[i]
		var mon:=Party.make(sid,5,STARTER_MOVES[sid].duplicate())
		mon.galar_partner=true
		mon.berry=""
		var where: String=g._store_mon(mon)
		g._flags().g_starter=sid
		g._persist()
		_say(g,[NAMES[i]+("加入了队伍！" if where=="party" else "已送入电脑箱。明天和赫普的初战，它会回来和你并肩作战。")]),func():Hoenn.abort_event(g),STARTERS)

static func _number(g,prefix: String="") -> void:
	var choices: Array=["0","1","2","3","4","5","6","7","8","9"]
	if not prefix.is_empty():choices.push_front("使用 "+prefix+" 号")
	g._pick("选球衣背号（1～3位）　"+prefix,choices,func(i):
		var next: String=prefix if choices[i].begins_with("使用 ") else prefix+str(choices[i])
		if next==prefix or next.length()==3:
			g._flags().g_uniform_number=next
			g._persist()
			_say(g,["背号 "+next+"，已经印上你的挑战者制服。"],"联盟接待员")
		else:_number(g,next),func():Hoenn.abort_event(g))

static func _heal_partner(g,mon: Dictionary) -> void:
	mon.hp=int(mon.max_hp)
	mon.hp_text="%d/%d"%[mon.hp,mon.max_hp]
	mon.erase("status")
	var restored: Array=[]
	for move in mon.moves:restored.append(int(g.get_node("/root/Data").move_of(int(move)).get("pp",1)))
	mon.pp=restored

static func _mist(g) -> void:
	var beast:=888 if version(g._flags())=="sword" else 889
	var battle=load("res://core/battle.gd")
	var ally:=partner(g.save_data)
	if ally.is_empty():
		Hoenn.abort_event(g)
		return
	if int(ally.get("hp",0))<=0:
		_heal_partner(g,ally)
		g._persist()
	var layer:=CanvasLayer.new()
	layer.layer=3
	g.add_child(layer)
	var ui=load("res://scenes/battle_ui.gd").new()
	layer.add_child(ui)
	ui.backdrop="grass"
	ui.setup([ally.duplicate(true)],[battle.make_combatant(beast,70,[163])],822)
	ui.state="watch"
	ui.menu.hide()
	ui.move_menu.hide()
	ui.enemy_sprite.modulate=Color(0.22,0.28,0.40)
	ui.enemy_hp.get_node("Name").text="？？？"
	ui.enemy_hp.get_node("Lv").hide()
	var fog:=ColorRect.new()
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(fog)
	_mist_turn(g,ui,layer,fog,ally,0)

static func _mist_turn(g,ui,layer: CanvasLayer,fog: ColorRect,ally: Dictionary,turn: int) -> void:
	fog.color=Color(0.66,0.72,0.78,0.20+turn*0.18)
	if turn==3:
		var end=g._dialog(["影子消失在雾里。你听见远处丹帝和喷火龙的脚步声。"],"微寐森林")
		end.closed.connect(func():
			layer.queue_free()
			g._story_step(),CONNECT_ONE_SHOT)
		return
	var moves: Array=[]
	for move in ally.moves:moves.append(g.get_node("/root/Data").move_of(int(move)).get("name","招式"))
	var label: String=["雾里出现了一个影子！","招式穿了过去，雾更浓了！","几乎看不见对方……"][turn]
	ui.msg.text=label
	g._pick(label,moves,func(i):
		var report=g._dialog(["%s用了%s。招式对雾里的宝可梦没有效果！"%[ally.name,moves[i]]])
		report.closed.connect(func():_mist_turn(g,ui,layer,fog,ally,turn+1),CONNECT_ONE_SHOT),
		func():
			layer.queue_free()
			Hoenn.abort_event(g))
	var veil=g.menu_layer.get_child(-1).get_child(0)
	if veil is ColorRect:veil.color.a=0.35

static func prompt(g,act: Dictionary) -> bool:
	if Later.prompt(g,act):return true
	if act.has("galar_starter"):
		if int(g._flags().get("g_starter",0)) in STARTERS:return false
		_choose_starter(g)
	elif act.has("galar_mist"):_mist(g)
	elif act.has("galar_number"):
		if g._flags().has("g_uniform_number"):return false
		_number(g)
	elif act.has("galar_catch"):
		if g._flags().get("g_caught_locally",false):return false
		Hoenn.catch_demonstration(g,831,3,[33],821,5,[64],["丹帝派出稚山雀，拦住野生的毛辫羊。","稚山雀，使出啄！毛辫羊的体力下降了。","丹帝投出精灵球。球晃动了几下，停住了！"])
	elif act.has("galar_parade"):
		var v:=version(g._flags())
		var pair:=["彩豆","玛瓜"] if v=="sword" else ["欧尼奥","美蓉"]
		_say(g,["草系的亚洛、水系的露璃娜、火系的卡芜依次入场！",
			"%s、波普菈、%s和奇巴纳也走上了赛场。尖钉镇的聂梓今天缺席。"%pair,
			"现在入场的是今年的挑战者。小悠，背号 "+str(g._flags().get("g_uniform_number",""))+"！"],"竞技场广播")
	else:return false
	return true

static func action(g,act: Dictionary) -> void:
	Later.action(g,act)
	if act.has("heal") and g.cur_story.get("id","") in ["g_partner","g_hop_first"]:
		var starter:=partner(g.save_data)
		if not starter.is_empty():_heal_partner(g,starter)
	if act.has("galar_partner_item") and not g._flags().get("g_partner_item_received",false):
		var gift: Array=PARTNER_GIFTS[int(g._flags().g_starter)]
		g._give_bag_item(gift[0],"held",gift[1])
		g._flags().g_partner_item_received=true
		g._show_toast("丹帝送来了"+gift[0]+"！")
	if act.has("galar_berry"):
		var berry: Dictionary=g.get_node("/root/Data").berries.get(act.galar_berry,{})
		if not berry.is_empty():g._give_bag_item(berry.name,"berry","",act.galar_berry)
	if act.has("galar_key") and g._bag_count(act.galar_key)==0:
		g._give_item(act.galar_key,1,"tm" if act.galar_key==preload("res://core/galar_items.gd").SWIFT else "key")
	if act.has("galar_train"):
		var m: Dictionary=g.get_node("/root/Data").load_map("galar",act.galar_train)
		g._do_warp({"region":"galar","map":m.id,"at":m.spawn,"facing":"down"})

static func use(g,item_name: String) -> bool:
	return preload("res://core/galar_items.gd").use(g,item_name)

static func encounters(mid: String,flags: Dictionary) -> Dictionary:
	if not mid.begins_with("galar_"):return {}
	if not flags.get("g_partner",false) or (mid=="galar_weald" and not flags.get("g_hop_first",false)):return {"pool":[],"rate":0.0}
	var tables: Dictionary=data().get("encounters",{})
	if not tables.has(mid):return Later.encounter_data(mid,flags)
	var field: Dictionary=tables[mid]
	return {"rate":field.rate,"pool":field.shared+field.get(version(flags),[])}
