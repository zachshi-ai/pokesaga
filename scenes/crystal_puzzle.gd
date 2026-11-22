extends ColorRect
## Four-by-four touch reconstruction of the original 48 px Alph fossil engraving.
signal finished(solved: bool)
var order: Array=[]
var tiles: Array[Button]=[]
var active: int=-1
var art: Texture2D
var label: Label

func setup(key: String, title: String, previous: Array):
	color=Color("#182521")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art=load("res://assets/johto_gba/puzzles/"+key.replace("ho_oh","hooh")+".png")
	order=previous.duplicate()
	if order.size()!=16:
		order=range(16)
		order.shuffle()
		if order==range(16): order.reverse()
	label=Label.new()
	label.position=Vector2(16,12)
	label.text=title+"石板"
	add_child(label)
	var grid:=GridContainer.new()
	grid.columns=4
	grid.position=Vector2(16,47)
	add_child(grid)
	for i in 16:
		var b:=Button.new()
		b.custom_minimum_size=Vector2(59,59)
		b.expand_icon=true
		b.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		b.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		b.pressed.connect(press.bind(i))
		grid.add_child(b)
		tiles.append(b)
	var hint:=Label.new()
	hint.text="点选两块石片交换位置，\n拼回完整的图案。"
	hint.position=Vector2(276,75)
	hint.add_theme_font_size_override("font_size",14)
	add_child(hint)
	var leave:=Button.new()
	leave.text="稍后再拼"
	leave.position=Vector2(283,225)
	leave.size=Vector2(155,48)
	leave.pressed.connect(func(): finished.emit(false))
	add_child(leave)
	draw_pieces()

func draw_pieces():
	for i in 16:
		var rect:=AtlasTexture.new()
		rect.atlas=art
		rect.region=Rect2(int(order[i])%4*12,int(order[i])/4*12,12,12)
		tiles[i].icon=rect
		tiles[i].modulate=Color(1,.78,.4) if i==active else Color.WHITE

func press(index: int):
	if active==-1: active=index
	else:
		var held=order[active]
		order[active]=order[index]
		order[index]=held
		active=-1
	draw_pieces()
	if order==range(16): finished.emit(true)

func handle_back():
	finished.emit(false)
