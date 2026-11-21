extends SceneTree
## Field, occupancy, story scripts and restored progress use the same object-event state.
const Save = preload("res://core/save_game.gd")
const Actors = preload("res://core/frlg_actors.gd")
var game
var failed := false

func _initialize():
	call_deferred("run")

func expect(ok: bool, why: String):
	if not ok:
		failed = true
		push_error("FRLG ACTORS: " + why)

func enter(mid: String, region := "kanto"):
	game._do_warp({"region":region,"map":mid,"at":[3,6]})
	game._close_all_dialogs()

func at_role(role: String) -> Vector2i:
	for n in game.world.npcs:
		if n.get("role","") == role:
			return Vector2i(int(n.at[0]),int(n.at[1]))
	return Vector2i(-1,-1)

func talk(role: String, heading := Vector2i.UP):
	var target := at_role(role)
	expect(target.x>=0,"missing speaker "+role)
	if target.x<0:return
	game.world.warp_to(target-heading)
	game.world.facing="up" if heading==Vector2i.UP else "left"
	game._on_action()
	game._close_all_dialogs()

func run():
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	var w=game.world
	enter("pallettown_professoroakslab")
	expect(at_role("lab_oak").x<0 and at_role("lab_rival")==Vector2i(5,4),"before Oak arrives")
	expect(at_role("lab_dex")==Vector2i(4,1),"Pokédex visible on desk")
	enter("kanto_main")
	expect(at_role("pallet_oak").x<0,"Oak has not been summoned")
	expect(at_role("old_man")==Vector2i(69,191) and w.is_blocked(Vector2i(69,191)),"initial Viridian roadblock")
	expect(at_role("gym_guide").x>=0 and at_role("shoes_aide").x<0,"Pewter before badge")
	w.warp_to(Vector2i(70,192))
	game._move("up")
	game._close_all_dialogs()
	expect(w.player_pos==Vector2i(70,192),"old man stops adjacent path before parcel")
	w.warp_to(Vector2i(84,191))
	game._move("up")
	w.tick_walk(0.5)
	game._close_all_dialogs()
	expect(w.map_data.id=="kanto_main" and w.player_pos==Vector2i(84,192),"Viridian gym locked on actual door")
	w.warp_to(Vector2i(73,262))
	game._move("up")
	for frame in 700:
		game._close_all_dialogs()
		if w.map_data.id=="pallettown_professoroakslab" and game.cur_story.is_empty():break
		await process_frame
	expect(w.map_data.id=="pallettown_professoroakslab" and at_role("lab_oak")==Vector2i(6,3),"right-hand original escort")
	talk("lab_oak")
	expect(game._flags().get("got_starter",false) and not game._flags().get("got_dex",false),"starter before parcel")
	w.warp_to(Vector2i(6,7))
	game._move("down")
	game._close_all_dialogs()
	expect(is_instance_valid(game.active_battle),"rival challenges on exit trigger")
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("b")
		game._close_all_dialogs()
		await process_frame
	expect(at_role("lab_rival").x<0 and not w.is_blocked(Vector2i(5,4)),"rival leaves after a loss")
	enter("viridiancity_mart")
	# Talk from the player's side of the counter, via the real interaction path.
	w.warp_to(Vector2i(4,3))
	w.facing="left"
	game._on_action()
	game._close_all_dialogs()
	expect(game._flags().get("carrying_oak_parcel",false),"parcel by talking over counter")
	enter("pallettown_professoroakslab")
	talk("lab_oak")
	expect(game._flags().get("got_dex",false) and at_role("lab_dex").x<0,"Pokédex picked up and removed")
	enter("kanto_main")
	expect(at_role("old_man")==Vector2i(69,188),"old man moved out of the road")
	expect(at_role("police")==Vector2i(294,52) and at_role("slowbro")==Vector2i(290,71),"Cerulean before ticket")
	game._grant_badge("灰色徽章")
	game._close_all_dialogs()
	expect(at_role("gym_guide").x<0 and at_role("shoes_aide")==Vector2i(94,80),"Pewter state after Brock")
	talk("shoes_aide")
	expect(at_role("shoes_aide").x<0,"aide has delivered shoes")
	enter("route25_sea_cottage")
	expect(at_role("bill").x<0 and at_role("bill_clefairy")==Vector2i(10,6),"Bill initially transformed")
	talk("bill_clefairy")
	expect(at_role("bill_clefairy").x<0 and at_role("bill").x<0,"inside teleporter")
	w.warp_to(Vector2i(4,6))
	w.facing="up"
	game._on_action()
	game._close_all_dialogs()
	expect(at_role("bill")==Vector2i(3,4),"PC restores Bill")
	talk("bill")
	expect(game._flags().get("ss_ticket",false),"Bill hands over the ticket")
	enter("kanto_main")
	expect(at_role("police")==Vector2i(295,52) and at_role("slowbro")==Vector2i(296,69),"Cerulean exits reopened")
	var guard := at_role("silph_guard")
	var rocket := guard + Vector2i(-11,-16)
	var civilian := guard + Vector2i(4,1)
	expect(guard==Vector2i(345,181) and w._npc_at(rocket).get("gfx","")=="team_rocket_m" and w._npc_at(civilian).is_empty(),"Saffron occupation")
	enter("pokemontower_7f")
	for i in range(1,4):
		var grunt := "tower_grunt_%d" % i
		talk(grunt)
		expect(is_instance_valid(game.active_battle),"tower grunt battle")
		if is_instance_valid(game.active_battle):
			game.active_battle.finished.emit("a")
			game._close_all_dialogs()
			await process_frame
		expect(at_role(grunt).x<0,"defeated grunt leaves tower")
	talk("tower_fuji")
	expect(w.map_data.id=="lavender_town_volunteer_pokemon_house" and at_role("home_fuji")==Vector2i(3,3),"Fuji returns home")
	talk("home_fuji")
	expect(game._flags().get("poke_flute",false),"received Poké Flute")
	enter("kanto_main")
	expect(w._npc_at(guard).is_empty() and at_role("silph_guard")==guard+Vector2i.RIGHT,"Fuji opened Silph approach")
	var sleeper := at_role("snorlax_12")
	expect(sleeper.x>=0 and w.is_blocked(sleeper),"Snorlax occupies Route 12")
	w.warp_to(sleeper + Vector2i.DOWN)
	w.facing="up"
	game._on_action()
	if not game._dialogs.is_empty():
		game._dialogs.back().btn_yes.pressed.emit()
	expect(is_instance_valid(game.active_battle),"Poké Flute starts a catchable battle")
	if is_instance_valid(game.active_battle):
		expect(game.active_battle.battle.cur_b().species_id==143 and game.active_battle.battle.cur_b().level==30,"wild Snorlax level 30")
		game.active_battle.finished.emit("fled")
		await process_frame
	expect(at_role("snorlax_12").x<0 and at_role("snorlax_16").x>=0,"each sleeping Snorlax clears independently")
	enter("silph_co_11f")
	talk("silph_giovanni")
	expect(is_instance_valid(game.active_battle),"Silph boss challenge")
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("a")
		game._close_all_dialogs()
		await process_frame
	expect(at_role("silph_giovanni").x<0,"Giovanni and grunts leave Silph")
	enter("kanto_main")
	expect(w._npc_at(rocket).is_empty() and not w._npc_at(civilian).is_empty(),"civilians replaced Team Rocket")
	game._persist()
	game._restore_from_save()
	expect(at_role("shoes_aide").x<0 and at_role("police")==Vector2i(295,52),"save and restore exact phase")
	enter("five_island_resort_gorgeous","sevii")
	expect(w._npc_at(Vector2i(39,9)).is_empty(),"hidden Selphy does not obstruct her front door")
	enter("mt_ember_exterior","sevii")
	talk("ember_grunt_2")
	expect(not is_instance_valid(game.active_battle), "no ruby battle before Celio asks")
	enter("one_island_pokemon_center_1f","sevii")
	talk("celio")
	expect(game._flags().get("ember_ruby_requested", false),"Celio requests ruby")
	enter("mt_ember_exterior","sevii")
	for role in ["ember_grunt_2","ember_grunt_1"]:
		talk(role)
		expect(is_instance_valid(game.active_battle), "original Ember guard battle " + role)
		if is_instance_valid(game.active_battle):
			game.active_battle.finished.emit("a")
			game._close_all_dialogs()
			await process_frame
	expect(at_role("ember_grunt_2").x<0 and at_role("ember_grunt_1").x<0,"both Ember grunts leave after second win")
	enter("mt_ember_ruby_path_b5f","sevii")
	talk("ember_ruby")
	expect(at_role("ember_ruby").x<0 and game._flags().get("got_ember_ruby",false),"collect ruby once")
	enter("one_island_pokemon_center_1f","sevii")
	talk("celio")
	expect(game._flags().get("delivered_ember_ruby",false),"deliver the ruby")
	enter("six_island_ruin_valley","sevii")
	expect(at_role("ruin_scientist")==Vector2i(24,25),"scientist blocks door before Icefall")
	enter("four_island_icefall_cave_back","sevii")
	talk("icefall_lorelei")
	expect(is_instance_valid(game.active_battle),"rescue Lorelei")
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("a")
		game._close_all_dialogs()
		await process_frame
	enter("six_island_ruin_valley","sevii")
	expect(at_role("ruin_scientist").x<0,"scientist leaves after Icefall rescue")
	w.warp_to(Vector2i(24,25))
	w.facing="up"
	game.save_data.party[0].moves=[15]
	game._on_action()
	var pick = game.menu_layer.get_child(-1)
	for button in pick.find_children("*","Button",true,false):
		if button.text == "使用居合斩": button.pressed.emit()
	expect(game._flags().get("ruin_valley_cut_door",false),"Cut opens Dotted Hole")
	var legacy := {"badges":["灰色徽章","绿色徽章"],"flags":{"got_starter":true,"got_dex":true,"beat_rival":true}}
	Actors.migrate_progress(legacy)
	expect(legacy.flags.beat_brock and legacy.flags.beat_giovanni and not Actors.hidden("FLAG_HIDE_OAK_IN_HIS_LAB",legacy.flags),"4.50 progress migration")
	enter("kanto_main")
	for badge in ["蓝色徽章","橙色徽章","彩虹徽章","粉红徽章","金色徽章","深红徽章"]:
		game._grant_badge(badge)
		game._close_all_dialogs()
	w.warp_to(Vector2i(84,191))
	game._move("up")
	w.tick_walk(0.5)
	expect(w.map_data.id=="viridiancity_gym" and at_role("gym_giovanni").x>=0,"gym door opens and leader returns")
	Save.clear_test_slot()
	print("FRLG STORY ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
