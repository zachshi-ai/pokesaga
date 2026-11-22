extends RefCounted
## Enumerate the same map IDs, doors and conditional destinations used by World.
const Field := preload("res://core/hgss_field.gd")
const Postgame := preload("res://core/johto_postgame.gd")

static func maps(db) -> Array:
	var rooms := []
	for rid in DirAccess.get_directories_at("res://content/regions"):
		for mid in db.load_region(rid).get("map_ids",[]):
			rooms.append({"rid":rid, "mid":mid, "m":db.load_map(rid,mid)})
	return rooms

static func active(map: Dictionary) -> Array:
	var cells := {}
	for warp in map.get("warps",[]):
		var p := Field.vec(warp.at)
		var trigger: String=warp.get("trigger","")
		# At Emerald map corners each outward direction connects to its own neighbor.
		var slot: Variant=[p,trigger] if (map.has("emerald_original") or map.has("platinum_native") or map.has("unova_native")) and trigger in ["up","down","left","right"] else p
		if not cells.has(slot):
			cells[slot]=warp
	return cells.values()

static func unova_terminus(current: Dictionary, target: Dictionary, era: String) -> Dictionary:
	if target.get("region","")=="unova" and era=="bw" and "_pass_" in str(current.id):
		var town: String={"unova_aspertia":"unova_nuvema","unova_virbank":"unova_castelia"}.get(target.map,target.map)
		return target.merged({"map":town},true)
	return target

static func atlas_return(current: Dictionary, target: Dictionary, native:Dictionary) -> Dictionary:
	if not native.has("platinum_native") and not native.has("unova_native"):return target
	for warp in native.warps:
		if warp.get("atlas","")=="world" and warp.to.map==current.id and warp.to.region==current.region:
			var facing: String={"up":"down","down":"up","left":"right","right":"left"}.get(warp.trigger,"down")
			return target.merged({"at":warp.at,"facing":facing,"unova_native" if native.has("unova_native") else "platinum_native":true},true)
	return target

static func key(target: Dictionary) -> String:
	return "%s/%s" % [target.region,target.map]

static func graph(rooms: Array) -> Dictionary:
	var links := {}
	var inward := {}
	var entrances := {}
	var recorded := {}
	var arrivals := {}
	var native_spawns := {}
	var technical := {}
	var native_maps := {}
	for room in rooms:
		if room.m.has("platinum_native") or room.m.has("unova_native"):
			native_spawns[room.mid]=room.m.spawn
			native_maps[room.mid]=room.m
			if room.m.get("platinum_technical",false) or room.m.get("unova_technical",false):
				technical[str(room.rid)+"/"+str(room.mid)]=true
	for room in rooms:
		var source := "%s/%s" % [room.rid,room.mid]
		var targets: Array = room.m.get("lift_stops",[]).duplicate()
		if room.m.has("emerald_original"):
			for row in preload("res://core/hoenn_field.gd").travel().passages.get(room.mid,[]):
				targets.append(row.target)
		for warp in active(room.m):
			var t: Dictionary=unova_terminus(room.m,warp.to,"b2" if native_maps.has("unova_aspertia") else "bw") if warp.get("atlas","")=="world" else warp.to
			if warp.get("atlas","")=="world" and t.region in ["sinnoh","unova"] and native_maps.has(t.map):t=atlas_return(room.m,t,native_maps[t.map])
			if t.has("remember_passage"):
				var slot: String=t.remember_passage.key
				if not recorded.has(slot): recorded[slot]=[]
				recorded[slot].append([room.rid,room.mid,warp])
			if t.has("recall_passage"):
				var slot: String=t.recall_passage
				if not entrances.has(slot): entrances[slot]=[]
				entrances[slot].append(source)
			for alternate in t.get("platinum_alternates",{}).values():targets.append(alternate)
			targets.append(Postgame.destination(room.mid,t,{},{"weekday":Time.WEEKDAY_MONDAY,"hour":21}))
			targets.append(Postgame.destination(room.mid,t,{"j2_westbound":true,"j2_power":true,"johto_champion":true},{"weekday":Time.WEEKDAY_SUNDAY,"hour":10}))
		links[source]={}
		for field in ["platinum_script_links","unova_script_links"]:
			for dest_id in room.m.get(field,[]): links[source][str(room.rid)+"/"+str(dest_id)]=true
		for target in targets:
			var dest:=Field.merged_destination(target)
			links[source][key(dest)]=true
			if not arrivals.has(key(dest)): arrivals[key(dest)]={}
			var at: Array=dest.at
			if dest.region in ["sinnoh","unova"] and native_spawns.has(dest.map) and not (dest.get("platinum_native",false) or dest.get("unova_native",false)):
				at=native_spawns[dest.map]
			arrivals[key(dest)][[at,dest.get("hgss",false)]]=true
	for slot in entrances:
		for source in entrances[slot]:
			for entry in recorded.get(slot,[]):
				var dest:=Field.merged_destination(entry[2].to.remember_passage.destination)
				links[source][key(dest)]=true
				if not arrivals.has(key(dest)): arrivals[key(dest)]={}
				arrivals[key(dest)][[dest.at,dest.get("hgss",false)]]=true
	for source in links:
		if not inward.has(source): inward[source]={}
		for target in links[source]:
			if not inward.has(target): inward[target]={}
			inward[target][source]=true
	return {"forward":links,"reverse":inward,"records":recorded,"arrivals":arrivals,"technical":technical}

static func reachable(start: String, links: Dictionary) -> Dictionary:
	var seen := {}
	var queue := [start]
	while not queue.is_empty():
		var current: String=queue.pop_back()
		if seen.has(current): continue
		seen[current]=true
		for dst in links.get(current,{}):
			if not seen.has(dst): queue.append(dst)
	return seen
