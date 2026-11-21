extends SceneTree
## Replay two simultaneous touch IDs through the actual field input, warp and save paths.
const Save := preload("res://core/save_game.gd")
const MART := Vector2i(4,7)
const STREET := Vector2i(84,200)
const STAIRS := Vector2i(10,2)
var game
var failed := false
var warp_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, reason: String) -> void:
	if not ok:
		push_error("FRLG PASSAGE " + reason)
		failed = true

func touch(id: int, key: String, pressed: bool) -> void:
	var button: Button = game._btn_b
	if key != "run":
		for spec in game._dpad:
			if spec.key == key:
				button = spec.btn
				break
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = button.get_global_rect().get_center()
	event.pressed = pressed
	root.push_input(event,true)

func frames(count: int) -> void:
	for i in count:
		game._process(1.0/60.0)

func place(map_id: String, pos: Vector2i) -> void:
	game.world.load_map(root.get_node("Data").load_map("kanto",map_id))
	game.world.warp_to(pos)

func at(map_id: String, pos: Vector2i) -> bool:
	return game.world.map_data.id == map_id and game.world.player_pos == pos and game.world.render_pos == Vector2(pos) and not game.world.walking

func run() -> void:
	Save.use_test_slot()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.story_on = false
	game.title_screen.new_button.pressed.emit()
	await process_frame
	game.set_process(false)
	game.world.warp_ready.connect(func(_target): warp_count += 1)
	place("kanto_main",STREET)

	touch(1,"run",true)
	frames(1)
	touch(2,"up",true)
	check(game.run_held and game.held_dir == "up" and not game.world.pending_warp.is_empty(),"two fingers, B first")
	frames(90)
	check(at("viridiancity_mart",MART) and game.world.facing == "up" and warp_count == 1,"held B + up arrives on the shop mat once")
	touch(2,"up",false)
	check(game.run_held and game.held_dir == "","releasing the D-pad keeps B held")
	touch(1,"run",false)
	touch(2,"down",true)
	touch(1,"run",true)
	check(game.run_held and game.held_dir == "down","two fingers, direction first")
	frames(90)
	check(at("kanto_main",STREET) and game.world.facing == "down" and warp_count == 2,"held B + down exits once and settles one square south")
	touch(1,"run",false)
	check(not game.run_held and game._field_fingers.has(2),"releasing B leaves the D-pad contact independent")
	touch(2,"down",false)
	check(game._field_fingers.is_empty(),"all contacts released")

	place("viridiancity_mart",MART+Vector2i.LEFT)
	touch(0,"right",true)
	touch(0,"right",false)
	frames(5)
	var before: Vector2 = game.world.render_pos
	touch(1,"run",true)
	frames(1)
	check(game.world.render_pos.x > before.x and game.world.render_pos.x < MART.x,"changing speed mid-step keeps continuous progress")
	touch(1,"run",false)
	frames(40)
	check(at("viridiancity_mart",MART) and warp_count == 2,"crossing the mat sideways keeps the player indoors")

	place("pallet_town_players_house_2f",STAIRS)
	game._move("left")
	frames(35)
	check(at("pallettown_playershouse_1f",STAIRS) and game.world.facing == "left","bedroom stairs to the living room")
	game._move("right")
	frames(35)
	check(at("pallet_town_players_house_2f",STAIRS) and game.world.facing == "right","living room stairs back to the bedroom")

	# Transfer at the piers and keep the original southbound S.S. Anne berth open.
	place("kanto_main",Vector2i(286,231))
	game._move("left")
	frames(35)
	check(game.world.map_data.id == "kanto_main" and not game._dialogs.is_empty(),"no pass bars boarding")
	game._close_all_dialogs()
	game._flags().sevii_meteorite_errand=true
	game._give_item("三岛通行证",1,"key")
	place("kanto_main",Vector2i(286,231))
	game._move("left")
	frames(35)
	var harbors := ["one_island","two_island","three_island","four_island","five_island",
		"six_island","seven_island","navel_rock","birth_island"]
	for i in harbors.size():
		check(at(harbors[i]+"_harbor",Vector2i(8,3)),"harbor on foot: " + harbors[i])
		for direction in ["left","down","down","left"]:
			game._move(direction)
			frames(35)
		if i == 2 or i == 6:
			check(game.world.map_data.id == harbors[i]+"_harbor" and not game._dialogs.is_empty(),"next route requires upgraded ticket")
			game._close_all_dialogs()
			if i == 2:
				game.bag_items = game.bag_items.filter(func(row):return row.name!="三岛通行证")
				game._give_item("彩虹通行证",1,"key")
				game._flags().delivered_ember_ruby=true
			else:
				game._flags().sevii_special_tickets=true
				game._give_item("神秘船票",1,"key")
				game._give_item("极光船票",1,"key")
			game._move("left")
			frames(35)
	check(at("one_island_harbor",Vector2i(8,3)),"round trip to first island")
	for direction in ["right","down","down","right"]:
		game._move(direction)
		frames(35)
	check(at("kanto_main",Vector2i(286,231)),"return from Sevii on the original pier")
	game._flags().ss_ticket=true
	place("kanto_main",Vector2i(287,234))
	game._move("down")
	frames(35)
	check(game.world.map_data.id == "s_s_anne_exterior","S.S. Anne remains accessible")

	var legacy := Save.empty()
	legacy.region = "kanto"
	legacy.map = "kanto_main"
	legacy.pos = [STREET.x,STREET.y-1]
	check(Save.save(legacy),"write old door save")
	game._restore_from_save()
	check(at("kanto_main",STREET),"4.50 save standing in the shop door moves to its doorstep")
	legacy.pos = [319,140]
	legacy.location_label = "关都·ROUTE8"
	check(Save.save(legacy),"write old Route 8 save")
	game._restore_from_save()
	check(at("kanto_main",Vector2i(319,140)),"retain a walkable Route 8 save beside the relocated Saffron city")
	legacy.pos = [288,159]
	legacy.location_label = "关都·SAFFRON_CITY"
	check(Save.save(legacy),"write old city save")
	game._restore_from_save()
	check(at("kanto_main",Vector2i(336,189)),"retain the old Saffron Pokémon Center doorstep inside the relocated city")
	Save.clear_test_slot()
	print("FIRERED PASSAGES ", "FAIL" if failed else "PASS", " field_warps=",warp_count)
	quit(1 if failed else 0)
