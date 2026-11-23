extends "res://tools/test_world_walks.gd"
## Walk both sides of the port gates, talk to each clerk and start a real tower battle.

const Save := preload("res://core/save_game.gd")

func test_reception() -> void:
	for x in [3, 13, 9]:
		if not walk(Vector2i(x, 4)):
			return
		world.facing = "up"
		world.step_interact()
		if world.last_npc.is_empty() or vec(world.last_npc.at) != Vector2i(x, 3):
			fail("unreachable reception at %s" % x)
			return
		if x == 9 and not world.last_npc.get("facility", false):
			fail("tower battle desk")
			return

func test_gate(target: Vector2i, destination: String, arrival: Vector2i) -> bool:
	if not walk(target):
		return false
	if current != "frontier/" + destination or world.player_pos != arrival:
		return fail("expected %s %s; reached %s %s" % [destination, arrival, current, world.player_pos])
	return true

func test_battle() -> void:
	Save.use_test_slot()
	var game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	game._do_warp({"region": "frontier", "map": "tower_lobby", "at": [9, 4]})
	await process_frame
	game._close_all_dialogs()
	game.world.facing = "up"
	game._on_action()
	await process_frame
	if not is_instance_valid(game.active_battle) or game.active_battle.battle == null:
		fail("tower reception did not open a battle")
	Save.clear_test_slot()

func run() -> void:
	db = root.get_node("Data")
	world = Walker.new()
	root.add_child(world)
	for id in ["harbor", "tower_lobby", "frontier_isle_walk"]:
		places["frontier/" + id] = db.load_map("frontier", id)
	world.warp_ready.connect(load_at)
	load_at({"region": "frontier", "map": "harbor", "at": [14, 15]})
	if not walk(Vector2i(14, 1)) or current != "frontier/tower_lobby":
		fail("north tower door")
	if not failed:
		test_reception()
	if not failed:
		test_gate(Vector2i(9, 15), "harbor", Vector2i(14, 2))
	if not failed and (not walk(Vector2i(6, 8)) or current != "frontier/frontier_isle_walk"):
		fail("sea wall gate")
	if not failed:
		test_gate(Vector2i(15, 22), "harbor", Vector2i(7, 8))
	if not failed and walk(Vector2i(14, 15)):
		world.facing = "right"
		world.step_interact()
		if not world.last_npc.get("transit", false):
			fail("navigator")
	if not failed:
		await test_battle()
	print("FRONTIER PORT ", "FAIL" if failed else "PASS", " desks=3 steps=", steps, " crossings=", transitions - 1)
	quit(1 if failed else 0)
