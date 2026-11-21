extends "test_world_walks.gd"
## Verify the entire directed map registry from the new-game bedroom and replay
## dynamic centre stairs, ferry voyages and elevators through World.step.

const Passage := preload("res://core/passage_memory.gd")
var journal := {}
var originals := {}

func load_at(target: Dictionary) -> void:
	var dest := Passage.resolve(journal,target)
	var k := str(dest.region)+"/"+str(dest.map)
	if not places.has(k):
		places[k]=db.load_map(str(dest.region),str(dest.map))
	super.load_at(dest)

func fill_reachable(seed_key: String, graph: Dictionary) -> Dictionary:
	var found := {}
	var todo := [seed_key]
	while not todo.is_empty():
		var key: String=todo.pop_back()
		if found.has(key):continue
		found[key]=true
		for dst in graph[key]:todo.append(dst)
	return found

func check_graph() -> int:
	var graph := {}
	var reverse := {}
	for r in atlas.regions:
		var folder := "res://content/regions/%s/maps/" % r
		var registry: Dictionary = db.load_json("res://content/regions/%s/region.json" % r)
		var actual := {}
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".json"): actual[file.get_basename()]=true
		if registry.maps.size()!=actual.size():
			fail("region map count differs from directory: "+str(r))
			return 0
		var seen_maps := {}
		for mid in registry.maps:
			var key := str(r)+"/"+str(mid)
			if seen_maps.has(mid) or not actual.has(mid):
				fail("missing or duplicate map "+key)
				return 0
			seen_maps[mid]=true
			if not reverse.has(key):reverse[key]=[]
			graph[key]=[]
			var map: Dictionary=db.load_map(str(r),str(mid))
			var cells := {}
			for w in map.warps:
				var at:=vec(w.at)
				if cells.has(at):continue
				cells[at]=true
				var target: Dictionary=w.to
				var dst:=str(target.region)+"/"+str(target.map)
				graph[key].append(dst)
				if not reverse.has(dst):reverse[dst]=[]
				reverse[dst].append(key)
				if target.has("remember_passage"):
					if not originals.has(target.remember_passage.key):
						originals[target.remember_passage.key]=[]
					originals[target.remember_passage.key].append([r,mid,w])
	for dst in reverse:
		if not graph.has(dst):
			fail("invalid warp target "+dst)
			return 0
	var bedroom := "kanto/pallet_town_players_house_2f"
	var outward := fill_reachable(bedroom,graph)
	var inward := fill_reachable(bedroom,reverse)
	if outward.size()!=graph.size() or inward.size()!=graph.size():
		fail("bedroom directed reach %d, reverse %d, registry %d"%[outward.size(),inward.size(),graph.size()])
		return 0
	return graph.size()

func probe(entry: Array, slot: String) -> bool:
	var r: String=entry[0]
	var mid: String=entry[1]
	var w: Dictionary=entry[2]
	var expected: Dictionary=w.to.remember_passage.destination
	var source: Dictionary={"region":r,"map":mid,"at":expected.at}
	match slot:
		"johto_lift":
			source.at=([3,1] if mid.ends_with("_1f") else [6,1])
		"johto_ship":
			source.at=([3,8] if mid=="johto_olivine_port" else [3,7])
	load_at(source)
	if not walk(vec(w.at)) or current!=r+"/"+str(w.to.map):
		return fail("did not enter shared room from "+r+"/"+mid)
	# Serialize/reload the same structure persisted by SaveGame, as if the
	# player continued on another day while visiting the shared room.
	journal=JSON.parse_string(JSON.stringify(journal))
	if slot=="johto_center" and mid.contains("cherrygrove"):
		# The mobile battle room was another dead end; its doors do not
		# overwrite the original city's shared stair reference.
		if not walk(Vector2i(4,1)) or not current.ends_with("johto_mobile_battle_room"):return fail("cannot visit mobile battle room")
		if not walk(Vector2i(2,3)) or not current.ends_with("johto_pokecenter_2f"):return fail("cannot leave mobile battle room")
	var back: Vector2i
	match slot:
		"johto_center":back=Vector2i(0,3)
		"johto_ship":back=Vector2i(12,0)
		"johto_lift":back=Vector2i(1,1)
		"sevii_lift":back=Vector2i(2,5)
	if not walk(back):return false
	if current!=str(expected.region)+"/"+str(expected.map) or world.player_pos!=vec(expected.at):
		return fail("wrong remembered destination from "+r+"/"+mid)
	return true

func run() -> void:
	db=root.get_node("Data")
	atlas=db.load_json("res://content/world_destinations.json")
	world=Walker.new()
	root.add_child(world)
	world.warp_ready.connect(load_at)
	var count := check_graph()
	var probes := 0
	if not failed:
		for slot in ["johto_center","johto_lift","johto_ship","sevii_lift"]:
			if not originals.has(slot):
				fail("unregistered shared passage "+slot)
				break
			for entry in originals[slot]:
				if not probe(entry,slot):break
				probes+=1
			if failed:break
	if not failed:
		journal.clear()
		load_at({"region":"sevii","map":"trainer_tower_elevator","at":[2,4]})
		if not walk(Vector2i(0,2)) or current!="sevii/trainer_tower_lobby":
			fail("trainer tower control panel cannot recall lobby")
	if not failed:
		journal.clear()
		load_at({"region":"johto","map":"johto_pokecenter_2f","at":[1,3]})
		if not walk(Vector2i(0,3)) or not current.ends_with("johto_cherrygrove_pokecenter_1f"):
			fail("old save upstairs has no default return")
	print("WORLD RETURNS ","FAIL" if failed else "PASS"," bedroom_out_and_back=",count," dynamic_origins=",probes)
	quit(1 if failed else 0)
