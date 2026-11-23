extends "res://tools/test_world_walks.gd"
## Walk Postwick's doors and both Route 1 trails through World.step, including sprint transitions.
## godot --headless --path . --script tools/test_postwick.gd

class PastureWalker extends Walker:
	var grass_steps := 0
	func step(dir: Vector2i) -> bool:
		var moved := super.step(dir)
		if moved and map_data.id == "galar_1" and wild_tile_here():
			grass_steps += 1
		return moved

func cross(at: Vector2i, destination: String, landing: Vector2i) -> bool:
	var before := transitions
	if not walk(at): return false
	if current != "galar/galar_" + destination or transitions != before + 1 or world.player_pos != landing:
		return fail("%s via %s arrived at %s %s, expected %s" % [destination, at, current, world.player_pos, landing])
	if world.is_blocked(landing) or not world.warp_at(landing).is_empty():
		return fail("unsafe return tile %s %s" % [current, landing])
	return true

func interact(from: Vector2i, dir: Vector2i, service: String) -> bool:
	if not walk(from): return false
	world.facing = DIR[dir]
	world.step_interact()
	return world.last_npc.get(service, false) or fail("unreachable %s in %s" % [service, current])

func houses() -> bool:
	for rug_x in [3, 4]:
		if not cross(Vector2i(12,14), "player_home", Vector2i(3,6)): return false
		if not interact(Vector2i(6,5), Vector2i.UP, "heal"): return false
		if not cross(Vector2i(rug_x,7), "postwick", Vector2i(12,15)): return false
	for rug_x in [8, 9]:
		if not cross(Vector2i(30,9), "hop_home", Vector2i(9,7)): return false
		if not interact(Vector2i(4,5), Vector2i.DOWN, "shop"): return false
		if not cross(Vector2i(8,2), "hop_upstairs", Vector2i(7,2)): return false
		if not cross(Vector2i(7,1), "hop_home", Vector2i(8,3)): return false
		if not cross(Vector2i(rug_x,8), "postwick", Vector2i(30,10)): return false
	return true

func route_one() -> bool:
	# Walk every column of the south entrance in both directions while holding run.
	world.running = true
	for offset in [-1, 0, 1]:
		if not cross(Vector2i(21+offset,0), "1", Vector2i(17+offset,29)): return false
		if not cross(Vector2i(17+offset,30), "postwick", Vector2i(21+offset,1)): return false
	if not cross(Vector2i(21,0), "1", Vector2i(17,29)): return false
	var before: int = world.grass_steps
	for p in [Vector2i(17,22), Vector2i(19,16), Vector2i(23,11), Vector2i(26,6)]:
		if not walk(p): return false
	# A clear trail reaches town even before the player has their first partner.
	for offset in [-1, 0, 1]:
		if not cross(Vector2i(26+offset,0), "wedgehurst", Vector2i(17,25)): return false
		if not cross(Vector2i(17,26), "1", Vector2i(26,1)): return false
	if world.grass_steps != before: return fail("the east trail forced a grass encounter tile")
	# Return by the western fork and walk through the encounter field itself.
	for p in [Vector2i(23,8), Vector2i(16,8), Vector2i(12,13), Vector2i(10,15), Vector2i(10,20), Vector2i(12,23), Vector2i(17,26)]:
		if not walk(p): return false
	if world.grass_steps == before: return fail("the western grass detour has no wild tiles")
	return cross(Vector2i(17,30), "postwick", Vector2i(21,1))

func forest() -> bool:
	if not cross(Vector2i(12,14), "player_home", Vector2i(3,6)): return false
	if not cross(Vector2i(3,7), "postwick", Vector2i(12,15)): return false
	for y in [17, 16, 18]:
		var gate := Vector2i(0,y)
		if y != 17 and world.is_blocked(gate): continue
		if not cross(gate, "weald", Vector2i(29,15)): return false
		if not cross(Vector2i(30,15), "postwick", Vector2i(1,17)): return false
	return true

func run() -> void:
	db = root.get_node("Data")
	atlas = {"regions": db.travel_regions()}
	world = PastureWalker.new()
	root.add_child(world)
	for area in ["postwick", "player_home", "hop_home", "hop_upstairs", "1", "wedgehurst", "weald"]:
		var mid: String = "galar_" + area
		places["galar/"+mid] = db.load_map("galar",mid)
	world.warp_ready.connect(load_at)
	load_at(atlas.regions.galar.hub)
	var ok := check_navigator() and houses() and route_one() and forest()
	print("POSTWICK ", "PASS" if ok else "FAIL", " steps=", steps, " crossings=", transitions-1, " tall_grass_steps=", world.grass_steps)
	quit(0 if ok else 1)
