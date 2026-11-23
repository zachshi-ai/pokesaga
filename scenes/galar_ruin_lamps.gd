extends Control
## Touch adaptation of the ten switch floor. The reliefs show the two seven-light patterns.
signal solved(species: int)
signal cancelled
const SPOTS: Array[Vector2i]=[Vector2i(2,0),Vector2i(1,1),Vector2i(3,1),Vector2i(0,2),Vector2i(1,2),Vector2i(2,2),Vector2i(3,2),Vector2i(4,2),Vector2i(1,3),Vector2i(3,3)]
const ELECTRIC := [1,2,3,5,7,8,9]
const DRAGON := [0,1,2,4,5,6,8]
var lamps: Array[Button]
var hint: Label

func caption(parent: Control,words: String,at: Vector2,font_size: int)->Label:
	var label:=Label.new()
	label.text=words
	label.position=at
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label

func command(words: String,at: Vector2,extent: Vector2)->Button:
	var button:=Button.new()
	button.text=words
	button.position=at
	button.size=extent
	button.add_theme_font_size_override("font_size",15)
	add_child(button)
	return button

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=ColorRect.new()
	panel.color=Color("#25363d")
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	caption(self,"抉择遗迹",Vector2(20,8),24)
	hint=caption(self,"按石壁上的纹样点亮地板，再唤醒石像。",Vector2(21,41),14)
	for i in SPOTS.size():
		var pos:=Vector2(SPOTS[i])
		var b:=command("○",Vector2(26,67)+pos*Vector2(43,39),Vector2(41,37))
		b.name="Lamp"+str(i+1)
		b.toggle_mode=true
		b.tooltip_text="石灯 "+str(i+1)
		b.toggled.connect(func(on):
			b.text="●" if on else "○"
			b.modulate=Color("#ffe59d") if on else Color.WHITE)
		lamps.append(b)
	for j in 2:
		var origin:=Vector2(296+j*95,105)
		caption(self,["电纹","龙首"][j],origin+Vector2(3,-30),16)
		for i in SPOTS.size():
			var dot:=ColorRect.new()
			dot.position=origin+Vector2(SPOTS[i])*12
			dot.size=Vector2(6,6)
			dot.color=(Color("#e6c87c") if j==0 else Color("#e9a5a1")) if i in [ELECTRIC,DRAGON][j] else Color("#506066")
			add_child(dot)
	command("检查石像",Vector2(278,210),Vector2(120,39)).pressed.connect(check)
	command("离开",Vector2(402,210),Vector2(67,39)).pressed.connect(func():cancelled.emit())

func check()->void:
	var lit: Array=[]
	for i in lamps.size():
		if lamps[i].button_pressed:lit.append(i)
	if lit==ELECTRIC:solved.emit(894)
	elif lit==DRAGON:solved.emit(895)
	else:hint.text="石像没有回应。再次触碰亮灯可以熄灭。"

func _unhandled_input(event: InputEvent)->void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
