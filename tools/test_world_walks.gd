extends SceneTree
## Walk outward and back over every international road. Platinum's domestic route
## network is tested by the fresh-save campaign and the directed world graph.
## godot --headless --path . --script tools/test_world_walks.gd

class Walker extends "res://core/world.gd":
	func _ready() -> void: pass
	func _rebuild(_story_flags: Variant = null) -> void: pass

const DIR := {Vector2i.UP:"up", Vector2i.DOWN:"down", Vector2i.LEFT:"left", Vector2i.RIGHT:"right"}
var world
var db
var atlas
var doors := {}
var places := {}
var checked := {}
var checked_hubs := {}
var steps := 0
var transitions := 0
var failed := false
var current := ""

func _initialize() -> void:
	call_deferred("run")

func vec(at: Array) -> Vector2i: return Vector2i(int(at[0]),int(at[1]))

func fail(reason: String) -> bool:
	if not failed: push_error("WORLD WALK FAIL " + reason)
	failed = true
	return false

func load_at(target: Dictionary) -> void:
	current = String(target.region) + "/" + String(target.map)
	world.load_map(places[current])
	# Circhester Bay is the water-mode Rotom Bike section of the international road circuit.
	world.bike=(world.map_data.id=="galar_circhester_bay")
	if world.bike:world.taken.g_water_bike=true
	world.arrive(target)
	world.finish_walk()
	transitions += 1

func path(target: Vector2i) -> Array:
	var start: Vector2i = world.player_pos
	var previous := {start:null}
	var q := [start]
	var warps := {}
	for w in world.map_data.warps: warps[vec(w.at)] = true
	var i := 0
	while i < q.size() and not previous.has(target):
		var p: Vector2i = q[i]
		i += 1
		for dir in DIR:
			world.player_pos = p
			var passage: Dictionary = world._warp_from(p,dir)
			if not passage.is_empty() and (passage.get("trigger") != "door" or vec(passage.at) != target): continue
			if passage.is_empty() and not world.can_step(dir):continue
			var next: Vector2i = world.jump_landing(dir) if world.hop_wanted(dir) else p+dir
			if previous.has(next) or (warps.has(next) and next != target): continue
			previous[next]=[p,dir]
			q.append(next)
	world.player_pos = start
	if not previous.has(target):
		fail("no walk from %s %s to %s" % [current,start,target])
		return []
	var out := []
	var p := target
	while p!=start:
		var edge: Array = previous[p]
		out.push_front(edge[1])
		p=edge[0]
	return out

func walk(target: Vector2i) -> bool:
	var origin := current
	for dir in path(target):
		if not world.step(dir): return fail("replay blocked at %s %s" % [current,world.player_pos])
		steps += 1
		world.tick_walk(1.0)
	if current == origin and world.player_pos == target:
		var direction: String = world.warp_at(target).get("trigger", "")
		if direction in world.WARP_DIR:
			if not world.step(world.WARP_DIR[direction]): return fail("cannot activate "+str(target))
			world.tick_walk(1.0)
	return not failed

func take_gate(target: String) -> bool:
	var gate: Vector2i = doors[current][target]
	if world.player_pos == gate:
		# A legacy doorway can spawn on its reciprocal trigger. Leave and re-enter it on foot.
		var safe := false
		for dir in DIR:
			var side: Vector2i = gate + dir
			var other_door: bool = world.map_data.warps.any(func(w): return vec(w.at)==side)
			if other_door or not world.can_step(dir):continue
			world.step(dir)
			world.tick_walk(1.0)
			steps += 1
			safe = true
			break
		if not safe:return fail("cannot re-enter "+current)
	if not walk(gate):return false
	if current!=target:return fail("wrong destination %s, expected %s" % [current,target])
	return true

func check_navigator() -> bool:
	var region: String = world.map_data.region
	var hub: Dictionary = atlas.regions[region].hub
	if checked_hubs.has(region) or current!=region+"/"+str(hub.map):return true
	var spot:=vec(hub.at)
	if not walk(spot):return false
	var dir:=vec(hub.npc_at)-spot
	if not DIR.has(dir):return fail("navigator not adjacent to landing in "+region)
	world.facing=DIR[dir]
	world.step_interact()
	if not world.last_npc.get("transit",false) or vec(world.last_npc.at)!=vec(hub.npc_at):return fail("navigator interaction in "+region)
	checked_hubs[region]=true
	return true

func run() -> void:
	db=root.get_node("Data")
	atlas={"regions":db.travel_regions()}
	world=Walker.new()
	root.add_child(world)
	for region in atlas.regions:
		for loc in atlas.regions[region].locations:
			var mid: String=loc.map
			var key: String=str(region)+"/"+mid
			if places.has(key):continue
			var map: Dictionary=db.load_map(region,mid)
			if map.is_empty():fail("missing map "+key);break
			var links := {}
			for w in map.warps:
				var to: Dictionary=preload("res://core/world_passages.gd").unova_terminus(map,w.to,db.unova_era) if w.get("atlas","")=="world" else w.to
				var dest:=str(to.region)+"/"+str(to.map)
				var legacy: bool=key in ["hoenn/littleroot_town","hoenn/route101"] and dest in ["hoenn/littleroot_town","hoenn/route101"]
				if w.get("atlas","")=="world" or legacy: links[dest]=vec(w.at)
			if not links.is_empty():
				places[key]=map
				doors[key]=links
	world.warp_ready.connect(load_at)
	load_at(atlas.regions.kanto.hub)
	var home:=current
	var tour:=home
	var trips:=1
	# The old atlas network assumed placeholder links between towns. Sinnoh now
	# connects the four international termini through real routes, caves and story
	# gates. Start a walking circuit at each independent atlas branch, and require
	# its entire road network (including the new hub) to return to that same town.
	var native_termini:=["sinnoh/sinnoh_twinleaf","sinnoh/sinnoh_canalave","sinnoh/sinnoh_celestic","sinnoh/sinnoh_spring"]
	for place in places:
		if places[place].has("unova_native") or places[place].has("kalos_native") or places[place].has("alola_native"):native_termini.append(place)
	var seen: Dictionary={}
	var done_edges: Dictionary={}
	var stack: Array=[]
	while not failed:
		if not seen.has(current):
			seen[current]=true
			if not check_navigator():break
		var target: String=""
		for dst in doors[current]:
			var pair:=edge_key(current,dst)
			if not done_edges.has(pair):
				target=dst
				done_edges[pair]=true
				break
		if not target.is_empty():
			var source:=current
			if not doors.has(target) or not doors[target].has(source):
				fail("missing return passage %s ↔ %s"%[source,target]);break
			if not take_gate(target):break
			if seen.has(target):
				if not take_gate(source):break
			else:stack.append(source)
		elif not stack.is_empty():
			if not take_gate(stack.pop_back()):break
		else:
			if current!=tour:
				fail("road circuit did not return to "+tour)
				break
			var next: Array=native_termini.filter(func(t):return not seen.has(t))
			if next.is_empty():break
			tour=next[0]
			var start: Dictionary=places[tour]
			load_at({"region":start.region,"map":start.id,"at":start.spawn,"platinum_native":start.has("platinum_native"),"unova_native":start.has("unova_native"),"kalos_native":start.has("kalos_native"),"alola_native":start.has("alola_native")})
			trips+=1
	if not failed and (current!=tour or seen.size()!=places.size() or checked_hubs.size()!=atlas.regions.size()):
		fail("incomplete tour: %s maps %s navigators %s" % [current,seen.size(),checked_hubs.size()])
	print("WORLD WALK ", "FAIL" if failed else "PASS", " regions=",checked_hubs.size()," maps=",seen.size()," pairs=",done_edges.size()," steps=",steps," crossings=",transitions-trips," road_circuits=",trips)
	quit(1 if failed else 0)

func edge_key(a: String,b: String) -> String:
	return a+"|"+b if a<b else b+"|"+a
