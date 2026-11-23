extends SceneTree
## Drive all four surf courses and visit the mall in an earned champion save.
## Use developed Pelago islands and advance their elapsed-time clocks for training and treasure.
var game
var side
var party
var save_io
var errors: Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,reason:String) -> bool:
	if not ok:errors.append(reason);push_error(reason)
	return ok
func frames() -> void:
	await process_frame
	await process_frame
func dismiss() -> void:
	game._close_all_dialogs()
	await frames()
func button(label:String):
	for b in game.menu_layer.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and not b.disabled and str(b.text).begins_with(label):return b
	return null
func press(label:String) -> bool:
	var b=button(label)
	if not check(b!=null,"missing button "+label):return false
	b.pressed.emit()
	await frames()
	return true
func visit(id:String) -> bool:
	var name: String=side.rows()[id].map
	var map: Dictionary=root.get_node("Data").load_map("alola",name)
	game._do_warp({"region":"alola","map":name,"at":map.spawn,"alola_native":true})
	await frames()
	var w=game.world
	if not check(w.map_data.id==name,"wrong map "+id):return false
	var actors: Array=w.npcs.filter(func(n):return str(n.get("alola_side",""))==id)
	if not check(actors.size()==1,"NPC missing "+id):return false
	var at: Array=actors[0].at
	var goal:=Vector2i(int(at[0]),int(at[1]))
	var dirs:={"left":Vector2i.LEFT,"right":Vector2i.RIGHT,"up":Vector2i.UP,"down":Vector2i.DOWN}
	var start: Vector2i=w.player_pos
	var paths: Dictionary={start:null}
	var todo: Array=[start]
	while not todo.is_empty():
		var pos: Vector2i=todo.pop_front()
		for face in dirs:
			var delta: Vector2i=dirs[face]
			var xy:=pos+delta
			if xy==goal:
				var walk: Array=[]
				while pos!=start:
					var step: Array=paths[pos]
					walk.push_front(step[1])
					pos=step[0]
				for step in walk:
					if not check(w.step(step),"blocked walking to "+id):return false
					w.tick_walk(1)
				w.facing=face
				game._on_action()
				await frames()
				return true
			if not paths.has(xy) and w.warp_at(xy).is_empty() and w.can_enter(xy,delta):
				paths[xy]=[pos,delta]
				todo.append(xy)
	return check(false,"no walk to "+id)
func surf(course:int) -> bool:
	if not await visit("surf"+str(course)):return false
	if not await press("出发"):return false
	var jump=button("乘浪")
	var trick=button("→")
	var ui=jump.get_parent()
	var elapsed:=0
	while ui.started and elapsed<1800:
		if ui.jump==0:jump.pressed.emit()
		else:trick.pressed.emit()
		ui._process(0.12)
		elapsed+=1
	print("wave ",course," score ",ui.score," time ",elapsed," distance ",ui.distance," flag ",game._flags().get("as_surf_best_"+str(course),-1))
	await frames()
	await dismiss()
	return check(game._flags().get("as_surf_top_"+str(course),false),"failed wave score "+str(course))
func train_ui(mon:Dictionary,cap:String,stat:String="",cancel:=false) -> void:
	if not await visit("hyper"):return
	if not await press(mon.name+"  Lv."):return
	if not await press(cap):return
	if stat!="" and not await press(party.STAT_LABELS[stat]):return
	await press("暂时不用" if cancel else "开始特训")
	await dismiss()
func train_at_resort(mon:Dictionary,slot:int) -> bool:
	var resort=load("res://core/alola_pelago.gd")
	var resort_state: Dictionary=resort.current(game)
	resort_state.ranks.evelup=3
	resort_state.ranks.aphun=3
	# Only the developed island facilities and their clocks are test fixtures.
	var boxes: Array=game.save_data.boxes
	boxes.push_front({"name":"特训","mons":[mon]})
	game.save_data.party[slot]={}
	var rounds:=0
	while int(mon.level)<100 and rounds<30:
		resort.start(game,resort_state,"evelup");await frames()
		if not await press("经验") or not await press("99 次") or not await press("特训 · "):return false
		resort_state.last=int(resort_state.last)-99*1800
		resort.current(game)
		resort.claim(game,resort_state,"evelup",resort_state.jobs.evelup[0]);await dismiss()
		rounds+=1
	game.save_data.party[slot]=mon
	boxes.pop_front()
	if not check(int(mon.level)==100,"resort experience did not reach level 100"):return false
	game.rng.seed=8282
	for i in 10:
		resort.start(game,resort_state,"aphun");await frames()
		if not await press("寻找珍贵的宝物"):return false
		resort_state.last=int(resort_state.last)-24*3600
		resort.current(game)
		resort.claim(game,resort_state,"aphun",resort_state.jobs.aphun[0]);await dismiss()
		if game._bag_count("银色王冠")>=2:
			print("RESORT ",rounds," rounds of experience, ",i+1," treasure expeditions; silver caps ",game._bag_count("银色王冠"))
			return true
	return check(false,"no silver cap after treasure expeditions")

func run() -> void:
	save_io=load("res://core/save_game.gd");save_io.use_test_slot()
	var args:=OS.get_cmdline_user_args()
	var seed: Dictionary
	if args.is_empty():
		root.get_node("Data").load_core_tables()
		party=load("res://core/party.gd")
		seed=save_io.empty()
		seed.chapters={"alola":"carried"}
		seed.region="alola";seed.map="alola_home";seed.pos=[8,7]
		seed.flags={"a_started":true,"a_version":"ultra_sun","a_hala":true,"a_olivia":true,"a_nanu":true,"a_sail":true,"a_nihilego":true,"a_flute1":true,"a_credits":true,"a_champion":true,"a_starter":728}
		seed.party=party.compact([party.make(730,75,[57])])
		seed.boxes=[]
	else:
		seed=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not check(seed.flags.get("a_credits",false) and str(seed.flags.a_version).begins_with("ultra"),"requires an earned Ultra champion"):quit(2);return
	save_io.save(seed)
	game=load("res://scenes/boot.tscn").instantiate();root.add_child(game);await frames()
	game.title_screen.continue_button.pressed.emit();await frames();await dismiss()
	side=load("res://core/alola_side.gd");party=load("res://core/party.gd")
	var hyper=load("res://core/alola_hyper_training.gd")
	for course in 4:
		if not await surf(course):finish();return
	game.appearance_rng.seed=617
	if not await visit("surfer"):finish();return
	await dismiss()
	var mons: Array=game.save_data.party
	var slot:=mons.find_custom(func(m):return m.get("held","")=="GOLD_BOTTLE_CAP")
	if not check(slot>=0,"surf Pikachu not in party (start with an available slot)"):finish();return
	var pika: Dictionary=mons[slot]
	check(pika.moves.has(57) and pika.ivs.values().count(31)>=3,"surf gift moves and original IVs")
	game._change_held(slot,"","",null)
	check(game._bag_count(hyper.GOLD)==1 and pika.held=="","cap was not returned to bag")
	var initial: Dictionary=pika.ivs.duplicate()
	var saved_legacy: Dictionary=mons[0].duplicate(true)
	var unchanged: Dictionary=saved_legacy.duplicate(true)
	party.recalc(unchanged,true)
	check(unchanged.stats.keys().all(func(k):return int(unchanged.stats[k])==int(saved_legacy.stats[k])) and int(unchanged.max_hp)==int(saved_legacy.max_hp),"legacy cross-region stats changed")
	check(not hyper.train(game,pika,hyper.GOLD,"") and game._bag_count(hyper.GOLD)==1,"level gate consumed gold")
	if not await train_at_resort(pika,slot):finish();return
	var stats: Array=hyper.missing(pika)
	if not check(stats.size()>=2,"test gift needs at least two non-perfect stats"):finish();return
	var stat: String=stats[0]
	var capped: String=pika.ivs.keys().filter(func(k):return int(pika.ivs[k])==31)[0]
	check(not hyper.train(game,pika,hyper.SILVER,capped),"natural 31 accepted silver cap")
	var before:=int(pika.max_hp if stat=="hp" else pika.stats[stat])
	var silver_start:=int(game._bag_count(hyper.SILVER))
	await train_ui(pika,hyper.SILVER,stat,true)
	check(game._bag_count(hyper.SILVER)==silver_start and pika.hyper_trained.is_empty(),"cancelled training charged a cap")
	await train_ui(pika,hyper.SILVER,stat)
	var after:=int(pika.max_hp if stat=="hp" else pika.stats[stat])
	check(after-before==31-int(initial[stat]) and pika.hyper_trained.size()==1 and game._bag_count(hyper.SILVER)==silver_start-1,"silver stat or charge wrong")
	check(not hyper.train(game,pika,hyper.SILVER,stat) and game._bag_count(hyper.SILVER)==silver_start-1,"duplicate training consumed silver")
	await train_ui(pika,hyper.GOLD)
	check(pika.ivs==initial and hyper.missing(pika).is_empty() and game._bag_count(hyper.GOLD)==0,"gold did not fill all gaps")
	check(not hyper.train(game,pika,hyper.SILVER,stat) and game._bag_count(hyper.SILVER)==silver_start-1,"all-perfect specimen charged")
	var battle=load("res://core/battle.gd").new(617)
	battle.start([game._make_team()[slot]],[party.make(19,70,[33])])
	check(battle.cur_a().stats==pika.stats and battle.cur_a().max_hp==pika.max_hp,"battle ignored trained stats")
	battle._take_action("a","move:0")
	check(int(battle.cur_b().hp)<int(battle.cur_b().max_hp),"trained Pikachu never attacked")
	var stored:Dictionary=save_io.load_game().party[slot]
	check(pika.ivs.keys().all(func(k):return int(stored.ivs[k])==int(pika.ivs[k])) and stored.hyper_trained==pika.hyper_trained and pika.stats.keys().all(func(k):return int(stored.stats[k])==int(pika.stats[k])),"save lost training or original IVs")
	print("SURF RECORDS ",[game._flags().as_surf_best_0,game._flags().as_surf_best_1,game._flags().as_surf_best_2,game._flags().as_surf_best_3]," SILVER ",stat," ",before," -> ",after," GOLD ",pika.hyper_trained)
	finish()
func finish() -> void:
	save_io.clear_test_slot()
	print("ALOLA HYPER TRAINING ", "PASS" if errors.is_empty() else "FAIL", " ",errors)
	quit(0 if errors.is_empty() else 1)
