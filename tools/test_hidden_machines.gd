extends SceneTree

const Save = preload("res://core/save_game.gd")
const Rules = preload("res://core/kanto_campaign.gd")
const DIRS = {"u":Vector2i.UP,"d":Vector2i.DOWN,"l":Vector2i.LEFT,"r":Vector2i.RIGHT}
var game
var failed := false

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failed=true
		push_error("HIDDEN MACHINES: "+label)

func close() -> void:
	game._close_all_dialogs()
	while game.panel_open>0: game._on_back()

func click_tile(x: int, y: int) -> void:
	game.world.warp_to(Vector2i(x,y+1))
	game.world.facing="up"
	game._on_action()
	close()

func visit(region: String, map: String, at: Vector2i) -> void:
	game._do_warp({"region":region,"map":map,"at":[at.x,at.y]})
	close()

func press_walk(sequence: String) -> void:
	var names := {"u":"up","d":"down","l":"left","r":"right"}
	for leg: String in sequence.split(" "):
		for i in int(leg.substr(1)):
			var forced: Vector2i=game.world.auto_step_dir()
			if forced != Vector2i.ZERO and forced != DIRS[leg[0]]:
				check(false,"cannot turn on ice at %s %s" % [game.world.map_data.id,game.world.player_pos])
				return
			game._move(names[leg[0]])
			game.world.tick_walk(0.5)
			close()

func run():
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	close()
	for key in root.get_node("Data").hms:
		check(game._bag_count(root.get_node("Data").hms[key].name)==0,"fresh bag contains "+str(key))
	check(not game._has_rod(),"new character has no rod")
	game._open_hm()
	check(not game._dialogs.is_empty() and game._dialogs.back().lines[0].begins_with("还没有获得"),"unearned machines hidden from teaching menu")
	close()
	game._persist()
	game._restore_from_save()
	check(game._bag_count("秘传学习器 03")==0 and not game._has_rod(),"reload does not grant field kit")

	var save: Dictionary=game.save_data
	save.party=[load("res://core/party.gd").make(149,55,[15,19,57,70]),
		load("res://core/party.gd").make(9,55,[148,249,127,291])]
	for move: String in Rules.FIELD_BADGES:
		check(not game._party_can_move(move),"badge missing for "+move)
		save.badges=[Rules.FIELD_BADGES[move]]
		save.regional_badges.kanto=[Rules.FIELD_BADGES[move]]
		check(game._party_can_move(move),"badge unlocks "+move)
		save.badges=[]
		save.regional_badges.kanto=[]
	visit("kanto","route16_house",Vector2i(4,3))
	click_tile(4,2)
	click_tile(4,2)
	check(game._bag_count("秘传学习器 02")==1,"Route 16 Fly given only once")
	visit("kanto","route2_east_building",Vector2i(4,7))
	game._flags().got_dex=true
	save.dex={"caught":[1,2,3,4,5,6,7,8,9,9,152]}
	click_tile(4,6)
	check(game._bag_count("秘传学习器 05")==0,"need ten distinct Kanto entries")
	save.dex.caught.append(10)
	click_tile(4,6)
	check(game._bag_count("秘传学习器 05")==1,"Oak's aide gives Flash")
	visit("sevii","one_island_kindle_road_ember_spa",Vector2i(10,6))
	click_tile(10,5)
	check(game._bag_count("秘传学习器 06")==1,"Ember Spa Rock Smash")
	save.party=[]
	var entrance := "four_island_icefall_cave_entrance"
	var puzzle := "four_island_icefall_cave_1f"
	visit("sevii",puzzle,Vector2i(3,17))
	var routes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("kanto_traversals.json")))
	press_walk(routes.icefall_cave[0])
	check(game.world.map_data.id==puzzle and game.world.player_pos==Vector2i(12,16) and game._bag_count("秘传学习器 07")==1,"fall through thin ice, slide into the stair and pick up Waterfall")
	press_walk(routes.icefall_cave[1])
	check(game.world.map_data.id==entrance and game.world.player_pos==Vector2i(10,22),"leave after taking Waterfall")
	game.world.warp_to(Vector2i(17,21))
	game.world.surfing=true
	game._move("up")
	check(game.world.player_pos==Vector2i(17,21),"cannot walk up flowing water")
	game._on_action()
	close()
	check(game.world.player_pos==Vector2i(17,21),"cannot climb without move and badge")
	save.party=[load("res://core/party.gd").make(9,55,[127])]
	save.badges=[Rules.FIELD_BADGES.WATERFALL]
	save.regional_badges.kanto=[Rules.FIELD_BADGES.WATERFALL]
	game._on_action()
	close()
	check(game.world.player_pos==Vector2i(17,13),"Waterfall reaches top of all seven water tiles")
	visit("hoenn","hoenn_mossdeep",Vector2i(15,14))
	click_tile(15,13)
	check(game._bag_count("秘传学习器 08")==0,"a visitor cannot pick up Dive before the Space Center events")
	game._flags().hm_kit=true
	game.save_data.species_override={"25":{"atk":89}}
	game._give_item("秘传学习器 03",1,"tm")
	game._give_item("钓竿",1,"key")
	game._persist()
	game._restore_from_save()
	check(game._bag_count("秘传学习器 03")==1 and game._bag_count("秘传学习器 01")==0 and game._has_rod(),"legacy items preserved without filling missing machines")
	check(game.save_data.species_override["25"].atk==89,"species editor setting survives migration")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("HIDDEN MACHINES ", "FAIL" if failed else "PASS")
	quit(int(failed))
