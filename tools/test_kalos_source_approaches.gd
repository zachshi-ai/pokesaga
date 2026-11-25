extends "res://tools/test_3ds_field_survey.gd"
## Replay each route from its field entrance. On Azure Bay board Surf at the
## actual shoreline, using the same field action as the Surf confirmation.

func route_over_water(gate: Dictionary) -> bool:
	var aboard := world.surfing
	if not aboard and not seek(gate, 60000).is_empty():
		push_error("Water crossing is reachable without Surf")
		return false
	var start := world.player_pos
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start: Vector2i.ZERO}
	var index := 0
	var here := start
	var path: Array = []
	while index < queue.size():
		here = queue[index]
		index += 1
		path = approach(gate, here)
		if not path.is_empty():
			break
		world.player_pos = here
		for direction: Vector2i in DIRS:
			if previous.has(here + direction):
				continue
			world.surfing = world.is_water(here) or world.is_water(here + direction)
			if blocked(direction):
				continue
			previous[here + direction] = direction
			queue.append(here + direction)
	world.surfing = aboard
	world.warp_to(start)
	if path.is_empty():
		print("No sea path, ",queue.size()," reachable from ",start)
		return false
	while here != start:
		var d: Vector2i = previous[here]
		path.push_front(d)
		here -= d
	var boarded := 0
	var sailed := 0
	for d: Vector2i in path:
		if not world.surfing and world.is_water(world.player_pos + d):
			world.facing = {Vector2i.UP:"up", Vector2i.DOWN:"down", Vector2i.LEFT:"left", Vector2i.RIGHT:"right"}[d]
			if world.toggle_surf() != "用冲浪下水了。":
				return false
			world.tick_walk(1.0)
			total_steps += 1
			boarded += 1
		elif not motion(d):
			return false
		if world.surfing:
			sailed += 1
	print("AZURE BAY boarded ", boarded, " water steps ", sailed)
	return (aboard or boarded > 0) and sailed > 0 and received.get("map") == gate.to.map

func coastal_crossing() -> bool:
	world.load_map(db.load_map("kalos", "kalos_12"))
	world.surfing = false
	var coast: Dictionary = world.map_data.warps.filter(func(w): return w.to.map == "kalos_azure")[0]
	if not route_over_water(coast):
		return false
	put_at(received)
	if not world.surfing or world.player_pos != Vector2i(55,203):
		return false
	var cave: Dictionary = world.map_data.warps.filter(func(w): return w.to.map == "kalos_sea_spirits_den")[0]
	if not route_over_water(cave):
		return false
	put_at(received)
	if world.surfing or not cross(world.map_data.warps[0], 60000):
		return false
	put_at(received)
	var back: Dictionary = world.map_data.warps.filter(func(w): return w.to.map == "kalos_12")[0]
	if not route_over_water(back):
		return false
	put_at(received)
	return world.surfing and world.player_pos == Vector2i(55,6)


func run() -> void:
	db = root.get_node("Data")
	root.add_child(world)
	world.warp_ready.connect(on_warp)
	for spec in [["azure",0,[72,71],[71,71]],["14",1,[10,22],[10,23]],["shalour",8,[41,40],[41,41]],["league_gate",0,[13,6],[13,7]]]:
		var mid: String = "kalos_" + spec[0]
		var field: Dictionary = db.load_map("kalos",mid)
		world.load_map(field)
		if mid == "kalos_14":
			for x in [8,9,11,12]:
				if world.can_enter(Vector2i(x,22),Vector2i.UP):
					push_error("Scary House wall permits standing inside")
					faults += 1
		var matches: Array = field.warps.filter(func(w): return w.get("source_warp") == "xy_" + str(spec[1]))
		var gate: Dictionary = matches[0]
		var before := total_steps
		received = {}
		var crossed := route_over_water(gate) if spec[0] == "azure" else cross(gate, 60000)
		if not crossed or pos(gate.at) != pos(spec[2]):
			push_error("Could not walk from field spawn to original door in " + mid)
			faults += 1
			continue
		put_at(received)
		var return_gates: Array = world.map_data.warps.filter(func(w): return w.to.map == mid and pos(w.to.at) == pos(spec[3]))
		if return_gates.is_empty() or not cross(return_gates[0],60000):
			push_error("Cannot return from " + gate.to.map)
			faults += 1
			continue
		put_at(received)
		if world.player_pos != pos(spec[3]):
			faults += 1
		print("FIELD ROUTE ",mid," ",gate.at," ",total_steps-before," moves return ",world.player_pos)
	var before_water := total_steps
	if not coastal_crossing():
		push_error("Route 12, the island cave and the return sailing failed")
		faults += 1
	print("ROUTE 12 SEA ROUND TRIP ", total_steps - before_water, " moves")
	var victory := {"region":"kalos", "map":"kalos_victory"}
	var guard = load("res://core/kalos_campaign.gd")
	if guard.gate(victory, {"k_started":true, "k_badge_8":true}).is_empty() or not guard.gate(victory, {"k_started":true, "k_badge_8":true, "k_league_gate":true}).is_empty():
		faults += 1
	print("KALOS SOURCE APPROACHES ", "PASS" if faults == 0 else "FAIL", " ", total_steps, " moves")
	quit(int(faults != 0))
