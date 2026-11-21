extends SceneTree
## Walk the route using the real movement checks, then replay every step and warp.
## godot --headless --path . --script tools/test_johto_passage.gd

const DIRS := [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]
class Walker extends "res://core/world.gd":
	func _ready() -> void: pass
	func _rebuild(_story_flags: Variant = null) -> void: pass

var world
var db
var goal := "johto_hall_of_fame"
var start = ["johto_olivine_port", Vector2i(7, 7)]

func _initialize() -> void:
	call_deferred("run")

func tile(at: Array) -> Vector2i:
	return Vector2i(int(at[0]), int(at[1]))

func enter(region: String, room: String, pos: Vector2i) -> void:
	world.load_map(db.load_map(region, room))
	world.warp_to(pos)
	world.surfing = world.is_water(pos)

func route_to(prev: Dictionary, cell: Vector2i, last_dir: Vector2i) -> Array:
	var path := [last_dir]
	while prev[cell] != null:
		var edge: Array = prev[cell]
		path.push_front(edge[1])
		cell = edge[0]
	return path

func exits_from(room: String, arrival: Vector2i) -> Dictionary:
	enter("johto", room, arrival)
	var doors := {}
	for w in world.map_data.warps:
		var at := tile(w.at)
		if not doors.has(at):
			if w.get("trigger","step") == "step": doors[at] = w.to
	var prev := {arrival: null}
	var queue := [arrival]
	var exits := {}
	var index := 0
	while index < queue.size():
		var p: Vector2i = queue[index]
		index += 1
		for dir in DIRS:
			world.player_pos = p
			world.surfing = world.is_water(p) or world.is_water(p + dir)
			if dir != Vector2i.DOWN and (world.is_waterfall(p) or world.is_waterfall(p+dir)):
				if dir==Vector2i.UP and world.is_waterfall(p+dir):
					var landing: Vector2i = world.waterfall_landing(p)
					if not prev.has(landing):
						prev[landing]=[p,dir]
						queue.append(landing)
				continue
			var directional: Dictionary = world._warp_from(p,dir)
			if not directional.is_empty():
				var target: Dictionary = directional.to
				if target.region == "johto":
					var next := [target.map,tile(target.at)]
					if not exits.has(next): exits[next] = route_to(prev,p,dir)
				continue
			if not world.can_step(dir):
				continue
			var dest: Vector2i = world.jump_landing(dir) if world.hop_wanted(dir) else p + dir
			if doors.has(dest):
				var to: Dictionary = doors[dest]
				if to.region == "johto":
					var next := [to.map, tile(to.at)]
					if not exits.has(next):
						exits[next] = route_to(prev, p, dir)
			elif not prev.has(dest):
				prev[dest] = [p, dir]
				queue.append(dest)
	return exits

func run() -> void:
	world = Walker.new()
	root.add_child(world)
	await process_frame
	db = root.get_node("Data")
	enter("kanto", "kanto_main", Vector2i(286, 232))
	if not world.step(Vector2i.LEFT) or world.pending_warp.get("map") != start[0]:
		fail("missing Kanto ferry")
		return
	var landing: Dictionary = world.pending_warp.duplicate()
	world.load_map(db.load_map("johto", start[0]))
	world.arrive(landing)
	start[1] = world.player_pos
	world.finish_walk()
	var queue := [start]
	var prev := {start: null}
	var index := 0
	while index < queue.size():
		var state: Array = queue[index]
		index += 1
		if state[0] == goal:
			await replay(prev, state)
			return
		var exits := exits_from(state[0], state[1])
		for dest in exits:
			if not prev.has(dest):
				queue.append(dest)
				prev[dest] = [state, exits[dest]]
		await process_frame
	fail("Hall of Fame unreachable from ferry, checked %d entrances" % prev.size())

func replay(prev: Dictionary, last: Array) -> void:
	var segments := []
	while prev[last] != null:
		var edge: Array = prev[last]
		segments.push_front([last, edge[1]])
		last = edge[0]
	enter("johto", start[0], start[1])
	var steps := 0
	var surf_entries := 0
	var sequence: Array = [start[0]]
	for leg in segments:
		var expected: Array = leg[0]
		for dir in leg[1]:
			if not world.surfing and world.is_water(world.player_pos + dir):
				world.facing = {Vector2i.DOWN:"down", Vector2i.UP:"up", Vector2i.RIGHT:"right", Vector2i.LEFT:"left"}[dir]
				var water: Vector2i = world.player_pos + dir
				if world.toggle_surf().is_empty() or not world.surfing or world.player_pos != water:
					fail("cannot surf from %s" % world.player_pos)
					return
				surf_entries += 1
			elif dir==Vector2i.UP and world.surfing and world.is_waterfall(world.player_pos+dir):
				var top: Vector2i=world.waterfall_landing(world.player_pos)
				world.warp_to(top)
				world.surfing=world.is_water(top)
			elif not world.step(dir):
				fail("blocked in %s at %s" % [world.map_data.id, world.player_pos])
				return
			var to: Dictionary = world.pending_warp
			world.finish_walk()
			steps += 1
			if not to.is_empty():
				enter(to.region, to.map, tile(to.at))
		if world.map_data.id != expected[0] or world.player_pos != expected[1]:
			fail("wrong exit, expected %s, got %s/%s" % [expected, world.map_data.id, world.player_pos])
			return
		sequence.append(expected[0])
		await process_frame
	if surf_entries == 0 or "johto_victory_road" not in sequence or "johto_route_23" not in sequence:
		fail("route did not exercise sea, Victory Road and Route 23")
		return
	print("PASS Kanto ferry -> Hall of Fame: %d steps, %d crossings, %d surf entries." % [steps, segments.size(), surf_entries])
	print(sequence)
	quit(0)

func fail(message: String) -> void:
	push_error(message)
	quit(1)
