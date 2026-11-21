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

func walk_to(destination: Vector2i) -> void:
	var origin: Vector2i = world.player_pos
	var cells: Array[Vector2i] = [origin]
	var parent := {origin: origin}
	var doors := {}
	for warp in world.map_data.warps:
		doors[Vector2i(warp.at[0],warp.at[1])] = true
	for pos in cells:
		if pos == destination:
			break
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = pos + direction
			if (not doors.has(next) or next==destination) and not parent.has(next) and world.can_enter(next,direction):
				cells.append(next)
				parent[next] = pos
	if not parent.has(destination):
		fail("no path in %s to %s" % [world.map_data.id,destination])
		return
	var steps: Array[Vector2i] = []
	var cell := destination
	while cell!=origin:
		steps.push_front(cell-parent[cell])
		cell = parent[cell]
	for step in steps: walk(step)

func visit_houses() -> void:
	for house in [["littleroot_west_home",5,8],["littleroot_east_home",14,8],["littleroot_birch_lab",7,16]]:
		var outside := Vector2i(house[1],house[2])
		var lab: bool = house[0]=="littleroot_birch_lab"
		var entry: String = house[0] if lab else house[0]+"_1f"
		walk_to(outside)
		at(entry,Vector2i(6,7))
		if not lab:
			walk_to(Vector2i(10,2))
			at(house[0]+"_2f",Vector2i(10,3))
			walk(Vector2i.UP)
			at(entry,Vector2i(10,3))
		walk_to(Vector2i(6,8))
		at("littleroot_town",outside+Vector2i.DOWN)
	walk_to(Vector2i(10,17))

func run() -> void:
	db = root.get_node("Data")
	world = load("res://core/world.gd").new()
	root.add_child(world)
	await process_frame
	world.warp_ready.connect(enter)
	enter({"region":"kanto","map":"kanto_main","at":[288,232]})
	walk(Vector2i.RIGHT)
	at("harbor",Vector2i(13,4))
	walk(Vector2i.DOWN,12)
	walk(Vector2i.RIGHT)
	walk(Vector2i.DOWN)
	at("littleroot_town",Vector2i(10,17))
	visit_houses()
	walk(Vector2i.LEFT)
	world.facing = "down"
	world.step_interact()
	if world.last_npc.get("name") != "开拓区接驳员" or world.last_npc.get("lines",[]).size() < 2:
		fail("missing transfer directions")
	walk(Vector2i.RIGHT)
	walk(Vector2i.DOWN)
	at("harbor",Vector2i(14,16))
	walk(Vector2i.UP,12)
	at("kanto_main",Vector2i(288,232))
	walk(Vector2i.UP,3)
	if crossings != 15: fail("wrong number of transfers")
	print("HOENN FERRY ", "FAIL" if failed else "PASS", " Kanto → Frontier → Littleroot → Frontier → Kanto")
	quit(1 if failed else 0)
