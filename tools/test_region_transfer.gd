extends SceneTree
## Exercise the reusable travel item through START and its pocket on a disposable save.
const Save := preload("res://core/save_game.gd")
const ITEM := "地区转移器"

var game
var catalog: Dictionary
var failed := false
var destinations_tested := 0
var departures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	if not ok:
		failed = true
		push_error("REGION TRANSFER: " + message)
	return ok

func frames() -> void:
	await process_frame
	await process_frame

func start_game(fresh: bool) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await frames()
	var button: Button = game.title_screen.new_button if fresh else game.title_screen.continue_button
	button.pressed.emit()
	await frames()
	game._close_all_dialogs()

func press(page: Control, caption: String) -> bool:
	if not is_instance_valid(page):
		return check(false, "missing page for " + caption)
	for button in page.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.text.strip_edges() == caption:
			button.pressed.emit()
			return true
	return check(false, "missing button " + caption)

func item_row(bag: Control) -> Button:
	for row in bag.row_box.get_children():
		for label in row.find_children("*", "Label", true, false):
			if label.text == ITEM: return row
	return null

func single_item(items: Array) -> bool:
	var rows := items.filter(func(item): return item.get("name", "") == ITEM)
	return rows.size() == 1 and rows[0].get("category") == "key" and int(rows[0].get("count", 0)) == 1

func atlas_from_bag() -> Control:
	game._toggle_start_menu()
	if not check(is_instance_valid(game.start_menu), "START opens in " + str(game.world.map_data.id)): return null
	if not press(game.start_menu, "背包"): return null
	var bag = game._bag_ui
	if not press(bag, "重要道具"): return null
	var row := item_row(bag)
	if not check(is_instance_valid(row), "selectable travel item in key pocket"): return null
	row.pressed.emit()
	var atlas = game.menu_layer.get_child(-1)
	if not check(atlas.has_signal("trip_requested") and atlas.travel, "item opens travel mode"): return null
	return atlas

func at_hub(hub: Dictionary) -> bool:
	var tile := Vector2i(int(hub.at[0]), int(hub.at[1]))
	return game.world.map_data.region == hub.region and game.world.map_data.id == hub.map and game.world.player_pos == tile

func trip(region: String, repeat_tap := false) -> bool:
	var destination: Dictionary = catalog[region]
	var first_arrival: bool = not game.save_data.get("chapters",{}).has(region)
	var atlas := atlas_from_bag()
	if atlas == null or not press(atlas, destination.name):
		return false
	var previous := departures
	atlas.trip_requested.connect(func(_id): departures += 1)
	if not press(atlas, "出发前往" + str(destination.name)):
		return false
	if repeat_tap:
		atlas._depart()
	check(departures == previous + 1, "confirm departure exactly once")
	await frames()
	if region=="hoenn" and game.panel_open>0:
		if not press(game.menu_layer.get_child(-1),"直接抵达"): return false
	if region in ["sinnoh","unova","kalos"] and not game.save_data.chapters.has(region):
		if not press(game.menu_layer.get_child(-1),"带现有队伍出发"): return false
		if region == "kalos":
			await frames()
			if not press(game.menu_layer.get_child(-1),"《X》"): return false
	await frames()
	game._close_all_dialogs()
	await frames()
	var hub: Dictionary = destination.hub
	if first_arrival and not at_hub(hub) and region in ["hoenn","johto","sinnoh","unova","kalos"]:
		check(game.save_data.chapters.has(region),"first arrival opened local story")
		if region=="kalos":
			if not check(game._flags().get("k_version")=="x" and preload("regional_start.gd").dress_in_vaniville(game),"Kalos adventure starts at the bedroom mirror in X"):return false
		return await trip(region)
	var saved := Save.existing()
	check(at_hub(hub), "arrival in " + region)
	check(saved.region == hub.region and saved.map == hub.map and saved.pos == hub.at, "saved landing in " + region)
	check(game.panel_open == 0 and game.touch_layer.visible, "field controls restored in " + region)
	check(single_item(saved.get("bag", [])), "permanent item in " + region)
	return not failed

func cancel_from_home() -> void:
	var pos: Vector2i = game.world.player_pos
	var atlas := atlas_from_bag()
	if atlas == null or not press(atlas, catalog.ultra.name): return
	game._on_back()
	game._on_back()
	await frames()
	var bag = game._bag_ui
	if not check(is_instance_valid(bag) and bag.is_visible_in_tree() and bag.cur_cat == "key", "cancel restores the key pocket"): return
	check(is_instance_valid(item_row(bag)) and single_item(game.bag_items), "cancel kept the device and quantity")
	check(game.world.player_pos == pos and game.world.map_data.id == "pallet_town_players_house_2f", "cancel kept location")
	game._on_back()
	await frames()
	game._on_back()
	await frames()

func run() -> void:
	Save.use_test_slot()
	await start_game(true)
	catalog = root.get_node("Data").travel_regions()
	check(single_item(game.bag_items), "new game grants one device")
	await cancel_from_home()
	if failed or not await trip("distortion", true):
		finish()
		return
	# A v4.51 save has no row for this item. Keep its own inventory and progress.
	var old := Save.empty()
	old.map = "mt_moon_b1f"
	old.pos = [45,4]
	old.bag = [{"name":"伤药","category":"heal","count":7}]
	old.money = 9191
	old.flags = {"hm_kit":true, "got_dex":true}
	old.dex_seen = [25]
	if not check(Save.save(old), "write legacy cave fixture"):
		finish()
		return
	await start_game(false)
	check(game.world.map_data.id == old.map and single_item(game.bag_items), "legacy cave save receives a device")
	game._persist()
	await start_game(false)
	check(single_item(game.bag_items), "loading a migrated inventory a second time still gives one device")
	for region in catalog:
		if not await trip(region): break
		destinations_tested += 1
	check(destinations_tested == 21, "visit all region hubs including all four special layers")
	# Enter the published pool water, then operate the same pocket while riding.
	game._do_warp({"region":"kanto","map":"ceruleancity_gym","at":[9,15],"facing":"left"})
	game._close_all_dialogs()
	game.world.toggle_surf()
	game.world.finish_walk()
	check(game.world.surfing and game.world.player_pos == Vector2i(8,15), "water test starts afloat")
	if not failed and await trip("ultra"):
		check(not game.world.surfing and not game.world.diving, "land arrival dismounts")
		await start_game(false)
		check(at_hub(catalog.ultra.hub) and single_item(game.bag_items), "cold continue keeps hub and a single device")
		check(game.bag_items.any(func(item): return item.name == "伤药" and int(item.count) == 7), "legacy supplies survive")
		check(int(game.save_data.money) == 9191 and game._flags().get("got_dex",false) and 25 in game.save_data.dex.seen, "money, story and Dex survive")
	finish()

func finish() -> void:
	Save.clear_test_slot()
	print("REGION TRANSFER ", "FAIL" if failed else "PASS", " destinations=",destinations_tested)
	quit(1 if failed else 0)
