extends RefCounted

const GATE := "em_route121_safari_zone_entrance"
const FIELD := "em_safari_zone_south"
const EXPANSION := ["em_safari_zone_northeast","em_safari_zone_southeast"]
static func inside(mid: String) -> bool:return mid.begins_with("em_safari_zone_")

static func admit(g) -> void:
	if g._bag_count("宝可方块盒")==0 or not g._flags().get("h_item_pokeblock_case",false):g._dialog(["请先去水静市的华丽大赛大厅领取宝可方块盒。"],"原野区接待员");return
	g._pick("原野区门票500元，含30枚原野球。可走500步。",["入园","取消"],func(i):
		if i!=0:return
		if int(g.save_data.money)<500:g._dialog(["入园需要500元。"]);return
		g.save_data.money-=500
		g._flags().h_safari={"balls":30,"steps":500,"feeders":{}}
		preload("res://core/emerald_legends.gd").warp(g,FIELD,[32,33]))

static func exit_park(g,reason: String) -> void:
	g._flags().erase("h_safari")
	preload("res://core/emerald_legends.gd").warp(g,GATE,[9,5])
	g._dialog([reason],"原野区")

static func talk(g, n: Dictionary) -> bool:
	match n.get("source_script",""):
		"Route121_SafariZoneEntrance_EventScript_WelcomeAttendant":admit(g)
		"Route121_SafariZoneEntrance_EventScript_InfoAttendant":g._dialog(["在园内可以靠近宝可梦、投宝可方块和原野球。越靠近越容易抓住，它逃跑的机会也越大。"])
		"SafariZone_South_EventScript_ExitAttendant":
			g._pick("结束这次捕捉？",["离开园区","继续"],func(i):
				if i==0:exit_park(g,"剩余的原野球已经归还。"))
		_:return false
	return true

static func passage(g, dest: Dictionary) -> String:
	var m:String=g.world.map_data.id
	var target:String=dest.get("map","")
	if target in EXPANSION and not g._flags().get("h_champion",false):return "扩建区仍在施工，成为丰缘联盟冠军后再来。"
	if m==GATE and inside(target) and not g._flags().has("h_safari"):return "请先向门厅里的接待员购票。"
	if inside(m) and not inside(target):g._flags().erase("h_safari")
	return ""

static func step(g) -> bool:
	if not inside(g.world.map_data.id):return false
	var visit: Dictionary=g._flags().get_or_add("h_safari",{"balls":30,"steps":500,"feeders":{}})
	visit.steps-=1
	for key in visit.feeders.keys():
		visit.feeders[key].steps-=1
		if visit.feeders[key].steps<=0:visit.feeders.erase(key)
	if visit.steps>0:return false
	exit_park(g,"时间到了！五百步已走完。")
	return true

static func name_of(block) -> String:
	return str(block.get("name","树果")) if block is Dictionary else str(block)

static func block_choice(g, f: Callable) -> void:
	var blocks:Array=g._flags().get("h_blocks",[])
	if blocks.is_empty():g._dialog(["盒子里没有宝可方块。"]);return
	var opts:Array=blocks.map(func(b):return name_of(b))
	opts.append("取消")
	g._pick("选择要投放的宝可方块",opts,func(i):
		if i<blocks.size():f.call(blocks.pop_at(i)))

static func feeder(g,at: Array) -> bool:
	var run:Dictionary=g._flags().get("h_safari",{})
	if run.is_empty():return false
	var key: String="%s/%s/%s"%[g.world.map_data.id,int(at[0]),int(at[1])]
	block_choice(g,func(block):
		run.feeders[key]={"at":at,"map":g.world.map_data.id,"steps":100,"block":block}
		g._persist()
		g._dialog(["宝可方块放进了喂食器。附近的宝可梦会被气味吸引。"]))
	return true

static func encounter(g,sid: int,level: int,form: String) -> bool:
	if not inside(g.world.map_data.id):return false
	var visit:Dictionary=g._flags().get_or_add("h_safari",{"balls":30,"steps":500,"feeders":{}})
	var mon:Dictionary=g.PartyScript.make(sid,level,g.EncounterScript.moves_for(sid,level),form)
	g.PartyScript.set_shiny_kind(mon,g.PartyScript.roll_shiny(g.appearance_rng))
	var tones:=["辣","涩","甜","苦","酸"]
	var natures:=["固执","内敛","胆小","温和","大胆"]
	var preferred:int=g.rng.randi_range(0,4)
	for entry in visit.feeders.values():
		var at: Array=entry.at
		if entry.map==g.world.map_data.id and g.world.player_pos.distance_to(Vector2i(at[0],at[1]))<=5 and g.rng.randi_range(0,1)==0:
			preferred=taste(entry.block)
			break
	mon.nature=natures[preferred]
	load("res://core/dex_variants.gd").record(g.save_data,mon,false)
	var species:Dictionary=g.get_node("/root/Data").species_of(sid)
	var state:={"catch":maxi(1,int(species.get("catch_rate",45))*100/1275),"escape":3,"near":0,"throws":0}
	var ui=load("res://scenes/frlg_safari_ui.gd").new()
	ui.name="HoennSafariEncounter"
	g.panel_open+=1
	g._set_hud_visible(false)
	g.menu_layer.add_child(ui)
	ui.setup(mon,"原野球 %d　剩余步数 %d"%[visit.balls,visit.steps],[["ball","扔原野球"],["block","投宝可方块"],["near","慢慢靠近"],["run","离开"]])
	var finish:=func(message: String):
		ui.queue_free()
		g.panel_open=maxi(0,g.panel_open-1)
		if visit.balls<=0:exit_park(g,message+" 原野球已用完。")
		else:
			g._set_hud_visible(true)
			g._show_toast(message)
		g._persist()
	var turn:=func(message: String):
		if g.rng.randi_range(0,99)<int(state.escape)*5:finish.call(mon.name+"逃走了。")
		else:ui.info.text=message+"　原野球 %d"%visit.balls
		g._persist()
	ui.action_chosen.connect(func(action):
		if ui.is_queued_for_deletion():return
		match action:
			"run":finish.call("离开了。")
			"near":
				state.catch=mini(20,int(state.catch)+[4,3,2,1][mini(3,int(state.near))])
				state.escape=mini(20,int(state.escape)+4)
				state.near=mini(3,int(state.near)+1)
				turn.call("你悄悄靠近了。")
			"block":
				block_choice(g,func(block):
					state.throws=mini(3,int(state.throws)+1)
					var delta:int=[5,3,2,1][int(state.throws)-1] if taste(block)==preferred else [3,2,1,1][int(state.throws)-1]
					state.escape=maxi(1,int(state.escape)-delta)
					turn.call("它对%s味的方块很感兴趣。"%tones[taste(block)]))
			"ball":
				visit.balls-=1
				var odds:=maxi(1,int(state.catch)*1275/100*15/10/3)
				if g.rng.randf()<float(odds)/255.0:
					var where:String=g._store_mon(mon)
					finish.call("抓到了%s！%s。"%[mon.name,"已加入队伍" if where=="party" else "已送入电脑"])
				elif visit.balls<=0:finish.call("宝可梦挣脱了。")
				else:turn.call("宝可梦挣脱了。")
	)
	return true

static func taste(block) -> int:
	var key:=str(block.get("berry","")) if block is Dictionary else str(block)
	var data:Dictionary=preload("res://core/emerald_contest.gd").data().berries.get(key,{})
	var flavors:Array=data.get("flavor",[])
	return flavors.find(flavors.max()) if not flavors.is_empty() else 0


static func feeder_field(g) -> bool:
	if not inside(g.world.map_data.id):return false
	var p: Vector2i=g.world.player_pos+g.world._dir_vec()
	if preload("res://core/hoenn_field.gd").behavior(g.world.map_data,p)!=0x87:return false
	return feeder(g,[p.x,p.y])
