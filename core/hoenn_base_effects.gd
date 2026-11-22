extends RefCounted

static var animations: Dictionary = {}
const POP_SOUNDS := {"RED_BALLOON":"balloon_red","BLUE_BALLOON":"balloon_blue","YELLOW_BALLOON":"balloon_yellow","MUD_BALL":"mud_ball"}
const NOTE_SOUNDS := {"C_LOW_NOTE_MAT":"note_c","D_NOTE_MAT":"note_d","E_NOTE_MAT":"note_e","F_NOTE_MAT":"note_f","G_NOTE_MAT":"note_g","A_NOTE_MAT":"note_a","B_NOTE_MAT":"note_b","C_HIGH_NOTE_MAT":"note_c_high"}

static func at(w, p: Vector2i) -> Dictionary:
	var base: Dictionary = w.map_data.get("mechanisms",{}).get("base",{})
	if base.is_empty():return {}
	for item in w.taken.get("h_base_furniture",[]):
		var entry: Dictionary = base.furniture[item.id]
		if not entry.has("surface"):continue
		var origin := Vector2i(item.at[0],item.at[1])
		var size := Vector2i(entry.size[0],entry.size[1])
		if Rect2i(origin,size).has_point(p):
			var local := p - origin
			return {"id":item.id,"key":"%s/%d/%d"%[item.id,origin.x,origin.y],"surface":int(entry.surface[local.y*size.x+local.x])}
	return {}

static func allows(w, p: Vector2i, dir: Vector2i) -> bool:
	if not w.map_data.get("mechanisms",{}).has("base"):return true
	var from: int = at(w,w.player_pos).get("surface",0)
	var to: int = at(w,p).get("surface",0)
	return not (to==185 or blocked(from,dir) or blocked(to,-dir))

static func blocked(surface: int, dir: Vector2i) -> bool:
	match surface:
		52:return dir in [Vector2i.UP,Vector2i.RIGHT]
		53:return dir in [Vector2i.UP,Vector2i.LEFT]
		193:return dir.x!=0
	return false

static func animate(w, item: Dictionary) -> void:
	var state: Dictionary = w.hoenn_local.get_or_add("decor_frames",{})
	if state.has(item.key):return
	if animations.is_empty():animations = JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/base_effects.json"))
	var frames: Array = animations[item.id]
	state[item.key] = 0
	w._rebuild()
	if frames.size()==1:return
	var tween: Tween = w.create_tween()
	for i in range(1,frames.size()):
		tween.tween_interval(7.0/60.0)
		tween.tween_callback(func():
			if is_same(w.hoenn_local.get("decor_frames"),state) and state.has(item.key):
				state[item.key]=i
				w._rebuild())

static func frame(w, item: Dictionary, tiles: Array) -> Array:
	var key := "%s/%d/%d"%[item.id,item.at[0],item.at[1]]
	var index: int = w.hoenn_local.get("decor_frames",{}).get(key,-1)
	if index < 0:return tiles
	return animations[item.id][index]

static func interact(g) -> bool:
	var w=g.world
	if not w.map_data.get("mechanisms",{}).has("base"):return false
	var item := at(w,w.player_pos+w._dir_vec())
	if item.get("surface")!=191:return false
	if not w.hoenn_local.get("decor_frames",{}).has(item.key):
		g.snd.play_sfx("mud_ball")
		animate(w,item)
	return true

static func landed(w) -> void:
	var item := at(w,w.player_pos)
	if item.is_empty():return
	var g=w.get_parent()
	if not g or not g.get("snd"):return
	if POP_SOUNDS.has(item.id) or item.surface==190:
		if not w.hoenn_local.get("decor_frames",{}).has(item.key):
			g.snd.play_sfx(POP_SOUNDS.get(item.id,"breakable_door"))
			animate(w,item)
	elif NOTE_SOUNDS.has(item.id):
		g.snd.play_sfx(NOTE_SOUNDS[item.id])
	elif item.surface==186:
		var sprite := Sprite2D.new()
		sprite.texture=preload("res://assets/hoenn_native/base_sparkle.png")
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.hframes=6
		sprite.z_index=200+w.player_pos.y*2
		sprite.position=Vector2(w.player_pos*16+Vector2i(8,4))
		w.add_child(sprite)
		var shimmer := sprite.create_tween()
		for duration in [8.0/60.0,4.0/60.0]:
			for i in 6:
				shimmer.tween_callback(func():sprite.frame=i)
				shimmer.tween_interval(duration)
		shimmer.tween_callback(sprite.queue_free)
	elif item.surface in [187,188]:
		var local: Dictionary = w.hoenn_local
		local.decor_busy=true
		var action: Tween=w.create_tween()
		if item.surface==187:
			for hop in 2:
				action.tween_callback(func():g.snd.play_sfx("ledge"))
				action.tween_method(func(t:float):
					if is_same(local,w.hoenn_local):
						w.jump_lift=8.0*sin(t*PI)
						w._sync_player(),0.0,1.0,0.32)
		else:
			var face: String=w.facing
			for direction in ["left","right","up","down",face]:
				action.tween_callback(func():
					if is_same(local,w.hoenn_local):
						w.facing=direction
						w._sync_player())
				action.tween_interval(0.09)
		action.tween_callback(func():
			if is_same(local,w.hoenn_local):
				local.erase("decor_busy")
				w.jump_lift=0.0
				w._sync_player()
				if item.surface==188:w.step(-w._dir_vec()))
