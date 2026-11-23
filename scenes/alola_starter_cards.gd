extends RefCounted
const UI=preload("res://core/field_ui.gd")
const COLORS=[Color("#619b57"),Color("#cc6543"),Color("#4094ad")]
const PALE=[Color("#eef4da"),Color("#fae9d7"),Color("#e4f3f1")]
const TYPES=["草  /  飞行","火","水"]

static func layout(g,page:Control,header:Label,scroller:Control,button_list:Control,options:Array,species:Array,activate:Callable) -> void:
	page.get_child(0).color=Color("#f5f1de")
	header.position=Vector2(18,14)
	header.size=Vector2(440,32)
	header.add_theme_color_override("font_color",UI.INK)
	header.add_theme_font_size_override("font_size",21)
	scroller.hide()
	var bounds:=g.get_viewport_rect().size as Vector2
	var margin:=16.0
	var gap:=8.0
	var width:=floorf((bounds.x-margin*2-gap*2)/3)
	var height:=minf(208,bounds.y-110)
	for i in species.size():
		var card:=Button.new()
		card.text=options[i]
		card.alignment=HORIZONTAL_ALIGNMENT_CENTER
		card.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		card.add_theme_color_override("font_color",Color.TRANSPARENT)
		for state in ["hover","pressed","focus","hover_pressed"]:
			card.add_theme_color_override("font_"+state+"_color",Color.TRANSPARENT)
		for state in ["normal","hover","pressed","focus"]:
			var skin:=StyleBoxFlat.new()
			skin.bg_color=PALE[i].darkened(0.08) if state=="pressed" else PALE[i]
			skin.border_color=COLORS[i]
			skin.set_border_width_all(2)
			skin.border_width_bottom=5
			skin.set_corner_radius_all(7)
			card.add_theme_stylebox_override(state,skin)
		UI.place(page,card,margin+i*(width+gap),53,width,height)
		var pic:=UI.portrait(int(species[i]))
		UI.place(card,pic,8,8,width-16,height-68)
		var title:=UI.label(options[i],18,UI.INK)
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		UI.place(card,title,2,height-61,width-4,28)
		var type:=UI.label(TYPES[i],13,UI.MUTED)
		type.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		UI.place(card,type,1,height-33,width-2,21)
		card.pressed.connect(activate.bind(i))
	button_list.hide()
