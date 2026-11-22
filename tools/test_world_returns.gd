extends "test_world_walks.gd"
## Verify the entire directed map registry from the new-game bedroom and replay
## dynamic centre stairs, ferry voyages and elevators through World.step.

const Field := preload("res://core/emerald_field.gd")
const Passage := preload("res://core/passage_memory.gd")
var journal := {}
var originals := {}

func load_at(target: Dictionary) -> void:
	var from: String=world.map_data.get("id","") if is_instance_valid(world) else ""
	var dest := preload("res://core/johto_postgame.gd").destination(from,target,journal)
	dest=preload("res://core/hgss_field.gd").merged_destination(Passage.resolve(journal,dest))
	var k := str(dest.region)+"/"+str(dest.map)
	if not places.has(k):
		places[k]=db.load_map(str(dest.region),str(dest.map))
	super.load_at(dest)

func check_graph() -> int:
	const Passages=preload("res://core/world_passages.gd")
	var rooms:=Passages.maps(db)
	var graph:=Passages.graph(rooms)
	originals=graph.records
	for room in rooms:
		var map: Dictionary=room.m
		var key:="%s/%s"%[room.rid,room.mid]
		if not map.has("hgss"):
			var field:=Field.plan_for(map)
			if field.is_empty():
				fail("missing Emerald scenery for "+key)
				return 0
			var bytes:=int(field.s[0])*int(field.s[1])*2
			for layer in ["t","a"]:
				if layer=="a" and not field.has(layer): continue
				if Marshalls.base64_to_raw(field[layer]).decompress(bytes,FileAccess.COMPRESSION_DEFLATE).size()!=bytes:
					fail("invalid Emerald tile layer "+key+" "+layer)
					return 0
		else:
			var directory:="res://assets/johto_gba/maps/%s/"%room.mid
			var art:=preload("res://core/hgss_field.gd").read_file(directory+"index.json")
			if art.get("pieces",[]).is_empty():
				fail("missing GBA scenery for "+key)
				return 0
			for piece in art.pieces:
				var path:String=piece.png
				if not path.begins_with("res://"): path=directory+path
				if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
					fail("missing GBA image "+path)
					return 0
	var bedroom:="kanto/pallet_town_players_house_2f"
	for links in [graph.forward,graph.reverse]:
		var seen:=Passages.reachable(bedroom,links)
		if seen.size()!=rooms.size():
			fail("bedroom directed reach %d/%d; missing %s"%[seen.size(),rooms.size(),links.keys().filter(func(k):return not seen.has(k))])
			return 0
	return rooms.size()

func approach(w: Dictionary) -> bool:
	var at := vec(w.at)
	for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var beside: Vector2i=at-direction
		if not world.can_enter(beside,direction) or not world.warp_at(beside).is_empty(): continue
		if w.get("trigger","")=="door" and direction!=Vector2i.UP: continue
		world.warp_to(beside)
		world.finish_walk()
		return walk(at)
	return fail("no approach to %s %s"%[current,at])

func probe(entry: Array, slot: String) -> bool:
	var source={"region":entry[0],"map":entry[1],"at":entry[2].at,"hgss":true}
	load_at(source)
	var w:Dictionary=entry[2]
	var expected:Dictionary=w.to.remember_passage.destination
	if not approach(w) or current!=entry[0]+"/"+str(w.to.map):
		return fail("did not enter shared room from "+str(entry[1]))
	journal=JSON.parse_string(JSON.stringify(journal))
	if slot=="johto_center" and str(entry[1]).contains("cherrygrove"):
		if not walk(Vector2i(4,1)) or not current.ends_with("johto_mobile_battle_room"):return fail("cannot visit mobile battle room")
		if not walk(Vector2i(2,3)) or not current.ends_with("johto_pokecenter_2f"):return fail("cannot leave mobile battle room")
	var exits:Array=world.map_data.warps.filter(func(row):return row.to.get("recall_passage","")==slot)
	if exits.is_empty():return fail("missing return "+slot+" from "+current)
	var departure:=vec(exits[0].at)
	if departure==world.player_pos and exits[0].get("trigger","step")=="step":
		for d in DIR:
			var side: Vector2i=departure+d
			if world.can_step(d) and world.warp_at(side).is_empty():
				if not walk(side):return false
				break
	if not walk(departure):return false
	var pos:=vec(expected.at)
	if not expected.get("hgss",false):pos=preload("res://core/hgss_field.gd").position(world.map_data,pos)
	if current!=str(expected.region)+"/"+str(expected.map) or world.player_pos!=pos:
		return fail("wrong remembered destination from %s: %s %s, expected %s %s"%[entry[1],current,world.player_pos,expected.map,pos])
	return true

func ship() -> bool:
	var ship_id:="johto_fast_ship_1f"
	for west in [false,true]:
		var from:="johto_vermilion_port" if west else "johto_olivine_port"
		var to:="johto_olivine_port" if west else "johto_vermilion_port"
		load_at({"region":"johto","map":from,"at":[0,0],"hgss":true})
		var quay:Array=world.map_data.warps.filter(func(w): return w.to.map==ship_id)
		journal["j2_westbound"]=west
		if quay.is_empty() or not approach(quay[0]) or current!="johto/"+ship_id:return fail("cannot board at "+from)
		journal=JSON.parse_string(JSON.stringify(journal))
		var exit:Array=world.map_data.warps.filter(func(w):return w.to.map in ["johto_vermilion_port","johto_olivine_port"])
		if not walk(vec(exit[0].at)) or current!="johto/"+to:return fail("cannot disembark at "+to)
	return true

func ruins() -> bool:
	for wing in ["kabuto","omanyte","aerodactyl","ho_oh"]:
		var item_room:="johto_ruins_of_alph_%s_item_room"%wing
		var gallery:="johto_ruins_of_alph_%s_word_room"%wing
		load_at({"region":"johto","map":item_room,"hgss":true,"at":[6,5]})
		var pits:Array=world.map_data.warps.filter(func(w):return w.to.map==gallery)
		if pits.size()!=1 or not approach(pits[0]) or current!="johto/"+gallery:
			return fail("no drop to "+gallery)
		var landing:Vector2i=world.player_pos
		if not world.can_enter(landing,Vector2i.DOWN):return fail("blocked scripted landing in "+gallery)
		var falls:Array=world.map_data.warps.filter(func(w):return w.to.map=="johto_ruins_of_alph_inner_chamber")
		if falls.size()!=1 or not walk(vec(falls[0].at)) or current!="johto/johto_ruins_of_alph_inner_chamber":
			return fail("no walking route from inscription room to hall "+gallery)
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
		for slot in originals:
			for entry in originals[slot]:
				if not probe(entry,slot):break
				probes+=1
			if failed:break
	if not failed and ship(): probes+=2
	if not failed: ruins()
	if not failed:
		journal.clear()
		load_at({"region":"sevii","map":"trainer_tower_elevator","at":[2,4]})
		walk(Vector2i(0,3))
		world.facing = "up"
		world.step_interact()
		if not world.pending_warp.is_empty(): load_at(world.pending_warp)
		if current!="sevii/trainer_tower_lobby":
			fail("trainer tower control panel cannot recall lobby")
	if not failed:
		journal.clear()
		load_at({"region":"johto","map":"johto_pokecenter_2f","at":[1,3]})
		if not walk(Vector2i(0,3)) or not current.ends_with("johto_cherrygrove_pokecenter_1f"):
			fail("old save upstairs has no default return")
	print("WORLD RETURNS ","FAIL" if failed else "PASS"," bedroom_out_and_back=",count," dynamic_origins=",probes)
	quit(1 if failed else 0)
