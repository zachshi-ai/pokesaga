extends "res://tools/test_world_walks.gd"
## Exercise the actual movement and warp signals through every redrawn map's doors.

func visit_service(person: Dictionary) -> bool:
	var start: Vector2i = world.player_pos
	var counter := vec(person.at)
	var queue := [start]
	var seen := {start:true}
	var index := 0
	var stand := Vector2i(-1,-1)
	while index < queue.size():
		var cell: Vector2i = queue[index]
		index += 1
		if DIR.has(counter-cell):
			stand = cell
			break
		world.player_pos = cell
		for direction in DIR:
			var next: Vector2i = cell + direction
			if seen.has(next) or not world.warp_at(next).is_empty() or not world.can_step(direction): continue
			seen[next] = true
			queue.append(next)
	world.player_pos = start
	if stand.x < 0 or not walk(stand): return fail("cannot reach counter in "+current)
	world.facing = DIR[counter-stand]
	world.step_interact()
	return world.last_npc.get("at",[]) == person.at or fail("wrong attendant at " + current)

func run() -> void:
	db = root.get_node("Data")
	world = Walker.new()
	root.add_child(world)
	var fields := []
	for region in ["galar", "hisui", "paldea"]:
		for id in db.load_region(region).map_ids:
			var map: Dictionary = db.load_map(region, id)
			var key := str(region) + "/" + str(id)
			places[key] = map
			if map.has("switch_field_revision"):
				fields.append(key)
	world.warp_ready.connect(load_at)
	var crossed := 0
	var services := 0
	for key in fields:
		var data: Dictionary = places[key]
		for door in data.warps:
			var t: Dictionary = door.to
			var destination := str(t.region) + "/" + str(t.map)
			if not places.has(destination): places[destination] = db.load_map(t.region,t.map)
			load_at({"region": data.region, "map": data.id, "at": data.spawn})
			var expected := vec(t.at)
			var arrival: Dictionary = places[destination]
			if arrival.has("kalos_native") and not t.get("kalos_native",false): expected = vec(arrival.spawn)
			if door.get("atlas", "") == "world" and (arrival.has("unova_native") or arrival.has("platinum_native")):
				for reverse in arrival.warps:
					if reverse.get("atlas", "") == "world" and reverse.to.map == data.id: expected = vec(reverse.at)
			var target:=vec(door.at)
			var reached:=false
			if door.get("trigger","")=="door":
				reached=walk(target+Vector2i.DOWN) and world.step(Vector2i.UP)
				world.tick_walk(1.0)
				steps+=1
			else:reached=walk(target)
			if not reached or current != destination or world.player_pos != expected:
				fail("%s %s -> %s at %s; arrived %s %s" % [key,door.at,destination,t.at,current,world.player_pos])
				break
			if world.is_blocked(world.player_pos) or world.is_water(world.player_pos):
				fail("invalid arrival in "+destination+str(world.player_pos))
				break
			crossed += 1
		if failed: break
		if data.has("switch_room"):
			for person in data.npcs:
				if not (person.get("shop",false) or person.get("heal",false)): continue
				load_at({"region":data.region, "map":data.id, "at":data.spawn})
				if not visit_service(person):break
				services += 1
		if failed:break
	print("SWITCH FIELDS ","FAIL" if failed else "PASS", " maps=", fields.size(), " exits=", crossed, " steps=", steps, " counters=", services)
	quit(1 if failed else 0)
