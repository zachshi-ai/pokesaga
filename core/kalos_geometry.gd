extends RefCounted

static var variants: Dictionary
static func phase(flags:Dictionary) -> String:
	if flags.get("k_last_lysandre",false) or flags.get("k_weapon",false):return "crater"
	if flags.get("k_two_buttons",false):return "weapon"
	return "stones"

static func town(world,plan:Dictionary,flags:Dictionary) -> Dictionary:
	if variants.is_empty():
		variants=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_geosenge.json"))
	var state:Dictionary=variants[phase(flags)]
	world.terrain_phase=phase(flags)
	world.emerald_collision=state.collision
	var art:=plan.duplicate()
	art.scene=["res://assets/kalos/maps/%s.png"%state.art,0,0]
	return art

## Relocate v4.61 saves relative to the nearest recorded doorway or landmark.
## Check current collision and story actors before permitting the first step.
static func opening_position(world, legacy: Vector2i) -> Vector2i:
	var plan: Dictionary = world.map_data
	var size := Vector2i(int(plan.size[0]), int(plan.size[1]))
	var points: Array = plan.get("kalos_legacy_points", [])
	var nearest := Vector2i(int(plan.spawn[0]), int(plan.spawn[1]))
	var distance := 2147483647
	for point in points:
		var old := Vector2i(int(point[0]), int(point[1]))
		var d := legacy.distance_squared_to(old)
		if d >= distance: continue
		distance = d
		nearest = Vector2i(int(point[2]), int(point[3])) + Vector2i(Vector2(legacy - old) * 0.4)
	nearest = nearest.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	# Flood from the town's verified spawn. A nearby isolated cell inside a
	# shop counter or on a river bank must never be chosen.
	var start := Vector2i(int(plan.spawn[0]), int(plan.spawn[1]))
	var pending := [start]
	var visited := {start: true}
	var best := start
	var index := 0
	while index < pending.size():
		var cell: Vector2i = pending[index]
		index += 1
		if not world.is_blocked(cell) and cell.distance_squared_to(nearest) < best.distance_squared_to(nearest):
			best = cell
			if best == nearest: break
		for dir in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var next: Vector2i = cell + dir
			if visited.has(next) or world.is_blocked(next) or world.is_water(next) or not world.warp_at(next).is_empty(): continue
			visited[next] = true
			pending.append(next)
	return best
