extends Control
## Two Island single-device practice with an NPC teammate.
signal completed(points: int, streak: int)
signal input_slot(slot: int)
var online:=false
var network_berries: Array=[]
var friend_height:=0.0
var mode: String
var sprite: Texture2D
var companion: Texture2D
var speed_class: String
var score:=0
var streak:=0
var best_streak:=0
var misses:=0
var elapsed:=0.0
var cycle:=1.65
var takeoff:=-1.0
var lane:=1
var shade:=0
var picked:=false
var done:=false
var running:=false
var hud:=Label.new()
var hint:=Label.new()
var buttons:=HBoxContainer.new()
var rng: RandomNumberGenerator

func setup(kind: String, sid: int, jump_type: String, random: RandomNumberGenerator) -> void:
	mode=kind
	speed_class=jump_type
	rng=random
	sprite=load(Data.sprite_path(sid))
	companion=load(Data.sprite_path(25 if mode=="jump" else 85))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top=-83
	hint.offset_bottom=-52
	hint.text="藤蔓落到脚边前起跳，和皮卡丘同时腾空可加分。" if mode=="jump" else "树果落进浅色区域时，点它所在的方向。"
	add_child(buttons)
	buttons.alignment=BoxContainer.ALIGNMENT_CENTER
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.offset_top=-48
	buttons.offset_bottom=-5
	var actions=["起跳"] if mode=="jump" else ["左","中","右"]
	for i in actions.size():
		var b:=Button.new()
		b.text=actions[i]
		b.custom_minimum_size=Vector2(74,38)
		var slot:=i
		b.pressed.connect(func():press(slot))
		buttons.add_child(b)
	var end:=Button.new()
	end.text="结束"
	end.pressed.connect(finish)
	buttons.add_child(end)
	update_hud()

func update_hud() -> void:
	var title="宝可梦跳绳" if mode=="jump" else "嘟嘟利摘树果"
	hud.text="%s　%d 分　%s"%[title,score,"连跳 %d"%streak if mode=="jump" else "掉落 %d / 10"%misses]

func press(slot: int) -> void:
	if done:return
	if online:
		input_slot.emit(slot)
		return
	if not running:
		running=true
		return
	if mode=="jump":
		if takeoff<0 or elapsed-takeoff>air_time():takeoff=elapsed
	elif slot==lane and not picked and elapsed/cycle>=0.70 and elapsed<cycle:
		picked=true
		score+=[10,30,50][shade]
		streak+=1
		best_streak=maxi(best_streak,streak)
	update_hud()
	queue_redraw()

func air_time() -> float:
	return {"FAST":0.58,"SLOW":0.87}.get(speed_class,0.72)

func _process(delta: float) -> void:
	if done or not running:return
	var prev:=elapsed
	elapsed+=delta
	if mode=="jump" and prev<cycle*0.85 and elapsed>=cycle*0.85:
		var progress:=(elapsed-takeoff)/air_time()
		if takeoff<0 or progress<=0 or progress>=1:
			finish()
			return
		score+=10
		if absf(progress-0.5)<0.15:score+=50
		streak+=1
		best_streak=maxi(best_streak,streak)
	elif mode!="jump" and elapsed>=cycle and not picked:
		misses+=1
		streak=0
		score=maxi(0,score-50)
		if misses>=10:
			finish()
			return
	if elapsed>=cycle:
		elapsed=fmod(elapsed,cycle)
		takeoff=-1
		picked=false
		lane=rng.randi_range(0,2)
		shade=rng.randi_range(0,2)
		cycle=maxf(0.7,cycle-0.018)
	update_hud()
	queue_redraw()

func finish() -> void:
	if done:return
	done=true
	completed.emit(score,best_streak)

func _draw() -> void:
	var w:=size.x
	var h:=size.y
	var ground:=h*0.65
	draw_rect(Rect2(Vector2.ZERO,size),Color("#295750"))
	draw_rect(Rect2(0,ground,w,h-ground),Color("#294338"))
	var t:=elapsed/cycle
	if mode=="jump":
		var arc:=0.0
		if takeoff>=0:arc=maxf(0,sin(clampf((elapsed-takeoff)/air_time(),0,1)*PI))*h*0.21
		if sprite:draw_texture_rect(sprite,Rect2(w*0.53,ground-68-arc,68,68),false)
		var npc_arc:=(friend_height if online else maxf(0,1.0-absf(t-0.85)*4))*h*0.21
		if companion:draw_texture_rect(companion,Rect2(w*0.33,ground-62-npc_arc,62,62),false)
		var nodes:=PackedVector2Array()
		for j in 33:
			var x:=float(j)/32
			nodes.append(Vector2(w*(0.14+x*0.72),ground-h*0.19+sin(PI*x)*cos((t-0.85)*TAU)*h*0.19))
		draw_polyline(nodes,Color("#e9d981"),4,true)
	else:
		if companion:draw_texture_rect(companion,Rect2(w*0.03,ground-56,56,56),false)
		var columns:=[w*0.32,w*0.5,w*0.68]
		for x in columns:draw_rect(Rect2(x-23,ground-h*0.20,46,h*0.17),Color("#6b977a"),false,2)
		if sprite:draw_texture_rect(sprite,Rect2(w*0.5-40,ground-39,80,63),false)
		if online:
			for fruit in network_berries:
				if fruit[1]<0:continue
				var pt:=Vector2(columns[int(fruit[0])],h*0.15+float(fruit[1])*h*0.47)
				draw_circle(pt,9,[Color("#5caff6"),Color("#98d356"),Color("#f0c95f")][int(fruit[2])],true)
				draw_line(pt-Vector2(0,7),pt+Vector2(5,-14),Color("#acd375"),3)
		elif not picked:
			var pt:=Vector2(columns[lane],h*0.15+t*h*0.47)
			draw_circle(pt,9,[Color("#5caff6"),Color("#98d356"),Color("#f0c95f")][shade],true)
			draw_line(pt-Vector2(0,7),pt+Vector2(5,-14),Color("#acd375"),3)
	if not running and not online:
		draw_string(ThemeDB.fallback_font,Vector2(w*0.24,h*0.25),"点击下方按钮开始练习",HORIZONTAL_ALIGNMENT_CENTER,w*0.52,17,Color.WHITE)
