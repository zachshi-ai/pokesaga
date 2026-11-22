extends RefCounted
## The box offsets, bounce phases, camera bob and braking sequence come from
## pokeemerald src/field_special_scene.c. The long lead-in is shortened for touch play.
const Field := preload("res://core/emerald_field.gd")
const PAN := [0,0,0,0,0,0,0,0,1,2,2,2,2,2,2,-1,-1,-1,0]
const REST := [Vector2(3,3),Vector2(0,-3),Vector2(-3,0)]
const STOP_FRAME := 168
const OPEN_FRAME := 188
const END_FRAME := 210

static func set_door(w,opened: bool) -> void:
	var m: Dictionary=w.map_data.mechanisms
	for field in w._tile_nodes:
		if not field is Field:continue
		for r in m.always if opened else m.closed:
			var p:=Vector2i(r[0],r[1])
			field._set_tile(field.ground,p,int(r[2]))
			if field.above:
				field.above.erase_cell(p)
				if r[3]:field._set_tile(field.above,p,int(r[3]))

static func pose(frame: int, w, boxes: Array, base: Array, camera: Vector2) -> void:
	var is_rolling:=frame<STOP_FRAME
	var pan:=0
	if frame>=100 and is_rolling:
		pan=PAN[clampi(floori(float(frame-100)*PAN.size()/68.0),0,PAN.size()-1)]
	var bob: int=(-1 if frame%120==0 else (1 if frame%10<5 else 0)) if is_rolling else 0
	w.cam.offset=camera+Vector2(pan,bob)
	for i in boxes.size():
		var phase: int=frame+30 if i==0 else frame
		var rem:=posmod(phase-30,78)
		var bounce:=0.0
		if is_rolling and rem<8:
			bounce=-roundf(sin(float(rem+1)/9.0*PI)*(2.0 if i==1 else 4.0))
		boxes[i].position=Vector2(base[i])+Vector2(-pan,bounce)
	w.set_meta("hoenn_truck_frame",frame)

static func play(g) -> void:
	var w=g.world
	if w.map_data.get("source_id","")!="MAP_INSIDE_OF_TRUCK":return
	var boxes: Array=[]
	var origins: Array=[]
	for i in w.npcs.size():
		if w.npcs[i].get("source_gfx","")=="OBJ_EVENT_GFX_MOVING_BOX":
			var sprite: Sprite2D=w._npc_nodes[2*i+1]
			boxes.append(sprite)
			origins.append(sprite.position)
	var camera: Vector2=w.cam.offset
	var tint: Color=w.modulate
	set_door(w,false)
	var opened:=false
	var elapsed:=0.0
	while elapsed*60.0<END_FRAME:
		if not is_instance_valid(w) or w.map_data.get("source_id","")!="MAP_INSIDE_OF_TRUCK":return
		var frame:=int(elapsed*60.0)
		pose(frame,w,boxes,origins,camera)
		w.modulate=tint*Color(1,1,1,clampf(0.35+elapsed*2.6,0.35,1.0))
		if not opened and frame>=OPEN_FRAME:
			set_door(w,true)
			g.snd.play_sfx("door")
			opened=true
		await g.get_tree().process_frame
		if not is_instance_valid(g) or not is_instance_valid(w):return
		elapsed+=clampf(g.get_process_delta_time(),1.0/240.0,0.1)
	if not opened:set_door(w,true)
	pose(END_FRAME,w,boxes,origins,camera)
	w.modulate=tint
	w.cam.offset=camera
