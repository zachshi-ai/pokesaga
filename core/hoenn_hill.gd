extends RefCounted

const MODES := ["Normal","Variety","Unique","Expert"]
const NAMES := ["普通","变化","独特","专家"]
const ENTRY := "em_trainer_hill_entrance"
const ROOF := "em_trainer_hill_roof"

static func counter(g) -> void:
	var f: Dictionary=g._flags()
	if not f.get("h_champion",false):g._dialog(["进入丰缘名人堂之后，再来挑战训练家山吧。"]);return
	if f.has("h_hill"):
		g._pick("要结束本次计时吗？",["继续挑战","退出"],func(i):
			if i==1:
				f.erase("h_hill")
				g._persist())
		return
	var opts: Array=NAMES.duplicate()
	opts.append("退出")
	g._pick("选择训练家山赛道",opts,func(i):
		if i>=MODES.size():return
		f.h_hill={"mode":MODES[i],"start":Time.get_unix_time_from_system(),"won":{}}
		g._heal_party()
		g._persist()
		g._dialog(["计时开始！穿过四层迷宫，到屋顶找主人。"],"接待员"))

static func reward(mode: String, seconds: int) -> Array:
	if seconds<720:
		if mode=="Variety":return ["PP 多项小补剂","medicine"]
		return ["招式学习器 %02d"%int({"Normal":11,"Unique":19,"Expert":31}[mode]),"tm"]
	if seconds<780:return ["PP 单项小补剂","medicine"]
	if seconds<840:return ["全满药","medicine"]
	if seconds<960:return ["活力碎片","revive"]
	if seconds<1080:return ["向尾喵的尾巴","other"]
	return ["超级球","ball"]

static func records(g) -> void:
	var times: Dictionary=g._flags().get("h_hill_times",{})
	var lines: Array=[]
	for i in MODES.size():
		if times.has(MODES[i]):
			var secs:=int(times[MODES[i]])
			lines.append("%s　%d分%02d秒"%[NAMES[i],floori(float(secs)/60),secs%60])
	g._dialog(["还没有登顶记录。"] if lines.is_empty() else lines,"训练家山纪录板")

static func talk(g,n: Dictionary) -> bool:
	var sc:=str(n.get("source_script",""))
	var flags: Dictionary=g._flags()
	match sc:
		"TrainerHill_Entrance_EventScript_Attendant":counter(g)
		"TrainerHill_Entrance_EventScript_Nurse":
			g._heal_party()
			g._dialog(["你的伙伴恢复精神了。"])
		"TrainerHill_Roof_EventScript_Owner":
			if not flags.has("h_hill"):g._dialog(["欢迎来到山顶。入口可以报名挑战。"]);return true
			var run: Dictionary=flags.h_hill
			var elapsed:=maxi(0,int(Time.get_unix_time_from_system()-float(run.start)))
			var times: Dictionary=flags.get_or_add("h_hill_times",{})
			times[run.mode]=mini(elapsed,int(times.get(run.mode,elapsed)))
			var prize:=reward(run.mode,elapsed)
			g._give_item(prize[0],1,prize[1])
			flags.erase("h_hill")
			g._persist()
			g._dialog(["用了%d分%02d秒。收下这份%s吧！"%[floori(float(elapsed)/60),elapsed%60,prize[0]]],"训练家山主人")
		"TrainerHill_Elevator_EventScript_Attendant":
			g._pick("乘电梯返回一楼？",["一楼","留在这里"],func(i):
				if i==0:
					flags.erase("h_hill")
					preload("res://core/emerald_legends.gd").warp(g,ENTRY,[9,5]))
		"EmeraldHillTrainer":
			var run: Dictionary=flags.get("h_hill",{})
			if run.is_empty() or run.won.has(n.hill_id):g._dialog(["祝你顺利登顶。"],n.name)
			else:fight(g,[n])
		_:return false
	return true

static func course(w) -> Dictionary:
	var layouts: Dictionary=w.map_data.get("mechanisms",{}).get("hill",{})
	return layouts.get(w.taken.get("h_hill",{}).get("mode","Normal"),{})

static func step(g) -> bool:
	var w=g.world
	if w.map_data.id==ENTRY and w.player_pos==Vector2i(9,6) and not w.taken.has("h_hill"):
		counter(g)
		return true
	if not w.map_data.get("mechanisms",{}).has("hill") or not w.taken.has("h_hill"):return false
	var seen: Array=[]
	for n in course(w).actors:
		if w.taken.h_hill.won.has(n.hill_id):continue
		var dir: Vector2i={"up":Vector2i.UP,"down":Vector2i.DOWN,"left":Vector2i.LEFT,"right":Vector2i.RIGHT}[n.facing]
		var p:=Vector2i(n.at[0],n.at[1])
		for i in int(n.sight):
			p+=dir
			if w.blocked_by_terrain(p):break
			if p==w.player_pos:
				seen.append(n)
				break
	if seen.is_empty():return false
	fight(g,seen)
	return true

static func fight(g, opponents: Array) -> void:
	if is_instance_valid(g.active_battle):return
	var mine: Array=g._make_team()
	if mine.is_empty():return
	var level:=1
	for mon in g.save_data.party:
		if mon is Dictionary:level=maxi(level,int(mon.get("level",1)))
	var enemy: Array=[]
	var trainers: Array=[]
	for n in opponents:
		trainers.append(n.name)
		for m in n.team:
			var mon: Dictionary=g.BattleScript.make_combatant(m.species,level,m.moves)
			if str(m.held).ends_with("_BERRY"):mon.berry=str(m.held).trim_suffix("_BERRY")
			else:mon.held=m.held
			enemy.append(mon)
	var ui=load("res://scenes/double_battle_ui.gd").new() if opponents.size()>1 and mine.size()>1 else load("res://scenes/battle_ui.gd").new()
	var layer:=CanvasLayer.new()
	layer.layer=6
	g.add_child(layer)
	layer.add_child(ui)
	g.active_battle=ui
	g.held_dir=""
	g._set_hud_visible(false)
	ui.setup(mine,enemy,g.rng.randi(),[]," / ".join(trainers))
	ui.finished.connect(func(result):
		g.active_battle=null
		g._set_hud_visible(true)
		layer.queue_free()
		g._writeback_team(ui.player_team)
		if result=="a":
			for n in opponents:g._flags().h_hill.won[n.hill_id]=true
		else:
			g._flags().erase("h_hill")
			g._heal_party()
			preload("res://core/emerald_legends.gd").warp(g,ENTRY,[9,7])
		g._persist())

static func shop(g) -> Array:
	var goods: Array=[]
	var stock: Array=[["厉害伤药",1200],["全满药",2500],["全复药",3000],["万灵药",600],["活力碎片",1500]] if g._flags().get("h_champion",false) else [["好伤药",700],["解毒药",100],["麻痹药",200],["解眠药",250]]
	for row in stock:goods.append({"name":row[0],"category":"heal","price":row[1],"count":1})
	var boosts: Dictionary=g.get_node("/root/Data").FIELD_BATTLE_ITEMS
	for key in ["X_SPEED","X_SPECIAL","X_ATTACK","X_DEFEND","DIRE_HIT","GUARD_SPEC","X_ACCURACY"]:
		if not boosts.has(key):continue
		goods.append({"name":boosts[key],"category":"battle","price":{"X_SPEED":350,"X_SPECIAL":350,"X_ATTACK":500,"X_DEFEND":550,"DIRE_HIT":650,"GUARD_SPEC":700,"X_ACCURACY":950}[key],"count":1})
	return goods
