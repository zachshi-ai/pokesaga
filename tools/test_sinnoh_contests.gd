extends SceneTree
const Save := preload("res://core/save_game.gd")
var Rules
var failures: Array=[]
var g
var shots := ""
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	if not ok: failures.append(title);push_error(title)
func snap(label: String) -> void:
	if shots.is_empty():return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots+"/"+label+".png")

func click(label: String, prefix:=false) -> bool:
	for node in g.menu_layer.get_children():
		if node.is_queued_for_deletion() or not node.visible: continue
		for b in node.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and (b.text.begins_with(label) if prefix else b.text==label):
				b.pressed.emit()
				return true
	check(false,"missing touch button "+label)
	return false

func speak(mid: String, script: String) -> void:
	g.world.load_map(root.get_node("Data").load_map("sinnoh",mid))
	g.world.refresh_story_actors(g._flags())
	for npc in g.world.npcs:
		if npc.get("source_script","")==script:
			g._talk_to_npc(npc)
			return
	check(false,"missing native receptionist "+script)

func run() -> void:
	Rules=load("res://core/sinnoh_contests.gd")
	Save.use_test_slot()
	shots=OS.get_environment("POKESAGA_CONTEST_SCREENSHOTS")
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"sinnoh")
	g._close_all_dialogs()
	g._flags().s_contest=true
	g._flags().s_jubilife_grunts=true
	g.rng.seed=407
	var mon: Dictionary=load("res://core/party.gd").make(25,25,[84,45,98,86])
	g.save_data.party=[mon]
	mon.nature="坦率"
	check(Rules.data().moves.size()==467 and Rules.data().opponents.size()==96 and Rules.data().themes.size()==12,"Platinum data")
	speak("sinnoh_hearthome_city_pokemon_fan_club","HearthomeCityPokemonFanClub_Gentleman")
	check(g._bag_count("宝芬盒")==1,"case from chair")
	g._close_all_dialogs()
	speak("sinnoh_contest_hall_lobby","ContestHallLobby_RichBoy")
	g._close_all_dialogs()
	check(g.save_data.get("sinnoh_poffins",[]).size()==1,"gift poffin")
	g._use_bag_item("宝芬盒")
	click("辣",true);click(mon.name,true)
	g._close_all_dialogs()
	check(mon.get("sheen",0)==40 and mon.get("contest_condition",[])[0]==60,"feed via case and party panel")
	g._give_bag_item("樱子果","berry","","cheri")
	speak("sinnoh_poffin_house","PoffinCommon_PokefanF");click("樱子果",true)
	var pan=g.menu_layer.get_child(-1)
	if not pan.has_method("stir"):check(false,"enter pan");quit(1);return
	for i in 190:
		if not pan.active:break
		click("顺时针",true) if pan.direction==1 else click("↺",true)
		pan._process(0.25)
	check(g.save_data.sinnoh_poffins.size()==1 and g.save_data.sinnoh_poffins[0].flavors[0]>0,"make, store and keep one poffin")
	g._close_all_dialogs()
	await process_frame
	mon.contest_condition=[255,255,255,255,255]
	mon.sheen=255
	speak("sinnoh_contest_hall_lobby","Contests_ReceptionistOfficialContest")
	click("帅气");click(mon.name);click("普通")
	var stage=g.menu_layer.get_child(-1)
	if not stage.has_method("tap"):check(false,"enter contest");quit(1);return
	await snap("dress")
	for id in stage.stock:
		if stage.dress.size()>=5:break
		click(Rules.data().accessories[int(id)])
		var touch:=InputEventScreenTouch.new()
		touch.pressed=true;touch.position=Vector2(40+stage.dress.size()*17,70)
		stage.portrait.gui_input.emit(touch)
	check(stage.dress.size()>=2,"attach different accessories")
	click("完成装扮")
	await snap("dance")
	check(stage.mode=="dance" and stage.scores[0][0]>0,"dress round")
	for turn in 8:
		for beat in stage.beats.size():
			stage.timed=0.9+stage.beat_time()*(beat if turn>=6 else beat+stage.beats.size()+1)
			click(stage.ARROWS[int(stage.beats[beat])])
		stage._process(10)
	check(stage.mode=="moves" and stage.scores[0][1]>0,"dance leader/follower cycle")
	await snap("acting")
	for turn in 4:
		var mid: int=stage.legal_moves(0)[0]
		click(root.get_node("Data").move_of(mid).name,true)
		var target: int=stage.voltage.find(stage.voltage.max())
		click(Rules.JUDGES[target],true)
		click("公布结果" if turn==3 else "下回合")
	check(stage.mode=="results" and stage.scores[0][2]>0,"four acting rounds")
	await snap("results")
	check(stage.standings()[0]==0,"won the seeded Normal contest on stage")
	click("回到会场")
	check(int(mon.get("sinnoh_ribbons",{}).get("0",0))==1,"ribbon on entrant")
	var saved:=Save.load_game()
	check(int(saved.party[0].get("sinnoh_ribbons",{}).get("0",0))==1 and saved.sinnoh_poffins.size()==1,"ribbon and poffins survived disk reload")
	g._close_all_dialogs()
	for obj in g.world.map_data.objects:
		if obj.get("source_script","")=="ContestHallLobby_Frame0":g._handle_object(obj);break
	var photo=g.menu_layer.get_child(-1)
	check(photo.get("mode")=="photo","winning portrait on original wall")
	await snap("photo")
	click("回到会场")
	speak("sinnoh_contest_hall_lobby","Contests_ReceptionistOfficialContest");click("帅气");click(mon.name)
	check(click("超级"),"won ribbon unlocks Great rank")
	var initial:int=mon.sinnoh_ribbons["0"]
	click("离场")
	check(int(mon.sinnoh_ribbons["0"])==initial,"abandon gives no ribbon")
	g._close_all_dialogs()
	g._give_bag_item("樱子果","berry","","cheri")
	speak("sinnoh_flower_shop","FlowerShop_Beauty")
	click(Rules.data().accessories[int(Rules.data().shop[0][0])],true)
	check(g._bag_count("樱子果")==0,"exchange berries for original Florist accessory")
	g._close_all_dialogs()
	speak("sinnoh_veilstone_city_southwest_house","VeilstoneCitySouthwestHouse_Beauty")
	click(mon.name,true)
	check(g._flags().get("s_accessory_massage","")==Time.get_date_string_from_system(),"daily massage")
	g._close_all_dialogs()
	g.world.load_map(root.get_node("Data").load_map("sinnoh","sinnoh_amity_square"))
	g.world.warp_to(Vector2i(12,47))
	g.world.tick_walk(1.0);g._move("up");g.world.tick_walk(1.0)
	click(mon.name)
	check(g._flags().has("s_square_walker"),"Amity gate chose allowed partner")
	if g._flags().has("s_square_walker"):
		for i in 200:
			g._move("up" if i%2==0 else "down")
			g.world.tick_walk(1.0)
		check(g._flags().s_square_walker.steps==200,"200 real field steps in Amity Square")
		g.world.facing="up"
		var state: Dictionary=g._flags().s_square_walker
		var original: int=g._bag_count(root.get_node("Data").berry_name(state.berry)) if state.prefers_item else int(Rules.case(g).accessories.get(str(state.accessory),0))
		var key: String=root.get_node("Data").berry_name(state.berry) if state.prefers_item else str(state.accessory)
		var item: bool=state.prefers_item
		g._on_action()
		check(state.steps==0,"talk to actual following Pokemon")
		check((g._bag_count(key) if item else int(Rules.case(g).accessories.get(key,0)))==original+1,"walking partner found weighted souvenir")
		g._close_all_dialogs()
		g._move("down");g.world.tick_walk(1)
		check(not g._flags().has("s_square_walker"),"return partner at square exit")
	g._close_all_dialogs()
	await process_frame
	g.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("SINNOH SUPER CONTEST UI ", "PASS" if failures.is_empty() else "FAIL", " ",failures)
	quit(0 if failures.is_empty() else 1)
