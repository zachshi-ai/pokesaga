extends RefCounted
## Native DS land sections, warp anchors, and legacy campaign locations.
const ROOT := "res://content/hgss/"
const ART := "res://assets/johto_gba/maps/"
const WATERS := [16,17,18,19,20,21,25,42,80,81,82,83,115,120,124]
const ENCOUNTERS := [2,3,5,8,11,37,114,119,123,166,167]
static var bindings: Dictionary = {}
static var merged: Dictionary = {}

static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func vec(at: Array) -> Vector2i:
	return Vector2i(int(at[0]),int(at[1]))

static func merged_destination(target: Dictionary) -> Dictionary:
	if target.get("region","")!="johto": return target
	if merged.is_empty(): merged=read_file(ROOT+"merged_rooms.json")
	var source: Dictionary=merged.get(target.get("map",""),{})
	if source.is_empty(): return target
	var size:=vec(source.size)
	var old:=vec(target.get("at",[0,0])).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var native:=target.duplicate()
	native.map=source.map
	native.at=source.positions[old.y*size.x+old.x]
	native.hgss=true
	return native

static var encounters: Dictionary = {}

static func period() -> String:
	var hour := int(Time.get_time_dict_from_system().hour)
	return "morn" if hour>=4 and hour<10 else ("day" if hour>=10 and hour<20 else "nite")

static func install(data: Dictionary, mid: String) -> Dictionary:
	var field := read_file(ROOT+"maps/"+mid+".json")
	if field.is_empty():
		return data
	if data.is_empty() and field.has("encounter_bank"):
		if encounters.is_empty(): encounters=read_file(ROOT+"wild.json")
		var bank: Dictionary = encounters.get(field.encounter_bank,{})
		if not bank.is_empty():
			data["hgss_encounters"]=bank.land
			data["encounters"]=bank.land[period()]
			data["encounter_rate"]=bank.land_rate
			data["water_encounters"]=bank.surf
			data["water_encounter_rate"]=bank.surf_rate
	data["hgss"] = field
	data["name"] = field.name
	data["emerald"] = "hgss_" + str(field.header)
	data["size"] = field.size
	data["spawn"] = field.spawn
	data["warps"] = field.warps
	if field.has("lift_stops"): data["lift_stops"] = field.lift_stops
	field["words"] = Marshalls.base64_to_raw(field.terrain)
	field.erase("terrain")
	field["conversion"] = Marshalls.base64_to_raw(field.legacy_xy)
	field.erase("legacy_xy")
	if bindings.is_empty():
		bindings = read_file(ROOT+"anchors.json").get("maps",{})
	field["anchors"] = bindings.get(mid,{})
	var obj := []
	for original in data.get("objects",[]):
		if field.has("lift_panel") and original.get("kind","")=="elevator": continue
		var row: Dictionary = original.duplicate(true)
		row["legacy_at"] = row.at
		var entry: Dictionary = field.anchors.get("objects",{}).get(row.get("source_script",row.get("flag","")),{})
		if entry.get("header",field.header) != field.header:
			continue
		var p := position(data,vec(row.at)) if entry.is_empty() else vec(entry.at)
		if field.get("native_objects",{}).has(row.get("source_script","")):
			p=vec(field.native_objects[row.source_script])
		row.at = [p.x,p.y]
		if entry.has("sprite"): row["hgss_sprite"] = entry.sprite
		obj.append(row)
	if field.has("lift_panel"):
		obj.append({"kind":"elevator","at":field.lift_panel,"sprite":"sign","text":"电梯"})
	if mid=="johto_players_house_2f":
		obj.append({"kind":"wall_map","at":[5,3],"native_fixture":true})
	obj.append_array(field.get("extra_objects",[]))
	if field.header=="MAP_ICE_PATH_B1F":
		data["npcs"]=data.get("npcs",[]).filter(func(n):return n.get("name","")!="岩石")
	elif field.header=="MAP_ICE_PATH_B3F":
		data["npcs"]=data.get("npcs",[]).filter(func(n):return vec(n.at)!=Vector2i(3,3) or n.name!="居民")
	data["objects"] = obj
	return data

static func position(data: Dictionary, legacy: Vector2i) -> Vector2i:
	if not data.has("hgss"):
		return legacy
	var f: Dictionary = data.hgss
	var anchor: Dictionary = f.anchors.get("sites",{}).get("%d,%d" % [legacy.x,legacy.y],{})
	if not anchor.is_empty() and anchor.get("header",f.header) == f.header:
		return vec(anchor.at)
	var size := vec(f.legacy_size)
	if legacy.x < 0 or legacy.y < 0 or legacy.x >= size.x or legacy.y >= size.y:
		return vec(f.spawn)
	var offset := (size.x*legacy.y+legacy.x)*4
	var xy: PackedByteArray = f.conversion
	return Vector2i(xy.decode_u16(offset),xy.decode_u16(offset+2))

static func saved_position(world, old: Vector2i, was_surfing: bool) -> Vector2i:
	var field: Dictionary=world.map_data.hgss
	var ground:=position(world.map_data,old)
	if not was_surfing and world.can_enter(ground,Vector2i.ZERO,true): return ground
	var target:=ground
	if was_surfing:
		# Landmarks are on the shore. Preserve the relative position offshore when
		# the old save was surfing, including bodies of water with no landmarks.
		var old_size:=vec(field.legacy_size)
		if old_size.x>0 and old_size.y>0:
			target=Vector2i(Vector2(old)*Vector2(world.tile_size)/Vector2(old_size))
	var answer:=ground
	var minimum:=INF
	var doors: Dictionary=world._warp_cells
	var old_mode: bool=world.surfing
	world.surfing=was_surfing
	for y in world.tile_size.y:
		for x in world.tile_size.x:
			var at:=Vector2i(x,y)
			var distance:=target.distance_squared_to(at)
			if distance>=minimum or doors.has(at) or world.is_water(at)!=was_surfing: continue
			if not world.can_enter(at,Vector2i.ZERO,true): continue
			minimum=distance
			answer=at
	world.surfing=old_mode
	return answer

static func roster(data: Dictionary, rows: Array) -> Array:
	if not data.has("hgss"): return rows
	var f: Dictionary = data.hgss
	var output := []
	var occupied := {}
	var exits := {}
	for w in data.warps: exits[vec(w.at)] = true
	for row in rows:
		var npc: Dictionary = row.duplicate()
		var key := "%d,%d" % npc.at
		var site: Dictionary = f.anchors.get("sites",{}).get(key,{})
		var entry: Dictionary = npc.get("native_anchor",f.anchors.get("roles",{}).get(npc.get("role",""),site))
		if entry.get("header",f.header) != f.header: continue
		var at := position(data,vec(npc.at)) if entry.is_empty() else vec(entry.at)
		if npc.get("hgss_native",false): at=vec(npc.at)
		if data.id=="johto_new_bark_town" and npc.get("transit",false): at=Vector2i(16,14)
		if npc.get("role","")=="j_farfetchd" and key!="7,15":
			at = position(data,vec(npc.at))
		if occupied.has(at) or exits.has(at) or (entry.is_empty() and word(f,at)&0x8000):
			at = adjacent_floor(f,at,occupied,exits)
		if at.x < 0: continue
		occupied[at]=true
		npc["legacy_at"]=npc.at
		npc.at=[at.x,at.y]
		if entry.has("sprite"): npc["hgss_sprite"]=entry.sprite
		if entry.has("facing"): npc["hgss_facing"]=entry.facing
		output.append(npc)
	return output

static func word(field: Dictionary, tile: Vector2i) -> int:
	var size := vec(field.size)
	if tile.x<0 or tile.y<0 or tile.x>=size.x or tile.y>=size.y: return 0x8000
	var words: PackedByteArray = field.words
	return words.decode_u16((tile.y*size.x+tile.x)*2)

static func adjacent_floor(f: Dictionary, at: Vector2i, occupied: Dictionary, exits: Dictionary) -> Vector2i:
	for radius in range(1,maxi(int(f.size[0]),int(f.size[1]))):
		for dy in range(-radius,radius+1):
			var dx := radius-absi(dy)
			for x in [at.x-dx,at.x+dx]:
				var q := Vector2i(x,at.y+dy)
				var value := word(f,q)
				if not (value & 0x8000) and (value & 255) not in WATERS and not exits.has(q) and not occupied.has(q):
					return q
	return Vector2i(-1,-1)

static func grids(f: Dictionary) -> Dictionary:
	var size := vec(f.size)
	var layers := {"collision":[],"grass":[],"water":[],"ledge":[],"slide":[],"whirl":[],"climb":[],"waterfall":[],"counter":[]}
	for y in size.y:
		var line := {}
		for name in layers: line[name]=[]
		for x in size.x:
			var value := word(f,Vector2i(x,y))
			var b := value & 255
			line.collision.append(int((value & 0x8000)!=0))
			line.grass.append(int(b in ENCOUNTERS))
			# Native traversal effects own the blocked water face and its landing lip.
			var cascade := b==19 or (b==34 and (word(f,Vector2i(x,y+1)) & 255)==19)
			line.water.append(int(cascade or b==17 or (b in WATERS and (value & 0x8000)==0)))
			line.ledge.append(int({56:4,57:8,58:1,59:2}.get(b,0)))
			line.slide.append(255 if b==32 else int({64:4,65:8,66:1,67:2}.get(b,0)))
			line.whirl.append(int(b==17))
			line.waterfall.append(int(cascade))
			line.climb.append(int(b in [75,76]))
			line.counter.append(int(b==128))
		for name in layers: layers[name].append(line[name])
	layers["size"]=f.size
	return layers

static func draw(world) -> void:
	var field: Dictionary = world.map_data.hgss
	var directory := ART+str(world.map_data.id)+"/"
	if not field.has("art"):
		field["art"] = read_file(directory+"index.json")
	var layout: Dictionary = field.art
	if layout.is_empty():
		push_error("Missing GBA artwork for "+str(world.map_data.id))
		return
	for piece in layout.pieces:
		var path: String = piece.png
		var sprite := Sprite2D.new()
		if not path.begins_with("res://"): path=directory+path
		if ResourceLoader.exists(path):
			sprite.texture=load(path)
		elif FileAccess.file_exists(path):
			var bitmap := Image.load_from_file(path)
			if bitmap != null and not bitmap.is_empty(): sprite.texture=ImageTexture.create_from_image(bitmap)
		else:
			push_error("Missing GBA image "+path)
		if sprite.texture==null:
			sprite.free()
			continue
		sprite.centered = false
		sprite.position = Vector2(vec(piece.at))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if piece.has("sort_y"): sprite.z_index = world.Z_ACTOR + floori(float(piece.sort_y)/world.TILE)*2+1
		world.add_child(sprite)
		world._tile_nodes.append(sprite)

static func camera_bounds(data: Dictionary, screen: Vector2i) -> Rect2i:
	var b: Array=data.hgss.get("art",{}).get("bounds",[])
	if b.size()!=4:
		return Rect2i(Vector2i.ZERO,vec(data.size)*16)
	var start:=Vector2i(int(b[0]),int(b[1]))
	var end:=Vector2i(int(b[2]),int(b[3]))
	var size: Vector2i=(end-start).max(screen)
	return Rect2i((start+end-size)/2,size)

static func source_rows(source: Dictionary, flags: Dictionary) -> Array:
	var rows := preload("res://core/johto_campaign.gd").roster(source,flags)
	rows = preload("res://core/johto_items.gd").roster(source,flags,rows)
	return preload("res://core/johto_postgame.gd").roster(source,flags,rows)

static var foreign_maps: Dictionary = {}
static var original_maps: Dictionary = {}

static func foreign_actors(data: Dictionary, flags: Dictionary) -> Array:
	if bindings.is_empty(): return []
	if foreign_maps.is_empty():
		for mid: String in bindings:
			var record: Dictionary = bindings[mid]
			for role: String in record.get("roles",{}):
				var header: String = record.roles[role].get("header","")
				if header == "": continue
				if not foreign_maps.has(header): foreign_maps[header]={}
				foreign_maps[header][mid]=true
	var result := []
	for mid: String in foreign_maps.get(data.hgss.header,{}):
		if mid==data.id: continue
		if not original_maps.has(mid):
			var source := read_file("res://content/regions/johto/maps/"+mid+".json")
			source["region"]="johto"
			source["id"]=mid
			original_maps[mid]=source
		for row in source_rows(original_maps[mid],flags):
			var role: String = row.get("role","")
			var entry: Dictionary = bindings[mid].get("roles",{}).get(role,{})
			if entry.get("header","") == data.hgss.header:
				var npc: Dictionary = row.duplicate()
				npc["story_map"]=mid
				npc["native_anchor"]=entry
				result.append(npc)
	return result

static func trigger_match(f: Dictionary, trigger: Dictionary, point: Vector2i) -> bool:
	var coords: Array = trigger.get("area",[])
	if coords.size()!=4:
		if not trigger.has("at"): return true
		var at: Array=trigger.at
		coords=[at[0],at[1],int(at[0])+1,int(at[1])+1]
	var sites: Dictionary = f.anchors.get("triggers",{})
	for y in range(int(coords[1]),int(coords[3])):
		for x in range(int(coords[0]),int(coords[2])):
			var site: Dictionary = sites.get("%d,%d" % [x,y],{})
			if not site.is_empty():
				if site.get("header",f.header)!=f.header: continue
				if Rect2i(vec(site.at),vec(site.get("size",[1,1]))).has_point(point): return true
			elif position({"hgss":f},Vector2i(x,y))==point:
				return true
	return false


static func foreign_step(f: Dictionary, tr: Dictionary, point: Vector2i) -> bool:
	var source: Dictionary = bindings.get(tr.get("map",""),{}).get("triggers",{})
	var area: Array = tr.get("area",[])
	if source.is_empty() or area.size()!=4: return false
	for y in range(int(area[1]),int(area[3])):
		for x in range(int(area[0]),int(area[2])):
			var anchor: Dictionary = source.get("%d,%d"%[x,y],{})
			if anchor.get("header","")==f.header and Rect2i(vec(anchor.at),vec(anchor.get("size",[1,1]))).has_point(point): return true
	return false
