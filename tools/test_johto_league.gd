extends SceneTree
## godot --headless --path . --script tools/test_johto_league.gd
## Walk the league, lose an actual fight, then defeat every original team and reload the save.

const SAVE = preload("res://core/save_game.gd")
const DIRS := {Vector2i.UP:"up", Vector2i.DOWN:"down", Vector2i.RIGHT:"right", Vector2i.LEFT:"left"}
var game
var world
var db
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, why: String) -> bool:
	if not value and not failed:
		failed = true
		push_error("LEAGUE FAIL: " + why)
	return value

func close_dialogs() -> void:
	for i in 80:
		if game._dialogs.is_empty(): return
		game._on_action()
	check(false, "dialog did not close")

func tile(at: Array) -> Vector2i:
	return Vector2i(int(at[0]), int(at[1]))

func step(dir: Vector2i) -> void:
	if check(world.step(dir), "step blocked at %s towards %s" % [world.player_pos, dir]):
		world.tick_walk(1.0)

func walk_to(target: Vector2i) -> bool:
	var start: Vector2i = world.player_pos
	var prev := {start: start}
	var doors := {}
	for w in world.map_data.warps:
		doors[tile(w.at)] = true
	var queue := [start]
	var cursor := 0
	while cursor < queue.size() and not prev.has(target):
		var p: Vector2i = queue[cursor]
		cursor += 1
		for dir in DIRS:
			var next: Vector2i = p + dir
			if prev.has(next) or (doors.has(next) and next != target): continue
			if not world.can_enter(next, dir): continue
			prev[next] = p
			queue.append(next)
	if not prev.has(target): return false
	var p := target
	var path := []
	while p != start:
		path.push_front(p - prev[p])
		p = prev[p]
	for dir in path:
		step(dir)
	return not failed

func door(dest: String) -> void:
	for w in world.map_data.warps:
		if w.to.map == dest:
			if not walk_to(tile(w.at)): continue
			if world.map_data.id == dest: return
			for dir in DIRS:
				if DIRS[dir]==w.get("trigger","step"):
					step(dir)
					break
			return
	check(false, "missing door to " + dest)

func talk(npc: Dictionary) -> void:
	var at := tile(npc.at)
	for dir in DIRS:
		var side: Vector2i = at - dir
		if world.map_data.warps.any(func(w): return tile(w.at) == side): continue
		if walk_to(side):
			world.facing = DIRS[dir]
			game._on_action()
			return
	check(false, "cannot address " + String(npc.name))

func battle(expected: String) -> void:
	close_dialogs()
	var ui = game.active_battle
	if not check(ui != null, "battle did not start"): return
	var turns := 0
	for frame in 2500:
		if game.active_battle == null: break
		if ui.state == "menu":
			turns += 1
			var mon: Dictionary = ui.battle.cur_a()
			var best := 0
			var high := -1.0
			for i in mon.moves.size():
				var mv: Dictionary = db.move_of(int(mon.moves[i]))
				var score := float(mv.get("power", 0)) * float(ui.battle.effectiveness_on(String(mv.type), ui.battle.cur_b()))
				if mon.pp[i] > 0 and score > high:
					best = i
					high = score
			ui._on_command_kind("fight")
			ui._on_move(best)
		ui._process(2.0)
	check(game.active_battle == null and ui.battle.winner == expected, "wrong result for " + String(ui.trainer_name))
	print("LEAGUE battle ", ui.trainer_name, " enemy=",ui.enemy_team.size()," turns=",turns," result=",ui.battle.winner)

func run() -> void:
	SAVE.use_test_slot()
	db = root.get_node("Data")
	db.load_core_tables()
	var party = load("res://core/party.gd")
	var old := SAVE.empty()
	old.region = "johto"
	old.map = "johto_victory_road"
	old.pos = [6,16]
	old.badges = ["灰色徽章"]
	old.party = [party.make(129, 1, [150])]
	old.flags = {"johto_victory_done":true}
	SAVE.save(old)
	seed(407)
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	world = game.world
	game.rng.seed = 486
	var migrated: Vector2i = preload("res://core/hgss_field.gd").position(world.map_data,tile(old.pos))
	check(world.map_data.id == old.map and world.player_pos == migrated and not world.is_blocked(migrated), "legacy Victory Road save restored on its native floor")
	check(game.save_data.badges == old.badges and game.save_data.party[0].species_id == 129, "legacy progress")
	door("hgss_victory_road_2f")
	check(world.map_data.id=="hgss_victory_road_2f" and world.player_pos==Vector2i(7,31), "legacy save reaches the native stair landing")
	var rules: Dictionary = game.johto_league.rules
	var rooms: Array = rules.rounds
	var lobby: String = rules.lobby
	game._do_warp({"region":"johto","map":lobby,"at":[4,3]})
	door(rooms[0].room)
	check(world.map_data.id == lobby and not game._dialogs.is_empty(), "badge gate")
	close_dialogs()
	game.save_data.badges.append_array(rules.badges)
	door(rooms[0].room)
	check(world.map_data.id == rooms[0].room, "first chamber")
	talk(world.npcs[0])
	battle("b")
	check(world.map_data.id == lobby and not game._flags().has(rooms[0].flag), "loss advanced")
	check(game.save_data.party[0].hp == game.save_data.party[0].max_hp, "blackout did not heal")
	game.save_data.party = [party.make(150,100,[94,58,85,247]),party.make(149,100,[89,63,58,85])]
	door(rooms[0].room)
	for i in rooms.size():
		if failed: break
		var row: Dictionary = rooms[i]
		var next_room: String = rooms[i+1].room if i+1 < rooms.size() else rules.hall
		check(world.map_data.id == row.room, "round order")
		door(next_room)
		check(world.map_data.id == row.room and not game._dialogs.is_empty(), "opponent gate " + String(row.name))
		close_dialogs()
		var npc: Dictionary = world.npcs[0]
		check(npc.name == row.name and npc.battle.team.size() == (6 if i == 4 else 5), "wrong team")
		for mon in npc.battle.team:
			check(mon.moves.size() == 4, "missing original moves")
		talk(npc)
		battle("a")
		check(SAVE.load_game().flags.get(row.flag,false), "round win did not save")
		if i == rooms.size()-1:
			close_dialogs()
			await process_frame  # Lance leads the player into the Hall after the press arrive.
			close_dialogs()
		if world.map_data.id != next_room:
			door(next_room)
	if not failed:
		var saved := SAVE.load_game()
		check(saved.flags.get("johto_champion",false) and saved.map == rules.hall, "champion did not save")
		if check(saved.has("hall_of_fame"), "missing hall record"):
			var original: Array = saved.hall_of_fame.johto
			check(original.size() == 2 and original[0].species_id == 150 and original[1].species_id == 149, "registered roster")
			close_dialogs()
			game._restore_from_save()
			check(game._dialogs.is_empty() and game.save_data.hall_of_fame.johto == original, "ceremony repeated on reload")
			talk(world.npcs[0])
			check(not game._dialogs.is_empty() and game._dialogs.back().lines.size() == 3, "record unreadable")
	close_dialogs()
	game.queue_free()
	await process_frame
	await process_frame
	SAVE.clear_test_slot()
	print("JOHTO LEAGUE ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
