extends SceneTree
## Exercise map input, dialogs, battles and save restoration through ordinary game actions.
## Launch with test_first_chapter.py after the first Godot import.

const Save = preload("res://core/save_game.gd")
const DIRS := {Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"}
var game
var world
var directory: String
var failed := false
var walks := 0
var encounters := 0
var balls_used := 0
var heal_requests := 0
var battle_wins := 0
var mode := "travel"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> bool:
	if not condition and not failed:
		failed = true
		push_error("CHAPTER FAIL: " + description)
	return condition

func run() -> void:
	directory = OS.get_environment("POKESAGA_CHAPTER_TEST_DIR")
	if not check(directory.is_absolute_path() and DirAccess.dir_exists_absolute(directory), "run via test_first_chapter.py"):
		quit(1)
		return
	Save.slot = directory.path_join("save.json")
	seed(219)
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	world = game.world
	game.rng.seed = 1947
	game.appearance_rng.seed = 7748
	var phase: String = OS.get_cmdline_user_args()[0]
	if phase == "play":
		await play()
	else:
		var expected = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("expected.json")))
		var restored = JSON.parse_string(JSON.stringify(snapshot()))
		for key in expected:
			check(restored.get(key) == expected[key], "changed after restarting: " + key)
	print("CHAPTER ", phase, " ", "FAIL" if failed else "PASS", " walks=", walks, " encounters=", encounters, " balls=", balls_used, " nurse=", heal_requests, " wins=", battle_wins)
	quit(1 if failed else 0)

func snapshot() -> Dictionary:
	return {"map": world.map_data.id, "region": world.map_data.region, "pos": [world.player_pos.x, world.player_pos.y],
		"badges": game.save_data.badges, "party": game.save_data.party, "dex": game.save_data.dex, "variants": game.save_data.dex_variants, "bag": game.bag_items,
		"got_starter": game._flags().get("got_starter", false), "beat_brock": game._flags().get("beat_brock", false)}

func dialogs() -> void:
	for i in 150:
		if game._dialogs.is_empty(): return
		var d = game._dialogs.back()
		if d.is_waiting_answer():
			if not check(d.speaker == "护士", "unexpected choice: " + d.speaker): return
			heal_requests += 1
			d.btn_yes.pressed.emit()
		else:
			game._on_action()
	check(false, "dialog did not finish")

func find_button(node: Node, prefix: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if child.visible and child.is_visible_in_tree() and not child.disabled and String(child.text).begins_with(prefix):
			return child
	return null

func choose(node: Node, prefix: String) -> bool:
	var button = find_button(node, prefix)
	if not check(button != null, "missing button: " + prefix): return false
	button.pressed.emit()
	return true

func teach_surf() -> void:
	game._open_hm()
	if not choose(game.menu_layer.get_child(-1), "冲浪"): return
	if not choose(game.menu_layer.get_child(-1), "皮卡丘"): return
	if not choose(game.menu_layer.get_child(-1), "摇尾巴"): return
	dialogs()
	check(57 in game.save_data.party[0].moves, "Surf was not taught")

func bag_count(name_text: String) -> int:
	for item in game.bag_items:
		if item.name == name_text: return int(item.count)
	return 0

func battle() -> void:
	var ui = game.active_battle
	if not is_instance_valid(ui): return
	var wild: bool = ui.trainer_name == ""
	if wild: encounters += 1
	var want_capture: bool = wild and mode == "catch" and game.save_data.party.size() > 0 and not game.save_data.get("dex",{}).get("caught",[]).any(func(id): return int(id) != 25)
	print("FIGHT ", ui.trainer_name if not wild else "wild", " ", ui.battle.cur_b().name, " level=", ui.battle.cur_b().level, " capture=", want_capture)
	var turns := 0
	for tick in 2000:
		if ui.is_queued_for_deletion() or game.active_battle == null: break
		if ui.state == "menu":
			turns += 1
			if not check(turns < 80, "battle exceeded turn limit"): return
			if want_capture:
				if not check(bag_count("精灵球") > 0, "ran out of balls"): return
				ui._on_command_kind("bag")
				if not choose(ui.get_node("BallPanel"), "精灵球"): return
				balls_used += 1
			elif wild and mode != "train":
				ui._on_command_kind("flee")
			else:
				var mon: Dictionary = ui.battle.cur_a()
				var idx: int = mon.moves.find(57)
				if idx < 0 or int(mon.pp[idx]) <= 0: idx = mon.moves.find(84)
				if idx < 0 or int(mon.pp[idx]) <= 0: idx = 0
				ui._on_command_kind("fight")
				ui._on_move(idx)
		ui._process(2.0)
		if ui.state == "end" and ui.battle.winner == "b":
			check(false, "lost to %s at Lv%d" % [ui.enemy_team[0].name, game.save_data.party[0].level])
			return
	if ui.battle.winner == "a": battle_wins += 1
	if want_capture: check(ui.battle.winner == "caught", "wild capture did not complete")
	check(game.active_battle == null, "battle UI did not finish")
	await process_frame
	dialogs()

func path_to(goal: Vector2i) -> Array:
	var start: Vector2i = world.player_pos
	var prev := {start: start}
	var q := [start]
	var doors := {}
	for warp in world.map_data.get("warps", []):
		doors[Vector2i(warp.at[0], warp.at[1])] = true
	doors.erase(goal)
	var i := 0
	while i < q.size() and not prev.has(goal):
		var here: Vector2i = q[i]
		i += 1
		for dir in DIRS:
			var next: Vector2i = here + dir
			if prev.has(next) or doors.has(next) or world.ledge_bits(next) != 0: continue
			if world.map_data.id == "kanto_main" and not Rect2i(45, 57, 53, 227).has_point(next): continue
			if not world.can_enter(next, dir): continue
			prev[next] = here
			q.append(next)
	var path := []
	if not prev.has(goal): return path
	var cursor := goal
	while cursor != start:
		path.push_front(cursor - prev[cursor])
		cursor = prev[cursor]
	return path

func walk(goal: Vector2i) -> void:
	if failed or goal == world.player_pos: return
	var id: String = world.map_data.id
	var path := path_to(goal)
	if not check(not path.is_empty(), "no walking route in %s %s -> %s" % [id,world.player_pos,goal]): return
	for delta in path:
		var old: Vector2i = world.player_pos
		game._move(DIRS[delta])
		walks += 1
		if not check(world.player_pos == old + delta, "step blocked in %s at %s -> %s" % [id,old,delta]): return
		world.tick_walk(0.5)
		dialogs()
		if is_instance_valid(game.active_battle): await battle()
		if failed: return
	print("WALK ", id, " to ", goal, " arrived ", world.map_data.id, " ", world.player_pos)

func talk(face: String) -> void:
	if failed: return
	game._move(face)  # attempting to move into the NPC or counter turns toward it
	game._on_action()
	dialogs()
	if is_instance_valid(game.active_battle): await battle()

func nurse_in_viridian() -> void:
	mode = "travel"
	await walk(Vector2i(74,206))
	if not check(world.map_data.id == "viridiancity_pokemoncenter_1f", "Viridian center door"): return
	await walk(Vector2i(7,4))
	await talk("up")
	await walk(Vector2i(7,8))

func play() -> void:
	if not check(world.map_data.id == "kanto_main" and world.player_pos == Vector2i(72,277) and not game._has_party(), "wrong fresh start"): return
	dialogs()
	await walk(Vector2i(76,273))
	if not check(world.map_data.id == "pallettown_professoroakslab", "lab door"): return
	await walk(Vector2i(6,4))
	await talk("up")
	if not check(game.save_data.party[0].get("species_id") == 25, "Oak starter"): return
	await process_frame
	teach_surf()
	if failed: return
	await walk(Vector2i(6,12))
	mode = "catch"
	var before := bag_count("精灵球")
	await walk(Vector2i(72,255))
	for lap in 12:
		if failed or balls_used > 0: break
		await walk(Vector2i(75,255))
		await walk(Vector2i(72,255))
	if not check(balls_used > 0 and bag_count("精灵球") == before - balls_used, "capture and ball count"): return
	if not check(game._flags().get("story_route1_blurb", false), "route 1 introduction"): return
	await nurse_in_viridian()
	if not check(heal_requests == 1, "first nurse interaction"): return
	# 在常磐市南门外的草地训练，HP 或招式 PP 见底前回中心补给。
	for lap in 150:
		if failed or int(game.save_data.party[0].level) >= 9: break
		mode = "travel"
		await walk(Vector2i(74,226))
		mode = "train"
		await walk(Vector2i(75,226))
		await walk(Vector2i(74,226))
		var lead: Dictionary = game.save_data.party[0]
		if int(lead.hp) < int(lead.max_hp) * 0.7 or int(lead.pp[lead.moves.find(57)]) <= 2:
			await nurse_in_viridian()
	if not check(int(game.save_data.party[0].level) >= 9, "training to gym level"): return
	mode = "travel"
	await walk(Vector2i(65,151))
	if not check(world.map_data.id == "route2_viridianforest_southentrance", "south forest gate"): return
	await walk(Vector2i(7,1))
	if not check(world.map_data.id == "viridianforest", "entering the forest"): return
	await walk(Vector2i(5,9))
	if not check(world.map_data.id == "route2_viridianforest_northentrance", "north forest gate"): return
	await walk(Vector2i(7,1))
	await walk(Vector2i(65,85))
	if not check(world.map_data.id == "pewtercity_pokemoncenter_1f", "Pewter center door"): return
	var earlier_heals := heal_requests
	await walk(Vector2i(7,4))
	await talk("up")
	if not check(heal_requests == earlier_heals + 1 and game.save_data.party[0].hp == game.save_data.party[0].max_hp, "nurse did not heal"): return
	await walk(Vector2i(7,8))
	await walk(Vector2i(63,76))
	if not check(world.map_data.id == "pewtercity_gym", "Pewter gym door"): return
	await walk(Vector2i(6,6))
	await talk("up")
	if not check("灰色徽章" in game.save_data.badges and game._flags().get("beat_brock", false), "Brock win and badge"): return
	check(not (74 in game.save_data.dex.caught or 95 in game.save_data.dex.caught), "trainer opponents counted as caught")
	if failed: return
	game._persist()
	var file := FileAccess.open(directory.path_join("expected.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot()))
	file.close()
