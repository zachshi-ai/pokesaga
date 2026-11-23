extends Node2D
## Fixed field markings for field walkways, script-operated lifts and doorways.
const FONT=preload("res://assets/fonts/field-sans.otf")
var world
var exits: Array=[]
var nearby: Dictionary={}
var last:=Vector2i(-9999,-9999)
var show_label:=true

func setup(field, passages: Array) -> void:
	world=field
	z_index=1001 if field.map_data.get("alola_native",false) else 91
	for p in passages:
		if p.has("kalos_label") or p.has("alola_label"):exits.append(p)
	queue_redraw()

func _process(_dt:float) -> void:
	if world==null:return
	var next_label: bool=world.get_parent().get("panel_open")==0
	if next_label!=show_label:
		show_label=next_label
		queue_redraw()
	if world.player_pos==last:return
	last=world.player_pos
	nearby={}
	var best:=4.01
	for p in exits:
		var d:float=Vector2(last).distance_to(Vector2(p.at[0],p.at[1]))
		if d<best:
			best=d
			nearby=p
	queue_redraw()

func draw_ice() -> void:
	for p in [Vector2i(24,35),Vector2i(18,30),Vector2i(18,13)]:
		if preload("res://core/kalos_gyms.gd").ice_gate(p,world.taken):continue
		var span:=Vector2(16,48) if p.x==24 else Vector2(48,16)
		draw_rect(Rect2(Vector2(p)*16,span),Color("#41657b"))
	for o in world.map_data.objects:
		if o.get("kind","")!="kalos_ice_switch":continue
		var point:=Vector2(o.at[0],o.at[1])*16+Vector2(8,7)
		var rotation_step:=int(world.taken.get("k_ice_turn_"+str(o.color),0))
		var dist:Vector2=[Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT][rotation_step]
		draw_line(point-dist*3,point+dist*3,Color("#3d4858"),2)
		draw_line(point+dist*3,point+dist+dist.orthogonal()*2,Color("#3d4858"),2)

func _draw() -> void:
	if world!=null and world.map_data.get("id","")=="kalos_gym_snowbelle":draw_ice()
	for p in exits:
		var at:=Vector2(p.at[0],p.at[1])*16
		if maxf(absf(p.at[0]-last.x),absf(p.at[1]-last.y))>24:continue
		var style:=str(p.get("source_warp",""))
		if p.has("alola_label"):continue # Markers are baked into the Emerald field image.
		if style.begins_with("script_"):
			draw_rect(Rect2(at+Vector2(2,7),Vector2(12,7)),Color("#39494f"))
			for i in 3:draw_line(at+Vector2(3,8+i*2),at+Vector2(12,8+i*2),Color("#f1d893"))
		else:
			draw_rect(Rect2(at+Vector2(3,10),Vector2(10,4)),Color("#445357"))
			draw_line(at+Vector2(4,11),at+Vector2(11,11),Color("#d8c795"))
	if nearby.is_empty() or not show_label:return
	var label:String=nearby.get("alola_label",nearby.get("kalos_label",""))
	var width:float=FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x+8
	var pos:=Vector2(nearby.at[0],nearby.at[1])*16+Vector2(8-width/2,-13)
	draw_rect(Rect2(pos,Vector2(width,12)),Color("#233239df"))
	draw_string(FONT,pos+Vector2(4,9),label,HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("#fff8d8"))
