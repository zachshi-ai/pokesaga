extends SceneTree
## godot --headless --path . --script tools/test_hoenn_ferry.gd
## Sail in both directions and verify that all four landing tiles can be walked from.
var world
var db
var failed := false
var crossings := 0

func _initialize() -> void:
	call_deferred("run")

func enter(target: Dictionary) -> void:
	world.load_map(db.load_map(target.region, target.map))
	world.warp_to(Vector2i(int(target.at[0]), int(target.at[1])))
	crossings += 1
	if world.is_blocked(world.player_pos):
		fail("blocked landing in " + String(target.map))

func fail(why: String) -> void:
	if not failed: push_error("HOENN FERRY " + why)
	failed = true

func walk(dir: Vector2i, n := 1) -> void:
	for i in n:
		if failed: return
		if not world.step(dir):
			fail("blocked at %s/%s" % [world.map_data.id, world.player_pos])
			return
		world.tick_walk(1.0)

func at(room: String, pos: Vector2i) -> void:
	if world.map_data.id != room or world.player_pos != pos: fail("unexpected map/landing " + room)

func run() -> void:
	db = root.get_node("Data")
	world = load("res://core/world.gd").new()
	root.add_child(world)
	await process_frame
	world.warp_ready.connect(enter)
	enter({"region":"kanto","map":"kanto_main","at":[288,234]})
	walk(Vector2i.DOWN)
	at("harbor",Vector2i(13,4))
	walk(Vector2i.DOWN,12)
	walk(Vector2i.RIGHT)
	walk(Vector2i.DOWN)
	at("littleroot_town",Vector2i(10,17))
	walk(Vector2i.LEFT)
	world.facing = "down"
	world.step_interact()
	if world.last_npc.get("name") != "开拓区接驳员" or world.last_npc.get("lines",[]).size() < 2:
		fail("missing transfer directions")
	walk(Vector2i.RIGHT)
	walk(Vector2i.DOWN)
	at("harbor",Vector2i(14,16))
	walk(Vector2i.UP,12)
	at("kanto_main",Vector2i(287,234))
	walk(Vector2i.UP,3)
	if crossings != 5: fail("wrong number of transfers")
	print("HOENN FERRY ", "FAIL" if failed else "PASS", " Kanto → Frontier → Littleroot → Frontier → Kanto")
	quit(1 if failed else 0)
