extends SceneTree
## Continue the first-badge save. Isolate story routing with field warps, a trained test party and capture supplies.
## Win every required battle with the combat engine and earn the National Dex from real capture records.
const Save := preload("res://core/save_game.gd")
const Campaign := preload("res://core/sevii_campaign.gd")
var game
var world
var db
var failed := false
var battles := 0
var accept_trip := false
var observed_reunion := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, reason: String) -> bool:
	if not ok and not failed:
		failed = true
		push_error("SEVII: " + reason)
		quit(1)
	return ok

func role(name: String) -> Dictionary:
	for n in world.npcs:
		if n.get("role","") == name: return n
	return {}

func item(name: String) -> int:
	for it in game.bag_items:
		if it.name == name: return int(it.count)
	return 0

func fight(capture: bool = false) -> void:
	var ui = game.active_battle
	for frame in 4000:
		if game.active_battle != ui: break
		if ui.state == "menu":
			if capture:
				ui._on_command_kind("bag")
				ui._throw("大师球")
			else:
				var mon: Dictionary = ui.battle.cur_a()
				var slot := 0
				var highest := -1.0
				for i in mon.moves.size():
					var move: Dictionary = db.move_of(mon.moves[i])
					var score := float(move.power) * float(ui.battle.effectiveness_on(move.type,ui.battle.cur_b()))
					if int(mon.pp[i])>0 and score>highest:
						slot=i
						highest=score
				ui._on_command_kind("fight")
				ui._on_move(slot)
		ui._process(5.0)
	if check(ui.battle.over and ui.battle.winner == ("caught" if capture else "a"),"battle result " + str(ui.trainer_name)):
		battles += 1

func settle() -> void:
	for i in 200:
		if failed: return
		if not game._dialogs.is_empty():
			var d = game._dialogs.back()
			if game._flags().get("kanto_champion",false) and world.map_data.id == "pallettown_professoroakslab" and role("lab_rival").get("role")=="lab_rival":
				observed_reunion=true
			if d.ask_mode: d._pick(accept_trip)
			else: d._close()
		elif is_instance_valid(game.active_battle):
			fight()
		else:
			return
	check(false,"unfinished dialog")

func visit(mid: String, region := "sevii") -> void:
	game._do_warp({"region":region,"map":mid,"at":[3,6]})
	settle()
	check(world.map_data.id==mid,"arriving at "+mid+" from "+str(world.map_data.id))

func speak(n: Dictionary) -> void:
	if not check(not n.is_empty(),"speaker missing in " + str(world.map_data.id)): return
	var at := Vector2i(int(n.at[0]),int(n.at[1]))
	for direction: Vector2i in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
		var from := at-direction
		if not world.can_enter(from,direction,true): continue
		world.warp_to(from)
		world.facing = {Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[direction]
		game._on_action()
		settle()
		return
	check(false,"surrounded speaker "+str(n.name))

func talk(name: String) -> void:
	speak(role(name))

func stage(name: String) -> void:
	check(game._flags().get(name,false),"missing milestone "+name)
	print("SEVII ",name)

func run() -> void:
	var file := OS.get_environment("POKESAGA_SEVII_ENTRY_SAVE")
	if not check(file.is_absolute_path() and FileAccess.file_exists(file),"provide a first-badge save via test_sevii_campaign.py"):return
	Save.use_test_slot()
	if not check(DirAccess.copy_absolute(file,ProjectSettings.globalize_path(Save.slot))==OK,"copy source save"):return
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	world=game.world
	db=root.get_node("Data")
	game.rng.seed=31415
	game.appearance_rng.seed=92
	var party = load("res://core/party.gd")
	game.save_data.party=[party.make(150,100,[94,58,85,15]),party.make(149,100,[89,53,58,85])]
	visit("one_island_pokemon_center_1f")
	talk("celio")
	check(not game._flags().get("ember_ruby_requested",false),"free transfer started the postgame")
	visit("four_island_icefall_cave_back")
	check(role("icefall_lorelei").is_empty(),"early Lorelei")
	visit("three_island_berry_forest")
	check(role("lostelle_forest").is_empty(),"early forest rescue")
	var gyms := ["ceruleancity_gym","vermilioncity_gym","celadoncity_gym","fuchsiacity_gym","saffroncity_gym","cinnabarisland_gym","viridiancity_gym"]
	for gym in gyms:
		game._heal_party()
		visit(gym,"kanto")
		for n in world.npcs:
			if n.has("badge"):
				game._start_battle(n)
				settle()
				check(n.badge in game.save_data.badges,"real badge "+str(n.badge))
				break
	game._do_warp({"region":"kanto","map":"kanto_main","at":[80,385]})
	check(not role("sevii_bill_outside").is_empty(),"Bill appears outside the gym")
	settle()
	stage("sevii_bill_waits")
	check(role("sevii_bill_outside").is_empty() and not game._flags().get("sevii_visit_started",false),"declining frees the sidewalk")
	visit("cinnabarisland_pokemoncenter_1f","kanto")
	talk("sevii_bill_port")
	check(not game._flags().get("sevii_visit_started",false),"can decline again at center")
	accept_trip=true
	talk("sevii_bill_port")
	check(world.map_data.id=="one_island_pokemon_center_1f","join Bill on the ferry")
	talk("celio")
	stage("sevii_meteorite_errand")
	check(item("陨石")==1 and item("三岛通行证")==1,"first delivery inventory")
	visit("two_island_joyful_game_corner")
	stage("sevii_lostelle_missing")
	visit("three_island")
	talk("sevii_defender")
	stage("sevii_bikers_left")
	check(role("sevii_biker").is_empty(),"bikers remain")
	visit("three_island_berry_forest")
	talk("lostelle_forest")
	stage("sevii_lostelle_rescued")
	check(world.map_data.id=="two_island_joyful_game_corner" and not role("lostelle_reunited").is_empty(),"return the girl to her father")
	talk("lostelle_father")
	check(item("陨石")==0 and item("月之石")==1,"exchange the meteorite")
	visit("one_island_pokemon_center_1f")
	talk("sevii_bill_lab")
	stage("sevii_detour_finished")
	check(world.map_data.id=="cinnabarisland_pokemoncenter_1f","return from first visit")
	game._persist()
	game._restore_from_save()
	visit("one_island_pokemon_center_1f")
	talk("celio")
	check(not game._flags().get("ember_ruby_requested",false),"postgame before championship")
	for opponent in preload("res://core/kanto_campaign.gd").data().league:
		game._heal_party()
		visit(opponent.room,"kanto")
		var name: String = str(opponent.flag).trim_prefix("kanto_").trim_suffix("_win")
		talk("league_"+name)
		stage(opponent.flag)
	visit("pokemon_league_hall_of_fame","kanto")
	stage("kanto_champion")
	visit("pallettown_professoroakslab","kanto")
	talk("lab_oak")
	check(not game._flags().get("national_dex",false),"premature National Dex")
	game._give_item("大师球",60,"ball")
	for sid in range(1,61):
		if game.save_data.dex.caught.any(func(s): return int(s)==sid):continue
		game._start_wild_battle(sid,5)
		fight(true)
	game._do_warp({"region":"kanto","map":"kanto_main","at":[66,268]})
	settle()
	stage("national_dex")
	check(world.map_data.id=="pallettown_professoroakslab" and observed_reunion and role("lab_rival").is_empty(),"Oak escorts the player and the rival leaves after the two upgrades")
	visit("one_island_pokemon_center_1f")
	talk("celio")
	stage("ember_ruby_requested")
	visit("mt_ember_exterior")
	talk("ember_grunt_1")
	stage("sevii_password_one")
	talk("ember_grunt_2")
	check(not world.quest_door_open,"Ruby door opened after only one guard")
	talk("ember_grunt_1")
	check(world.quest_door_open and role("ember_grunt_1").is_empty(),"Ember guards leave")
	visit("mt_ember_ruby_path_b5f")
	talk("ember_ruby")
	visit("one_island_pokemon_center_1f")
	talk("celio")
	stage("delivered_ember_ruby")
	check(item("红宝石")==0 and item("三岛通行证")==0 and item("彩虹通行证")==1,"upgrade the actual pass")
	visit("four_island_icefall_cave_back")
	talk("icefall_lorelei")
	stage("rescued_icefall")
	visit("six_island_ruin_valley")
	check(role("ruin_scientist").is_empty(),"scientist still blocks Cut door")
	world.warp_to(Vector2i(24,25))
	world.facing="up"
	game._on_action()
	for b in game.menu_layer.get_child(-1).find_children("*","Button",true,false):
		if b.text=="使用居合斩": b.pressed.emit()
	stage("ruin_valley_cut_door")
	visit("five_island_meadow")
	game._do_warp({"region":"sevii","map":"five_island_rocket_warehouse","at":[24,25]})
	settle()
	check(world.map_data.id=="five_island_meadow","one password admitted player")
	visit("six_island_dotted_hole_b4f")
	visit("six_island_dotted_hole_sapphire_room")
	talk("sapphire")
	stage("sevii_password_two")
	check(role("sapphire").is_empty() and item("蓝宝石")==0,"stolen Sapphire must leave the pedestal")
	visit("five_island_rocket_warehouse")
	for guard in ["warehouse_grunt1","warehouse_grunt2","warehouse_grunt3","warehouse_admin1","warehouse_admin2"]:
		game._heal_party()
		talk(guard)
		stage("sevii_"+guard)
	check(role("warehouse_admin1").is_empty(),"warehouse failed to evacuate")
	talk("gideon")
	check(item("蓝宝石")==1,"Gideon returns sapphire")
	visit("one_island_pokemon_center_1f")
	talk("celio")
	stage("sevii_network_online")
	game._persist()
	game._restore_from_save()
	talk("celio")
	check(item("蓝宝石")==0 and item("彩虹通行证")==1 and game._flags().get("sevii_network_online",false),"persist final machine without duplicating rewards")
	visit("one_island_pokemon_center_2f")
	talk("sevii_gift_clerk")
	talk("sevii_gift_clerk")
	check(item("神秘船票")==1 and item("极光船票")==1 and Campaign.destinations(game.bag_items).size()==9,"two special tickets available once after network repair")
	game._do_warp({"region":"sevii","map":"five_island_lost_cave_room10","at":[5,8]})
	settle()
	stage("sevii_selphy_home")
	check(world.map_data.id=="five_island_resort_gorgeous" and role("selphy_returning").is_empty(),"Selphy returned to the house")
	visit("five_island_resort_gorgeous_house")
	check(not role("selphy_home").is_empty() and not role("selphy_butler").is_empty(),"Selphy and her butler live at the resort")
	talk("selphy_home")
	var request: Dictionary = game.save_data.selphy_request.duplicate()
	check(int(request.species) in game.save_data.dex.seen,"requests use the player's sightings")
	game._persist()
	game._restore_from_save()
	check(game.save_data.selphy_request.species==request.species,"saved specific request")
	var display := {"dex":{"seen":[25]},"party":[{"species_id":25}]}
	check(Campaign.show_partner(display,game.rng).get("species")==25,"first request")
	check(Campaign.show_partner(display,game.rng).has("reward") and display.get("selphy_thanked",false),"show owned partner for a reward")
	Campaign.show_partner(display,game.rng)
	for i in 250: Campaign.request_step(display)
	check(display.selphy_request.expired and not Campaign.show_partner(display,game.rng).has("reward"),"250 steps expire the request")
	var legacy := {"flags":{"story_ember_warehouse_password":true,"delivered_ember_ruby":true},"badges":[]}
	Campaign.sync(legacy)
	var legacy_bag := [{"name":"三岛通行证","count":1}]
	Campaign.reconcile_pass(legacy.flags,legacy_bag)
	Campaign.reconcile_pass(legacy.flags,legacy_bag)
	check(legacy.flags.sevii_password_one and legacy_bag.size()==1 and legacy_bag[0].name=="彩虹通行证","4.52 heard-password and exchanged-pass migration is idempotent")
	var mystic_only := [{"name":"彩虹通行证","count":1},{"name":"神秘船票","count":1}]
	check("navel_rock_harbor" in Campaign.destinations(mystic_only) and "birth_island_harbor" not in Campaign.destinations(mystic_only),"special tickets checked separately")
	Save.clear_test_slot()
	print("SEVII CAMPAIGN ","FAIL" if failed else "PASS"," battles=",battles)
	quit(1 if failed else 0)
