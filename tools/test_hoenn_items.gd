extends SceneTree
## Independent field fixtures. Uses a fresh, uniquely named save. Scenario setup puts the
## player beside native objects; rewards, locks, teaching, and warps use the real game.
const Save := preload("res://core/save_game.gd")
const Items := preload("res://core/hoenn_items.gd")
var game
var failed := false
var checks := 0
func _initialize(): run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failed=true
		push_error("HOENN FIELD "+label)
	else: print("PASS ",label)

func dismiss() -> void:
	game._close_all_dialogs()
	for node in game.menu_layer.get_children():
		if node.is_queued_for_deletion(): continue
		if node.has_meta("choice_back"): node.get_meta("choice_back").call()
		elif node.has_method("handle_back"): node.handle_back()
	game.world.finish_walk()

func visit(mid: String) -> void:
	dismiss()
	var m: Dictionary = root.get_node("Data").load_map("hoenn",mid)
	check(m.has("emerald_original"),"native map "+mid)
	game.world.load_map(m)
	game.world.arrive({"at":m.spawn,"hoenn_native":true})
	game.world.finish_walk()

func choose(label: String) -> void:
	for menu in game.menu_layer.get_children():
		if menu.is_queued_for_deletion(): continue
		for b in menu.find_children("*","Button",true,false):
			if b.text==label:
				b.pressed.emit()
				return
	check(false,"choice "+label)

func face(at: Array) -> void:
	game.world.warp_to(Vector2i(at[0],at[1]+1))
	game.world.finish_walk()
	game.world.facing="up"

func talk(script: String) -> void:
	var candidates: Array = game.world.npcs.filter(func(n):return n.get("source_script","")==script)
	check(candidates.size()==1,"staged actor "+script)
	if candidates.is_empty(): return
	face(candidates[0].at)
	game._on_action()

func pick_object(pos: Array) -> void:
	var at := Vector2i(pos[0],pos[1])
	game.world.warp_to(at)
	game.world.finish_walk()
	game._on_action()
	dismiss()

func native_gifts() -> void:
	for row in [
		["em_rustboro_city_cutters_house","RustboroCity_CuttersHouse_EventScript_Cutter","ITEM_HM_CUT"],
		["hoenn_granite","GraniteCave_1F_EventScript_Hiker","ITEM_HM_FLASH"],
		["em_mauville_city_house1","MauvilleCity_House1_EventScript_RockSmashDude","ITEM_HM_ROCK_SMASH"],
		["hoenn_dewford","DewfordTown_EventScript_OldRodFisherman","ITEM_OLD_ROD"],
		["hoenn_118","Route118_EventScript_GoodRodFisherman","ITEM_GOOD_ROD"],
		["em_mossdeep_city_house3","MossdeepCity_House3_EventScript_SuperRodFisherman","ITEM_SUPER_ROD"],
		["em_route104_pretty_petal_flower_shop","Route104_PrettyPetalFlowerShop_EventScript_WailmerPailGirl","ITEM_WAILMER_PAIL"],
		["em_lilycove_city_contest_lobby","LilycoveCity_ContestLobby_EventScript_ContestReceptionist","ITEM_POKEBLOCK_CASE"],
		["em_route113_glass_workshop","Route113_GlassWorkshop_EventScript_GlassWorker","ITEM_SOOT_SACK"]]:
		visit(row[0])
		talk(row[1])
		check(Items.received(game._flags(),row[2]) and game._bag_count(Items.name_for(row[2]))==1,"earned "+row[2])
		dismiss()

func test_moves() -> void:
	visit("hoenn_rusturf")
	game.save_data.party=[game.PartyScript.make(259,32,[57,249,291,127])]
	for move in Items.MACHINES:
		var row: Array = Items.MACHINES[move]
		game.save_data.badges.append(row[2])
		check(not Items.permission(game._flags(),move).is_empty(),move+" rejects external badge")
	check(game._can_learn_move(258,57) and not game._can_learn_move(255,57),"Emerald machine compatibility")
	face([24,5])
	game._on_action()
	check(not Items.received(game._flags(),"ITEM_HM_STRENGTH"),"Wanda locked before Dynamo Badge")
	dismiss()
	game._flags().h_badge_3=true
	face([24,5])
	game._on_action()
	check(Items.received(game._flags(),"ITEM_HM_STRENGTH"),"real tunnel rewards Strength on rock smash")
	dismiss()
	check(game.world.object_at(Vector2i(24,4)).is_empty() and game.world.object_at(Vector2i(24,5)).is_empty(),"both tunnel rocks clear")
	visit("hoenn_128")
	var at := Vector2i(-1,-1)
	for y in game.world.tile_size.y:
		for x in game.world.tile_size.x:
			var cell := Vector2i(x,y)
			if Items.behavior(game.world.map_data,cell)==0x12 and not game.world.is_blocked(cell):
				at=cell
				break
		if at.x>=0: break
	check(at.x>=0,"Route 128 dark water")
	game.world.warp_to(at)
	game.world.surfing=true
	game._flags().h_badge_7=true
	game._on_action()
	check(game.world.map_data.id=="hoenn_128" and not game._dialogs.is_empty(),"Dive HM must be locally received")
	dismiss()
	Items.grant(game,"ITEM_HM_DIVE")
	game._on_action()
	choose("下潜")
	check(game.world.map_data.id=="em_underwater_route128" and game.world.player_pos==at and game.world.diving,"Dive changes map at original coordinates")
	game._on_back()
	choose("上浮")
	check(game.world.map_data.id=="hoenn_128" and game.world.player_pos==at and game.world.surfing,"B emerges at matching surface square")
	visit("em_underwater_seafloor_cavern")
	game.world.warp_to(Vector2i(6,5))
	game.world.diving=true
	game._on_action()
	choose("上浮")
	check(game.world.map_data.id=="hoenn_seafloor" and game.world.player_pos==Vector2i(10,17),"submarine chamber emerges inside Seafloor Cavern")

func test_optional_tools() -> void:
	visit("hoenn_111")
	var gate: Array = Items.data().sand_gates[0]
	var square := Vector2i(gate[0],gate[1])
	check(not Items.can_enter(game.world,square,Vector2i.UP),"sandstorm denies visiting team")
	Items.grant(game,"ITEM_GO_GOGGLES")
	check(Items.can_enter(game.world,square,Vector2i.UP),"goggles unlock the native desert entrance")
	visit("hoenn_113")
	var ash := Vector2i(-1,-1)
	for y in game.world.tile_size.y:
		for x in game.world.tile_size.x:
			if Items.behavior(game.world.map_data,Vector2i(x,y))==0x24: ash=Vector2i(x,y)
	game.world.warp_to(ash)
	Items.field_step(game)
	Items.field_step(game)
	check(game._flags().get("h_ash",0)==1,"soot sack counts a patch once")
	Items.leave(game,{"id":"hoenn_114"})
	Items.field_step(game)
	check(game._flags().get("h_ash",0)==2,"ash regrows after leaving")
	visit("hoenn_mauville")
	game._flags().h_badge_5=true
	game.world.refresh_story_actors(game._flags())
	talk("MauvilleCity_EventScript_Wattson")
	dismiss()
	check(Items.received(game._flags(),"ITEM_BASEMENT_KEY"),"Wattson's basement key")
	visit("em_new_mauville_entrance")
	game._do_warp({"region":"hoenn","hoenn_native":true,"map":"em_new_mauville_inside","at":[32,33]})
	check(game.world.map_data.id=="em_new_mauville_inside","basement key unlocks the door")
	game.world.warp_to(Vector2i(33,7))
	game.world.finish_walk()
	game._move("up")
	game.world.tick_walk(1.0)
	dismiss()
	check(game._flags().get("h_generator_off",false),"stepping on the generator's red switch cuts power")
	visit("hoenn_mauville")
	talk("MauvilleCity_EventScript_Wattson")
	dismiss()
	check(game._bag_count("招式学习器 24")==1,"return to Wattson for Thunderbolt")
	visit("em_mirage_tower_4f")
	talk("MirageTower_4F_EventScript_RootFossil")
	choose("取下")
	dismiss()
	check(Items.received(game._flags(),"ITEM_ROOT_FOSSIL") and game.world.map_data.id=="hoenn_111","chosen fossil and Mirage Tower collapse")
	visit("em_rustboro_city_devon_corp_2f")
	talk("RustboroCity_DevonCorp_2F_EventScript_FossilScientist")
	choose("根状化石")
	dismiss()
	var stair: Dictionary = game.world.map_data.warps[0].to
	game._do_warp(stair)
	visit("em_rustboro_city_devon_corp_2f")
	talk("RustboroCity_DevonCorp_2F_EventScript_FossilScientist")
	dismiss()
	check(game.save_data.party.any(func(m):return int(m.get("species_id",0))==345 and int(m.level)==20),"revive Lileep at level 20")
	visit("em_lilycove_city_contest_lobby")
	game._give_bag_item("橙橙果","berry","","ORAN")
	var blender: Dictionary = game.world.objects.filter(func(o):return o.source_script=="BerryBlender_EventScript_BerryBlender1")[0]
	face(blender.at)
	game._on_action()
	choose("橙橙果")
	var machine=game.menu_layer.get_child(-1)
	if machine.has_method("make_block"):
		for frame in 1200:
			if machine.done:break
			machine._process(1.0/60)
			if absf(wrapf(machine.angle-PI/2,-PI,PI))<0.17:machine.action.pressed.emit()
		check(machine.done and machine.precise>0,"touch timing speeds up the berry blender")
		machine.action.pressed.emit()
	dismiss()
	check(game._flags().get("h_blocks",[]).size()==1,"blending fruit makes a Pokeblock")
	game._use_bag_item("宝可方块盒")
	choose(game.save_data.party[0].name)
	dismiss()
	check(game._flags().get("h_blocks",[]).is_empty() and game.save_data.party[0].get("sheen",0)>0,"Pokeblock can be fed")
	game._flags().h_champion=true
	Items.grant(game,"ITEM_SS_TICKET")
	visit("em_slateport_city_harbor")
	talk("SlateportCity_Harbor_EventScript_FerryAttendant")
	choose("水静市")
	dismiss()
	check(game.world.map_data.id=="em_ss_tidal_corridor","ticket boards S.S. Tidal")
	talk("SSTidalCorridor_EventScript_ExitSailor")
	check(game.world.map_data.id=="em_lilycove_city_harbor","ship disembarks at its selected port")

func test_bike() -> void:
	visit("em_mauville_city_bike_shop")
	talk("MauvilleCity_BikeShop_EventScript_Rydel")
	choose("音速自行车")
	dismiss()
	check(game._bag_count("音速自行车")==1,"Rydel lends Mach Bike")
	talk("MauvilleCity_BikeShop_EventScript_Rydel")
	choose("越野自行车")
	dismiss()
	check(game._bag_count("音速自行车")==0 and game._bag_count("越野自行车")==1,"switch between bikes without duplication")
	visit("hoenn_mauville")
	game._use_bag_item("越野自行车")
	check(game.world.bike,"bag equips active Hoenn bicycle")

func test_ship_rooms() -> void:
	visit("em_abandoned_ship_hidden_floor_corridors")
	var into_rooms := {"region":"hoenn","hoenn_native":true,"map":"em_abandoned_ship_hidden_floor_rooms","at":[21,14]}
	game._do_warp(into_rooms)
	check(game.world.map_data.id=="em_abandoned_ship_hidden_floor_corridors","Room 2 remains locked")
	dismiss()
	for pair in [["ITEM_ROOM_1_KEY",[42,10]],["ITEM_ROOM_4_KEY",[1,12]],["ITEM_ROOM_6_KEY",[1,2]],["ITEM_ROOM_2_KEY",[20,5]],["ITEM_SCANNER",[16,10]]]:
		visit("em_abandoned_ship_hidden_floor_rooms")
		pick_object(pair[1])
		check(Items.received(game._flags(),pair[0]),"native pickup "+str(pair[0]))
	visit("em_abandoned_ship_hidden_floor_corridors")
	game._do_warp(into_rooms)
	check(game.world.map_data.id=="em_abandoned_ship_hidden_floor_rooms" and game._bag_count("2号房钥匙")==0,"Room 2 opens and consumes its key")
	visit("em_abandoned_ship_hidden_floor_corridors")
	game._do_warp(into_rooms)
	check(game.world.map_data.id=="em_abandoned_ship_hidden_floor_rooms","unlocked room stays open")
	visit("em_abandoned_ship_captains_office")
	pick_object([0,6])
	check(Items.received(game._flags(),"ITEM_STORAGE_KEY"),"native storage key")

func run() -> void:
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"hoenn")
	dismiss()
	# Isolated optional-area tests deliberately stage map positions independently of the story journey.
	game._flags().h_started=false
	game.world.taken=game._flags()
	native_gifts()
	test_moves()
	test_bike()
	test_ship_rooms()
	test_optional_tools()
	Save.clear_test_slot()
	print("HOENN FIELD ", "FAIL" if failed else "PASS"," (",checks," checks)")
	quit(1 if failed else 0)
