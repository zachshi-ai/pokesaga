extends SceneTree
const Contest := preload("res://core/emerald_contest.gd")
const Hall := preload("res://core/contest_hall.gd")
const Stage := preload("res://scenes/contest_stage.gd")
const Press := preload("res://scenes/berry_press.gd")
const Powder := preload("res://core/berry_powder.gd")
const Save := preload("res://core/save_game.gd")
var issues: Array=[]
var game

func _initialize() -> void:run.call_deferred()
func check(ok: bool, value: String) -> void:
	if not ok:
		issues.append(value)
		push_error(value)

func click(prefix: String) -> bool:
	for node in game.menu_layer.get_children():
		if node.is_queued_for_deletion() or not node.visible:continue
		for b in node.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and b.text.begins_with(prefix):
				b.pressed.emit()
				return true
	check(false,"Missing choice "+prefix)
	return false

func run() -> void:
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"hoenn")
	await process_frame
	game._close_all_dialogs()
	var mon: Dictionary=load("res://core/party.gd").make(25,35,[85,9,86,33])
	mon.contest_condition=[255,255,255,255,255]
	mon.sheen=255
	game.save_data.party=[mon]
	var db=root.get_node("Data")
	var daily=load("res://core/hoenn_daily.gd")
	game._flags().h_roaming_species=381
	game._flags().h_blender_news=daily.date_number()
	check(not daily.blender_active(game._flags()),"guest waits for news")
	daily.television(game,"EmeraldRoamingTV")
	game._close_all_dialogs()
	check(daily.blender_active(game._flags()),"watching the news announces the visiting master")
	game._flags().erase("h_blender_news")
	var farmer: String="Route123_BerryMastersHouse_EventScript_BerryMaster"
	var wife: String="Route123_BerryMastersHouse_EventScript_BerryMastersWife"
	var before: int=game.bag_items.reduce(func(count,entry):return count+int(entry.count) if entry.get("category","")=="berry" else count,0)
	daily.talk(game,farmer)
	game._close_all_dialogs()
	daily.talk(game,farmer)
	game._close_all_dialogs()
	var after: int=game.bag_items.reduce(func(count,entry):return count+int(entry.count) if entry.get("category","")=="berry" else count,0)
	check(after-before==2,"Berry Master gives two berries once per day")
	daily.talk(game,wife)
	click("精彩")
	click("战斗")
	check(game._flags().get("h_saying_spelon",false) and game._bag_count(db.berry_name("spelon"))==1,"say a special phrase and receive the actual rare berry")
	game._close_all_dialogs()
	var seed_value:=4321
	var probe:=RandomNumberGenerator.new()
	probe.seed=seed_value
	var winning_id:=probe.randi_range(0,65535)
	game.rng.seed=seed_value
	game.save_data.js_trainer_id=47
	game.save_data.boxes=[{"mons":[{"name":"交换伙伴","ot_id":winning_id}]}]
	daily.lottery(game,"2003-07-01")
	var count_once: int=game._bag_count("大师球")
	game._close_all_dialogs()
	daily.lottery(game,"2003-07-01")
	check(count_once==1 and count_once==game._bag_count("大师球"),"Lilycove lottery checks a boxed original trainer ID once daily")
	var services=load("res://core/hoenn_move_services.gd")
	var trainee: Dictionary=load("res://core/party.gd").make(25,30,[33])
	game.save_data.party=[trainee]
	var tutor:="LilycoveCity_DepartmentStoreRooftop_EventScript_SubstituteTutor"
	services.talk(game,tutor)
	click(trainee.name)
	check(trainee.moves.has(164) and game._flags().get("h_tutor_SubstituteTutor",false),"rooftop substitute tutor really teaches once")
	game._close_all_dialogs()
	services.talk(game,"LilycoveCity_MoveDeletersHouse_EventScript_MoveDeleter")
	click(trainee.name)
	click(db.move_of(164).name)
	click("确认遗忘")
	check(not trainee.moves.has(164) and trainee.moves.size()==trainee.pp.size(),"move deleter clears move and PP")
	game._close_all_dialogs()
	game._give_item("心之鳞片",1)
	services.talk(game,"FallarborTown_MoveRelearnersHouse_EventScript_MoveRelearner")
	click(trainee.name)
	click(db.move_of(84).name)
	check(trainee.moves.has(84) and game._bag_count("心之鳞片")==0,"Emerald reminder uses heart scale and original level-up moves")
	game._close_all_dialogs()
	game.save_data.party=[mon]
	game.save_data.contest_paintings={"0":{},"1":{},"2":{},"3":{},"4":{}}
	Hall.talk(game,"LilycoveCity_LilycoveMuseum_2F_EventScript_Curator")
	check(game._flags().get("h_decorations",{}).get("GLASS_ORNAMENT",0)==1,"five paintings give placeable glass ornament")
	game._close_all_dialogs()
	for post in [false,true]:
		for cat in 5:
			for rank in 4:
				var runner:=Contest.new()
				runner.begin(mon,cat,rank,post,db)
				check(runner.entrants.size()==4,"three opponents in %s/%s" % [cat,rank])
				for i in 5:check(runner.turn(mon.moves[i%4]).size()==4,"each contestant appeals")
				check(runner.standings().size()==4 and runner.round_number==5,"ranked after five rounds")
	var lobby: Dictionary=db.load_map("hoenn","em_lilycove_city_contest_lobby")
	game.world.load_map(lobby)
	var npc: Dictionary=game.world.npcs.filter(func(n):return n.get("source_script","").ends_with("_ContestReceptionist"))[0]
	game.world.warp_to(Vector2i(int(npc.at[0]),int(npc.at[1])+2))
	game.world.finish_walk()
	game.world.facing="up"
	game._on_action()
	if game._bag_count("宝可方块盒")==0:print("counter diagnostic ",game.world.player_pos," ",game.world.facing," ",game.panel_open," ",game._dialogs," ",game.world.last_event," ",game.world.is_desk(Vector2i(14,3))," ",game.world._npc_at(Vector2i(14,2)).get("source_script",""))
	check(game._bag_count("宝可方块盒")==1,"case granted at actual counter")
	game._close_all_dialogs()
	game._on_action()
	click("帅气")
	click(mon.name)
	click("普通")
	var stage=game.menu_layer.get_child(-1)
	if stage is Stage:
		for round_idx in 5:
			click(db.move_of(mon.moves[round_idx%4]).name)
			click("查看名次" if round_idx==4 else "下一回合")
		click("领取结果")
		check(game.save_data.has("contest_winners"),"live contest recorded")
		check(mon.get("contest_ribbons",{}).get("0",0)==1,"normal ribbon awarded to entered mon")
	else:check(false,"registered at actual reception")
	game._close_all_dialogs()
	Powder.vendor(game)
	check(game._bag_count("粉末瓶")==1,"powder jar")
	game._close_all_dialogs()
	game._give_bag_item("橙橙果","berry","","ORAN")
	Powder.club(game)
	click("橙橙果")
	click("与工作人员练习")
	var practice=game.menu_layer.get_child(-1)
	if practice is Press:
		while practice.phase=="play":
			practice.remaining-=0.1
			practice.press()
		click("装入粉末瓶")
		check(game.save_data.get("berry_powder",0)>0 and game._bag_count("橙橙果")==0,"practice consumes berry and persists powder")
	game._close_all_dialogs()
	game.save_data.berry_powder=80
	Powder.vendor(game)
	click("元气根")
	check(game.save_data.berry_powder==0 and game._bag_count("元气根")==1,"exchange exact price")
	game._close_all_dialogs()
	var host:=Press.new()
	var client:=Press.new()
	root.add_child(host)
	root.add_child(client)
	host.setup("oran")
	client.setup("cheri")
	host.host_room()
	client.join_menu()
	client.join_room("127.0.0.1")
	for i in 320:
		if host.players.size()==2:break
		await create_timer(.01).timeout
	check(host.players.size()==2 and client.phase=="lobby","two ENet peers joined actual LAN room")
	if host.players.size()==2:
		for b in host.find_children("*","Button",true,false):
			if b.text=="开始压榨":b.pressed.emit()
		for i in 420:
			if client.phase=="play" and host.phase=="play":
				client.press()
				host.press()
			if host.phase=="result" and client.phase=="result":break
			await create_timer(.055).timeout
		check(host.finished_reward>0 and host.finished_reward==client.finished_reward,"networked presses paid both participants equally")
	host.leave(0)
	client.leave(0)
	var shared=load("res://scenes/contest_blender_room.gd")
	var mixer=shared.new()
	var partner=shared.new()
	root.add_child(mixer)
	root.add_child(partner)
	mixer.setup("oran")
	partner.setup("cheri")
	mixer.host_room()
	partner.join_room("127.0.0.1")
	for frame in 300:
		if mixer.players.size()==2:break
		await create_timer(0.01).timeout
	check(mixer.players.size()==2,"two wireless blender peers")
	if mixer.players.size()==2:
		mixer.begin_mix()
		for frame in 1300:
			if partner.phase=="result":break
			if partner.phase=="mixing" and frame%10==0:partner.machine.action.pressed.emit()
			if mixer.phase=="mixing":
				mixer._process(.042)
				if absf(wrapf(mixer.machine.angle-PI/2,-PI,PI))<0.19:mixer.machine.action.pressed.emit()
			await process_frame
		print("WIRELESS BLENDER ",mixer.phase," ",partner.phase," ",mixer.paid," ",partner.paid)
		check(partner.phase=="result" and mixer.phase=="result" and partner.paid.flavor.map(func(v):return int(v))==mixer.paid.flavor and int(partner.paid.people)==2,"both receive the same block from the shared machine")
	mixer.leave(0)
	partner.leave(0)

	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("CONTEST AND BERRY CRUSH ", "PASS" if issues.is_empty() else issues)
	quit(int(not issues.is_empty()))
