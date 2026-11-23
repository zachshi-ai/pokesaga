extends Control
## Touch course with wave timing, directional tricks, airborne collisions and landing.
signal finished(score: int)
const UI := preload("res://core/field_ui.gd")
const BEACH := ["大浪海滩","慷待海滩","乌拉乌拉海滩","波尼海滩"]
const TRICKS := [
	["→→→","猎斑鱼回旋",2300,0],["←←←","樱花鱼回旋",2300,0],
	["↑↓↑","电灯怪３６０",3300,1],["↓↓↓","西狮海壬旋转",3600,2],
	["→←→↑","宝石海星７２０",4700,3],["↑→↓←","暴鲤龙腾跃",5800,4]]
var course:=0
var mastered:=0
var distance:=0.0
var speed:=48.0
var jump:=0.0
var air_time:=0.0
var track:=0.0
var next_obstacle:=160.0
var score:=0
var combo:=0
var sequence:=""
var hint: Label
var meter: Label
var report: Label
var mantine: Texture2D
var started:=false
var frame:=0.0

func setup(which: int,unlocked: int) -> void:
	course=which
	mastered=unlocked
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mantine=load(get_node("/root/Data").sprite_path(226))
	UI.place(self,UI.label(BEACH[which]+"　巨翅飞鱼冲浪",16,Color.WHITE),14,7,305,28)
	meter=UI.label("",13,Color.WHITE)
	UI.place(self,meter,14,37,450,23)
	report=UI.label("从浪底加速，到浪峰起跳。",14,Color("ffe392"))
	UI.place(self,report,14,61,440,24)
	hint=UI.label("空中连续按三次 → 或三次 ← 做回旋",14,Color.WHITE)
	UI.place(self,hint,14,201,460,25)
	UI.place(self,UI.button("离开",func():finished.emit(-1)),398,8,72,35)
	for i in 4:
		var direction: String=["←","↑","↓","→"][i]
		UI.place(self,UI.button(direction,action.bind(direction)),9+61*i,245,55,59)
	UI.place(self,UI.button("乘浪／起跳",action.bind("jump")),265,245,204,59)
	var begin:=UI.button("出发",func():started=true)
	UI.place(self,begin,185,140,110,44)
	begin.pressed.connect(func():begin.hide())

func length_of_course() -> float:return 530.0+course*230
func crest() -> float:return sin(distance*.065)
func surface_y() -> float:return 145.0-crest()*17

func action(direction: String) -> void:
	if not started:return
	if direction=="jump":
		if jump>0:return
		air_time=1.45+speed*.013+maxf(crest(),0)*.8
		jump=air_time
		sequence="";combo=0
		report.text="起跳！"
	elif jump>0:
		sequence=(sequence+direction).right(4)
		for trick in TRICKS:
			if mastered<int(trick[3]) or not sequence.ends_with(trick[0]):continue
			combo+=1
			var value:=int(float(trick[2])*(1.0+mini(combo-1,4)*.25))
			score+=value
			report.text="%s　＋%d"%[trick[1],value]
			sequence=""
			break
	else:
		if direction in ["↓","↑"]:
			speed=minf(92,speed+6)
			report.text="压浪加速"
		else:track=clampf(track+(-1 if direction=="←" else 1),-1,1)

func _process(delta: float) -> void:
	frame+=delta
	if not started:queue_redraw();return
	distance+=speed*delta
	if jump>0:
		jump=maxf(0,jump-delta)
		if jump==0:
			if combo>0:score+=combo*550;report.text="平稳着水　＋%d"%(combo*550)
			else:report.text="着水"
	if distance>=next_obstacle:
		if jump==0 and absi(roundi(track))==0:
			speed=maxf(35,speed-18)
			report.text="擦到礁石，速度下降"
		next_obstacle+=145+int(course*6)
	meter.text="航程 %d％　速度 %d　积分 %d"%[clampi(int(100*distance/length_of_course()),0,100),int(speed),score]
	queue_redraw()
	if distance>=length_of_course():
		started=false
		finished.emit(score)

func _draw() -> void:
	draw_rect(Rect2(0,0,480,320),Color("#164b61"))
	draw_rect(Rect2(0,82,480,146),Color("#8bd7df"))
	var islands:=PackedVector2Array([Vector2(0,116),Vector2(28,103),Vector2(51,109),Vector2(82,99),Vector2(104,116)])
	draw_colored_polygon(islands,Color("#719b79"))
	for layer in 3:
		var points:=PackedVector2Array()
		for x in range(0,489,4):
			var y:=137.0+layer*15+sin((x+distance)*.04+layer)*9
			points.append(Vector2(x,y))
		var water:=points.duplicate()
		water.append(Vector2(488,229));water.append(Vector2(0,229))
		draw_colored_polygon(water,[Color("#5eb5c7"),Color("#337da7"),Color("#266486")][layer])
		draw_polyline(points,Color("#c0eff1"),2)
	var rock_x: float=110+(next_obstacle-distance)*1.6
	if rock_x<500:draw_colored_polygon(PackedVector2Array([Vector2(rock_x-14,162),Vector2(rock_x-5,148),Vector2(rock_x+9,143),Vector2(rock_x+17,162)]),Color("#5e6d78"))
	var y:=surface_y()+track*8
	if jump>0:y-=sin(PI*(1-jump/air_time))*67
	if mantine!=null:draw_texture_rect(mantine,Rect2(77,y-37,68,68),false)

func handle_back() -> void:
	finished.emit(-1)
