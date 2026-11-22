extends RefCounted

const SHAPES := {"l1":[1,1,0,0],"l2":[2,1,0,0],"l3":[1,2,0,0],"l4":[2,2,0,0],"t1":[1,1,1,0],"t2":[2,1,1,0],"t3":[1,2,1,0],"t4":[1,1,2,0]}
const CW := [[0,-1],[1,-2],[0,0],[1,0],[-1,0],[-1,1],[-1,-1],[-2,-1]]
const CCW := [[-1,-1],[-1,-2],[0,-1],[1,-1],[0,0],[0,1],[-1,0],[-2,0]]
const TRAINERS := {"Entrance":"entrance","Speed":"TRAINER_RANDALL","Accuracy":"TRAINER_MARY","Confusion":"TRAINER_PARKER","Defense":"TRAINER_ALEXIA","Recovery":"TRAINER_GEORGE","Strength":"TRAINER_JODY","OHKO":"TRAINER_BERKE"}

static func vec(p: Array) -> Vector2i:
	return Vector2i(p[0],p[1])

static func key(p: Vector2i) -> String:
	return "%d,%d"%[p.x,p.y]

static func open_door(flags: Dictionary, gate: String) -> bool:
	return flags.get("h_badge_5",false) or (flags.get("h_father_challenge",false) if gate=="entrance" else flags.get("h_trainer_"+gate,false))

static func overrides(w, flags: Dictionary) -> Array:
	var m: Dictionary=w.map_data.get("mechanisms",{})
	var out: Array=m.get("always",[]).duplicate()
	if m.has("mirage"):
		w.emerald_water=w.map_data.physics.water.duplicate(true)
		w.emerald_elevation=w.map_data.physics.elevation.duplicate(true)
		w.emerald_grass=w.map_data.physics.get("grass",[]).duplicate(true)
		if w.emerald_grass.is_empty():
			for y in w.tile_size.y:
				var line:=[];line.resize(w.tile_size.x);line.fill(0);w.emerald_grass.append(line)
		if flags.get("h_mirage_today",false):
			out.append_array(m.mirage.tiles)
			for cell in m.mirage.ground:
				w.emerald_water[cell[1]][cell[0]]=cell[2]
				w.emerald_elevation[cell[1]][cell[0]]=cell[3]
				w.emerald_grass[cell[1]][cell[0]]=cell[4]
	if m.has("hill"):
		out.append_array(preload("res://core/hoenn_hill.gd").course(w).get("tiles",[]))
		w.emerald_elevation=w.map_data.physics.elevation.duplicate(true)
		for y in range(5,21):w.emerald_elevation[y].fill(3)
	out.append_array(preload("res://core/hoenn_base.gd").tiles(w,flags))
	if m.has("sealed") and not flags.get(m.sealed.flag,false):out.append_array(m.sealed.closed)
	if m.has("weather_sites"):
		var site: Dictionary=m.weather_sites.get(flags.get("h_weather_site",""),{})
		out.append_array(site.get("tiles",[]))
	if flags.get("h_champion",false): out.append_array(m.get("champion_cave",[]))
	if m.has("trick_buttons"):
		var pressed: Dictionary=w.hoenn_local.get("trick_buttons",{})
		if m.has("trick_shutters"):
			out.append_array(m.trick_shutters[int(w.hoenn_local.get("shutter",0))])
		for i in pressed:out.append_array(m.button_tiles[i])
	if m.has("legends"):
		var fighting: bool=flags.get("h_kyogre",false) and not flags.get("h_peace",false)
		w.emerald_water=w.map_data.physics.water.duplicate(true)
		w.emerald_elevation=w.map_data.physics.elevation.duplicate(true)
		if fighting:
			out.append_array(m.legends)
			for row in m.lake_terrain:
				w.emerald_water[row[1]][row[0]]=row[2]
				w.emerald_elevation[row[1]][row[0]]=row[3]
	if m.has("league_exit") and flags.get(m.league_exit.flag,false):out.append_array(m.league_exit.open)
	if m.has("pillar_door") and flags.get("h_pillar",false):out.append_array(m.pillar_door)
	if m.has("clean") and not flags.get("h_peace",false):out.append_array(m.clean)
	for flag in m.get("ship_locks",{}):
		var door: Dictionary=m.ship_locks[flag]
		out.append_array(door.open if flags.get(flag,false) else door.closed)
	if m.has("power_barriers"):
		out.append_array(m.power_barriers.get(w.hoenn_local.get("power_color",""),[]))
		if flags.get("h_generator_off",false): out.append_array(m.generator_off)
	if m.has("alt"):
		var won: bool=flags.get("h_badge_3",false)
		if won:out.append_array(m.off)
		elif flags.get("h_wattson_alt",false):out.append_array(m.alt)
		for b in m.buttons:
			if won or int(flags.get("h_wattson_switch",0))==int(b[2]):out.append([b[0],b[1],m.pressed[0],m.pressed[1],0])
	if m.has("doors"):
		for room in m.doors:
			if open_door(flags,TRAINERS[room]):out.append_array(m.doors[room])
	if m.has("stairs"):
		var ice: Dictionary=w.hoenn_local.get("ice",{})
		for p: String in ice:
			var coords:=p.split(",")
			out.append([int(coords[0]),int(coords[1]),m.cracked[0],m.cracked[1],0])
		var count:=ice.size()
		for i in m.stairs.size():
			if flags.get("h_badge_8",false) or count>=[7,26,64][floori(i/2.0)]:
				out.append(m.stairs[i])
	return out

static func gate(w, p: Vector2i, d: Vector2i, commit: bool) -> bool:
	var m: Dictionary=w.map_data.get("mechanisms",{})
	if not m.has("gates") or d==Vector2i.ZERO:return true
	var face: String={Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}.get(d,"")
	if face=="":return false
	for i in m.gates.size():
		var g: Array=m.gates[i]
		var pivot:=Vector2i(g[0],g[1])
		var delta:=p-pivot+Vector2i(2,2)
		if delta.x<0 or delta.x>3 or delta.y<0 or delta.y>3:continue
		var info: Array=m.rotation[face][delta.y*4+delta.x]
		if info.is_empty():continue
		var angle:=int(w.hoenn_local.get(str(i),g[3]))
		var arms: Array=SHAPES[g[2]]
		if arms[posmod(int(info[1])-angle,4)]<=int(info[2]):continue
		var sweep: Array=CW if int(info[0])>0 else CCW
		for arm in 4:
			for index in int(arms[arm]):
				var tile:=pivot+vec(sweep[2*posmod(angle+arm,4)+index])
				if w.blocked_by_terrain(tile):return false
		if commit:
			w.hoenn_local[str(i)]=posmod(angle+int(info[0]),4)
			w._rebuild()
		return true
	return true

static func draw(layer: Node2D,w) -> void:
	preload("res://core/hoenn_base.gd").draw(layer,w)
	var m: Dictionary=w.map_data.get("mechanisms",{})
	for i in m.get("gates",[]).size():
		var g: Array=m.gates[i]
		var sprite:=Sprite2D.new()
		sprite.texture=load("res://assets/hoenn_native/%s.png"%g[2])
		sprite.position=Vector2(float(g[0])*16,float(g[1])*16)
		sprite.rotation=float(w.hoenn_local.get(str(i),g[3]))*PI*0.5
		sprite.z_index=100+int(g[1])*2
		layer.add_child(sprite)

static func adjust_actors(w, actors: Array) -> void:
	if w.map_data.get("mechanisms",{}).has("hill") and w.taken.has("h_hill"):
		actors.append_array(preload("res://core/hoenn_hill.gd").course(w).get("actors",[]).duplicate(true))
	preload("res://core/emerald_legends.gd").positions(w,actors)
	var positions: Dictionary=w.hoenn_local.get("positions",{})
	for n in actors:
		if positions.has(str(n.get("local_id",0))):
			var saved: Array=positions[str(n.local_id)]
			n.at=saved[0]
			n.facing=saved[1]

static func landed(w) -> void:
	if w.map_data.mechanisms.has("base"):preload("res://core/hoenn_base_effects.gd").landed(w)
	var m: Dictionary=w.map_data.get("mechanisms",{})
	var p: Vector2i=w.player_pos
	var point:=key(p)
	if m.get("trick_buttons",{}).has(point):
		var button:=str(int(m.trick_buttons[point]))
		var pressed: Dictionary=w.hoenn_local.get_or_add("trick_buttons",{})
		if not pressed.has(button):
			if m.has("trick_shutters"):
				pressed.clear()
				w.hoenn_local.shutter=1-int(w.hoenn_local.get("shutter",0))
			pressed[button]=true
			w._rebuild()
	var power_switch: String=m.get("power_switches",{}).get(point,"")
	if power_switch in ["Blue","Green"] and w.hoenn_local.get("power_color","")!=power_switch:
		w.hoenn_local.power_color=power_switch
		w._rebuild()
	for b in m.get("buttons",[]):
		if vec(b)==p and not w.taken.get("h_badge_3",false) and int(w.taken.get("h_wattson_switch",0))!=int(b[2]):
			w.taken.h_wattson_switch=int(b[2])
			w.taken.h_wattson_alt=not w.taken.get("h_wattson_alt",false)
			w._rebuild()
	if m.has("stairs") and preload("res://core/hoenn_field.gd").behavior(w.map_data,p)==0x26 and not w.taken.get("h_badge_8",false):
		var ice: Dictionary=w.hoenn_local.get("ice",{})
		if ice.has(point):
			w._queue_passage({"to":{"region":"hoenn","map":"em_sootopolis_city_gym_b1f","at":[p.x,p.y],"hoenn_native":true}})
		else:
			ice[point]=true
			w.hoenn_local.ice=ice
			w._rebuild()
	if m.get("switches",{}).has(point):
		var positions: Dictionary=w.hoenn_local.get("positions",{})
		var dirs: Array=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
		var faces:=["right","down","left","up"]
		for n in w.npcs:
			var a:=vec(n.at)
			var tile:=int(m.arrows.get(key(a),-1))
			if tile<0 or (tile>>3)!=int(m.switches[point]) or (tile%8)>3:continue
			a+=Vector2i(dirs[tile%8])
			var next:=int(m.arrows.get(key(a),tile))%8
			var face:=str(n.get("facing","down"))
			if next<4:face=faces[posmod(faces.find(face)+next-tile%8,4)]
			n.at=[a.x,a.y]
			n.facing=face
			positions[str(n.local_id)]=[n.at,face]
		w.hoenn_local.positions=positions
		w._draw_npcs()
